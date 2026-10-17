import 'dart:io';
import 'app/TeamIdentity.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await conn.execute('BEGIN');
    try {
      await TeamIdentity.sync(conn);
      final rows = await conn.execute('''SELECT count(*) AS seasons,
        count(DISTINCT id_franchise) AS franchises FROM m_team_season_identity''');
      print(rows.single.toColumnMap());
      final hawks = await conn.execute('''SELECT int_year,name_full,name_short
        FROM m_team_season_identity WHERE id_franchise=7
          AND int_year IN (1988,1989,2004,2005) ORDER BY int_year''');
      for (final row in hawks) { print(row.toColumnMap()); }
      await conn.execute('COMMIT');
    } catch (_) { await conn.execute('ROLLBACK'); rethrow; }
  });
  exit(0);
}
