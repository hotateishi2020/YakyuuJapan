import 'dart:io';
import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await conn.execute('ALTER TABLE m_user ADD COLUMN IF NOT EXISTS residence_prefecture TEXT');
    await conn.execute("UPDATE m_user SET residence_prefecture=CASE id WHEN 1 THEN '佐賀県' WHEN 2 THEN '長野県' END, updat=NOW() WHERE id IN (1,2) AND residence_prefecture IS NULL");
    final rows = await conn.execute('SELECT id,residence_prefecture FROM m_user WHERE id IN (1,2) ORDER BY id');
    for (final row in rows) { print('userid=${row[0]}: ${row[1]}'); }
  });
  exit(0);
}
