"""Enrich historical starting lineups with official season statistics.

Only unique names within the same team/season are resolved. Mixed-role pitching
innings remain unknown until game-level data is available; never estimate them.
"""
import concurrent.futures
import json
from pathlib import Path
import re
import sys
import unicodedata
import urllib.request
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parent
CACHE = Path('/tmp/koko-regular-official')
CODES = {'巨人':'g', '阪神':'t', '中日':'d', 'DeNA':'yb', '広島':'c',
         'ヤクルト':'s', 'ソフトバンク':'h', '西武':'l', '日本ハム':'f',
         'ロッテ':'m', '楽天':'e', 'オリックス':'bs', '近鉄':'bu'}


def normalized(name):
    return re.sub(r'[\s・･.]+', '', unicodedata.normalize('NFKC', name)).translate(
        str.maketrans({'髙':'高', '﨑':'崎', '瀨':'瀬', '海':'海'}))


def fetch(year, code, kind):
    url = f'https://npb.jp/bis/{year}/stats/{kind}_{code}.html'
    CACHE.mkdir(exist_ok=True)
    path = CACHE / f'{year}-{kind}-{code}.html'
    if not path.exists():
        with urllib.request.urlopen(url, timeout=35) as response:
            body = response.read().decode('utf-8')
        path.write_text(body)
    return path.read_text(), url


def outs(text):
    text = re.sub(r'\s+', '', text)
    match = re.fullmatch(r'(\d+?)([12])/3', text)
    if match:
        return int(match[1]) * 3 + int(match[2])
    if text in ('1/3', '2/3'):
        return int(text[0])
    match = re.fullmatch(r'(\d+)(?:\.([12]))?', text)
    return int(match[1]) * 3 + int(match[2] or 0) if match else None


def metrics(body, pitching):
    soup = BeautifulSoup(body, 'html.parser')
    result = []
    for tr in soup.select('tr'):
        cells = [c.get_text(' ', strip=True) for c in tr.select('td')]
        # Archived tables put the left/switch-handed marker in its own cell.
        if len(cells) in ((25, 26) if pitching else (24,)) and cells[0] in ('', '*', '+'):
            cells = [cells[0] + cells[1], *cells[2:]]
        if pitching and len(cells) == 25:
            cells = [*cells[:12], cells[12] + cells[13], *cells[14:]]
        if len(cells) < 23 or not re.fullmatch(r'\d+', cells[1]):
            continue
        raw = cells[0]
        name = re.sub(r'^[*+]\s*', '', raw).strip()
        def integer(i):
            return int(cells[i]) if cells[i].isdigit() else None
        def decimal(i):
            try:
                return float(cells[i])
            except ValueError:
                return None
        player = {'name': normalized(name), 'source_surname': name.split()[0],
                  'player_key': 'npb:history:' + normalized(name)}
        player['throws' if pitching else 'bats'] = (
            '左' if raw.startswith('*') else '両' if raw.startswith('+') else '右')
        if pitching:
            total = outs(cells[12])
            player.update(appearances=integer(1), saves=integer(4),
                          holds=integer(5), total_outs=total,
                          whip=(integer(13)+integer(15))*3/total if total else None)
        else:
            obp, slg = decimal(22), decimal(21)
            player.update(pa=integer(2), home_runs=integer(8),
                          ops=obp+slg if obp is not None and slg is not None else None)
        result.append(player)
    if not result:
        raise ValueError('No official player statistics')
    return result


def normalize_groups(row):
    batters = [p for p in row.get('batting_stats', []) if (p.get('pa') or 0) > 0]
    pitchers = row.get('pitching_stats', [])
    # Official full names distinguish two players with the same surname.
    def resolve(name, pool):
        query = normalized(name)
        exact = [p for p in pool if normalized(p['name']) == query]
        candidates = exact or [p for p in pool
                              if normalized(p['name']).startswith(query)]
        return candidates[0] if len(candidates) == 1 else None
    unresolved = set()
    for field in ('positions', 'batting_order'):
        for group in row.get(field, []):
            merged = {}
            pool = pitchers if group['slot'] == 'P' else batters
            for original in group['players']:
                player = resolve(original.get('source_name', original['name']), pool)
                value = {**original}
                if player:
                    value.update(name=player['name'], player_key=player['player_key'])
                    value['source_name'] = original.get('source_name', original['name'])
                else:
                    unresolved.add(original['name'])
                    value['player_key'] = original.get('player_key') or (
                        f"npb:archive:{row['club_name']}:{normalized(original['name'])}")
                key = value['player_key']
                if key in merged:
                    merged[key]['count'] += value['count']
                else:
                    merged[key] = value
            group['players'] = sorted(merged.values(), key=lambda p:(-p['count'], p['name']))
            for player in group['players']:
                player['rate'] = round(player['count'] * 100 / group['total'], 1)
    starts = {p['player_key']: p['count'] for g in row['positions']
              if g['slot'] == 'P' for p in g['players']}
    workload = []
    for pitcher in pitchers:
        count = starts.get(pitcher['player_key'])
        # An unresolved starting name could be this pitcher: do not assume relief.
        unresolved_starts = any(p.get('player_key', '').startswith('npb:archive:')
                                for g in row['positions'] if g['slot'] == 'P'
                                for p in g['players'])
        p = {**pitcher}
        if count is not None or not unresolved_starts:
            p['starts'] = count or 0
            if p['starts'] == p['appearances']:
                p.update(starter_outs=p['total_outs'], relief_outs=0)
            elif p['starts'] == 0:
                p.update(starter_outs=0, relief_outs=p['total_outs'])
        workload.append(p)
    row['pitching_workload'] = workload
    row['roster'] = list({p['player_key']: p for p in [*pitchers, *batters]}.values())
    row['unresolved_names'] = sorted(unresolved)
    row['historical_enrichment_version'] = 1


def main():
    path = ROOT / 'data/regular-history.json'
    data = json.loads(path.read_text())
    errors = []
    def run(row):
        year = row['year']
        if '--modern-only' in sys.argv and year < 2005:
            return row
        code = CODES[row['club_name']]
        if row['club_name'] == 'DeNA' and year >= 2012:
            code = 'db'
        if row['club_name'] == 'オリックス' and year < 2005:
            code = 'bw'
        if row['club_name'] == 'オリックス' and year >= 2019:
            code = 'b'
        sources = []
        for kind, field in [('idb1', 'batting_stats'), ('idp1', 'pitching_stats')]:
            try:
                body, url = fetch(year, code, kind)
                row[field] = metrics(body, field == 'pitching_stats')
                sources.append(url)
            except Exception as error:
                errors.append(f'{year} {row["club_name"]} {kind}: {error}')
        if sources:
            row['official_stat_sources'] = sources
            normalize_groups(row)
        return row
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for index, row in enumerate(pool.map(run, data['rows']), 1):
            if index % 24 == 0:
                print(f'{index}/{len(data["rows"])} seasons', flush=True)
    data['enrichment_errors'] = errors
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False))
    temporary.replace(path)
    print(json.dumps({'enriched':sum(bool(r.get('official_stat_sources')) for r in data['rows']),
                      'unavailable':len(errors)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
