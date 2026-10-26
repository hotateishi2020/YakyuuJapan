"""Read-only collection. Resumable HTTP cache; never transliterate/guess a name."""
import concurrent.futures, datetime, html, json, pathlib, re, time, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[2]
CACHE = pathlib.Path('/tmp/koko-player-identity-http'); CACHE.mkdir(exist_ok=True)
def get(url):
    import hashlib
    path = CACHE / hashlib.sha256(url.encode()).hexdigest()
    if path.exists(): return path.read_text()
    for attempt in range(3):
        try:
            req=urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0'})
            with urllib.request.urlopen(req,timeout=25) as r: text=r.read().decode('utf-8')
            path.write_text(text); return text
        except Exception:
            if attempt==2: raise
            time.sleep(2)
def clean(text): return html.unescape(re.sub('<[^>]+>', '', text)).strip()
players=json.load(open('/tmp/player_identity_audit.json'))
teams=json.load(open('/tmp/identity_teams.json'))
top=get('https://baseball.yahoo.co.jp/mlb/teams')
team_urls=dict(re.findall(r'href="(/mlb/teams/\d+/top)">([^<]+)',top))
rosters=[]
def roster(entry):
    path,name=entry; url='https://baseball.yahoo.co.jp'+path.replace('/top','/players')
    doc=get(url)
    title=clean(re.search(r'<title>(.*?)</title>',doc,re.S)[1]).replace('ブリュワーズ','ブルワーズ')
    matches=[t for t in teams if t['name_short'] in title or t['name_full'] in title]
    team=matches[0]['id'] if len(matches)==1 else None
    result=[]
    for link,body in re.findall(r'<a class="bb-playerList__link" href="([^"]+)"[^>]*>(.*?)</a>',doc,re.S):
        n=re.search(r'class="bb-playerList__name">(.*?)</p>',body,re.S)
        if n: result.append({'url':'https://baseball.yahoo.co.jp'+link,'name':clean(n[1]),'team_id':team,'roster_source':url})
    return result
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
    for rows in ex.map(roster,team_urls.items()):rosters.extend(rows)
by_url={re.sub(r'/top/?$','/',p['url']):p for p in rosters}
for p in players:
    if p['id_league'] in (3,4) and p['last_year']==2026 and '/mlb/player/' in (p['url'] or ''):
        url=re.sub(r'/top/?$','/',p['url']); url=url.rstrip('/')+'/'
        by_url.setdefault(url,{'url':url,'name':p['name_full'],'team_id':p['id_team'],'roster_source':'existing DB'})
print('rosters',len(rosters),'profiles',len(by_url),flush=True)
profiles=[]; errors=[]
def profile(entry):
    url,seed=entry
    try:
        doc=get(url)
        n=re.search(r'class="bb-profile__ruby">(.*?)</ruby>',doc,re.S)
        b=re.search(r'(\d{4})年(\d+)月(\d+)日',doc)
        if not n or not b:raise ValueError('profile fields missing')
        facts={clean(k):clean(v) for k,v in re.findall(r'<dt[^>]*>(.*?)</dt>\s*<dd[^>]*>(.*?)</dd>',doc,re.S)}
        return {**seed,'url':url,'yahoo_id':re.search(r'/player/(\d+)',url)[1], 'name':clean(n[1]),'birth_date':f'{int(b[1]):04}-{int(b[2]):02}-{int(b[3]):02}', 'facts':{k:v for k,v in facts.items() if k in ('出身地','生年月日（満年齢）','身長','体重','投打')}}
    except Exception as e:return {'error':str(e),'url':url}
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
    for i,p in enumerate(ex.map(profile,by_url.items())):
        (errors if 'error' in p else profiles).append(p)
        if i%100==0:print('profiles collected',i,flush=True)
profile_birthdays={p['birth_date'] for p in profiles}
ids=sorted({str(p['external_id']) for p in players if p['source_key']=='mlb' and (p['last_year']==2026 or (p['date_birth'] or '').split(' ')[0] in profile_birthdays)})
official=[]
for i in range(0,len(ids),100):
    url='https://statsapi.mlb.com/api/v1/people?personIds='+','.join(ids[i:i+100])
    people=json.loads(get(url)).get('people',[])
    for p in people:
        official.append({k:p.get(k) for k in ['id','fullName','fullFMLName','firstLastName','lastFirstName','nameFirstLast','useName','firstName','middleName','lastName','nickName','birthDate','height','weight','primaryNumber','batSide','pitchHand','currentTeam']})
output={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sources':['https://baseball.yahoo.co.jp/mlb/teams','https://statsapi.mlb.com/api/v1/people'],'japanese_profiles':profiles,'official_profiles':official,'errors':errors}
(ROOT/'data/mlb-player-name-evidence.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
print('DONE',len(profiles),len(official),'errors',len(errors),flush=True)
