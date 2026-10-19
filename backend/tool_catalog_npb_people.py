"""Enrich uniform history with NPB official surnames and current NPB/OB classification."""
import json,re,concurrent.futures,unicodedata
from tool_refresh_baseball_catalog import fetch,text,ROOT

def key(s):return re.sub(r'[\s　・･.]','',unicodedata.normalize('NFKC',s)).replace('髙','高').replace('﨑','崎')
def main():
 index=fetch('https://npb.jp/bis/players/all/index.html','npb-all-index')
 pages=sorted(set(re.findall(r'index_[a-z]+\.html',index)))
 def read(page):
  body=fetch('https://npb.jp/bis/players/all/'+page,'npb-people-'+page)
  rows=[]
  for pid,cls,inner in re.findall(r'<a href="/bis/players/(\d+)\.html" class="([^"]*player_unit[^"]*)">(.*?)</a>',body,re.S):
   m=re.search(r'<dd class="name">(.*?)</dd>',inner,re.S)
   if not m:continue
   name=text(m[1]);pos=re.search(r'<dd class="pos">(.*?)</dd>',inner,re.S);team=re.search(r'<dd class="team">(.*?)</dd>',inner,re.S)
   rows.append(dict(name=name,surname=re.split(r'[\s　]+',name)[0],status='npb_ob' if 'old_player' in cls else 'active',npb_id=pid,number=(re.search(r'\d+',text(pos[1]))[0] if pos and re.search(r'\d+',text(pos[1])) else None),team=text(team[1]) if team else None))
  return rows
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:people=[r for batch in ex.map(read,pages) for r in batch]
 p=ROOT/'data/baseball-catalog.json';d=json.loads(p.read_text());d['npb_people']=people
 # NPB OB includes active MLB players. Recognize these before calling anyone retired.
 mlb_names={key(r['name']) for r in d.get('mlb_uniforms',[]) if r['status']=='active'}
 combined=json.loads((ROOT/'data/combined_career_records.json').read_text())
 active_abroad={key(r['name']) for r in combined.get('players',[]) if r.get('active') is True}
 people_by_name={key(r['name']):r for r in people}
 for r in d['uniforms']:
  person=people_by_name.get(key(r['name']))
  if person:
   r['surname']=person['surname']
   # Old NPB status is not proof of retirement: former NPB players may play abroad/independent leagues.
   r['status']='active' if person['status']=='active' or key(r['name']) in active_abroad else 'unknown'
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n');print('NPB people',len(people),'matched uniforms',sum('surname' in r for r in d['uniforms']))
if __name__=='__main__':main()
