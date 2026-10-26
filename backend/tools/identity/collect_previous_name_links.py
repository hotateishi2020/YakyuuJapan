"""Verify legacy club membership from NPB official 2025 stats, not guessed names."""
import concurrent.futures,datetime,hashlib,html,json,pathlib,re,time,unicodedata,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[2];CACHE=pathlib.Path('/tmp/koko-player-identity-http')
def get(url):
 p=CACHE/hashlib.sha256(url.encode()).hexdigest()
 if p.exists():return p.read_text()
 with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'}),timeout=25) as r:s=r.read().decode('utf-8')
 p.write_text(s);return s
def clean(s):return html.unescape(re.sub('<[^>]+>','',s)).strip()
def key(s):return re.sub(r'[\s　・･.]','',unicodedata.normalize('NFKC',s)).replace('髙','高').replace('﨑','崎')
e=json.loads((ROOT/'data/player-name-link-evidence.json').read_text());known={p['npb_id']:p for p in e['npb_roster']}
reviews=json.loads((ROOT/'data/player-identity-pending-review.json').read_text())
wanted={key(r['evidence']['name']) for r in reviews if r['review_key'].startswith('remaining:') and r['evidence']['team_id']<=12}
teams=[t for t in json.load(open('/tmp/identity_teams.json')) if t['id_league'] in (1,2) and t['url_npb_players']]
errors=[];out=[]
def page(task):
 team,kind=task;code=re.search(r'rst_(\w+)\.html',team['url_npb_players'])[1]
 url=f'https://npb.jp/bis/2025/stats/{kind}_{code}.html'
 try:
  doc=get(url);result=[]
  # Historical NPB team-stat tables omit player links. Confirm the named player
  # using the current official profile's 2025 career row for that club.
  for tr in re.findall(r'<tr[^>]*>(.*?)</tr>',doc,re.S):
   cells=re.findall(r'<td[^>]*>(.*?)</td>',tr,re.S)
   if not cells:continue
   name=clean(cells[0])
   if key(name) not in wanted:continue
   matches=[p for p in known.values() if key(p['name'])==key(name)]
   if len(matches)!=1:continue
   person=matches[0];profile=get(person['url'])
   career=[clean(row) for row in re.findall(r'<tr[^>]*>(.*?)</tr>',profile,re.S)]
   if not any('2025' in row and key(team['name_short']) in key(row).replace('読売','巨人') for row in career):continue
   result.append({**person,'team_id':team['id'],'name':name,'source':url,'profile_source':person['url'],'season':2025})
  for path,identifier,name in re.findall(r'<a[^>]*href="([^" ]*/players/(\d+)\.html)"[^>]*>(.*?)</a>',doc,re.S):
   name=clean(name)
   if key(name) not in wanted:continue
   profile_url='https://npb.jp/bis/players/'+identifier+'.html'
   date=known.get(identifier,{}).get('birth_date')
   if not date:
    profile=get(profile_url)
    m=re.search(r'(\d{4})年\s*(\d+)月\s*(\d+)日',profile)
    if not m:raise ValueError('Birth date unavailable: '+profile_url)
    date=f'{int(m[1]):04}-{int(m[2]):02}-{int(m[3]):02}'
   result.append({'team_id':team['id'],'name':name,'npb_id':identifier,'url':profile_url,'birth_date':date,'source':url,'season':2025})
  return result
 except Exception as error:errors.append({'source':url,'error':str(error)});return []
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
 for rows in ex.map(page,[(t,k) for t in teams for k in ('idb1','idp1')]):out+=rows
# A retired player/manager can be verified directly through the existing ID registry.
for link in json.loads((ROOT/'data/npb_mlb_player_ids.json').read_text())['players']:
 if link['name_en']!='Shingo Takatsu':continue
 url=f"https://npb.jp/bis/players/{link['npb_id']}.html";doc=get(url)
 if '高津' in doc and '臣吾' in doc:
  out.append({'team_id':4,'name':'高津 臣吾','npb_id':link['npb_id'],'url':url,'birth_date':link['birth_date'],'source':url,'registry_source':'https://github.com/chadwickbureau/register','mlb_id':link['mlb_id']})
# Confirm earlier club membership directly in official career rows.
manual={key('デュプランティエ'):'13715150',key('佐藤 龍世'):'81785138'}
for review in reviews:
 if not review['review_key'].startswith('remaining:') or review['evidence']['team_id']>12:continue
 name=review['evidence']['name'];team=next(t for t in teams if t['id']==review['evidence']['team_id'])
 candidates=[p for p in known.values() if key(p['name'])==key(name)]
 identifier=manual.get(key(name)) or (candidates[0]['npb_id'] if len(candidates)==1 else None)
 if not identifier:continue
 url=f'https://npb.jp/bis/players/{identifier}.html';doc=get(url)
 career=[clean(row) for row in re.findall(r'<tr[^>]*>(.*?)</tr>',doc,re.S)]
 if not any(re.search(r'(?:19|20)\d{2}',row) and key(team['name_short']) in key(row).replace('読売','巨人') for row in career):continue
 m=re.search(r'(\d{4})年\s*(\d+)月\s*(\d+)日',doc)
 if not m:continue
 date=f'{int(m[1]):04}-{int(m[2]):02}-{int(m[3]):02}'
 out.append({'team_id':team['id'],'name':name,'npb_id':identifier,'url':url,'birth_date':date,'source':url,'verified_previous_club':team['name_short']})
out=list({(p['team_id'],p['npb_id']):p for p in out}.values())
e['npb_roster']+=out;e['errors']=errors;e['previous_roster_checked_at']=datetime.datetime.now(datetime.timezone.utc).isoformat()
(ROOT/'data/player-name-link-evidence.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n')
print('verified previous roster identities',len(out),'errors',errors,flush=True)
