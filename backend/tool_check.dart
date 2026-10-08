import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final c = await conn.execute('SELECT id,name,emoji FROM m_country').timeout(const Duration(seconds: 10));
    print('countries:');
    for (final r in c) {
      print(r.toColumnMap());
    }
    final p = await conn.execute('''
      SELECT p.id, p.name_full, p.id_country, c.name, c.emoji
      FROM m_player p LEFT JOIN m_country c ON c.id=p.id_country
      WHERE p.id_country IS NOT NULL LIMIT 20
    ''').timeout(const Duration(seconds: 10));
    print('players:');
    for (final r in p) {
      print(r.toColumnMap());
    }
  });
}
