"""Collect observed abbreviations and official NPB roster IDs (no DB writes)."""
import concurrent.futures, datetime, hashlib, html, json, pathlib, re, time, urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[2]
CACHE=pathlib.Path('/tmp/koko-player-identity-http');CACHE.mkdir(exist_ok=True)
def get(url):
 p=CACHE/hashlib.sha256(url.encode()).hexdigest()
 if p.exists():return p.read_text()
 for attempt in range(3):
  try:
   with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'}),timeout=25) as r:s=r.read().decode('utf-8')
   p.write_text(s);return s
  except Exception:
   if attempt==2:raise
   time.sleep(2)
def clean(s):return html.unescape(re.sub('<[^>]+>','',s)).strip()
links=[];npb=[];errors=[]
def rank(url):
 try:
  doc=get(url);out=[]
  for member in re.findall(r'<p class="bb-playerTable__member"[^>]*>(.*?)</p>',doc,re.S):
   for link,name in re.findall(r'<a[^>]+href="([^"]*/mlb/player/\d+[^" ]*)"[^>]*>(.*?)</a>',member,re.S):
    out.append({'name':clean(name),'yahoo_id':re.search(r'/player/(\d+)',link)[1],'source':url})
  return out
 except Exception as e:errors.append({'source':url,'error':str(e)});return []
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
 for rows in ex.map(rank,json.load(open('/tmp/identity_ranking_urls.json'))):links+=rows
print('ranking aliases',len(links),flush=True)
def roster(team):
 url=team['url_npb_players']
 try:
  doc=get(url);out=[]
  for tr in re.findall(r'<tr class="rosterPlayer"[^>]*>(.*?)</tr>',doc,re.S):
   cells=re.findall(r'<td[^>]*>(.*?)</td>',tr,re.S)
   if len(cells)<7:continue
   link=re.search(r'href="(/bis/players/(\d+)\.html)"',cells[1])
   if not link:continue
   date=clean(cells[2]).replace('.','-')
   if not re.fullmatch(r'\d{4}-\d{2}-\d{2}',date):continue
   out.append({'team_id':team['id'],'name':clean(cells[1]),'npb_id':link[2],'url':'https://npb.jp'+link[1],'birth_date':date,'source':url})
  return out
 except Exception as e:errors.append({'source':url,'error':str(e)});return []
current=[t for t in json.load(open('/tmp/identity_teams.json')) if t['id_league'] in (1,2) and t['url_npb_players']]
teams=current
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
 for rows in ex.map(roster,teams):npb+=rows
links=list({(p['yahoo_id'],p['name']):p for p in links}.values())
(ROOT/'data/player-name-link-evidence.json').write_text(json.dumps({'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'mlb_aliases':links,'npb_roster':npb,'errors':errors},ensure_ascii=False,indent=2)+'\n')
print('DONE',len(links),'MLB aliases',len(npb),'NPB profiles',len(errors),'errors',flush=True)
