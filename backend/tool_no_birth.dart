import 'dart:io';
import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''
      SELECT p.name_full, t.name_shortest, p.url, p.date_birth
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id=tsp.id_player
      JOIN m_team t ON t.id=p.id_team
      WHERE tsp.id_league IN (3,4) AND p.date_birth IS NULL
      GROUP BY p.id, p.name_full, t.name_shortest, p.url, p.date_birth
    ''').timeout(const Duration(seconds: 20));
    for (final r in rows) stdout.writeln(r.toColumnMap());
  });
}
