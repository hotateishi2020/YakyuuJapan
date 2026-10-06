import 'dart:io';

import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await conn.execute('''
      DELETE FROM t_stats_team
      WHERE year = 1936
        AND id_team IN (
          SELECT id FROM m_team WHERE source_key LIKE 'npb:%'
        )
    ''');
    final deleted = await conn.execute('''
      DELETE FROM historical_backfill_checkpoint
      WHERE org = 'npb'
        AND (
          (
            (dataset LIKE 'hitting%' OR dataset LIKE 'pitching%')
            AND status = 'complete'
            AND COALESCE(row_count, 0) = 0
          )
          OR (int_year = 1936 AND (
            dataset LIKE 'standings%'
            OR dataset LIKE 'hitting%'
            OR dataset LIKE 'pitching%'
          ))
        )
      RETURNING org, int_year, dataset
    ''');
    print('cleared ${deleted.length} checkpoints');
    for (final row in deleted) {
      print('  ${row[0]} ${row[1]} ${row[2]}');
    }
    final all = await conn.execute('''
      SELECT org, int_year, dataset, status, row_count
      FROM historical_backfill_checkpoint
      ORDER BY org, int_year, dataset
    ''');
    for (final row in all) {
      print('cp ${row[0]} ${row[1]} ${row[2]} ${row[3]} rows=${row[4]}');
    }
  });
  exit(0);
}
