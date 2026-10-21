"""Refresh public hall/member and NPB uniform history snapshots (no DB writes).
Run with python3 backend/tool_refresh_baseball_catalog.py. Downloads are cached.
"""
import concurrent.futures, datetime, html, json, pathlib, re, subprocess, time
from tool_enrich_meikyukai_dates import enrich
ROOT = pathlib.Path(__file__).resolve().parent
CACHE = pathlib.Path('/tmp/koko-catalog'); CACHE.mkdir(exist_ok=True)
def text(s): return html.unescape(re.sub('<[^>]+>', '', s)).strip()
def fetch(url, key):
 p = CACHE / (key + '.html')
 if not p.exists():
  temporary = p.with_suffix('.part')
  subprocess.run(['curl','-sS','-L','--fail','--max-time','40',url,'-o',str(temporary)],check=True)
  temporary.replace(p)
  time.sleep(.2)
 return p.read_text()
def build():
 hall=[]
 for row in re.findall(r'<tr\b[^>]*>(.*?)</tr>',fetch('https://baseball-museum.or.jp/hall-of-famers/list/search/','hall'),re.S):
  cells=[text(c) for c in re.findall(r'<td\b[^>]*>(.*?)</td>',row,re.S)]
  if len(cells)<6:continue
  hall.append(dict(name=cells[3],year=int(re.search(r'\d{4}',cells[1])[0]),category=cells[2]))
 members={}
 for url,body in re.findall(r'<a\b[^>]*href="(https://meikyukai.jp/members/(?:batter|pitcher|honor)/[^"/]+/)"[^>]*>(.*?)</a>',fetch('https://meikyukai.jp/members-all/','members'),re.S):
  name=text(body)
  if name and name!='Read More' and '<img' not in body: members[url]=dict(name=name,source=url)
 def number(n):
  url=f'https://npb-meikan.jp/number-{n}/'
  
  try: s=fetch(url,'uniform-'+n)
  except subprocess.CalledProcessError:
   if n=='00': return []
   raise
  out=[]
  for pid,name,desc in re.findall(r'<a\b[^>]*href="https://npb-meikan.jp/(\d+)/"[^>]*>\s*<strong>(.*?)</strong>\s*<p>(.*?)</p>',s,re.S):
   desc=text(desc); years=re.findall(r'\d{4}',desc)
   if not years:continue
   team=re.split(r'[\s\u3000]+(?=\d{4})',desc)[0]
   out.append(dict(player_key='meikan:'+pid,name=text(name),number=n,team=team,first_year=int(years[0]),last_year=int(years[-1]),source=url))
  if not out and n != '00': raise ValueError('No uniform rows: '+url)
  return out
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
  uniforms=[row for group in ex.map(number,['00']+[str(i) for i in range(100)]) for row in group]
 data=dict(checked_at=datetime.date.today().isoformat(),hall=hall,members=list(members.values()),uniforms=uniforms,
  sources=['https://baseball-museum.or.jp/hall-of-famers/list/search/','https://meikyukai.jp/members-all/','https://npb-meikan.jp/number/'])
 assert len(hall)>200 and len(members)>50 and len(uniforms)>10000
 target=ROOT/'data/baseball-catalog.json'
 if target.exists():
  old=json.loads(target.read_text())
  previous_members={r['source']:r for r in old.get('members',[]) if r.get('source')}
  data['members']=[{**previous_members.get(r['source'],{}),**r} for r in data['members']]
  data['uniforms'] += [r for r in old.get('uniforms',[]) if r.get('registration')=='育成']; data={**old,**data}
 enrich(data['members'], fetch('https://ja.wikipedia.org/wiki/日本プロ野球名球会',
                              'membership-dates-'+datetime.date.today().isoformat()))
 target.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 print(f'hall={len(hall)} members={len(members)} uniform tenures={len(uniforms)}')
if __name__=='__main__': build()
