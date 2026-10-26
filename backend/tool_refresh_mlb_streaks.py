"""Full-season MLB streak audit, with resumable official-source downloads.
Run from backend: python3 tool_refresh_mlb_streaks.py YEAR --cache DIRECTORY
Use a fresh cache for a new observation date. --offline verifies cached evidence.
No snapshot is replaced until every game and every counted annual total agrees.
"""
import argparse
import collections
import concurrent.futures
import hashlib
import json
import pathlib
import time
import urllib.request
from datetime import datetime, timezone

HITS = {'single', 'double', 'triple', 'home_run'}
ONBASE = HITS | {'walk', 'intent_walk', 'hit_by_pitch'}
PA = ONBASE | {'field_out', 'strikeout', 'force_out', 'grounded_into_double_play',
    'sac_fly', 'field_error', 'sac_bunt', 'fielders_choice', 'double_play',
    'fielders_choice_out', 'strikeout_double_play', 'catcher_interf',
    'sac_fly_double_play', 'triple_play', 'sac_bunt_double_play'}
NON_PA = {'other_out', 'wild_pitch', 'game_advisory', 'passed_ball', 'balk',
          'defensive_indiff', 'runner_double_play'}
GAME_KEYS = ['wins','saves','holds','scoreless_games','hit_games','onbase_games','hr_games','appearances']
EVENT_KEYS = ['hit_pa','hr_pa','onbase_pa','outs','strikeouts','steals']

class Runs:
    def __init__(self):
        self.current = collections.defaultdict(int)
        self.best = collections.defaultdict(int)
    def add(self, key, player, success):
        pair = (key, player)
        self.current[pair] = self.current[pair]+1 if success else 0
        self.best[pair] = max(self.best[pair], self.current[pair])
    def leaders(self, key, people, year):
        maximum = max((n for (k,p),n in self.best.items() if k==key), default=0)
        return [{'player_id':p, 'name':people[p]['fullName'], 'value':n,
                 'year':year, 'status':'active' if people[p].get('active') else 'unknown'}
                for (k,p),n in sorted(self.best.items()) if k==key and n==maximum and n>0]

def ordered_games(schedule):
    games = {g['gamePk']:g for d in schedule['dates'] for g in d['games']
             if g['gameType']=='R' and g['status']['detailedState']!='Cancelled'}
    if not games or any(g['status']['abstractGameState']!='Final' for g in games.values()):
        raise ValueError('The complete regular season must be final')
    return sorted(games.values(), key=lambda g:(g['officialDate'], g['gameNumber'], g['gamePk']))

def game_runs(people, games, totals, runs):
    order = {g['gamePk']:i for i,g in enumerate(games)}
    for person in people.values():
        p = person['id']
        for group in person.get('stats',[]):
            name = group['group']['displayName']
            rows = sorted((r for r in group['splits'] if r['gameType']=='R'), key=lambda r:order[r['game']['gamePk']])
            expected = totals[name].get(p, {})
            fields = (['wins','losses','saves','holds','runs','strikeOuts','gamesPlayed'] if name=='pitching'
                      else ['hits','homeRuns','plateAppearances','stolenBases','caughtStealing'])
            for field in fields:
                if sum(r['stat'].get(field,0) for r in rows) != expected.get(field,0):
                    raise ValueError(f'Incomplete game logs: {p} {name} {field}')
            for row in rows:
                s = row['stat']
                if name=='pitching':
                    if s['wins']+s['losses']>0: runs.add('wins',p,s['wins']>0)
                    for key in ['saves','holds']: runs.add(key,p,s[key]>0)
                    runs.add('scoreless_games',p,s['runs']==0)
                else:
                    if s['hits'] or s['atBats'] or s.get('sacFlies',0): runs.add('hit_games',p,s['hits']>0)
                    if s['plateAppearances']:
                        runs.add('onbase_games',p,s['hits']+s['baseOnBalls']+s['hitByPitch']>0)
                        runs.add('hr_games',p,s['homeRuns']>0)
    # Official annual appearances equal to the largest club schedule prove the
    # maximum without omitting defensive-only appearances from hitting game logs.
    lengths = collections.Counter(t['team']['id'] for g in games for t in g['teams'].values())
    maximum = max(lengths.values())
    leaders = [p for p,s in totals['hitting'].items() if s['gamesPlayed']==maximum]
    if not leaders or any(s['gamesPlayed']>maximum for s in totals['hitting'].values()):
        raise ValueError('Appearance upper-bound proof unavailable; complete box scores required')
    for p in leaders: runs.best['appearances',p] = maximum

def consume_plays(plays, runs, counts):
    seen = set()
    last_pitcher = {}
    for play in sorted(plays, key=lambda p:p['atBatIndex']):
        event = play['result']['eventType']
        if not play['about']['isComplete'] and event!='game_advisory':
            raise ValueError('Incomplete play')
        actual_batter = play['matchup']['batter']['id']
        b = actual_batter; p = play['matchup']['pitcher']['id']
        half = play['about'].get('isTopInning',False)
        previous = last_pitcher.get(half)
        last_pitcher[half] = p
        if event in {'walk','intent_walk'}:
            charged = None
            for substitution in play.get('playEvents',[]):
                if substitution['details'].get('eventType')!='pitching_substitution': continue
                count = substitution.get('count',{})
                incoming = substitution['player']['id']
                # Rule 9.16(h): inherit a favorable count, but charge the
                # completed walk and batter faced to the preceding pitcher.
                favorable = count.get('balls',0)==3 or (count.get('balls')==2 and count.get('strikes',0)<2)
                if favorable:
                    if charged is None: charged = previous
                    if charged is None: raise ValueError('Unknown pitcher before inherited walk')
                else: charged = incoming
                previous = incoming
            if charged is not None: p = charged
        # Rule 9.15(b): a replacement batter who inherits two strikes and
        # strikes out leaves the PA/K charged to the original batter.
        if event in {'strikeout','strikeout_double_play'}:
            for substitution in reversed(play.get('playEvents',[])):
                if (substitution['details'].get('eventType')=='offensive_substitution'
                    and substitution.get('player',{}).get('id')==b
                    and substitution.get('count',{}).get('strikes')==2):
                    b = substitution['replacedPlayer']['id']
        for runner in play.get('runners',[]):
            d = runner['details']; e = d.get('eventType',''); r = d['runner']['id']
            token = (play['atBatIndex'], d.get('playIndex'), r, e)
            if token in seen: continue
            if e.startswith('stolen_base_') or ('caught_stealing' in e and
                    (runner['movement'].get('isOut') or 'caught_stealing' in (d.get('movementReason') or ''))):
                seen.add(token)
                success = e.startswith('stolen_base_')
                runs.add('steals',r,success)
                counts['hitting',r,'stolenBases' if success else 'caughtStealing'] += 1
        if event not in PA:
            if event not in NON_PA and not event.startswith(('pickoff_', 'caught_stealing_', 'stolen_base_')):
                raise ValueError(f'Unclassified result: {event}')
            continue
        counts['hitting',b,'plateAppearances'] += 1
        counts['hitting',b,'hits'] += event in HITS
        counts['hitting',b,'homeRuns'] += event=='home_run'
        counts['hitting',b,'baseOnBalls'] += event in {'walk','intent_walk'}
        counts['hitting',b,'hitByPitch'] += event=='hit_by_pitch'
        strikeout = event in {'strikeout','strikeout_double_play'}
        counts['pitching',p,'strikeOuts'] += strikeout
        counts['pitching',p,'battersFaced'] += 1
        runs.add('hit_pa',b,event in HITS)
        runs.add('hr_pa',b,event=='home_run')
        runs.add('onbase_pa',b,event in ONBASE)
        runs.add('strikeouts',p,strikeout)
        # A force out of another runner is NOT retirement of this batter.
        retired = (event not in ONBASE | {'field_error','fielders_choice','fielders_choice_out','catcher_interf'}
                   and any(r['details']['runner']['id']==actual_batter and r['movement'].get('isOut') for r in play.get('runners',[])))
        runs.add('outs',p,retired)

def verify_events(counts, totals):
    fields = {'hitting':['plateAppearances','hits','homeRuns','baseOnBalls','hitByPitch','stolenBases','caughtStealing'],
              'pitching':['strikeOuts','battersFaced']}
    mismatches = []
    for group, columns in fields.items():
        ids = set(totals[group]) | {p for g,p,k in counts if g==group}
        for p in ids:
            for field in columns:
                actual = counts[group,p,field]; expected = totals[group].get(p,{}).get(field,0)
                if actual!=expected: mismatches.append([group,p,field,expected,actual])
    return mismatches

def main():
    ap=argparse.ArgumentParser();ap.add_argument('year',type=int);ap.add_argument('--cache',type=pathlib.Path,required=True);ap.add_argument('--offline',action='store_true')
    args=ap.parse_args();year=args.year;root=args.cache;root.mkdir(parents=True,exist_ok=True)
    def get(path,url):
        target=root/path
        if target.exists(): return json.loads(target.read_bytes())
        if args.offline: raise ValueError(f'Missing evidence: {target}')
        for attempt in range(4):
            try:
                raw=urllib.request.urlopen(url,timeout=90).read();data=json.loads(raw)
                target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw);return data
            except Exception:
                if attempt==3: raise
                time.sleep(2)
    base='https://statsapi.mlb.com/api/v1';totals={};ids=set()
    for group in ['hitting','pitching']:
        stats=get(group+'.json',f'{base}/stats?stats=season&group={group}&season={year}&sportIds=1&playerPool=ALL&limit=10000')['stats'][0]
        if len(stats['splits'])!=stats['totalSplits']:raise ValueError('Incomplete annual participants')
        totals[group]={r['player']['id']:r['stat'] for r in stats['splits']}
        if len(totals[group])!=len(stats['splits']):raise ValueError('Duplicate annual participants')
        ids.update(totals[group])
    batches=[sorted(ids)[i:i+30] for i in range(0,len(ids),30)]
    def fetch_people(item):
        i,batch=item
        people=get(f'people-{i:03}.json',f'{base}/people?personIds='+','.join(map(str,batch))+f'&hydrate=stats(group=[hitting,pitching],type=[gameLog],season={year})')['people']
        if {p['id'] for p in people}!=set(batch):raise ValueError('Incomplete participants')
        return people
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        people={p['id']:p for batch in ex.map(fetch_people,enumerate(batches)) for p in batch}
    games=ordered_games(get('schedule.json',f'{base}/schedule?sportId=1&gameType=R&season={year}'))
    if any(not g['officialDate'].startswith(str(year)) for g in games):raise ValueError('Wrong schedule year')
    def fetch_game(g):
        # Retain all official runner movements for attribution and ordering checks.
        pk=g['gamePk'];return get(f'plays/{pk}.json',f'{base}/game/{pk}/playByPlay')['allPlays']
    runs=Runs();game_runs(people,games,totals,runs);counts=collections.Counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        for i,plays in enumerate(ex.map(fetch_game,games),1):
            consume_plays(plays,runs,counts)
            if i%200==0:print(f'{i}/{len(games)} games verified',flush=True)
    mismatches=verify_events(counts,totals)
    (root/'event-total-mismatches.json').write_text(json.dumps(mismatches,indent=2))
    if mismatches:raise ValueError(f'{len(mismatches)} official event totals disagree; see event-total-mismatches.json')
    records={k:runs.leaders(k,people,year) for k in GAME_KEYS+EVENT_KEYS}
    metadata={k:{'status':'verified','sources':[f'{base}/schedule?sportId=1&gameType=R&season={year}',f'{base}/stats?stats=season&group=hitting,pitching&season={year}&sportIds=1&playerPool=ALL&limit=10000'],
        'note':f'MLB公式の全{len(games)}試合・全{len(people)}選手を集計。試合別・打席別の年間合計を公式シーズン成績と照合。'} for k in records}
    for key,leaders in records.items():
        for r in leaders:
            url=f"{base}/people/{r['player_id']}/stats?stats=gameLog&group=hitting,pitching&season={year}"
            r['source_url']=url;metadata[key]['sources'].append(url)
    records['scoreless_innings']=[]
    metadata['scoreless_innings']={'status':'unavailable','sources':[], 'note':'失点時点と継承走者を含む公式の年度内最長無失点投球回は未確認。'}
    snapshot={'checked_at':datetime.now(timezone.utc).isoformat(),'note':f'{year}年度内・MLBレギュラーシーズンのみ。',
        'records':records,'categories':metadata,'audit':{'games':len(games),'participants':len(people),'event_total_mismatches':0},
        'evidence_sha256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.glob('*.json')) if not p.name.endswith('mismatches.json')},
        'plays_sha256':hashlib.sha256(''.join(hashlib.sha256((root/'plays'/f"{g['gamePk']}.json").read_bytes()).hexdigest() for g in games).encode()).hexdigest()}
    target=pathlib.Path('data/records.json');data=json.loads(target.read_text());data['mlb'].setdefault('current_streaks',{})[str(year)]=snapshot
    temp=target.with_suffix('.json.tmp');temp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');temp.replace(target)
    print(json.dumps({k:[(r['name'],r['value']) for r in v] for k,v in records.items()},ensure_ascii=False))

if __name__=='__main__':main()
