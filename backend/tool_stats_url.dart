import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''
      SELECT id_league, id_stats, url, int_idx_col
      FROM m_stats_details
      WHERE id_league IN (3,4) AND COALESCE(flg_delete,FALSE)=FALSE
      ORDER BY id_league, id_stats
      LIMIT 20
    ''').timeout(const Duration(seconds: 15));
    for (final r in rows) {
      print(r.toColumnMap());
    }
  });
}
