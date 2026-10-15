import 'dart:convert';
import 'dart:io';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';
Future<void> main(List<String> args) async {
 final year=args.isEmpty?DateTime.now().year:int.parse(args.first);var failures=0;
 final result=<String,Map<String,int>>{};
 await Postgres.withConnection((c)async{
 final rows=await c.execute('SELECT code_org,payload FROM t_team_strength WHERE int_year=\$1',parameters:[year]);
 for(final row in rows){
  final team=usageMap(row[1] is String?jsonDecode(row[1] as String):row[1]);
  final sums=result.putIfAbsent('${row[0]}',()=>{'teams':0,'batting_players':0,'pitching_players':0,'contract_players':0,'salary_records':0,'contract_periods':0,'unmatched_batting':0,'unknown_pa':0});
  sums['teams']=sums['teams']!+1;
  final roster=usageMaps(team['roster']);final byKey={for(final p in roster) p['player_key']:p};
  final batting=usageMaps(team['batting_stats']);final pitching=usageMaps(team['pitching_stats']);final contracts=usageMaps(team['contracts']);
  sums['batting_players']=sums['batting_players']!+batting.length;sums['pitching_players']=sums['pitching_players']!+pitching.length;
  sums['contract_players']=sums['contract_players']!+contracts.length;
  for(final p in contracts){sums['salary_records']=sums['salary_records']!+usageMaps(p['salary_history']).length;sums['contract_periods']=sums['contract_periods']!+usageMaps(p['periods']).length;}
  if(batting.isEmpty||pitching.isEmpty||contracts.isEmpty)failures++;
  for(final p in batting){
   final total=usageInt(p['home_runs'])*4+usageInt(p['triples'])*3+usageInt(p['doubles'])*2+usageInt(p['singles'])+usageInt(p['walks']);
   if(total!=usageInt(p['total_bases_walks'])||usageInt(p['singles'])<0)failures++;
   if(!byKey.containsKey(p['player_key'])){sums['unmatched_batting']=sums['unmatched_batting']!+1;if('${p['bats']??''}'.isEmpty)sums['unknown_pa']=sums['unknown_pa']!+usageInt(p['pa']);if(usageInt(p['pa'])>0)print('名簿未照合 ${team['name_team']} ${p['name']} ${p['pa']}打席');}
  }
 }
 });
 print(jsonEncode({'year':year,'summary':result,'failures':failures}));exit(failures==0?0:1);
}
