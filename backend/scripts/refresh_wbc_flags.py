"""Refresh actual WBC appearances from MLB's official statistics (no roster guesses)."""
import concurrent.futures
import datetime
import json
from pathlib import Path
import urllib.request

COUNTRIES = {'Australia':'AU','Canada':'CA','China':'CN','Chinese Taipei':'TW',
 'Colombia':'CO','Cuba':'CU','Czechia':'CZ','Czech Republic':'CZ',
 'Dominican Republic':'DO','Great Britain':'GB','Israel':'IL','Italy':'IT',
 'Spain':'ES','Germany':'DE','France':'FR','Pakistan':'PK','Argentina':'AR','New Zealand':'NZ','Philippines':'PH','Japan':'JP','Kingdom of the Netherlands':'NL','Netherlands':'NL','Korea':'KR',
 'Mexico':'MX','Nicaragua':'NI','Panama':'PA','Puerto Rico':'PR',
 'United States':'US','Venezuela':'VE','South Africa':'ZA','Brazil':'BR'}

def fetch(pair):
 year, stage = pair
 url = (f'https://statsapi.mlb.com/api/v1/stats?stats=season&group=hitting,pitching,fielding'
        f'&sportIds=51&season={year}&gameType={stage}&limit=2000&playerPool=ALL')
 with urllib.request.urlopen(url, timeout=45) as response:
  data = json.load(response)
 rows = []
 for group in data['stats']:
  assert group['totalSplits'] == len(group['splits']), 'Truncated official response'
  for row in group['splits']:
   if row['stat'].get('gamesPlayed',0) <= 0 or row.get('league',{}).get('name') != 'WBC':
    continue
   country = COUNTRIES[row['team']['name']]
   rows.append({'source_player_id':str(row['player']['id']), 'name':row['player'].get('fullName',''),
                'country_code':country, 'year':year, 'tournament':'WBC', 'source':url})
 return rows

if __name__ == '__main__':
 years = [y for y in (2006,2009,2013,2017,2023,2026) if y <= datetime.date.today().year]
 pairs = [(y,s) for y in years for s in ('F','D','L','W')]
 records = {}
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
  for rows in pool.map(fetch,pairs):
   for row in rows:
    records[(row['source_player_id'],row['year'],row['country_code'])] = row
 result = {'checked_at':datetime.date.today().isoformat(), 'appearances':sorted(records.values(),key=lambda r:(r['source_player_id'],r['year']))}
 path = Path(__file__).resolve().parents[1] / 'data/wbc_appearances.json'
 path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print(f'Saved {len(records)} player/tournament appearances')
