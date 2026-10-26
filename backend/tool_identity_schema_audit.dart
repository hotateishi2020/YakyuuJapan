import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((c) async {
    final teams = await c.execute(
        'SELECT * FROM m_team WHERE id_league IN (1,2,3,4) AND NOT coalesce(flg_delete,false)');
    File('/tmp/identity_teams.json').writeAsStringSync(jsonEncode(
        teams.map((r) => r.toColumnMap()).toList(),
        toEncodable: (v) => v.toString()));
    final urls=await c.execute("SELECT DISTINCT url FROM m_stats_details WHERE id_league IN(3,4) AND NOT coalesce(flg_delete,false) AND coalesce(url,'')<>''");
    File('/tmp/identity_ranking_urls.json').writeAsStringSync(jsonEncode(urls.map((r)=>r[0]).toList()));
    final indexes = await c.execute(
        "SELECT tablename,indexdef FROM pg_indexes WHERE schemaname='public'");
    File('/tmp/identity_indexes.json').writeAsStringSync(
        jsonEncode(indexes.map((r) => r.toColumnMap()).toList()));
  });
  exit(0);
}
