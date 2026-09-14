import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.openConnection((conn) async {
    Future<void> tryInsert(String table) async {
      try {
        await conn.execute('BEGIN');
        final sql = '''
          INSERT INTO $table (
            id_league, id_stats, id_player, id_team, int_rank, stats
          )
          (
            SELECT 1 AS id_league, 1 AS id_stats, m_player.id AS id_player,
                   m_player.id_team, 9999 AS int_rank, 0.3 AS stats
            FROM m_player
            LEFT OUTER JOIN m_team ON m_team.id = m_player.id_team
            WHERE m_team.name_shortest IS NOT NULL
            ORDER BY m_player.id ASC
            LIMIT 1
          )
        ''';
        final r = await conn.execute(sql);
        print('test insert $table OK affected=${r.affectedRows}');
        await conn.execute('ROLLBACK');
      } catch (e) {
        print('test insert $table FAILED: $e');
        try { await conn.execute('ROLLBACK'); } catch (_) {}
      }
    }

    await tryInsert('t_stats_player');
    await tryInsert('t_stats_player_latest');
  });
}
