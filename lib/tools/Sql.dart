import 'package:koko/DB/t_stats_player.dart';
import 'package:koko/DB/t_stats_player.dart';

class Sql {
  //m_stats_details
  static String selectStatsDetails() {
    return '''
      SELECT
        id_stats,
        id_league,
        url,
        int_idx_col 
      FROM m_stats_details
      WHERE flg_predict = TRUE
    ''';
  }

  // m_team
  static String selectTeams() {
    return '''
      SELECT
        id,
        url_npb_players
      FROM m_team
    ''';
  }

  // t_predict_player
  static String selectPredictPlayer() {
    return '''
      SELECT
      id_user,
  CASE 
    WHEN id_user = 0 THEN '現在'
    ELSE m_user.name_last
  END AS username,
  m_league.name_short AS league_name,
  m_stats.title,
  m_player.name_last || m_player.name_first AS player_name,
  CASE
    WHEN id_user = 0 THEN FALSE
    ELSE 
      CASE
        WHEN COUNT(*) OVER (PARTITION BY u.id_league, u.id_stats, u.id_player) >= 2
        THEN TRUE
        ELSE FALSE
      END 
    END AS flg_atari
FROM (
  -- 1) ユーザー予測
  SELECT
    id_user,
    id_league,
    id_stats,
    id_player,
    id_team
  FROM t_predict_player

  UNION ALL

  -- 2) 現在値（正/負のトップ1を統合）
  SELECT
    id_user, id_league, id_stats, id_player, id_team
  FROM (
    SELECT
      0 AS id_user,
      tsp.id_league,
      tsp.id_stats,
      tsp.id_player,
      tsp.id_team,
      RANK() OVER (PARTITION BY tsp.id_stats, tsp.id_league ORDER BY tsp.stats DESC) AS rnk
    FROM t_stats_player tsp
    LEFT JOIN m_stats  ON m_stats.id  = tsp.id_stats
    WHERE m_stats.flg_positive = TRUE

    UNION ALL

    SELECT
      0 AS id_user,
      tsp.id_league,
      tsp.id_stats,
      tsp.id_player,
      tsp.id_team,
      RANK() OVER (PARTITION BY tsp.id_stats, tsp.id_league ORDER BY tsp.stats ASC) AS rnk
    FROM t_stats_player tsp
    LEFT JOIN m_stats  ON m_stats.id  = tsp.id_stats
    WHERE m_stats.flg_positive = FALSE
  ) t
  WHERE t.rnk = 1
) u
LEFT JOIN m_user ON m_user.id = u.id_user
LEFT JOIN m_league ON m_league.id = u.id_league
LEFT JOIN m_stats ON m_stats.id = u.id_stats
LEFT JOIN m_player ON m_player.id = u.id_player
LEFT JOIN m_team ON m_team.id = u.id_team
ORDER BY id_user, u.id_league, id_stats;
    ''';
  }

  // t_predict_team
  static String selectPredictNPBTeams() {
    return '''
      SELECT
        t_predict_team.id AS id_predict,
        m_user.id AS id_user,
        m_user.name_last,
        m_team.name_short,
        m_team.id_league,
        int_rank,
        flg_champion
      FROM t_predict_team
          LEFT OUTER JOIN m_user ON m_user.id = t_predict_team.id_user
          LEFT OUTER JOIN m_team ON m_team.id = t_predict_team.id_team
      ORDER BY m_user.id, id_league, int_rank
    ''';
  }

  //m_player
  static (String, Map<String, dynamic>) selectInsertPlayerStats(
      List<t_stats_player> stats) {
    Map<String, dynamic> map = {};
    String sql = '''
        INSERT INTO ${stats.first.tableName} (
          id_league,
          id_stats,
          id_player,
          id_team,
          stats
        )
        ''';
    int cnt = 1;

    for (final stat in stats) {
      print(3);

      // 文字列補間を使用して値を直接埋め込み
      sql += '''(
        SELECT 
          ${stat.id_league} AS id_league,
          ${stat.id_stats} AS id_stats,
          m_player.id AS id_player, 
          m_player.id_team,
          ${stat.stats} AS stats
        FROM m_player
        LEFT OUTER JOIN m_team ON m_team.id = m_player.id_team
        WHERE m_team.name_shortest = '${stat.teamName}'
          AND m_player.name_last || m_player.name_first LIKE '%${stat.playerName}%' 
        ORDER BY m_player.name_last ASC
        LIMIT 1
      )''';

      if (cnt < stats.length) {
        sql += '''
                UNION
               ''';
      }

      cnt++;
    }
    return (sql, map);
  }
}
