import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  try {
    await Postgres.withConnection((conn) async {
      await conn.runTx((tx) async {
        await tx.execute('ALTER TABLE m_user ADD COLUMN IF NOT EXISTS flg_special BOOLEAN NOT NULL DEFAULT FALSE');
        await tx.execute('UPDATE m_user SET flg_special = (id IN (1, 2)) WHERE flg_special IS DISTINCT FROM (id IN (1, 2))');
      });
      final result = await conn.execute('SELECT id, flg_special FROM m_user WHERE flg_special ORDER BY id');
      for (final row in result) { print(row.toColumnMap()); }
      final other = await conn.execute('SELECT COUNT(*) FROM m_user WHERE id NOT IN (1, 2) AND flg_special IS DISTINCT FROM FALSE');
      if (other.single[0] != 0 || result.length != 2) throw StateError('Unexpected special users');
      print('Verified: only users 1 and 2 are special; other users are false.');
    });
    exit(0);
  } catch (_) {
    stderr.writeln('Special user migration failed.');
    exit(1);
  }
}
