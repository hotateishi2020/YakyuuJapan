"""Audit all 12 NPB clubs, independently of the national leaderboard.
Run from backend: python3 tool_refresh_club_streaks.py YEAR --cache DIRECTORY
A fresh cache is required for a new observation date. Updates only club snapshots.
"""
import unicodedata
import argparse, concurrent.futures, hashlib, html, json, pathlib, re, urllib.request
from datetime import datetime, timezone
from tool_refresh_npb_streaks import TEAMS, UNKNOWN, table_rows, audit_steals

CLUB_KEYS = ['hit_games','hr_games','onbase_games','hit_pa','hr_pa','onbase_pa',
             'wins','holds','saves','scoreless_games']

def normalize(s):return re.sub(r'^[*+]|[\s\u3000]','',unicodedata.normalize('NFKC',s)).replace('髙','高')

def batting_log_maxima(body, official, year):
 if f'{year}年度版' not in body:raise ValueError('Wrong batting-log year')
 rows=[r for r in table_rows(body) if len(r)==26 and re.fullmatch(r'\d+/\d+',r[0])]
 dates=[tuple(map(int,r[0].split('/'))) for r in rows]
 if dates!=sorted(set(dates)):raise ValueError('Batting log order is ambiguous')
 runs={k:0 for k in ['hit_games','hr_games','onbase_games','hit_pa','hr_pa','onbase_pa']};best=dict(runs)
 pa=hits=homers=walks=0
 def add(k,yes):
  runs[k]=runs[k]+1 if yes else 0;best[k]=max(best[k],runs[k])
 for r in rows:
  tokens=r[25].split();dayhits=dayhr=daywalks=0
  for token in tokens:
   token=re.sub(r'\(.*?\)','',token)
   hit=bool(re.search(r'(安|２|３|本)$',token));hr=token.endswith('本');walk=token in ['四球','死球','敬遠','故意四']
   dayhits+=hit;dayhr+=hr;daywalks+=walk
   for k,yes in [('hit_pa',hit),('hr_pa',hr),('onbase_pa',hit or walk)]:add(k,yes)
  if dayhits!=int(r[12]) or dayhr!=int(r[13]):raise ValueError('Unknown batting result token: '+repr(r))
  if int(r[10])>0 or any('犠飛' in t for t in tokens):add('hit_games',dayhits>0)
  if tokens:
   add('onbase_games',dayhits+daywalks>0);add('hr_games',dayhr>0)
  pa+=len(tokens);hits+=dayhits;homers+=dayhr;walks+=daywalks
 if (len(rows),sum(int(r[17]) for r in rows),sum(int(r[18]) for r in rows),pa,hits,homers,walks)!=(int(official[1]),int(official[11]),int(official[12]),int(official[2]),int(official[5]),int(official[8]),int(official[15])+int(official[17])):
  raise ValueError('Batting-log totals disagree with NPB annual stats')
 return best
def appearance_leaders(get, batters, jobs, code, year):
 league=0 if code in ['T','DB','G','D','C','S'] else 1
 logs={};sources={};dates=set()
 def log(player):
  n=player['name']
  if n in logs:return logs[n]
  paths=[u for c,fp,p,u in jobs if c==code and fp==0 and p==n]
  if len(paths)!=1:raise ValueError(f'Unknown appearance candidate {code} {n}')
  number=paths[0].split('/')[-1].removesuffix('_stat.htm')
  url=f'https://nf3.sakura.ne.jp/php/stat_disp/stat_disp.php?fpnum={number}&leg={league}&mon=0&tm={code}&vst=all&y=0'
  body=get(url)
  if f'{year}年度版' not in body:raise ValueError('Wrong appearance-log year')
  rows=[r for r in table_rows(body) if len(r)==26 and re.fullmatch(r'\d+/\d+',r[0])]
  played=[tuple(map(int,r[0].split('/'))) for r in rows]
  if len(played)!=player['gp'] or len(set(played))!=len(played):raise ValueError(f'Appearance totals disagree: {code} {n}')
  logs[n]=set(played);sources[n]=url;return logs[n]
 ordered=sorted(batters,key=lambda p:-p['gp'])
 for p in ordered:
  dates.update(log(p))
  if len(dates)==143:break
 if len(dates)!=143:raise ValueError(f'Incomplete 143-game club calendar {code}: {len(dates)}')
 best=0;leaders=[]
 for p in ordered:
  if p['gp']<best:break
  played=log(p);run=peak=0
  for day in sorted(dates):
   run=run+1 if day in played else 0;peak=max(peak,run)
  if peak>best:best=peak;leaders=[]
  if peak==best:leaders.append({'name':p['name'],'team':TEAMS[code],'team_code':code,'year':year,'value':peak,'source_url':sources[p['name']],'status':'active'})
 return leaders

def pitching_log_maxima(body,official,year):
 if f'{year}年度版' not in body:raise ValueError('Wrong pitching-log year')
 rows=[r for r in table_rows(body) if len(r)==28 and re.fullmatch(r'\d+/\d+',r[0])]
 dates=[tuple(map(int,r[0].split('/'))) for r in rows]
 if dates!=sorted(set(dates)):raise ValueError('Pitching log order is ambiguous')
 actual=(len(rows),sum(r[8]=='○' for r in rows),sum(r[8]=='●' for r in rows),sum(r[8]=='S' for r in rows),sum(r[8]=='H' for r in rows),sum(int(r[16]) for r in rows),sum(int(r[14]) for r in rows))
 expected=tuple(int(official[i]) for i in [1,2,3,4,5,21,18])
 if actual!=expected:raise ValueError(f'Pitching totals disagree: {official[0]} {actual} != {expected}')
 runs={k:0 for k in ['wins','saves','holds','scoreless_games']};best=dict(runs)
 for r in rows:
  for k,yes,skip in [('wins',r[8]=='○',r[8] not in ['○','●']),('saves',r[8]=='S',False),('holds',r[8]=='H',False),('scoreless_games',int(r[16])==0,False)]:
   if skip:continue
   runs[k]=runs[k]+1 if yes else 0;best[k]=max(best[k],runs[k])
 return best

def main():
 ap=argparse.ArgumentParser();ap.add_argument('year',type=int);ap.add_argument('--cache',type=pathlib.Path,required=True)
 args=ap.parse_args();year=args.year;cache=args.cache;cache.mkdir(parents=True,exist_ok=True);evidence={}
 def get(url):
  path=cache/(hashlib.sha256(url.encode()).hexdigest()+'.html')
  if path.exists():raw=path.read_bytes()
  else:
   raw=urllib.request.urlopen(url,timeout=60).read();path.write_bytes(raw)
  evidence[url]=hashlib.sha256(raw).hexdigest();return raw.decode('utf-8')
 for league in ['c','p']:
  rows=table_rows(get(f'https://npb.jp/bis/{year}/stats/std_{league}.html'))
  if len([r for r in rows if len(r)>5 and '143' in r[:4]])!=6:raise ValueError('Incomplete official season')
 order_path=pathlib.Path(f'data/streak-steal-orders-{year}.json')
 order_data=json.loads(order_path.read_text()) if order_path.exists() else {'year':year,'orders':{}}
 if order_data['year']!=year:raise ValueError('Wrong event-order year')
 jobs=[];batters={c:[] for c in TEAMS};tasks=[]
 for code in TEAMS:
  league=0 if code in ['T','DB','G','D','C','S'] else 1
  for fp,role in [(0,'f'),(1,'p')]:
   url=f'https://nf3.sakura.ne.jp/php/stat_disp/stat_disp.php?y=0&leg={league}&tm={code}&fp={fp}&dn=1&dk=0'
   body=get(url)
   links={u:normalize(html.unescape(re.sub('<[^>]+>','',n))) for u,n in re.findall(r"href=['\"]([^'\"]*/"+role+r"/[^'\"]*_stat.htm)['\"][^>]*>(.*?)</a>",body,re.S)}
   paths={n:'https://nf3.sakura.ne.jp/'+u.removeprefix('./') for u,n in links.items()}
   if len(paths)!=len(links):raise ValueError('Ambiguous player names')
   jobs.extend((code,fp,n,u) for n,u in paths.items())
   official_url=f'https://npb.jp/bis/{year}/stats/id{"p" if fp else "b"}1_{code.lower()}.html'
   official_body=get(official_url)
   if str(year) not in official_body:raise ValueError('Wrong official year')
   rows=[r for r in table_rows(official_body) if len(r)==(24 if fp else 23) and r[1].isdigit() and int(r[1])>0]
   if not rows:raise ValueError('No official participants')
   for r in rows:
    n=normalize(r[0])
    if n not in paths:raise ValueError(f'Unresolved participant: {code} {fp} {n}')
    number=paths[n].split('/')[-1].removesuffix('_stat.htm')
    url=(f'https://nf3.sakura.ne.jp/php/stat_disp/stat_disp.php?y=0&leg={league}&pcnum={number}&tm={code}&mon=0&vst=all' if fp else
      f'https://nf3.sakura.ne.jp/php/stat_disp/stat_disp.php?fpnum={number}&leg={league}&mon=0&tm={code}&vst=all&y=0')
    tasks.append((code,fp,n,url,r))
    if not fp:batters[code].append({'name':n,'code':code,'gp':int(r[1]),'sb':int(r[11]),'cs':int(r[12]),'official':official_url})
 def fetch(task):
  code,fp,n,url,annual=task;body=get(url)
  try:values=pitching_log_maxima(body,annual,year) if fp else batting_log_maxima(body,annual,year)
  except ValueError as e:raise ValueError(f'{code} {n}: {e}') from e
  return code,fp,n,url,values
 players=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
  for i,p in enumerate(ex.map(fetch,tasks),1):
   players.append(p)
   if i%50==0:print(f'{i}/{len(tasks)} official participants verified',flush=True)
 clubs={c:{'records':{},'categories':{}} for c in TEAMS}
 for code,club in clubs.items():
  for key in sorted(CLUB_KEYS):
   pool=[(n,u,v[key]) for c,fp,n,u,v in players if c==code and key in v];maximum=max(v for n,u,v in pool)
   club['records'][key]=[{'name':n,'team':TEAMS[code],'team_code':code,'value':v,'year':year,'source_url':u,'status':'active'} for n,u,v in pool if v==maximum and v>0]
   club['categories'][key]={'status':'verified','note':'NPB公式の全出場選手を母集団に、試合別成績を年度内で再集計。公式年間合計と照合し同率を全員保持。','sources':sorted({u for n,u,v in pool if v==maximum})}
  club['records']['appearances']=appearance_leaders(get,batters[code],jobs,code,year)
  club['categories']['appearances']={'status':'verified','note':'NPB公式年間出場数と試合別出場を照合。143試合の日程で欠場を区切り年度内最長を計算。','sources':[r['source_url'] for r in club['records']['appearances']]}
  try:
   leaders,checked=audit_steals(get,[p for p in batters[code] if p['sb']>0],year,orders=order_data['orders'])
   club['records']['steals']=leaders;club['steals_audit']=checked
   club['categories']['steals']={'status':'verified','note':'公式年間盗塁・盗塁死と試合別合計を照合。同日内で順序により首位が変わるケースは試合経過で実際の順序を確認。','sources':list({u for p in checked for u in [p['source_url'],p['official'],*p['event_order_sources']]})}
  except ValueError as e:
   if not str(e).startswith('Steal event order'):raise
   club['records']['steals']=[];club['steals_pending']=str(e)
   club['categories']['steals']={'status':'unavailable','note':'同じ試合内の盗塁成功と盗塁死の順序により首位が変わるため、プレー順の照合が必要。','sources':[]}
  for k,note in UNKNOWN.items():club['records'][k]=[];club['categories'][k]={'status':'unavailable','note':note,'sources':[]}
  print(code,{k:[(r['name'],r['value']) for r in v] for k,v in club['records'].items()},flush=True)
 display={(c,normalize(r[0])):re.sub(r'^[*+]|[\s\u3000]','',r[0]) for c,fp,n,u,r in tasks}
 for c,club in clubs.items():
  for records in club['records'].values():
   for row in records:row['name']=display[c,normalize(row['name'])]
 snapshot={'year':year,'checked_at':datetime.now(timezone.utc).isoformat(),'note':'球団別に全出場選手の年度内最長を試合順から再計算。','clubs':clubs,'player_team_roles':len(players),'resolved_steal_orders':order_data,'evidence_sha256':evidence}
 path=pathlib.Path('data/records.json');data=json.loads(path.read_text());data['npb'].setdefault('club_current_streaks',{})[str(year)]=snapshot
 tmp=path.with_suffix('.json.tmp');tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');tmp.replace(path)

if __name__=='__main__':main()
