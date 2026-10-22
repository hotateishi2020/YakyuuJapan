"""Build a compact birth-country/identity index from official MLB people records."""
import concurrent.futures
import datetime
import json
from pathlib import Path
import urllib.request
from refresh_wbc_flags import COUNTRIES

ROOT = Path(__file__).resolve().parents[1] / 'data'
COUNTRIES.update({'USA':'US','D.R.':'DO','Curacao':'CW','Curaçao':'CW','Aruba':'AW',
                 'United Kingdom':'GB','Republic of Korea':'KR','DOM':'DO','VEN':'VE','Canary Islands':'ES','Czechoslovakia':'CZ','Guatemala':'GT','Mongolia':'MN','Peru':'PE','Saint Martin':'MF','Singapore':'SG','Slovakia':'SK','South Korea':'KR','Taiwan':'TW','Viet Nam':'VN','Vietnam':'VN',
                 'Hong Kong':'HK','Honduras':'HN','Bahamas':'BS','U.S. Virgin Islands':'VI',
                 'Saudi Arabia':'SA','Belgium':'BE','Indonesia':'ID'})
def get(url):
 with urllib.request.urlopen(url,timeout=45) as r:return json.load(r)
def fetch(ids):
 return get('https://statsapi.mlb.com/api/v1/people?personIds='+','.join(ids))['people']
if __name__ == '__main__':
 year=datetime.date.today().year
 people=get(f'https://statsapi.mlb.com/api/v1/sports/1/players?season={year}')['people']
 by_id={str(p['id']):p for p in people}
 ids=sorted({r['source_player_id'] for r in json.loads((ROOT/'wbc_appearances.json').read_text())['appearances']} - set(by_id))
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
  for group in pool.map(fetch,[ids[i:i+100] for i in range(0,len(ids),100)]):
   by_id.update({str(p['id']):p for p in group})
 rows=[]
 for key,p in by_id.items():
  code=COUNTRIES.get(p.get('birthCountry',''),'')
  rows.append({'source_player_id':key,'name':p['fullName'], 'last_name':p.get('lastName',''),
               'birth_date':p.get('birthDate',''),'birth_country':p.get('birthCountry',''),
               'emoji_country':''.join(chr(ord(c)+127397) for c in code),
               'source':f'https://statsapi.mlb.com/api/v1/people/{key}'})
 (ROOT/'mlb_country_profiles.json').write_text(json.dumps({'checked_at':datetime.date.today().isoformat(),'players':rows},ensure_ascii=False,indent=2)+'\n')
 print('Profiles',len(rows),'unknown countries',sorted({p['birth_country'] for p in rows if not p['emoji_country']}))
