import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final columns = await conn.execute(
        "SELECT column_name,data_type FROM information_schema.columns WHERE table_name='m_player' ORDER BY ordinal_position");
    print(
        jsonEncode({'columns': columns.map((r) => r.toColumnMap()).toList()}));
    final rows = await conn.execute(
        """SELECT p.id,p.name_full,p.name_last,p.name_first,p.name_first_initial,p.name_patterns,p.identity_sources,p.source_key,p.external_id,p.url,p.date_birth::text,p.id_team,t.name_full AS team,t.id_league,p.flg_delete,
    (SELECT max(int_year) FROM m_player_career c WHERE c.id_player=p.id AND NOT coalesce(c.flg_delete,false)) AS last_year
    FROM m_player p LEFT JOIN m_team t ON t.id=p.id_team WHERE NOT coalesce(p.flg_delete,false)""");
    final data = rows.map((r) => r.toColumnMap()).toList();
    File('/tmp/player_identity_audit.json').writeAsStringSync(jsonEncode(data));
    print(jsonEncode({
      'players': data.length,
      'mlb': data.where((p) => [3, 4].contains(p['id_league'])).length,
      'english_mlb': data
          .where((p) =>
              [3, 4].contains(p['id_league']) &&
              RegExp(r'^[A-Za-z]').hasMatch('${p['name_full']}'))
          .length
    }));
    final refs = await conn.execute(
        "SELECT table_name,column_name,data_type FROM information_schema.columns WHERE table_schema='public' AND (column_name LIKE '%player%' OR column_name LIKE '%pitcher%' OR column_name='id_batter') ORDER BY table_name,column_name");
    File('/tmp/player_identity_references.json').writeAsStringSync(
        jsonEncode(refs.map((r) => r.toColumnMap()).toList()));
  });
  exit(0);
}
