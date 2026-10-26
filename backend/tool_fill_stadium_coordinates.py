"""Fill missing coordinates from NPB's official stadium JSON; retain provenance."""
import concurrent.futures, json, pathlib, re, urllib.request
path=pathlib.Path(__file__).parent/'data/stadium-catalog.json'
data=json.loads(path.read_text())
def fill(row):
    match=re.search(r'(?:json/|detail.html\?)(\d+)',row.get('source',''))
    if row.get('latitude') is not None or not match: return
    url=f'https://npb.jp/stadium/json/{match[1]}.json'
    try:
        info=json.loads(urllib.request.urlopen(url,timeout=20).read())
        lat,lon=float(info['lat']),float(info['lng'])
        if not (-85<=lat<=85 and -180<=lon<=180): return
        row.update(latitude=lat,longitude=lon,coordinates_source=url)
        row['aliases']=list(dict.fromkeys(row.get('aliases',[])+[v for v in [info.get('alias'),info.get('name')] if v]))
    except Exception as e: print(row['name'],type(e).__name__)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool: list(pool.map(fill,data['stadiums']))
path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
print('Coordinates:',sum(r.get('latitude') is not None for r in data['stadiums']))
