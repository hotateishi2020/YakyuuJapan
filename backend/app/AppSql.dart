import 'DB/t_stats_player.dart';
import 'Value.dart';

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

  static String selectTeamsWhereNameShortest() {
    return '''
      SELECT
        id
      FROM m_team
      WHERE name_shortest = \$1 
      LIMIT 1
    ''';
  }

  //t_events_details
  static String selectEventsDetails() {
    return '''
      SELECT 
        * 
      FROM (
        SELECT
          event_category.name1 AS event_category,  
          event_category_sub.name1 AS event_category_sub,
          events.title_event,
          CASE WHEN events.date_from IS NOT NULL THEN events.date_from
               ELSE 
                 (CASE WHEN m_event.code_date_from = 'EARLY' THEN to_char(make_date(EXTRACT(YEAR FROM m_event.date_from)::int,EXTRACT(MONTH FROM m_event.date_from)::int,1),'YYYY-MM-DD')::timestamp
                       WHEN m_event.code_date_from = 'MID' THEN to_char(make_date(EXTRACT(YEAR FROM m_event.date_from)::int,EXTRACT(MONTH FROM m_event.date_from)::int,10),'YYYY-MM-DD')::timestamp
                       WHEN m_event.code_date_from = 'LATE' THEN to_char(make_date(EXTRACT(YEAR FROM m_event.date_from)::int,EXTRACT(MONTH FROM m_event.date_from)::int,20),'YYYY-MM-DD')::timestamp
                       WHEN m_event.code_date_from = 'MONTH' THEN to_char(make_date(EXTRACT(YEAR FROM m_event.date_from)::int,EXTRACT(MONTH FROM m_event.date_from)::int,1),'YYYY-MM-DD')::timestamp
                       WHEN m_event.code_date_from = 'DATE' THEN m_event.date_from
                       WHEN m_event.code_date_from = '7_DAYS_LATOR_JS' THEN m_event.date_from
                  END)
          END AS date_from_temp,
          CASE WHEN events.date_from IS NOT NULL THEN 
           (CASE WHEN m_event.flg_span = TRUE AND events.date_to IS NOT NULL THEN to_char(events.date_from, 'YYYY"年"MM"月"DD"日"') || '〜' || to_char(events.date_to, 'YYYY"年"MM"月"DD"日"')
                 ELSE (CASE WHEN EXTRACT(HOUR FROM events.date_from) = 0 THEN to_char(events.date_from, 'YYYY"年"MM"月"DD"日"')
                            ELSE to_char(events.date_from, 'YYYY"年"MM"月"DD"日" HH24":"MI')
                            END)
                 END)
               ELSE 
                 (CASE WHEN m_event.code_date_from = 'EARLY' THEN EXTRACT(MONTH FROM m_event.date_from) || '月上旬'
                       WHEN m_event.code_date_from = 'MID' THEN EXTRACT(MONTH FROM m_event.date_from) || '月中旬'
                       WHEN m_event.code_date_from = 'LATE' THEN EXTRACT(MONTH FROM m_event.date_from) || '月下旬'
                       WHEN m_event.code_date_from = 'MONTH' THEN EXTRACT(MONTH FROM m_event.date_from) || '月中'
                       WHEN m_event.code_date_from = 'DATE' THEN to_char(m_event.date_from, 'YYYY"年"MM"月"DD"日"')
                       WHEN m_event.code_date_from = '7_DAYS_LATOR_JS' THEN '日本シリーズ終了の翌日から土日祝日を除く7日後'
                  END)
          END AS txt_timing,
          event_category.code_color1 AS event_category_color_back,
          event_category.code_color2 AS event_category_color_font,
          event_category_sub.code_color1 AS event_category_sub_color_back,
          event_category_sub.code_color2 AS event_category_sub_color_font
        FROM (
          SELECT id_event, title_event, date_from, date_to FROM t_event
          UNION ALL
          SELECT t_event.id_event, t_event_details.title_event, t_event_details.datetime_start AS date_from, NULL FROM t_event_details
            LEFT OUTER JOIN t_event ON t_event.id = t_event_details.id_t_event
        ) AS events
          LEFT OUTER JOIN m_event ON m_event.id = events.id_event
          LEFT OUTER JOIN m_system_code AS event_category ON event_category.key = m_event.code_category AND event_category.code = 'EVENT'
          LEFT OUTER JOIN m_system_code AS event_category_sub ON event_category_sub.key = m_event.code_category_sub AND event_category_sub.code = 'EVENT_SUB'
          ORDER BY events.date_from
        ) AS t
      WHERE date_from_temp >= CURRENT_DATE
      ORDER BY date_from_temp, txt_timing;
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
      WHERE t_game.datetime_start BETWEEN (CURRENT_DATE - INTERVAL '1 day') AND (CURRENT_DATE + INTERVAL '3 day');
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
      END AS flg_atari,
      int_index,
      flg_pitcher
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
     ORDER BY id_user, u.id_league, int_index;
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
        int_win,
        int_lose,
        int_draw,
        game_behind,
        int_win / (int_win + int_lose) AS pct_win,
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
  static String selectStatsPlayer() {
    return '''
      SELECT
        m_stats.title,
        t_stats_player.int_rank,
        m_team.name_shortest AS name_team,
        m_player.name_full   AS name_player,
        t_stats_player.stats,
        COALESCE('/' || string_agg(DISTINCT t_predict_player.id_user::text, '/' 
                                ORDER BY t_predict_player.id_user::text) || '/', '') AS id_users,
        t_stats_player.id_league,
        m_stats.int_index,
        t_stats_player.id_stats
      FROM t_stats_player
        LEFT JOIN m_stats   ON m_stats.id   = t_stats_player.id_stats
        LEFT JOIN m_team    ON m_team.id    = t_stats_player.id_team
        LEFT JOIN m_player  ON m_player.id  = t_stats_player.id_player
        LEFT JOIN m_league  ON m_league.id  = m_team.id_league
        LEFT JOIN t_predict_player
          ON t_predict_player.id_player = t_stats_player.id_player
          AND t_predict_player.id_stats  = t_stats_player.id_stats
          AND t_predict_player.year      = \$1
      WHERE t_stats_player.crtat = (SELECT MAX(crtat) FROM t_stats_player WHERE EXTRACT(YEAR FROM crtat) = \$1)
      GROUP BY
        m_stats.title,
        t_stats_player.int_rank,
        m_team.name_shortest,
        m_player.name_full,
        t_stats_player.stats,
        t_stats_player.id_league,
        m_stats.int_index,
        t_stats_player.id_stats
      ORDER BY t_stats_player.id_league, m_stats.int_index, t_stats_player.int_rank;
    ''';
  }

  static String deleteStatsPlayer() {
    return '''
      DELETE FROM ${t_stats_player().tableName} 
      WHERE EXTRACT(YEAR FROM crtat) = \$1
        AND code_category = '${Value.code_category_game_npb}';
    ''';
  }

  static String selectInsertStatsPlayer(List<t_stats_player> stats) {
    String sql = '''
        INSERT INTO ${stats.first.tableName} (
          id_league,
          id_stats,
          id_player,
          id_team,
          int_rank,
          stats,
          code_category
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
          ${stat.stats} AS stats,
          '${stat.code_category}' AS code_category
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
