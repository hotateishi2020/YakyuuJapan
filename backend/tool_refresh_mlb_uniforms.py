"""Import MLB all-time roster numbers and verified team-tenure years from StatsAPI.
The all-time endpoint supplies one registered number per player/team, not every number change.
"""
import concurrent.futures,json
from tool_refresh_baseball_catalog import fetch,ROOT
FIELDS='roster,jerseyNumber,parentTeamId,person,id,fullName,lastName,active,stats,splits,season,team'
def main():
 teams=json.loads(fetch('https://statsapi.mlb.com/api/v1/teams?sportId=1&season=2026','mlb-teams'))['teams']
 def read(t):
  url=f"https://statsapi.mlb.com/api/v1/teams/{t['id']}/roster?rosterType=allTime&hydrate=person(stats(group=%5Bhitting,pitching%5D,type=%5ByearByYear%5D))&fields={FIELDS}"
  rows=json.loads(fetch(url,'mlb-history-'+str(t['id'])))['roster']; result=[]
  for r in rows:
   p=r['person']; n=r.get('jerseyNumber',''); years=sorted({int(s['season']) for g in p.get('stats',[]) for s in g.get('splits',[]) if s.get('team',{}).get('id')==t['id']})
   if not n.isdigit() or not years:continue
   result.append(dict(player_key='mlb:'+str(p['id']),name=p['fullName'],surname=p.get('lastName',p['fullName']),number=n,source_team_id=t['id'],team=t['name'],first_year=min(years),last_year=max(years),status='active' if p.get('active') else 'retired',source=url))
  print(t['name'],len(result),flush=True);return result
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:rows=[r for batch in pool.map(read,teams) for r in batch]
 p=ROOT/'data/baseball-catalog.json';d=json.loads(p.read_text());d['mlb_uniforms']=rows;p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n');print('MLB total',len(rows))
if __name__=='__main__':main()
