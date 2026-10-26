"""Audit current NPB maxima. Run from backend; only replaces the selected snapshot.

NF3's season-best columns (not ongoing streak columns) are checked for both
leagues. Official NPB records independently confirm holds and all-game players.
Missing categories are explicitly unavailable, never filled with partial DB runs.
"""
import argparse
import concurrent.futures
import hashlib
import html
import json
import itertools
import pathlib
import re
import urllib.request
from datetime import datetime, timezone

SPECS = {'hit_games': (0, 11, '安打'), 'hr_games': (0, 14, '本塁'),
         'onbase_games': (0, 15, '出塁'), 'hit_pa': (0, 16, '安打'),
         'hr_pa': (0, 17, '本塁打'), 'onbase_pa': (0, 21, '出塁'),
         'wins': (1, 11, '勝利'), 'holds': (1, 13, 'ホールド'),
         'saves': (1, 14, 'セーブ'), 'scoreless_games': (1, 17, '無失点')}
TEAMS = {'T':'阪神', 'DB':'DeNA', 'G':'巨人', 'D':'中日', 'C':'広島', 'S':'ヤクルト',
         'H':'ソフトバンク', 'F':'日本ハム', 'B':'オリックス', 'E':'楽天', 'L':'西武', 'M':'ロッテ'}
UNKNOWN = {'outs':'走者の出塁・打者のアウトを全公式戦の打席順で確認できる資料が未取得。',
           'scoreless_innings':'失点時点・端数回・前任投手の残した走者を含む公式の年度内最長値が未確認。',
           'strikeouts':'試合をまたぐ対戦打者順を含めた年度内最長値が未確認。'}

def table_rows(body):
    return [[html.unescape(re.sub('<[^>]+>', '', c)).strip()
             for c in re.findall(r'<t[dh]\b[^>]*>(.*?)</t[dh]>', row, re.S|re.I)]
            for row in re.findall(r'<tr\b[^>]*>(.*?)</tr>', body, re.S|re.I)]

def parse_leaders(body, key, year, url):
    fp, column, heading = SPECS[key]
    if f'{year}年度版' not in body or '最高記録' not in body:
        raise ValueError(f'Wrong year or scope: {url}')
    rows = table_rows(body)
    headers = [r for r in rows if len(r) > column and r[:3] == ['順','名前','TM']]
    if not headers or headers[0][column] != heading:
        raise ValueError(f'Unexpected column layout: {url}')
    data = [r for r in rows if len(r) == len(headers[0]) and r[0].isdigit()]
    if not data or data[0][0] != '1' or data[-1][0] == '1':
        raise ValueError(f'Cannot establish complete first-place ties: {url}')
    values = [int(r[column]) for r in data]
    if values != sorted(values, reverse=True):
        raise ValueError(f'Not sorted by season maximum: {url}')
    maximum = values[0]
    return [{'name': r[1], 'team': TEAMS[r[2]], 'value': maximum, 'year': year,
             'status': 'active', 'source_url': url}
            for r in data if int(r[column]) == maximum]


def steal_run_bounds(rows):
    # Every ordering of steals/caught-stealing within each day is considered.
    # Publish only when ambiguity cannot change either the maximum or its ties.
    states = {(0, 0)}
    for successes, failures in rows:
        next_states = set()
        for sequence in set(itertools.permutations([1]*successes + [0]*failures)):
            for run, best in states:
                for success in sequence:
                    run = run+1 if success else 0
                    best = max(run, best)
                next_states.add((run, best))
        states = next_states
    return min(best for _,best in states), max(best for _,best in states)

def audit_steals(get, players, year, orders=None):
    def normalize(name):
        return re.sub(r'^[*+]|[\s\u3000]', '', name).replace('髙','高')
    checked, lower = [], 0
    for player in sorted(players, key=lambda p:-p['sb']):
        if player['sb'] < lower: break  # Annual total bounds any possible streak.
        code = player['code']
        league = 0 if code in ['T','DB','G','D','C','S'] else 1
        roster = get(f'https://nf3.sakura.ne.jp/php/stat_disp/stat_disp.php?y=0&leg={league}&tm={code}&fp=0&dn=1&dk=0')
        links = [(u, normalize(html.unescape(re.sub('<[^>]+>', '', n)))) for u,n in
          re.findall(r"href=['\"]([^'\"]*/f/[^'\"]*_stat.htm)['\"][^>]*>(.*?)</a>", roster, re.S)]
        paths = [u for u,n in links if n == normalize(player['name'])]
        if len(paths) != 1: raise ValueError(f'Unresolved player: {player}')
        number = paths[0].split('/')[-1].removesuffix('_stat.htm')
        url = f'https://nf3.sakura.ne.jp/php/stat_disp/stat_disp.php?fpnum={number}&leg={league}&mon=0&tm={code}&vst=all&y=0'
        body = get(url)
        if f'{year}年度版' not in body: raise ValueError('Wrong steal log year')
        rows = [r for r in table_rows(body) if len(r)==26 and re.fullmatch(r'\d+/\d+',r[0])]
        attempts = []
        order_sources = []
        for r in rows:
            resolved = (orders or {}).get(f"{code}|{normalize(player['name'])}|{r[0]}")
            if resolved is None:
                attempts.append((int(r[17]),int(r[18])))
            else:
                sequence = resolved['sequence']
                if any(x not in [0,1] for x in sequence) or (sequence.count(1),sequence.count(0)) != (int(r[17]),int(r[18])) or not resolved['sources']:
                    raise ValueError('Resolved event order disagrees with daily totals')
                attempts.extend((1,0) if x else (0,1) for x in sequence)
                order_sources.extend(resolved['sources'])
        if (sum(a for a,b in attempts),sum(b for a,b in attempts)) != (player['sb'],player['cs']):
            raise ValueError(f'Steal totals disagree with official season stats: {player}')
        low, high = steal_run_bounds(attempts)
        lower = max(lower, low)
        checked.append({**player, 'minimum':low, 'maximum':high, 'source_url':url, 'event_order_sources':order_sources})
    contenders = [p for p in checked if p['maximum'] >= lower]
    if not contenders or any(p['minimum'] != lower or p['maximum'] != lower for p in contenders):
        raise ValueError('Steal event order must be checked before publishing leaders: '+json.dumps(contenders,ensure_ascii=False))
    leaders = [{'name':p['name'], 'team':TEAMS[p['code']], 'year':year, 'value':lower,
                'status':'active', 'source_url':p['source_url'], 'sources':[p['source_url'],p['official'],*p['event_order_sources']]}
               for p in contenders]
    return leaders, checked

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('year', type=int)
    ap.add_argument('--cache', type=pathlib.Path, required=True)
    args = ap.parse_args()
    year = args.year
    args.cache.mkdir(parents=True, exist_ok=True)
    evidence = {}
    def get(url):
        path = args.cache / (hashlib.sha256(url.encode()).hexdigest()+'.html')
        if path.exists(): raw = path.read_bytes()
        else:
            raw = urllib.request.urlopen(url, timeout=45).read()
            path.write_bytes(raw)
        evidence[url] = hashlib.sha256(raw).hexdigest()
        return raw.decode('utf-8')
    def fetch(spec):
        key, league = spec
        fp, column, _ = SPECS[key]
        # y=0 means the current edition; parser rejects any other year.
        url = f'https://nf3.sakura.ne.jp/php/stat_disp/stat_disp.php?y=0&leg={league}&tm=srk&fp={fp}&dn={column}'
        return key, parse_leaders(get(url), key, year, url)
    records = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        for key, rows in ex.map(fetch, [(k,l) for k in SPECS for l in [0,1]]):
            records.setdefault(key, []).extend(rows)
    for key, rows in records.items():
        maximum = max(r['value'] for r in rows)
        records[key] = [r for r in rows if r['value'] == maximum]
    # Official season record review: corroborate the exceptional hold streak.
    official = f'https://npb.jp/history/{year}/review_rec_p.html'
    review = html.unescape(re.sub('<[^>]+>', ' ', get(official)))
    hold = records['holds']
    if len(hold) == 1 and f"{hold[0]['value']}試合連続ホールド" in review and hold[0]['name'] in review:
        hold[0]['sources'] = [hold[0]['source_url'], official]
    # Complete official club rosters include players below qualifying PA.
    # A 143-game player on a club with 143 games proves the season upper bound.
    appearances, stealing_players = [], []
    for league in ['c','p']:
        standings = get(f'https://npb.jp/bis/{year}/stats/std_{league}.html')
        club_rows = [r for r in table_rows(standings) if len(r)>5 and '143' in r[:4]]
        if len(club_rows) != 6:
            raise ValueError('All twelve clubs must have completed 143 games')
    for code in ['t','db','g','d','c','s','h','f','b','e','l','m']:
        url = f'https://npb.jp/bis/{year}/stats/idb1_{code}.html'
        body = get(url)
        if str(year) not in body: raise ValueError('Wrong official season')
        rows = table_rows(body)
        if not any(r[:2] == ['選手','試合'] for r in rows): raise ValueError('Unknown official batting table')
        for r in rows:
            if len(r)==23 and r[11].isdigit() and int(r[11])>0:
                stealing_players.append({'name':re.sub(r'^[*+]|[\s\u3000]', '', r[0]), 'code':code.upper(), 'sb':int(r[11]), 'cs':int(r[12]), 'official':url})
            if len(r)==23 and r[1]=='143':
                appearances.append({'name': re.sub(r'^[*+]|[\s\u3000]', '', r[0]),
                  'team': TEAMS[code.upper()], 'value':143, 'year':year, 'status':'active', 'source_url':url})
    if not appearances: raise ValueError('Cannot infer maximum from total appearances')
    records['appearances'] = appearances
    records['steals'], steals_audit = audit_steals(get, stealing_players, year)
    metadata = {k: {'status':'verified', 'sources':sorted({url for r in v for url in [r['source_url'], *r.get('sources',[])]}),
      'note':'セ・パ両リーグのシーズン最高記録を照合。同率を全員保持。出典：ヌルデータ置き場f3。'} for k,v in records.items()}
    metadata['appearances']['note'] = 'NPB公式の12球団全選手成績を照合。各球団143試合、143試合出場者は全試合連続出場。'
    metadata['steals']['note'] = 'NPB公式年間盗塁・盗塁刺と全候補者の試合別合計を照合。同日の成功・失敗の全順序で最長値と同率首位が変わらないことを確認。年間盗塁数が確定最長値未満の選手は上限で除外。'
    for key, reason in UNKNOWN.items():
        records[key] = []
        metadata[key] = {'status':'unavailable','note':reason,'sources':[]}
    snapshot = {'checked_at':datetime.now(timezone.utc).isoformat(),
      'note':f'{year}年度内・一軍公式戦のみ。年間最高値を照合し、未確認の項目に部分取得区間の値を代入しない。',
      'records':records, 'categories':metadata, 'evidence_sha256':evidence, 'steals_audit':steals_audit}
    target=pathlib.Path('data/records.json')
    data=json.loads(target.read_text());data['npb'].setdefault('current_streaks',{})[str(year)]=snapshot
    temp=target.with_suffix('.json.tmp');temp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');temp.replace(target)
    print(json.dumps({k: [(r['name'],r['value']) for r in v] for k,v in records.items()},ensure_ascii=False))

if __name__ == '__main__': main()
