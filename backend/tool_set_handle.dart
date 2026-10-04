import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await conn.execute("ALTER TABLE m_user ADD COLUMN IF NOT EXISTS name_handle VARCHAR(100) DEFAULT ''");
    // fill empty handles from mail local-part for existing users
    await conn.execute('''
      UPDATE m_user SET name_handle = split_part(mailaddress, '@', 1)
      WHERE COALESCE(name_handle, '') = '' AND COALESCE(mailaddress, '') <> ''
    ''');
    final rows = await conn.execute('SELECT id, name_last, name_handle, mailaddress FROM m_user ORDER BY id');
    for (final r in rows) print(r.toColumnMap());
  });
}
