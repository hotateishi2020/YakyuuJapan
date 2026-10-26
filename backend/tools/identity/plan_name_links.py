"""Link only observed source aliases/current official roster identities."""
import collections, datetime, json, pathlib, re, unicodedata
ROOT=pathlib.Path(__file__).resolve().parents[2]
players=json.load(open('/tmp/player_identity_audit.json'));byid={p['id']:p for p in players}
e=json.loads((ROOT/'data/player-name-link-evidence.json').read_text())
def key(s):
 s=unicodedata.normalize('NFKD',unicodedata.normalize('NFKC',s or '')).casefold().translate(str.maketrans('髙濵濱邊邉齋齊','高浜浜辺辺斎斉'))
 return ''.join(c for c in s if not (0x300<=ord(c)<=0x36f) and c not in ' ・･.．,，-‐‑–—_\'’`*\t\n\r')
def birth(p):return (p['date_birth'] or '').split(' ')[0]
def sources(p):return p.get('identity_sources') or {}
byyahoo={str(sources(p).get('yahoo_mlb')):p for p in players if sources(p).get('yahoo_mlb') and sources(p).get('mlb')}
info={};reviews=[];verified_merges=collections.defaultdict(list)
for a in e['mlb_aliases']:
 p=byyahoo.get(a['yahoo_id'])
 if not p:continue
 t=info.setdefault(p['id'],{'patterns':set(p.get('name_patterns') or [p['name_full']]),'evidence':[],'sources':sources(p).copy(),'birth':birth(p),'name':p['name_full'],'team':p['id_team'],'url':p['url']})
 t['patterns'].add(a['name']);t['evidence'].append(a)
for row in e['npb_roster']:
 candidates=[p for p in players if p['id_team']==row['team_id'] and key(p['name_full'])==key(row['name']) and (not birth(p) or birth(p)==row['birth_date'])]
 if not candidates:continue
 official={str(sources(p).get('npb')) for p in candidates if str(sources(p).get('npb','')).isdigit()}
 if official and official!={row['npb_id']}:
  reviews.append({'name':row['name'],'reason':'conflicting NPB official ID','ids':[p['id'] for p in candidates],'evidence':row});continue
 known=[p for p in players if str(sources(p).get('npb'))==row['npb_id']]
 known_info=[i for i,t in info.items() if str(t['sources'].get('npb'))==row['npb_id']]
 if len(known)>1 or len(known_info)>1:
  reviews.append({'name':row['name'],'reason':'multiple official NPB identities','npb_id':row['npb_id']});continue
 canonical=known[0] if known else (byid[known_info[0]] if known_info else min(candidates,key=lambda p:(0 if birth(p) else 1,p['id'])))
 for candidate in candidates:
  if candidate['id']!=canonical['id'] and candidate['last_year'] in (None,2025,2026):verified_merges[canonical['id']].append(candidate['id'])
 t=info.setdefault(canonical['id'],{'patterns':set(canonical.get('name_patterns') or [canonical['name_full']]),'evidence':[],'sources':sources(canonical).copy(),'birth':row['birth_date'],'name':row['name'],'team':row['team_id'],'url':row['url']})
 t['patterns'].add(row['name']);t['sources']['npb']=row['npb_id'];t['evidence'].append(row)
# Registered aliases are valid evidence; they must point to exactly one current
# canonical player on that team. A collision remains a review item.
targets=collections.defaultdict(set)
for i,t in info.items():
 for name in t['patterns']:targets[(t['team'],key(name))].add(i)
merge=collections.defaultdict(list,{i:list(set(ids)) for i,ids in verified_merges.items()})
for p in players:
 if p['id'] in info or p['id'] in {old for ids in merge.values() for old in ids}:continue
 ids=targets.get((p['id_team'],key(p['name_full'])),set())
 if len(ids)!=1:
  if len(ids)>1:reviews.append({'name':p['name_full'],'ids':[p['id'],*sorted(ids)],'reason':'ambiguous observed alias'})
  continue
 target=next(iter(ids));t=info[target]
 if birth(p) and t['birth'] and birth(p)!=t['birth']:continue
 if p['last_year'] not in (None,2026):continue
 conflict=False
 for source,external in sources(p).items():
  if source in t['sources'] and t['sources'][source]!=external and not str(external).startswith('name:'):conflict=True
 if conflict:
  reviews.append({'name':p['name_full'],'ids':[p['id'],target],'reason':'conflicting official identity'});continue
 merge[target].append(p['id'])
# The NPB roster now supplies authoritative IDs for the existing crosswalk.
by_mlb={str(sources(p).get('mlb')):p for p in players if sources(p).get('mlb')}
crosswalk={p['npb_id']:p for p in json.loads((ROOT/'data/npb_mlb_player_ids.json').read_text())['players']}
for target,t in info.items():
 link=crosswalk.get(str(t['sources'].get('npb')))
 if not link or link['birth_date']!=t['birth']:continue
 old=by_mlb.get(str(link['mlb_id']))
 if not old or old['id']==target or old['id'] in info:continue
 if birth(old)!=link['birth_date']:continue
 if old['id'] in {i for ids in merge.values() for i in ids}:continue
 merge[target].append(old['id']);t['sources']['mlb']=str(link['mlb_id'])
 t['patterns'].add(old['name_full'])
 t['evidence'].append({'source':'https://github.com/chadwickbureau/register',**link})
plan=[]
for i,t in info.items():
 original=byid[i];new_patterns=t['patterns']-set(original.get('name_patterns') or [])
 if not merge[i] and not new_patterns and t['sources']==sources(original):continue
 patterns=set(t['patterns'])
 for old in merge[i]:patterns.update(byid[old].get('name_patterns') or [byid[old]['name_full']])
 plan.append({'canonical_id':i,'merge_ids':merge[i],'name_ja':t['name'],'name_en':None,'team_id':t['team'],'birth_date':t['birth'] or None,'patterns':sorted(patterns),'identity_sources':t['sources'],'url':t['url'],'evidence':t['evidence']})
(ROOT/('data/player-identity-roster-history-plan.json' if '--history' in __import__('sys').argv else 'data/player-identity-observed-alias-plan.json')).write_text(json.dumps({'generated_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'groups':plan,'review':reviews},ensure_ascii=False,indent=2)+'\n')
print('groups',len(plan),'merge rows',sum(len(p['merge_ids']) for p in plan),'review',len(reviews))
for g in plan:
 if g['identity_sources'].get('mlb') in ('660271','808967','621566'):print(g['name_ja'],g['merge_ids'],g['patterns'])
