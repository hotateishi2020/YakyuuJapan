import 'dart:io';
import 'tools/Postgres.dart';
import 'app/NewsReadDate.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await ensureNewsReadDate(conn);
    final rows = await conn.execute("SELECT data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='m_user' AND column_name='date_read_news'");
    if (rows.length != 1 || rows.single[0] != 'timestamp with time zone') throw StateError('Migration verification failed');
    print('Verified m_user.date_read_news: timestamp with time zone');
  });
  exit(0);
}
