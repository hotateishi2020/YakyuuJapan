import 'dart:io';
import 'app/FetchMLB.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  stdout.writeln('MLB生年月日・URL補完開始');
  await Postgres.withConnection((conn) async {
    await FetchMLB.enrichMlbPlayersForMarks(conn);
    final a = await conn.execute('''
      SELECT
        COUNT(DISTINCT p.id) AS players,
        COUNT(DISTINCT p.id) FILTER (WHERE p.date_birth IS NOT NULL) AS with_birth,
        COUNT(DISTINCT p.id) FILTER (WHERE p.date_birth IS NULL) AS no_birth,
        COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(p.url,'')<>'') AS with_url
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id = tsp.id_player
      WHERE tsp.id_league IN (3,4)
    ''').timeout(const Duration(seconds: 30));
    stdout.writeln('個人成績: ${a.first.toColumnMap()}');
    final b = await conn.execute('''
      SELECT p.name_full, p.date_birth::text AS birth,
        CASE WHEN p.date_birth::date <= (CURRENT_DATE - INTERVAL '35 years') THEN '🍁' ELSE '' END AS m,
        CASE WHEN p.date_birth::date > (CURRENT_DATE - INTERVAL '21 years') THEN '🌱' ELSE '' END AS s
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id = tsp.id_player
      WHERE tsp.id_league IN (3,4) AND p.date_birth IS NOT NULL
      GROUP BY p.id, p.name_full, p.date_birth
      HAVING p.date_birth::date <= (CURRENT_DATE - INTERVAL '35 years')
          OR p.date_birth::date > (CURRENT_DATE - INTERVAL '21 years')
      ORDER BY p.date_birth
      LIMIT 20
    ''').timeout(const Duration(seconds: 30));
    stdout.writeln('🍁🌱対象サンプル:');
    for (final r in b) {
      stdout.writeln(r.toColumnMap());
    }
  });
  stdout.writeln('完了');
}
