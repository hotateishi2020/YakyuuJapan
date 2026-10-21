import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
Future<void> main() async {
 final rows=await Postgres.withConnection((c) async => (await c.execute("SELECT p.id,p.name_full,p.url,p.uniform_number,p.date_birth::text,p.height,p.weight,p.txt_position,p.year_retire,p.flg_delete,t.id AS id_team,t.name_full AS team_name,t.name_short,t.id_league FROM m_player p JOIN m_team t ON t.id=p.id_team WHERE t.name_short LIKE '%ソフトバンク%' ORDER BY p.id")).map((r)=>r.toColumnMap()).toList());
 await File('/tmp/koko-softbank-players.json').writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
 print(jsonEncode({'count':rows.length,'sample':rows.take(4).toList()}));
 exit(0);
}
