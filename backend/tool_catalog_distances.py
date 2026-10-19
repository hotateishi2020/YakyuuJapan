"""Compute clearly labelled straight-line distances from public coordinate snapshots.
Inputs: /tmp/koko-catalog/airports.csv (OurAirports) and optional stations.json (OSM Overpass).
Airport set is restricted to scheduled airline airports; heliports/seaplane bases excluded.
"""
import csv,json,math,pathlib
ROOT=pathlib.Path(__file__).resolve().parent
CACHE=pathlib.Path('/tmp/koko-catalog')
def distance(lat,lon,a,b):
 p,q=math.radians(lat),math.radians(a)
 h=math.sin((q-p)/2)**2+math.cos(p)*math.cos(q)*math.sin(math.radians(b-lon)/2)**2
 return 6371.0088*2*math.asin(min(1,math.sqrt(h)))
def main():
 p=ROOT/'data/stadium-catalog.json';data=json.loads(p.read_text())
 airports=[r for r in csv.DictReader((CACHE/'airports.csv').open()) if r['scheduled_service']=='yes' and r['type'] in ('small_airport','medium_airport','large_airport')]
 stations=[]
 if (CACHE/'stations.json').exists():
  try:stations=json.loads((CACHE/'stations.json').read_text()).get('elements',[])
  except ValueError:pass
 for r in data['stadiums']:
  lat,lon=r['latitude'],r['longitude']
  nearest=min(airports,key=lambda a:distance(lat,lon,float(a['latitude_deg']),float(a['longitude_deg'])))
  km=distance(lat,lon,float(nearest['latitude_deg']),float(nearest['longitude_deg']))
  name=nearest['name'];code=nearest['iata_code']
  r['airport_distance']=f'{name}' + (f' ({code})' if code else '') + f'：約{km:.1f}km（直線）'
  r['airport_distance_source']='https://ourairports.com/airports/'+nearest['ident']+'/'
  choices=[]
  for s in stations:
   c=s.get('center',s);t=s.get('tags',{});name=t.get('name:ja',t.get('name'))
   if name and 'lat' in c:
    km=distance(lat,lon,c['lat'],c['lon'])
    if km<=15:choices.append((km,name,s))
  if choices and not r.get('station_distance'):
   km,name,s=min(choices,key=lambda x:x[0]);r['station_distance']=f'{name}：約{km:.1f}km（直線）'
   r['station_distance_source']=f"https://www.openstreetmap.org/{s['type']}/{s['id']}"
 p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 print('airport distances',len(data['stadiums']),'station distances',sum(bool(r.get('station_distance')) for r in data['stadiums']))
if __name__=='__main__':main()
