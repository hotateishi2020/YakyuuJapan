import 'package:postgres/postgres.dart';

/// One-time migration: preserve the legacy read/unread state at migration time.
Future<void> ensureNewsReadDate(Connection conn) async {
  await conn.execute(r'''
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='m_user' AND column_name='date_read_news') THEN
        ALTER TABLE m_user ADD COLUMN date_read_news TIMESTAMPTZ;
        UPDATE m_user SET date_read_news=NOW() WHERE COALESCE(flg_read_news,TRUE);
      END IF;
    END $$
  ''');
}
