"""NPB official milestone ages; preserve the source's month precision."""
import concurrent.futures, datetime, html, json, pathlib, re, urllib.parse, urllib.request
ROOT=pathlib.Path(__file__).resolve().parent
BASE='https://npb.jp/history/alltime/'
def fetch(url):return urllib.request.urlopen(url,timeout=30).read().decode()
def clean(s):return html.unescape(re.sub('<[^>]+>','',s)).strip()
def read(url):
 s=fetch(url); title=re.search(r'<h4[^>]*>(.*?)</h4>',s,re.S)
 label=clean(title[1]) if title else '';out=[]
 for tr in re.findall(r'<tr\b[^>]*>(.*?)</tr>',s,re.S):
  cells=[clean(c) for c in re.findall(r'<t[dh]\b[^>]*>(.*?)</t[dh]>',tr,re.S)]
  age=next((re.fullmatch(r'(\d+)歳(\d+)カ月',c) for c in cells if re.fullmatch(r'(\d+)歳(\d+)カ月',c)),None)
  date=next((c for c in cells if re.fullmatch(r'\d{4}\.\d{1,2}\.\d{1,2}',c)),None)
  if not age or not date or len(cells)<4:continue
  ageindex=cells.index(age[0]);rank=cells[ageindex+1] if len(cells)>ageindex+1 else ''
  out.append(dict(label=label,name=cells[1],team=cells[2],date=date,year=int(date[:4]),age_label=age[0],age_months=int(age[1])*12+int(age[2]),age_order=rank,source=url))
 return out
if __name__=='__main__':
 urls=set()
 for side in ['b','p']:
  for link in re.findall(r'href="([^"]+)',fetch(BASE+f'index_{side}.html')):
   if 'milestones_' in link and '/history/2026/' not in link and 'team_' not in link:urls.add(urllib.parse.urljoin(BASE,link))
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool: rows=[r for group in pool.map(read,sorted(urls)) for r in group]
 assert len(rows)>100
 p=ROOT/'data/age-records.json';p.write_text(json.dumps(dict(checked_at=datetime.date.today().isoformat(),rows=rows),ensure_ascii=False,indent=2)+'\n');print('Milestone age entries:',len(rows),'categories:',len({r['label'] for r in rows}))
