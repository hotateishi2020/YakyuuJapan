import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final cols = await conn.execute('''
      SELECT column_name FROM information_schema.columns
      WHERE table_name='m_user' ORDER BY ordinal_position
    ''');
    print(cols.map((r) => r[0]).join(', '));
    final rows = await conn.execute('SELECT id, name_last, mailaddress FROM m_user ORDER BY id LIMIT 5');
    for (final r in rows) print(r.toColumnMap());
  });
}
