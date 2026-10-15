import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/StrengthUsage.dart';
Future<void> main(List<String> args) async {
 final year=int.parse(args.firstOrNull??'2026');
 final rows=await Postgres.withConnection((c)=>c.execute('SELECT code_org,payload FROM t_team_strength WHERE int_year=\$1',parameters:[year]));
 final players=<String,List<Map<String,dynamic>>>{};
 for(final r in rows)players.putIfAbsent('${r[0]}',()=>[]).addAll(usageMaps(usageMap(r[1] is String?jsonDecode(r[1] as String):r[1])['roster']));
 for(final e in players.entries){
  final paths=<String,Set<String>>{},awards=<String,int>{};
  for(final p in e.value){
   for(final c in usageMaps(p['career_history']))paths.putIfAbsent('${c['category']}',()=>{}).add('${p['player_key']}');
   for(final a in usageMaps(p['additional_achievements']))awards.update('${a['label']}',(n)=>n+1,ifAbsent:()=>1);
  }
  print('${e.key}: 経歴登録${e.value.where((p)=>usageMaps(p['career_history']).isNotEmpty).length}人 / ${paths.map((k,v)=>MapEntry(k,v.length))}');
  print(awards);
  for(final p in e.value.where((p)=>['Shohei Ohtani','Yoshinobu Yamamoto'].contains(p['name']))) print('${p['name']}: ${usageMaps(p['career_history']).map((c)=>c['team']).join(',')}');
 }
 exit(0);
}
