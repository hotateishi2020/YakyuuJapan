import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await conn.runTx((tx) async {
      await tx.execute(
          'ALTER TABLE m_user ADD COLUMN IF NOT EXISTS favorite_high_school TEXT');
      await tx.execute(
          "UPDATE m_user SET favorite_high_school='佐賀北' WHERE id=1 AND favorite_high_school IS NULL");
    });
    final rows = await conn
        .execute('SELECT id,favorite_high_school FROM m_user WHERE id=1');
    print(rows);
  });
  exit(0);
}
