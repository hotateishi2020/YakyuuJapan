import 'DB/t_stats_player.dart';

class AppSql {
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

  //m_player
  static String selectTodayPitcher() {
    return '''
      SELECT 
        id 
      FROM m_player 
      WHERE name_full = \$1 
      AND id_team = \$2 
      LIMIT 1
    ''';
  }

  //m_stadium
  static String selectStadium() {
    return '''
      SELECT 
        id 
      FROM m_stadium 
      WHERE name_short LIKE \$1
      LIMIT 1
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

  static String selectTeamsWhereName() {
    return '''
      SELECT
        id
      FROM m_team
      WHERE name_short = \$1 
      LIMIT 1
    ''';
  }

  //t_game
  static String selectExistsGame() {
    return '''
      SELECT
        id
      FROM t_game
      WHERE id_team_home = \$1 
        AND id_team_away = \$2
        AND datetime_start = \$3
      LIMIT 1
    ''';
  }

  static String selectGames() {
    return '''
      SELECT 
        to_char(t_game.datetime_start, 'YYYY-MM-DD') AS date_game,
        to_char(t_game.datetime_start, 'HH24:MI')    AS time_game,
        team_home.name_short AS name_team_home,
        team_away.name_short AS name_team_away,
        pitcher_home.name_full AS name_pitcher_home,
        pitcher_away.name_full AS name_pitcher_away,
        pitcher_win.name_full AS name_pitcher_win,
        pitcher_lose.name_full AS name_pitcher_lose,
        m_stadium.name_short AS name_stadium,
        t_game.score_home,
        t_game.score_away,
        team_home.id_league AS id_league_home,
        team_away.id_league AS id_league_away
      FROM t_game
        LEFT OUTER JOIN m_player AS pitcher_home ON pitcher_home.id = t_game.id_pitcher_home
        LEFT OUTER JOIN m_player AS pitcher_away ON pitcher_away.id = t_game.id_pitcher_away
        LEFT OUTER JOIN m_team AS team_home ON team_home.id = t_game.id_team_home
        LEFT OUTER JOIN m_team AS team_away ON team_away.id = t_game.id_team_away
        LEFT OUTER JOIN m_player AS pitcher_win ON pitcher_win.id = t_game.id_pitcher_win
        LEFT OUTER JOIN m_player AS pitcher_lose ON pitcher_lose.id = t_game.id_pitcher_lose
        LEFT OUTER JOIN m_stadium ON m_stadium.id = t_game.id_stadium
      WHERE datetime_start::date = \$1;
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
        SELECT
          id_user,
          id_league,
          id_stats,
          id_player,
          id_team
        FROM t_predict_player

        UNION ALL

        SELECT
          id_user, 
          id_league, 
          id_stats, 
          id_player, 
          id_team
        FROM (
          SELECT
            0 AS id_user,
            tsp.id_league,
            tsp.id_stats,
            tsp.id_player,
            tsp.id_team,
            tsp.crtat,
            RANK() OVER (PARTITION BY tsp.id_stats, tsp.id_league ORDER BY tsp.stats DESC) AS rnk
          FROM t_stats_player tsp
          LEFT JOIN m_stats  ON m_stats.id  = tsp.id_stats
          WHERE m_stats.flg_positive = TRUE
          AND tsp.crtat = (SELECT MAX(crtat) FROM t_stats_player)

          UNION ALL

          SELECT
            0 AS id_user,
            tsp.id_league,
            tsp.id_stats,
            tsp.id_player,
            tsp.id_team,
            tsp.crtat,
            RANK() OVER (PARTITION BY tsp.id_stats, tsp.id_league ORDER BY tsp.stats ASC) AS rnk
          FROM t_stats_player tsp
          LEFT JOIN m_stats  ON m_stats.id  = tsp.id_stats
          WHERE m_stats.flg_positive = FALSE
          AND tsp.crtat = (SELECT MAX(crtat) FROM t_stats_player)
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
        m_user.name_last AS name_user_last,
        m_team.name_short AS name_team_short,
        m_team.id_league,
        int_rank,
        flg_champion
      FROM t_predict_team
          LEFT OUTER JOIN m_user ON m_user.id = t_predict_team.id_user
          LEFT OUTER JOIN m_team ON m_team.id = t_predict_team.id_team
      ORDER BY m_user.id, id_league, int_rank
    ''';
  }

  //t_stats_team
  static String selectStatsTeam() {
    return '''
      SELECT 
        year,
        int_rank,
        id_team,
        m_team.name_short AS name_team,
        id_league,
        m_league.name_short AS name_league,
        int_game,
        int_win	int_lose,
        int_draw,
        game_behind,
        num_avg_batting,
        int_homerun,
        int_rbi,
        int_sh,
        num_era_total,
        num_era_starter,
        num_era_relief,
        num_avg_fielding
      FROM t_stats_team
        LEFT OUTER JOIN m_team ON m_team.id = t_stats_team.id_team
        LEFT OUTER JOIN m_league ON m_league.id = m_team.id_league
        WHERE t_stats_team.crtat = (SELECT MAX(crtat) FROM t_stats_team)
      ORDER BY id_league, int_rank
    ''';
  }

  //t_stats_player
  static String selectInsertPlayerStats(List<t_stats_player> stats) {
    String sql = '''
        INSERT INTO ${stats.first.tableName} (
          id_league,
          id_stats,
          id_player,
          id_team,
          int_rank,
          stats
        )
        ''';
    int cnt = 1;

    for (final stat in stats) {
      // 文字列補間を使用して値を直接埋め込み
      sql += '''(
        SELECT 
          ${stat.id_league} AS id_league,
          ${stat.id_stats} AS id_stats,
          m_player.id AS id_player, 
          m_player.id_team,
          ${stat.int_rank} AS int_rank,
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
    return sql;
  }
}
