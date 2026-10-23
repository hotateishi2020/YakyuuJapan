import 'dart:io';
import 'app/FetchURL.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  await Postgres.withConnection((conn) async {
    if (!args.contains('--check')) {
      await FetchURL.fetchStatsPlayerForLeagues(conn, const [1,2,3,4], onlyTitle: '勝率');
    }
    final rows = await conn.execute('''
      SELECT d.id_league,s.id,s.title,s.flg_pitcher,d.url,
        (SELECT COUNT(*) FROM t_stats_player_latest p WHERE p.id_stats=s.id AND p.id_league=d.id_league) AS players
      FROM m_stats s LEFT JOIN m_stats_details d ON d.id_stats=s.id
      WHERE s.title='勝率' AND NOT COALESCE(s.flg_delete,false) ORDER BY d.id_league
    ''');
    for (final row in rows) { print(row.toColumnMap()); }
  });
  exit(0);
}
