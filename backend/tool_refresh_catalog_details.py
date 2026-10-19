"""Public catalog details. Uses local snapshots; no database writes."""
import json, re, pathlib, concurrent.futures
from tool_refresh_baseball_catalog import fetch, text, ROOT

def main():
 p=ROOT/'data/baseball-catalog.json'; d=json.loads(p.read_text()); d['year']=2026
 d['mlb_hall']=[dict(name=r['player']['nameFirstLast'],year=int(r['season']),category=r.get('notes','殿堂入り')) for r in json.loads(fetch('https://statsapi.mlb.com/api/v1/awards/MLBHOF/recipients','mlb-hall'))['awards'] if 'player' in r]
 d['active_career']=[]
 for key,label,suffix in [('hits','安打','b_h'),('wins','勝利','p_w'),('saves','セーブ','p_sv')]:
  rows=[]; url='https://npb.jp/bis/history/ac'+suffix+'.html'
  for tr in re.findall(r'<tr\b[^>]*>(.*?)</tr>',fetch(url,'active-'+key),re.S):
   cells=[text(c) for c in re.findall(r'<td\b[^>]*>(.*?)</td>',tr,re.S)]
   if len(cells)>=3 and cells[0].isdigit() and cells[2].isdigit():rows.append(dict(name=cells[1],value=int(cells[2]),status='active'))
  assert len(rows)>10
  d['active_career'].append(dict(key=key,label=label,leaders=rows,source=url))
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
 franchise=fetch('https://npb.jp/stadium/franchise.html','franchise')
 ids=list(dict.fromkeys(re.findall(r'detail.html\?(\d+)',franchise)))
 def stadium(id):
  url=f'https://npb.jp/stadium/json/{id}.json'; r=json.loads(fetch(url,'stadium-'+id))
  name=r['alias']; category='屋外球場'
  if any(x in name for x in ['エスコン','PayPay']):category='開閉式ドーム'
  elif 'ドーム' in name:category='固定屋根（側面開放）' if 'ベルーナ' in name else 'ドーム球場'
  capacity={'東京ドーム':'約43,500人（野球時）','阪神甲子園球場':'47,359人'}.get(name)
  return dict(match=name,name=name,team=r['team'],category=category,completed=None,opened=r.get('open'),capacity=capacity,source=url)
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:stadiums=list(ex.map(stadium,ids))
 # Do not substitute opening dates for completion dates, or club revenue for venue revenue.
 target=ROOT/'data/stadium-catalog.json'
 if target.exists():
  previous=json.loads(target.read_text())['stadiums']; by_name={r['match']:r for r in previous}
  stadiums=[{**r,**by_name.get(r['match'],{})} for r in stadiums]+[r for r in previous if r.get('org')=='mlb']
 target.write_text(json.dumps(dict(stadiums=stadiums),ensure_ascii=False,indent=2)+'\n')
 print('active career:',sum(len(r['leaders']) for r in d['active_career']),'MLB hall:',len(d['mlb_hall']),'stadiums:',len(stadiums))
if __name__=='__main__':main()
