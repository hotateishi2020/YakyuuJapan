import 'dart:io';
import 'app/FetchMLB.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  stdout.writeln('MLB過去成績バックフィル開始');
  await Postgres.withConnection((conn) async {
    await FetchMLB.enrichMlbPlayersForMarks(conn);
    final summary = await conn.execute('''
      SELECT
        COUNT(*) FILTER (WHERE t.id_league IN (3,4)) AS mlb_rows,
        COUNT(*) FILTER (WHERE t.id_league IN (3,4) AND c.int_year < EXTRACT(YEAR FROM CURRENT_DATE)::int) AS mlb_prior_rows,
        COUNT(DISTINCT c.id_player) FILTER (WHERE t.id_league IN (3,4)) AS mlb_players,
        COUNT(DISTINCT c.id_player) FILTER (
          WHERE t.id_league IN (3,4) AND c.int_year < EXTRACT(YEAR FROM CURRENT_DATE)::int
        ) AS mlb_players_with_prior
      FROM m_player_career c
      JOIN m_team t ON t.id = c.id_team
      WHERE COALESCE(c.flg_delete, FALSE) = FALSE
    ''').timeout(const Duration(seconds: 30));
    stdout.writeln('結果: ${summary.first.toColumnMap()}');

    final urls = await conn.execute('''
      SELECT
        COUNT(DISTINCT p.id) AS players,
        COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(p.url,'')<>'') AS with_url
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id = tsp.id_player
      WHERE tsp.id_league IN (3,4)
    ''').timeout(const Duration(seconds: 30));
    stdout.writeln('個人成績選手: ${urls.first.toColumnMap()}');

    final sample = await conn.execute('''
      SELECT p.name_full, c.int_year, mt.name_short AS career_team,
             c.int_batting, c.double_inning
      FROM m_player p
      JOIN m_player_career c ON c.id_player = p.id AND COALESCE(c.flg_delete,FALSE)=FALSE
      JOIN m_team mt ON mt.id = c.id_team
      WHERE p.name_full IN ('吉田正尚','山本由伸','大谷翔平','岡本和真')
      ORDER BY p.name_full, c.int_year
    ''').timeout(const Duration(seconds: 30));
    for (final r in sample) {
      stdout.writeln('${r.toColumnMap()}');
    }
  });
  stdout.writeln('完了');
}
