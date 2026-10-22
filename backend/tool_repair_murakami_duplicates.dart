import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/DisplaySnapshot.dart';

/// Only verified Yahoo 202101502 duplicates; NPB and MLB historical IDs stay intact.
Future<void> main() async {
 const keep=5601;
 const aliases=[5141,5366,5427];
 await Postgres.withConnection((conn) async {
  await conn.runTx((tx) async {
   final players=await tx.execute("SELECT * FROM m_player WHERE id=ANY(\$1::int[]) FOR UPDATE",parameters:[[keep,...aliases]]);
   if(players.length!=4 || players.any((r) {final p=r.toColumnMap();return p['id_team']!=18 || RegExp(r'/mlb/player/(\d+)').firstMatch('${p['url']}')?[1]!='202101502';})) throw StateError('Identity verification failed');
   final backup=<String,dynamic>{'players':players.map((r)=>r.toColumnMap()).toList()};
   for(final table in ['m_player_career','t_stats_player','t_stats_player_latest','t_predict_player','t_game_summary']) {
    backup[table]=(await tx.execute('SELECT * FROM $table WHERE id_player=ANY(\$1::int[])',parameters:[[keep,...aliases]])).map((r)=>r.toColumnMap()).toList();
   }
   backup['t_game_details']=(await tx.execute('SELECT * FROM t_game_details WHERE id_batter=ANY(\$1::int[]) OR id_pitcher=ANY(\$1::int[])',parameters:[[keep,...aliases]])).map((r)=>r.toColumnMap()).toList();
   final backupPath='/tmp/koko-murakami-before-${DateTime.now().millisecondsSinceEpoch}.json';
   File(backupPath).writeAsStringSync(JsonEncoder.withIndent('  ',(v)=>v.toString()).convert(backup));
   print('Backup: $backupPath');
   // Duplicate career totals are archived, never summed into double totals.
   await tx.execute('''UPDATE m_player_career a SET flg_delete=true WHERE a.id_player=ANY(\$1::int[])
    AND EXISTS(SELECT 1 FROM m_player_career k WHERE k.id_player=\$2 AND k.int_year=a.int_year AND k.id_team=a.id_team AND NOT COALESCE(k.flg_delete,false))''',parameters:[aliases,keep]);
   await tx.execute('UPDATE m_player_career SET id_player=\$2 WHERE id_player=ANY(\$1::int[]) AND NOT COALESCE(flg_delete,false)',parameters:[aliases,keep]);
   // Latest rows are a replaceable cache: preserve canonical totals and move
   // any metric which exists only on an alias.
   await tx.execute('''DELETE FROM t_stats_player_latest a WHERE a.id_player=ANY(\$1::int[])
    AND EXISTS(SELECT 1 FROM t_stats_player_latest k WHERE k.id_player=\$2 AND k.id_stats=a.id_stats AND k.id_league=a.id_league AND k.id_team=a.id_team)''',parameters:[aliases,keep]);
   for(final table in ['t_stats_player','t_stats_player_latest','t_predict_player','t_game_summary']) {
    final n=await tx.execute('UPDATE $table SET id_player=\$2 WHERE id_player=ANY(\$1::int[])',parameters:[aliases,keep]);print('$table: ${n.affectedRows}');
   }
   for(final column in ['id_batter','id_pitcher']) {await tx.execute('UPDATE t_game_details SET $column=\$2 WHERE $column=ANY(\$1::int[])',parameters:[aliases,keep]);}
   for(final column in ['id_pitcher_home','id_pitcher_away']) {await tx.execute('UPDATE t_game SET $column=\$2 WHERE $column=ANY(\$1::int[])',parameters:[aliases,keep]);}
   await tx.execute("UPDATE m_player SET name_full='村上宗隆',name_last='村上',name_first='宗隆',updat=now() WHERE id=\$1",parameters:[keep]);
   await tx.execute('UPDATE m_player SET flg_delete=true,updat=now() WHERE id=ANY(\$1::int[])',parameters:[aliases]);
  });
  await DisplaySnapshot.refreshPlayers(conn,2026);
  final check=await conn.execute("SELECT payload->>'title' AS title,array_agg(DISTINCT payload->>'id_player') AS ids,count(*) FROM v_stats_player WHERE int_year=2026 AND payload->>'id_player'=ANY(\$1::text[]) GROUP BY payload->>'title' ORDER BY title",parameters:[['5601','5141','5366','5427']]);
  for(final r in check) {print(r.toColumnMap());}
 });exit(0);
}
