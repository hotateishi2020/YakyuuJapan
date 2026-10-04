import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''
      SELECT id, name_last, name_first, mailaddress
      FROM m_user WHERE COALESCE(flg_delete,FALSE)=FALSE ORDER BY id LIMIT 20
    ''');
    for (final r in rows) print(r.toColumnMap());
  });
}
