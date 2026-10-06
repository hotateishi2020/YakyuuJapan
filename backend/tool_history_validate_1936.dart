import 'dart:io';

import 'app/HistoricalBaseballImporter.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await HistoricalBaseballImporter().ensureSchema(conn);
    final teams = await conn.execute('''
      SELECT id, source_key, name_full, flg_delete
      FROM m_team
      WHERE source_key LIKE 'npb:%' OR id <= 12
      ORDER BY id
    ''');
    print('teams ${teams.length}');
    for (final row in teams) {
      print('  id=${row[0]} del=${row[3]} ${row[1]} ${row[2]}');
    }
    final standings = await conn.execute('''
      SELECT int_rank, name_team, id_team, int_win, int_lose, int_draw
      FROM t_stats_team WHERE year = 1936 ORDER BY int_rank
    ''');
    print('1936 standings ${standings.length}');
    for (final row in standings) {
      print('  ${row[0]} ${row[1]} team=${row[2]} ${row[3]}-${row[4]}-${row[5]}');
    }
  });
  exit(0);
}
