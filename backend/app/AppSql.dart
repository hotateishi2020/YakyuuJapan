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
  static String selectPlayerWhereFullNameAndTeamID() {
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

  //m_user
  static String selectUserWhereId() {
    return '''
      SELECT 
        * 
      FROM m_user 
      WHERE id = \$1 
      LIMIT 1
    ''';
  }

  //t_events_details
  static String selectEventsDetails() {
    return '''
            SELECT 
        *,
        CASE WHEN date_From_temp < (CURRENT_DATE + INTERVAL '1 day') THEN TRUE ELSE FALSE END AS flg_today 
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
          events.date_to,
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
      WHERE date_from_temp > CURRENT_DATE 
        OR (date_to IS NOT NULL AND date_to > CURRENT_DATE AND date_from_temp > (CURRENT_DATE - INTERVAL '10 day'))
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
        CASE WHEN to_char(t_game.datetime_start, 'HH24:MI') BETWEEN '06:00' AND '16:59' THEN '☀️ ' || to_char(t_game.datetime_start, 'HH24:MI')
             WHEN to_char(t_game.datetime_start, 'HH24:MI') BETWEEN '17:00' AND '24:00' THEN '🌙 ' || to_char(t_game.datetime_start, 'HH24:MI')
             ELSE '' END AS time_game,
        team_home.name_short AS name_team_home,
        team_away.name_short AS name_team_away,
        team_home.color_font AS color_font_home,
        team_home.color_back AS color_back_home,
        team_away.color_font AS color_font_away,
        team_away.color_back AS color_back_away,
        pitcher_home.name_full AS name_pitcher_home,
        pitcher_away.name_full AS name_pitcher_away,
        pitcher_win.name_full AS name_pitcher_win,
        pitcher_lose.name_full AS name_pitcher_lose,
        pitcher_save.name_full AS name_pitcher_save,
        m_stadium.name_short AS name_stadium,
        t_game.score_home,
        t_game.score_away,
        team_home.id AS id_team_home,
        team_away.id AS id_team_away,
        pitcher_win.id_team AS id_team_pitcher_win,
        pitcher_lose.id_team AS id_team_pitcher_lose,
        pitcher_save.id_team AS id_team_pitcher_save,
        team_home.id_league AS id_league_home,
        team_away.id_league AS id_league_away,
        t_game.state,
        COALESCE('/' || string_agg(DISTINCT user_pitcher_home.code_color, '/' 
                                ORDER BY user_pitcher_home.code_color) || '/', '') AS colors_pitcher_home,
        COALESCE('/' || string_agg(DISTINCT user_pitcher_away.code_color, '/' 
                                ORDER BY user_pitcher_away.code_color) || '/', '') AS colors_pitcher_away
      FROM t_game
        LEFT OUTER JOIN m_player AS pitcher_home ON pitcher_home.id = t_game.id_pitcher_home
        LEFT OUTER JOIN m_player AS pitcher_away ON pitcher_away.id = t_game.id_pitcher_away
        LEFT OUTER JOIN m_team AS team_home ON team_home.id = t_game.id_team_home
        LEFT OUTER JOIN m_team AS team_away ON team_away.id = t_game.id_team_away
        LEFT OUTER JOIN m_player AS pitcher_win ON pitcher_win.id = t_game.id_pitcher_win
        LEFT OUTER JOIN m_player AS pitcher_lose ON pitcher_lose.id = t_game.id_pitcher_lose
        LEFT OUTER JOIN m_player AS pitcher_save ON pitcher_save.id = t_game.id_pitcher_save
        LEFT OUTER JOIN m_stadium ON m_stadium.id = t_game.id_stadium
        LEFT OUTER JOIN (SELECT * FROM t_predict_player LEFT OUTER JOIN m_user ON m_user.id = t_predict_player.id_user WHERE year = \$1) AS user_pitcher_home ON user_pitcher_home.id_player = pitcher_home.id
        LEFT OUTER JOIN (SELECT * FROM t_predict_player LEFT OUTER JOIN m_user ON m_user.id = t_predict_player.id_user WHERE year = \$1) AS user_pitcher_away ON user_pitcher_away.id_player = pitcher_away.id
      WHERE t_game.datetime_start BETWEEN (CURRENT_DATE - INTERVAL '1 day') AND (CURRENT_DATE + INTERVAL '3 day')
      GROUP BY t_game.datetime_start, team_home.name_short, team_away.name_short, pitcher_home.name_full, pitcher_away.name_full,
               pitcher_win.name_full, pitcher_lose.name_full, m_stadium.name_short, t_game.score_home, t_game.score_away,
               team_home.id_league, team_away.id_league, team_home.color_font, team_home.color_back, team_away.color_font,
               team_away.color_back, team_home.id, team_away.id, pitcher_win.id_team, pitcher_lose.id_team, pitcher_save.name_full, 
               pitcher_save.id_team, t_game.state
      ORDER BY to_char(t_game.datetime_start, 'YYYY-MM-DD'), team_home.id;
    ''';
  }

  //t_nortification
  static String selectNotification() {
    return '''
      SELECT  
        tag_main.name1 AS tag_main_title,
        tag_sub.name1 AS tag_sub_title,
        title,
        text_main,
        id_user,
        flg_read,
        url,
        tag_main.code_color1 AS tag_main_color_back,
        tag_main.code_color2 AS tag_main_color_font,
        tag_sub.code_color1 AS tag_sub_color_back,
        tag_sub.code_color2 AS tag_sub_color_font
      FROM t_nortification
        LEFT OUTER JOIN m_system_code AS tag_main ON tag_main.key = t_nortification.code_tag_main AND tag_main.code = 'NORTIFICATION'
        LEFT OUTER JOIN m_system_code AS tag_sub ON tag_sub.key = t_nortification.code_tag_sub AND tag_sub.code = 'NORTIFICATION_SUB'
      ORDER BY t_nortification.crtat DESC
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
      CASE WHEN t_game_home.id_pitcher_home > 0 THEN m_user.code_color
           WHEN t_game_away.id_pitcher_away > 0 THEN m_user.code_color
           ELSE '' END AS color_today,
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
        WHERE year = \$1

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
     LEFT JOIN (SELECT id_pitcher_home FROM t_game WHERE datetime_start::date = CURRENT_DATE) AS t_game_home ON t_game_home.id_pitcher_home = u.id_player
     LEFT JOIN (SELECT id_pitcher_away FROM t_game WHERE datetime_start::date = CURRENT_DATE) AS t_game_away ON t_game_away.id_pitcher_away = u.id_player
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
      WHERE t_predict_team.int_year = \$1
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
        m_team.color_font,
        m_team.color_back,
        id_league,
        m_league.name_short AS name_league,
        int_game,
        int_win,
        int_lose,
        int_draw,
        game_behind,
        to_char(int_win / (int_win + int_lose) ::NUMERIC * 100, 'FM990.0') || '%' AS pct_win,
        regexp_replace(to_char(num_avg_batting, 'FM0.000'), '^0(?=\.)', '') AS num_avg_batting,
        int_homerun,
        int_rbi,
        int_sh,
        to_char(num_era_total, '0.00') AS num_era_total,
        to_char(num_era_starter, '0.00') AS num_era_starter,
        to_char(num_era_relief, '0.00') AS num_era_relief,
        to_char((1 -num_avg_fielding) * 100, 'FM990.0') || '%' AS num_avg_fielding,
  
        CASE WHEN num_avg_batting = MAX(num_avg_batting) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_top_num_avg_batting,
        CASE WHEN int_homerun = MAX(int_homerun) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_top_int_homerun,
        CASE WHEN int_rbi = MAX(int_rbi) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_top_int_rbi,
        CASE WHEN int_sh = MAX(int_sh) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_top_int_sh,
        CASE WHEN num_era_total = MIN(num_era_total) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_top_num_era_total,
        CASE WHEN num_era_starter = MIN(num_era_starter) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_top_num_era_starter,
        CASE WHEN num_era_relief = MIN(num_era_relief) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_top_num_era_relief,
        CASE WHEN num_avg_fielding = MAX(num_avg_fielding) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_top_num_avg_fielding,

        CASE WHEN num_avg_batting = MIN(num_avg_batting) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_worst_num_avg_batting,
        CASE WHEN int_homerun = MIN(int_homerun) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_worst_int_homerun,
        CASE WHEN int_rbi = MIN(int_rbi) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_worst_int_rbi,
        CASE WHEN int_sh = MIN(int_sh) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_worst_int_sh,
        CASE WHEN num_era_total = MAX(num_era_total) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_worst_num_era_total,
        CASE WHEN num_era_starter = MAX(num_era_starter) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_worst_num_era_starter,
        CASE WHEN num_era_relief = MAX(num_era_relief) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_worst_num_era_relief,
        CASE WHEN num_avg_fielding = MIN(num_avg_fielding) OVER (PARTITION BY id_league) THEN TRUE ELSE FALSE END AS flg_worst_num_avg_fielding

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
        m_team.color_font,
        m_team.color_back,
        m_player.name_full   AS name_player,
        CASE WHEN m_stats.code_display = 'INTEGER' THEN TRUNC(stats)::int::text
             WHEN m_stats.code_display = 'INT_DEC_2' THEN to_char(stats, '0.00')
             WHEN m_stats.code_display = 'INT_DEC_3' THEN to_char(stats, '0.000')
             WHEN m_stats.code_display = 'NUM_NO_ZERO_3' THEN regexp_replace(to_char(stats, 'FM0.000'), '^0(?=\.)', '')
             ELSE to_char(stats, '')
        END AS stats,
        COALESCE('/' || string_agg(DISTINCT t_predict_player.id_user::text, '/' 
                                ORDER BY t_predict_player.id_user::text) || '/', '') AS id_users,
        COALESCE('/' || string_agg(DISTINCT m_user.code_color, '/' 
                                ORDER BY m_user.code_color) || '/', '') AS colors_user,
        CASE WHEN t_game_home.id_pitcher_home > 0 THEN TRUE
             WHEN t_game_away.id_pitcher_away > 0 THEN TRUE
             ELSE FALSE END AS flg_today,
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
        LEFT JOIN m_user    ON m_user.id = t_predict_player.id_user
        LEFT JOIN (SELECT id_pitcher_home FROM t_game WHERE datetime_start::date = CURRENT_DATE) AS t_game_home ON t_game_home.id_pitcher_home = t_predict_player.id_player
        LEFT JOIN (SELECT id_pitcher_away FROM t_game WHERE datetime_start::date = CURRENT_DATE) AS t_game_away ON t_game_away.id_pitcher_away = t_predict_player.id_player
      WHERE t_stats_player.crtat = (SELECT MAX(crtat) FROM t_stats_player WHERE EXTRACT(YEAR FROM crtat) = \$1)
      GROUP BY
        m_stats.title,
        t_stats_player.int_rank,
        m_team.name_shortest,
        m_team.color_font,
        m_team.color_back,
        m_player.name_full,
        t_stats_player.stats,
        t_stats_player.id_league,
        m_stats.int_index,
        m_stats.code_display,
        t_stats_player.id_stats,
        t_game_home.id_pitcher_home,
        t_game_away.id_pitcher_away
      ORDER BY t_stats_player.id_league, m_stats.int_index, t_stats_player.int_rank;
    ''';
  }

  static String deleteStatsPlayer() {
    return '''
      DELETE FROM ${t_stats_player().tableName} 
      WHERE EXTRACT(YEAR FROM crtat) = \$1
        AND code_category = '${Value.SystemCode.Key.NPB}';
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
