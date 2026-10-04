import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''
      SELECT id, name_shortest, name_short, name_full, id_league, path_img_logo
      FROM m_team WHERE id_league IN (3,4) ORDER BY id_league, id
    ''').timeout(const Duration(seconds:15));
    for (final r in rows) print(r.toColumnMap());
  });
}
