import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final cols = await conn.execute('''
      SELECT column_name, data_type FROM information_schema.columns
      WHERE table_name='m_user' ORDER BY ordinal_position
    ''');
    for (final r in cols) {
      print(r.toColumnMap());
    }
    final teams = await conn.execute('''
      SELECT id, name_shortest, name_short, id_league FROM m_team
      WHERE COALESCE(flg_delete, FALSE)=FALSE AND id_league IN (1,2,3,4)
      ORDER BY id_league, id LIMIT 50
    ''');
    print('teams sample:');
    for (final r in teams) {
      print(r.toColumnMap());
    }
  });
}
