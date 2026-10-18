import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/CatcherCounts.dart';
import 'app/ExtendedPlayerMetrics.dart';
import 'app/StrengthUsage.dart';
Future<void> main(List<String> args) async {
 final year=args.isEmpty ? DateTime.now().year : int.parse(args.first);
 final file=File('data/player-metrics-$year.json');
 final data=usageMap(jsonDecode(file.readAsStringSync()));
 final players=usageMaps(data['players']);
 final client=http.Client();
 Future<String> get(String url) async {
  final r=await client.get(Uri.parse(url)).timeout(const Duration(seconds:40));
  if(r.statusCode!=200) throw StateError('HTTP ${r.statusCode}: $url');
  return utf8.decode(r.bodyBytes);
 }
 try {
  await refreshNpbCatcherCounts(year,players,get);
  final url='https://statsapi.mlb.com/api/v1/stats?stats=season&group=fielding&season=$year&sportIds=1&playerPool=ALL&limit=5000';
  final mlb=usageMap(jsonDecode(await get(url)));
  for(final block in usageMaps(mlb['stats'])) {
   for(final split in usageMaps(block['splits'])) {
    if(usageMap(split['position'])['abbreviation']!='C') continue;
    final id='${usageMap(split['player'])['id']}';
    final count=num.tryParse('${usageMap(split['stat'])['caughtStealing']}');
    if(count==null) continue;
    final person=players.where((p)=>p['org']=='mlb' && '${p['source_player_id']}'==id).firstOrNull;
    if(person==null) continue;
    final metrics=person['metrics'] as List;
    metrics.removeWhere((m)=>m['title']=='盗塁阻止率' || m['title']=='盗塁阻止数');
    metrics.add({...metric('盗塁阻止数',count),'source':url,'catcher_metric':true});
   }
  }
  final temp=File('${file.path}.tmp');
  temp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({...data,'players':players,'catcher_counts_checked_at':DateTime.now().toUtc().toIso8601String()}));
  temp.renameSync(file.path);
  for(final org in ['npb','mlb']) {
   print('$org: ${players.where((p)=>p['org']==org && usageMaps(p['metrics']).any((m)=>m['title']=='盗塁阻止数')).length} catchers');
  }
 } finally {client.close();}
}
