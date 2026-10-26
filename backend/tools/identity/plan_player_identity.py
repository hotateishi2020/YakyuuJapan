"""Produce a reviewable merge/localization plan; does not write the database."""
import collections, datetime, json, pathlib, re, unicodedata
ROOT=pathlib.Path(__file__).resolve().parents[2]
players=json.load(open('/tmp/player_identity_audit.json'))
evidence=json.loads((ROOT/'data/mlb-player-name-evidence.json').read_text())
byid={p['id']:p for p in players}
byofficial={str(p['external_id']):p for p in players if p['source_key']=='mlb'}
byurl=collections.defaultdict(list)
for p in players:
 m=re.search(r'/mlb/player/(\d+)',p['url'] or '')
 if m:byurl[m[1]].append(p)
def key(s):
 s=unicodedata.normalize('NFKD',unicodedata.normalize('NFKC',s or '')).casefold()
 s=s.translate(str.maketrans('髙﨑神塚濵濱邊邉齋齊','高崎神塚浜浜辺辺斎斉'))
 return ''.join(c for c in s if not (0x300 <= ord(c) <= 0x36f) and c not in ' ・･.．,，-‐‑–—_\'’`*\t\n\r')
def japanese(s):return bool(re.search('[ぁ-んァ-ヶ一-龯]',s or ''))
def birth(p):return (p.get('date_birth') or '').split(' ')[0]
def height(p):
 m=re.match(r"(\d+)'\s*(\d+)",p.get('height') or '')
 return (int(m[1])*12+int(m[2]))*2.54 if m else None
def number(s):
 m=re.search(r'\d+',s or '')
 return int(m[0]) if m else None
bybirth=collections.defaultdict(list)
for p in evidence['official_profiles']:bybirth[p['birthDate']].append(p)
parent={p['id']:p['id'] for p in players}; reasons=collections.defaultdict(list); translations={}; reviews=[]
def root(i):
 while parent[i]!=i: parent[i]=parent[parent[i]];i=parent[i]
 return i
def join(ids,why):
 ids=sorted(set(ids)); roots={root(i) for i in ids}
 sources=collections.defaultdict(set)
 for p in players:
  if root(p['id']) in roots and p['source_key'] and p['external_id']:sources[p['source_key']].add(p['external_id'])
 if any(len(v)>1 for k,v in sources.items() if k=='mlb') or len({v for v in sources.get('npb',set()) if str(v).isdigit()})>1:
  reviews.append({'ids':ids,'reason':'conflicting MLB IDs','evidence':why});return
 first=min(roots)
 for i in roots:parent[i]=first
 reasons[first].append(why)
# First connect a bilingual profile using multiple independently matching facts.
for j in evidence['japanese_profiles']:
 facts=j['facts']; jheight=number(facts.get('身長')); jweight=number(facts.get('体重'))
 hands=facts.get('投打',''); candidates=[]
 for o in bybirth[j['birth_date']]:
  db=byofficial.get(str(o['id'])); h=height(o)
  if not db or not h or not jheight or abs(h-jheight)>1.1:continue
  weight_ok=jweight and o.get('weight') and abs(o['weight']*0.45359237-jweight)<=2
  hand={'R':'右','L':'左','S':'両'}
  expected=hand.get((o.get('pitchHand') or {}).get('code'),'?')+'投'+hand.get((o.get('batSide') or {}).get('code'),'?')+'打'
  team_ok=db['id_team']==j['team_id']
  if (team_ok and expected in hands) or (weight_ok and expected in hands): candidates.append(o)
 if len(candidates)!=1:
  reviews.append({'yahoo_id':j['yahoo_id'],'name':j['name'],'reason':'bilingual evidence incomplete/ambiguous','candidates':[p['id'] for p in candidates]});continue
 o=candidates[0]; db=byofficial[str(o['id'])]
 english=[o.get(k) for k in ['fullName','fullFMLName','firstLastName','lastFirstName','nameFirstLast'] if o.get(k)]
 patterns=sorted(set([j['name'],*english]))
 if str(o['id'])=='592518':patterns+=['マチャド','M.マチャド']
 if str(o['id'])=='571771':patterns+=['エンリケ・ヘルナンデス','キケ・ヘルナンデス','Kiké Hernández']
 translations[db['id']]={'official_id':str(o['id']),'name_ja':j['name'],'name_en':o['fullName'],'team_id':j['team_id'],'birth_date':j['birth_date'],'patterns':patterns,'yahoo_id':j['yahoo_id'],'url':j['url'],'evidence':{'birth_date':j['birth_date'],'height_cm':jheight,'hands':hands,'official_source':f"https://statsapi.mlb.com/api/v1/people/{o['id']}",'japanese_source':j['url']}}
 same=[db['id']]
 for p in byurl[j['yahoo_id']]:
  if birth(p) and birth(p)!=j['birth_date']:continue
  # Avoid retaining a mistakenly attached URL for an unrelated surname.
  surname=key(j['name'].split('・')[-1]); old=re.sub(r'^[A-Za-zＡ-Ｚ]+[.．]','',p['name_full'])
  oldsurname=key(old.split('・')[-1])
  if key(p['name_full']) in {key(x) for x in patterns} or (oldsurname==surname and birth(p)==j['birth_date']):same.append(p['id'])
 if len(same)>1:join(same,translations[db['id']]['evidence'])
# Full Japanese names on the same current roster can link legacy placeholder
# rows without a birthday/URL. Never use surname-only or initial-only variants.
for official_id,t in translations.items():
 if not t.get('team_id'):continue
 matches=[p['id'] for p in players if p['id']!=official_id
   and p['id_team']==t['team_id'] and p['last_year'] in (None,2026)
   and key(p['name_full'])==key(t['name_ja'])
   and (not birth(p) or birth(p)==t['birth_date'])]
 if matches:join([official_id,*matches],{**t['evidence'],'matched_by':'verified current roster full name + team; legacy placeholder'})
# Strong same-source Japanese aliases not covered by current official roster.
for yahoo,ps in byurl.items():
 groups=collections.defaultdict(list)
 for p in ps:
  if birth(p):groups[birth(p)].append(p)
 for b,rows in groups.items():
  names={key(p['name_full']) for p in rows}
  if len(rows)>1 and len(names)==1:join([p['id'] for p in rows],{'source':'same Yahoo ID, birth date, normalized full name','yahoo_id':yahoo})
# Japanese orthographic duplicates with same full name and birth date.
groups=collections.defaultdict(list)
for p in players:
 if birth(p):groups[(key(p['name_full']),birth(p))].append(p)
for (name,b),ps in groups.items():
 if len(ps)>1:join([p['id'] for p in ps],{'source':'same full name and birth date','name_key':name,'birth_date':b})
# Cross-league identities are linked only through the verified registry crosswalk.
npb_by_id=collections.defaultdict(list)
for p in players:
 m=re.search(r'/players/(\d+)\.html',p['url'] or '')
 if m:npb_by_id[m[1]].append(p)
 if p['source_key']=='npb' and str(p['external_id']).isdigit():npb_by_id[p['external_id']].append(p)
for link in json.loads((ROOT/'data/npb_mlb_player_ids.json').read_text())['players']:
 official=byofficial.get(str(link['mlb_id']))
 if not official:continue
 npb=[p for p in npb_by_id[link['npb_id']] if not birth(p) or birth(p)==link['birth_date']]
 if not npb or (birth(official) and birth(official)!=link['birth_date']):continue
 join([official['id'],*[p['id'] for p in npb]],{'source':'https://github.com/chadwickbureau/register','npb_id':link['npb_id'],'mlb_id':link['mlb_id'],'birth_date':link['birth_date']})
# Aggregate all aliases and evidence. Prefer existing full Japanese master IDs.
groups=collections.defaultdict(list)
for p in players:groups[root(p['id'])].append(p)
plan=[]
for r,ps in groups.items():
 ts=[translations[p['id']] for p in ps if p['id'] in translations]
 if not ts and len(ps)==1:continue
 if len({t['official_id'] for t in ts})>1:raise ValueError('conflicting group')
 t=ts[0] if ts else {}
 preferred=sorted(ps,key=lambda p:(0 if t and key(p['name_full'])==key(t['name_ja']) else 1,0 if japanese(p['name_full']) and not re.match(r'^[A-Za-zＡ-Ｚ]+[.．]',p['name_full']) else 1,p['id']))[0]
 aliases=sorted(set([p['name_full'] for p in ps if p['name_full']]+t.get('patterns',[])))
 source_ids={p['source_key']:p['external_id'] for p in sorted(ps,key=lambda p:str(p['external_id']).isdigit()) if p['source_key'] and p['external_id']}
 if t:source_ids.update(mlb=t['official_id'],yahoo_mlb=t['yahoo_id'])
 plan.append({'canonical_id':preferred['id'],'merge_ids':[p['id'] for p in ps if p['id']!=preferred['id']],'name_ja':t.get('name_ja') or (preferred['name_full'] if japanese(preferred['name_full']) else None),'name_en':t.get('name_en'),'team_id':t.get('team_id'),'birth_date':t.get('birth_date'),'patterns':aliases,'identity_sources':source_ids,'url':t.get('url'),'evidence':[t['evidence']] if t else reasons.get(r,[])})
if '--expanded' in __import__('sys').argv:plan=[p for p in plan if p['merge_ids'] or (p['name_ja'] and key(byid[p['canonical_id']]['name_full'])!=key(p['name_ja']))]
elif '--followup' in __import__('sys').argv:plan=[p for p in plan if p['merge_ids']]
output={'generated_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'groups':plan,'review':reviews}
(ROOT/('data/player-identity-expanded-plan.json' if '--expanded' in __import__('sys').argv else 'data/player-identity-followup-plan.json' if '--followup' in __import__('sys').argv else 'data/player-identity-plan.json')).write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
print('groups',len(plan),'merge rows',sum(len(p['merge_ids']) for p in plan),'japanese names',sum(bool(p['name_ja']) for p in plan),'review',len(reviews))
for p in plan:
 if p['identity_sources'].get('mlb') in ('592518','571771','660271','808967'):print(p)
