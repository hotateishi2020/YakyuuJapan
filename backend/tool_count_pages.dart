import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final n = await conn.execute('''
      SELECT COUNT(DISTINCT url) n FROM m_stats_details
      WHERE id_league IN (3,4) AND COALESCE(url,'')<>''
    ''').timeout(const Duration(seconds: 10));
    print(n.first.toColumnMap());
  });
}
