import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/DisplaySnapshot.dart';
Future<void> main(List<String> args) async {
 if(args.length!=2) throw ArgumentError('old_id canonical_id');
 final old=int.parse(args[0]), canonical=int.parse(args[1]);
 await Postgres.withConnection((c) async {
  final identity=await c.execute('SELECT merged_into_player_id FROM m_player WHERE id=\$1',parameters:[old]);
  if(identity.length!=1 || identity.first[0]!=canonical) throw StateError('No verified identity redirect');
  final before=await c.execute("SELECT * FROM v_predict_stats WHERE (payload->>'id_player')::int=\$1",parameters:[old]);
  final path='/tmp/koko-prediction-player-$old-${DateTime.now().millisecondsSinceEpoch}.json';
  File(path).writeAsStringSync(jsonEncode(before.map((r)=>r.toColumnMap()).toList(),toEncodable:(v)=>v.toString()));
  // Verify the read-time redirect against the stale stored payload before repair.
  final current=(await DisplaySnapshot.playerPart(c,2026,[1,2])).stats;
  if(current.any((r)=>r['id_player']==old)) throw StateError('Read-time redirect failed');
  final changed=await c.execute("UPDATE v_predict_stats SET payload=jsonb_set(payload,'{id_player}',to_jsonb(\$2::int)),updated_at=now() WHERE (payload->>'id_player')::int=\$1 RETURNING int_year,kind",parameters:[old,canonical]);
  final remaining=await c.execute("SELECT count(*) FROM v_predict_stats WHERE (payload->>'id_player')::int=\$1",parameters:[old]);
  if(remaining.first[0]!=0) throw StateError('Stale IDs remain');
  print('Repaired ${changed.length} rows; backup: $path');
  final after=(await DisplaySnapshot.playerPart(c,2026,[1,2])).stats;
  print(jsonEncode(after.where((r)=>r['id_player']==canonical && ['最多勝','勝率'].contains(r['title'])).map((r)=>{'title':r['title'],'id_player':r['id_player'],'stats':r['stats']}).toList()));
 });
 exit(0);
}
