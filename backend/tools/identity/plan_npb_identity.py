"""Reaudit NPB names across clubs/seasons; verify each merge with official profiles."""
import collections,concurrent.futures,datetime,hashlib,html,json,pathlib,re,unicodedata,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[2]
CACHE=pathlib.Path('/tmp/koko-player-identity-http');CACHE.mkdir(exist_ok=True)
def key(s):
 return re.sub(r'[\s・･.．]','',unicodedata.normalize('NFKC',s or '')).translate(str.maketrans('髙濵濱邊邉齋齊','高浜浜辺辺斎斉'))
def clean(s):return html.unescape(re.sub('<[^>]+>','',s)).strip()
def birth(p):return (p.get('date_birth') or '').split(' ')[0]
def get(url):
 f=CACHE/hashlib.sha256(url.encode()).hexdigest()
 if f.exists():return f.read_text()
 with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'}),timeout=30) as r:s=r.read().decode('utf-8')
 f.write_text(s);return s
players=json.load(open('/tmp/player_identity_audit.json'))
byname=collections.defaultdict(list)
for p in players:byname[key(p['name_full'])].append(p)
candidates=[ps for ps in byname.values() if len(ps)>1 and any(p['id_league'] in (1,2) for p in ps)]
manual={key('村上宗隆'):'41845136',key('岡本和真'):'11515130',key('今井達也'):'31335134',key('吉井理人'):'51653860',key('セデーニョ'):'13915157'}
club={1:['読売','巨人'],2:['阪神'],3:['中日'],4:['ヤクルト'],5:['横浜','DeNA'],6:['広島'],7:['ソフトバンク','ダイエー','南海'],8:['西武'],9:['日本ハム'],10:['オリックス','阪急'],11:['楽天'],12:['ロッテ']}
profile_ids=set(manual.values())
for ps in candidates:
 for p in ps:
  n=str(p['identity_sources'].get('npb',''))
  if n.isdigit():profile_ids.add(n)
def profile(n):
 url=f'https://npb.jp/bis/players/{n}.html';s=get(url)
 m=re.search(r'(\d{4})年\s*(\d+)月\s*(\d+)日',s)
 if not m:raise ValueError('Missing birth date: '+url)
 date=f'{int(m[1]):04}-{int(m[2]):02}-{int(m[3]):02}'
 title=clean(re.search(r'<title>(.*?)</title>',s,re.S)[1]).split('（')[0].strip()
 career=[]
 for row in re.findall(r'<tr[^>]*>(.*?)</tr>',s,re.S):
  cells=[clean(x) for x in re.findall(r'<td[^>]*>(.*?)</td>',row,re.S)]
  if len(cells)>1 and re.fullmatch(r'(19|20)\d\d',cells[0]):career.append({'year':int(cells[0]),'club':cells[1]})
 return n,{'npb_id':n,'name':title,'birth_date':date,'career':career,'source':url}
profiles={};errors=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
 futures={ex.submit(profile,n):n for n in profile_ids}
 for f in concurrent.futures.as_completed(futures):
  try:n,p=f.result();profiles[n]=p
  except Exception as e:errors.append({'npb_id':futures[f],'error':str(e)})
plan=[];review=[]
for ps in candidates:
 namekey=key(ps[0]['name_full'])
 ids={str(p['identity_sources'].get('npb')) for p in ps if str(p['identity_sources'].get('npb','')).isdigit()}
 if namekey in manual:ids.add(manual[namekey])
 if len(ids)!=1:
  review.append({'name':ps[0]['name_full'],'ids':[p['id'] for p in ps],'reason':'different official IDs / no single verified profile'});continue
 n=next(iter(ids));profile=profiles.get(n)
 if not profile or key(re.sub(r'^[A-Z]\.', '', unicodedata.normalize('NFKC',profile['name'])))!=namekey:
  review.append({'name':ps[0]['name_full'],'ids':[p['id'] for p in ps],'reason':'official full name does not match','npb_id':n});continue
 matches=[p for p in ps if birth(p)==profile['birth_date']]
 if not matches:continue
 # Keep an established official identity; otherwise prefer the current verified career.
 canonical=min(matches,key=lambda p:(0 if p['identity_sources'].get('mlb') else 1,0 if p['identity_sources'].get('npb')==n else 1,-(p['last_year'] or 0),p['id']))
 old=[];evidence=[profile];patterns=set(canonical['name_patterns']);patterns.add(profile['name']);sources=canonical['identity_sources'].copy();sources['npb']=n
 for p in ps:
  if p['id']==canonical['id']:continue
  conflicts=any(k in sources and sources[k]!=v and not str(v).startswith('name:') for k,v in p['identity_sources'].items())
  correct_club=any(any(key(label) in key(row['club']) for label in club.get(p['id_team'],[])) for row in profile['career'])
  same_birth=birth(p)==profile['birth_date']
  if conflicts or (birth(p) and not same_birth) or not (same_birth or correct_club):
   review.append({'name':p['name_full'],'ids':[p['id'],canonical['id']],'reason':'birth/source conflict or unverified former club'});continue
  old.append(p['id']);patterns.update(p['name_patterns']);evidence.append({'old_id':p['id'],'name':p['name_full'],'team_id':p['id_team'],'last_year':p['last_year'],'same_birth':same_birth,'official_previous_club':correct_club})
  sources.update({k:v for k,v in p['identity_sources'].items() if not str(v).startswith('name:')})
 if old:
  # Current populated record's club is retained when the ID-bearing legacy row is stale.
  current=max(matches,key=lambda p:(p['last_year'] or 0,p['id']))
  plan.append({'canonical_id':canonical['id'],'merge_ids':old,'name_ja':canonical['name_full'],'name_en':None,'team_id':current['id_team'],'birth_date':profile['birth_date'],'patterns':sorted(patterns),'identity_sources':sources,'url':canonical['url'] or profile['source'],'evidence':evidence})
# Confirm the English retired-player record using both official biographies.
for g in plan:
 if g['identity_sources'].get('npb')!='51653860':continue
 url='https://statsapi.mlb.com/api/v1/people/134180'
 person=json.loads(get(url))['people'][0]
 assert person['fullName']=='Masato Yoshii' and person['birthDate']==g['birth_date']
 old=[p for p in players if p['identity_sources'].get('mlb')=='134180']
 assert len(old)==1 and birth(old[0])==g['birth_date']
 g['merge_ids'].append(old[0]['id']);g['patterns']=sorted(set(g['patterns']+old[0]['name_patterns']))
 g['identity_sources']['mlb']='134180';g['name_en']='Masato Yoshii'
 g['team_id']=11
 g['evidence'].append({'source':url,'name':person['fullName'],'birth_date':person['birthDate'],
   'japanese_biography':'https://www.marines.co.jp/team/player/detail/2025_00001092.html',
   'current_role_source':'https://www.rakuteneagles.jp/news/detail/202601127900.html'})
out={'generated_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'groups':plan,'review':review,'errors':errors}
(ROOT/'data/npb-player-identity-plan.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print('groups',len(plan),'merge rows',sum(len(p['merge_ids']) for p in plan),'review',len(review),'errors',errors)
for p in plan:print(p['canonical_id'],p['name_ja'],p['merge_ids'])
for r in review:print('REVIEW',r)
