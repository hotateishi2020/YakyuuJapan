"""Supplement archived lineups with sourced season statistics and throwing hands.

NPB official totals remain authoritative where present. Archive starts are checked
against official appearances, and role innings are only filled for single-role
pitchers. Missing splits are never estimated.
"""
import concurrent.futures
import copy
from functools import lru_cache
import json
import re
from pathlib import Path
from urllib.parse import urljoin
import urllib.request
from bs4 import BeautifulSoup
from tool_enrich_regular_history import ROOT, normalized, normalize_groups, outs

CACHE = Path('/tmp/koko-regular-archive')
CODES = {'巨人':'giants','阪神':'tigers','中日':'dragons','DeNA':'baystars',
         '広島':'carp','ヤクルト':'swallows','ソフトバンク':'hawks','西武':'lions',
         '日本ハム':'fighters','ロッテ':'marines','楽天':'eagles','オリックス':'bluewave','近鉄':'buffaloes'}


def fetch_body(url):
    path = CACHE / url.split('2689web.com/')[-1]
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        with urllib.request.urlopen(url, timeout=40) as response:
            body = response.read().decode('cp932')
        path.write_text(body)
    return path.read_text()


def fetch(url):
    return BeautifulSoup(fetch_body(url), 'html.parser')


@lru_cache(maxsize=None)
def throwing_hand(url):
    hand = re.search(r'([左右両])投', fetch_body(url))
    if not hand:
        raise ValueError('Unknown throwing hand: '+url)
    return hand[1]


def season_stats(soup, url):
    result = {'pitching_stats': [], 'batting_stats': []}
    headers = []
    expected_starts = None
    for tr in soup.select('tr'):
        nodes = tr.find_all(['td', 'th'], recursive=False)
        cells = [c.get_text(' ', strip=True) for c in nodes]
        if '選手名' in cells:
            headers = cells
            continue
        if cells and cells[0] == 'チーム計' and '投球回' in headers:
            expected_starts = int(cells[headers.index('先発') - 1])
        if len(cells) != len(headers) or '選手名' not in headers:
            continue
        d = dict(zip(headers, cells))
        if not re.fullmatch(r'\d+(?:[･・]\d+)*', d.get('背番', '')) or not d.get('選手名'):
            continue
        pitching = '投球回' in d
        batting = 'OPS' in d and '打席' in d
        if not pitching and not batting:
            continue
        def integer(key):
            return int(d[key]) if d.get(key, '').isdigit() else None
        def decimal(key):
            try:
                return float(d[key])
            except (KeyError, ValueError):
                return None
        name = normalized(d['選手名'])
        link = nodes[headers.index('選手名')].find('a', href=True)
        p = {'name':name,'source_surname':d['選手名'].split()[0],
             'player_key':'npb:history:'+name,'source_url':url}
        if pitching:
            if not link:
                raise ValueError('No pitcher profile: '+name)
            profile_url = urljoin(url, link['href'])
            hand = throwing_hand(profile_url)
            total = outs(d['投球回'])
            p.update(throws=hand, appearances=integer('登板'), starts=integer('先発'),
                     total_outs=total, holds=integer('Ｈ'), saves=integer('Ｓ'),
                     whip=(integer('安打')+integer('四球'))*3/total if total else None,
                     profile_source_url=profile_url)
            if p['starts'] is None or p['starts'] > p['appearances']:
                raise ValueError('Invalid starts: '+name)
        else:
            p.update(pa=integer('打席'),home_runs=integer('本塁'),ops=decimal('OPS'))
        result['pitching_stats' if pitching else 'batting_stats'].append(p)
    if not all(result.values()):
        raise ValueError('Missing season statistics: '+url)
    if expected_starts is None or sum(p['starts'] for p in result['pitching_stats']) != expected_starts:
        raise ValueError('Pitcher starts do not match team total: '+url)
    return result


def apply(row, stats, url):
    archive_pitchers = {}
    for field, values in stats.items():
        existing = row.get(field, []) if row.get('official_stat_sources') else []
        for p in values:
            def identity(name):
                value = re.sub(r'^[A-Z]+', '', normalized(name)).replace('Jr', 'ジュニア')
                # 2689 uses the initial suffix for the official registration ジェン.
                return 'ジェン' if value == 'ジェンK' else value
            matches = [v for v in existing if identity(v['name']) == identity(p['name'])]
            if len(matches) == 1:
                q = matches[0]
                if field == 'pitching_stats':
                    for key in ['appearances','total_outs','saves','holds']:
                        if q.get(key) is not None and p.get(key) is not None and q[key] != p[key]:
                            raise ValueError(f'{row["year"]} {row["club_name"]} {p["name"]}: {key} mismatch')
                    q.update(starts=p['starts'], starts_source_url=url)
                target = q
            elif not existing or not row.get('official_stat_sources'):
                target = p
            else:
                continue
            if field == 'pitching_stats':
                archive_pitchers[target['player_key']] = target
        if not existing:
            row[field] = values
    normalize_groups(row)
    for p in row['pitching_workload']:
        source = archive_pitchers.get(p['player_key'])
        if source and source.get('starts') is not None:
            p['starts'] = source['starts']
            p['starts_source_url'] = url
            p['relief_appearances'] = p['appearances'] - p['starts']
            if p['starts'] == 0:
                p.update(starter_outs=0,relief_outs=p['total_outs'])
            elif p['starts'] == p['appearances']:
                p.update(starter_outs=p['total_outs'],relief_outs=0)
    row['archive_stat_sources'] = [url]
    row['historical_enrichment_version'] = 2


def main():
    path = ROOT/'data/regular-history.json'
    data = json.loads(path.read_text())
    errors = []
    def run(row):
        code = CODES[row['club_name']]
        if row['club_name']=='DeNA' and row['year']<1993: code='whales'
        if row['club_name']=='オリックス': code='braves' if row['year']<1991 else 'bluewave' if row['year']<2005 else 'buffaloes'
        if row['club_name']=='ロッテ' and row['year']<1992: code='orions'
        url=f'https://2689web.com/{row["year"]}/{code}.html'
        try:
            updated = copy.deepcopy(row)
            apply(updated,season_stats(fetch(url),url),url)
            row.clear(); row.update(updated)
        except Exception as error:
            errors.append(f'{row["year"]} {row["club_name"]}: {error}')
            print(errors[-1], flush=True)
        return row
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for index, row in enumerate(pool.map(run,data['rows']),1):
            if index%24==0:print(f'{index}/{len(data["rows"])}',flush=True)
    data['archive_enrichment_errors']=errors
    temp=path.with_suffix('.tmp')
    temp.write_text(json.dumps(data,ensure_ascii=False));temp.replace(path)
    print(json.dumps({'enriched':sum(bool(r.get('pitching_workload')) for r in data['rows']),'errors':errors},ensure_ascii=False),flush=True)

if __name__=='__main__':main()
