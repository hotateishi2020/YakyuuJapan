"""Combine verified profile/history plans and the two inspected role corrections."""
import json,pathlib,datetime
ROOT=pathlib.Path(__file__).resolve().parents[2]
players={p['id']:p for p in json.load(open('/tmp/player_identity_audit.json'))}
official={str(p['id']):p for p in json.loads((ROOT/'data/mlb-player-name-evidence.json').read_text())['official_profiles']}
groups={};reviews=[]
for file in ['player-identity-expanded-plan.json','player-identity-roster-history-plan.json']:
 plan=json.loads((ROOT/'data'/file).read_text());reviews+=plan['review']
 for g in plan['groups']:
  if g['canonical_id'] in groups:raise ValueError('Overlapping canonical plans require explicit review')
  groups[g['canonical_id']]=g
splits=[{'old_id':5619,'batter_id':5129,'pitcher_id':5547,'incorrect_profile_url':'https://baseball.yahoo.co.jp/mlb/player/202100490/','evidence':'Old full name and 525 historical batting rows belong to Brooks Lee; profile birth date and 31 pitching appearances/178.1 IP belong to Taj Bradley. No game summaries on old ID.'},
 {'old_id':5969,'batter_id':26961,'pitcher_id':6622,'incorrect_profile_url':'https://baseball.yahoo.co.jp/mlb/player/2102328/','evidence':'Old full name and four batting game summaries belong to Austin Riley; profile birth date, 71 pitching appearances/67 IP, and hold statistics belong to Dylan Lee. No pitching game summaries on old ID.'}]
for split in splits:
 for identity in ('batter_id','pitcher_id'):
  i=split[identity];p=players[i];source=p['identity_sources'];o=official[str(source['mlb'])]
  g=groups.setdefault(i,{'canonical_id':i,'merge_ids':[],'name_ja':p['name_full'],'name_en':o['fullName'],'team_id':p['id_team'],'birth_date':p['date_birth'].split(' ')[0],'patterns':p['name_patterns'],'identity_sources':source,'url':p['url'],'evidence':[]})
  g['evidence'].append(split)
  if identity=='batter_id':g['merge_ids'].append(split['old_id'])
old=[i for g in groups.values() for i in g['merge_ids']]
assert len(old)==len(set(old)),'duplicate source IDs'
assert not set(old)&set(groups),'canonical/source chains require review'
plan={'generated_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'groups':list(groups.values()),'review':reviews,'role_splits':splits}
(ROOT/'data/player-identity-final-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n')
print('Final verified groups',len(groups),'merge rows',len(old),'unresolved profile candidates',len(reviews))
