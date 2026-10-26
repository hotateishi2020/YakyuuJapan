import 'dart:convert';
import 'dart:io';
import 'app/ClubRecords.dart';
import 'app/OrgLeague.dart';
import 'app/PageSnapshot.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

String canonical(dynamic value) {
  if (value is Map) {
    final keys=value.keys.map((k)=>'$k').toList()..sort();
    return '{${keys.map((k)=>'${jsonEncode(k)}:${canonical(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(canonical).join(',')}]';
  return jsonEncode(value);
}
Future<void> main(List<String> args) async {
  final year=int.parse(args[0]);
  final backup=Directory(args[1])..createSync(recursive:true);
  final data=usageMap(jsonDecode(File('data/records.json').readAsStringSync()));
  final snapshot=usageMap(usageMap(usageMap(data['npb'])['club_current_streaks'])['$year']);
  final clubs=usageMap(snapshot['clubs']);
  if(clubs.length!=12 || clubs.values.any((c)=>usageMap(usageMap(c)['categories']).length!=15)) {
    throw StateError('Incomplete 12-club audit');
  }
  await Postgres.withConnection((conn) async {
    final saved=await PageSnapshot.read(conn,kind:'records',org:OrgKind.npb,year:year);
    final old=usageMap(saved['club_records']);
    if(usageMaps(old['teams']).length!=12) throw StateError('Missing club page');
    final before=File('${backup.path}/club-$year-before.json');
    if(!before.existsSync()) before.writeAsStringSync(jsonEncode(old));
    final updated=applyAuditedClubStreaks(old,snapshot);
    final cells=usageMaps(updated['metrics']).where((m)=>m['group']=='streak').expand((m)=>usageMaps(m['cells'])).toList();
    if(cells.length!=180 || cells.any((c)=>!['verified','unavailable'].contains(c['current_status']))) throw StateError('Incomplete cells');
    await PageSnapshot.refresh(conn,kind:'records',org:OrgKind.npb,year:year,
      build:() async=>{...saved,'club_records':updated}..remove('updated_at'));
    final read=await PageSnapshot.read(conn,kind:'records',org:OrgKind.npb,year:year);
    if(canonical(read['club_records'])!=canonical(updated)) throw StateError('Read-back mismatch');
    File('${backup.path}/club-$year-after.json').writeAsStringSync(jsonEncode(updated));
    print('Published ${cells.where((c)=>c['current_status']=='verified').length}/180 verified club cells; read-back matched');
  });
  exit(0);
}
