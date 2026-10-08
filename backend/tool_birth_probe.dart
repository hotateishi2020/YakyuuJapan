import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final a = await conn.execute('''
      SELECT
        COUNT(DISTINCT p.id) AS players,
        COUNT(DISTINCT p.id) FILTER (WHERE p.date_birth IS NOT NULL) AS with_birth,
        COUNT(DISTINCT p.id) FILTER (WHERE p.date_birth IS NULL) AS no_birth,
        COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(p.url,'')<>'') AS with_url,
        COUNT(DISTINCT p.id) FILTER (WHERE p.date_birth IS NULL AND COALESCE(p.url,'')<>'') AS no_birth_with_url
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id = tsp.id_player
      WHERE tsp.id_league IN (3,4)
    ''').timeout(const Duration(seconds: 20));
    stdout.writeln(a.first.toColumnMap());
    final b = await conn.execute('''
      SELECT p.name_full, p.date_birth, COALESCE(p.url,'')<>'' AS has_url,
        CASE WHEN p.date_birth IS NOT NULL AND p.date_birth::date <= (CURRENT_DATE - INTERVAL '35 years') THEN true ELSE false END AS age35,
        CASE WHEN p.date_birth IS NOT NULL AND p.date_birth::date > (CURRENT_DATE - INTERVAL '21 years') THEN true ELSE false END AS under21
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id = tsp.id_player
      WHERE tsp.id_league IN (3,4)
      GROUP BY p.id, p.name_full, p.date_birth, p.url
      ORDER BY (p.date_birth IS NULL) DESC, p.name_full
      LIMIT 15
    ''').timeout(const Duration(seconds: 20));
    for (final r in b) {
      stdout.writeln(r.toColumnMap());
    }
  });
}
