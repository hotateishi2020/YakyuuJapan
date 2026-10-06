import 'dart:io';

import 'app/HistoricalBaseballImporter.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  print('year_retire backfill...');
  await Postgres.withConnection((conn) async {
    await HistoricalBaseballImporter.ensureYearRetire(conn)
        .timeout(const Duration(minutes: 3));
    final rows = await conn.execute('''
      SELECT
        count(*) AS players,
        count(year_retire) AS retired,
        min(year_retire) AS oldest,
        max(year_retire) AS newest
      FROM m_player
      WHERE COALESCE(flg_delete, false) = false
    ''').timeout(const Duration(seconds: 30));
    print(rows.first.toColumnMap());
    final sample = await conn.execute('''
      SELECT id, name_full, year_retire
      FROM m_player
      WHERE year_retire IS NOT NULL
        AND COALESCE(flg_delete, false) = false
      ORDER BY year_retire DESC, id
      LIMIT 8
    ''').timeout(const Duration(seconds: 20));
    for (final row in sample) {
      print(row.toColumnMap());
    }
  }).timeout(const Duration(minutes: 4));
  print('done');
  exit(0);
}
