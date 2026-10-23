import 'package:intl/intl.dart';
import 'package:postgres/postgres.dart';

import 'GameFetchSchedule.dart';

/// t_game.flg_stats_loaded — 終了試合の選手成績（出場成績＋打席）を取り終えたか。
class GameStatsLoad {
  /// 全成績は試合終了後、保存が完了するまでだけ取得する。
  static bool needsRefresh({required bool finished, required bool loaded}) {
    return finished && !loaded;
  }

  static Future<bool> canFetchDetails(Connection conn, int gameId) async {
    final rows = await conn.execute("SELECT state, COALESCE(flg_stats_loaded, FALSE) FROM t_game WHERE id = \$1", parameters: [gameId]);
    return rows.isNotEmpty && needsRefresh(finished: '${rows.first[0]}'.contains('試合終了'), loaded: rows.first[1] == true);
  }

  /// 試合終了で勝利投手がいるのに、出場成績の勝・負・H・Sが一人も無い。
  static bool needsDecisionRefresh({
    required bool finished,
    required bool hasWinner,
    required bool hasDecisionCode,
  }) {
    return finished && hasWinner && !hasDecisionCode;
  }

  /// その日の Yahoo 試合が1件以上あり、未完了・試合中が残っていない。
  static bool dateFullyLoaded({required bool hasYahooGames, required bool hasPending}) {
    return hasYahooGames && !hasPending;
  }

  static Future<bool> isDateFullyLoaded(Connection conn, String date, List<int> leagueIds) async {
    if (date.isEmpty) return false;
    final ids = leagueIds.where((id) => id > 0).toSet().join(', ');
    if (ids.isEmpty) return false;
    final rows = await conn.execute(
      '''
        SELECT
          EXISTS (
            SELECT 1
            FROM t_game g
            JOIN m_team th ON th.id = g.id_team_home
            WHERE g.datetime_start::date = \$1::date
              AND COALESCE(g.flg_delete, FALSE) = FALSE
              AND th.id_league IN ($ids)
              AND g.id < 2000
          ) AS has_games,
          EXISTS (
            SELECT 1
            FROM t_game g
            JOIN m_team th ON th.id = g.id_team_home
            WHERE g.datetime_start::date = \$1::date
              AND COALESCE(g.flg_delete, FALSE) = FALSE
              AND th.id_league IN ($ids)
              AND g.id < 2000
              AND (
                COALESCE(g.flg_stats_loaded, FALSE) = FALSE
                OR g.state LIKE '%回%'
                OR g.state LIKE '%試合中%'
              )
          ) AS has_pending
      ''',
      parameters: [date],
    );
    if (rows.isEmpty) return false;
    final map = rows.first.toColumnMap();
    return dateFullyLoaded(
      hasYahooGames: map['has_games'] == true,
      hasPending: map['has_pending'] == true,
    );
  }

  /// 昨日以前で、その日の Yahoo 試合が全部読み込み済みなら日程ページに行かない。
  static Future<bool> skipPastSchedule(
    Connection conn, {
    required String org,
    required DateTime date,
    required DateTime now,
    required List<int> leagueIds,
  }) async {
    if (!GameFetchSchedule.isPastDay(date, now)) return false;
    final key = DateFormat('yyyy-MM-dd').format(date);
    if (GameFetchSchedule.pastDateDone(org, key)) return true;
    if (await isDateFullyLoaded(conn, key, leagueIds)) {
      GameFetchSchedule.markPastDateDone(org, key);
      return true;
    }
    return false;
  }

  static Future<void> rememberPastDateIfSettled(
    Connection conn, {
    required String org,
    required String date,
    required List<int> leagueIds,
    bool emptySchedule = false,
  }) async {
    if (emptySchedule || await isDateFullyLoaded(conn, date, leagueIds)) {
      GameFetchSchedule.markPastDateDone(org, date);
    }
  }

  static Future<void> ensureColumn(Connection conn) async {
    final rows = await conn.execute(
      '''
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 't_game'
          AND column_name = 'flg_stats_loaded'
        LIMIT 1
      ''',
    );
    if (rows.isNotEmpty) return;
    await conn.execute("SET lock_timeout = '2s'");
    try {
      await conn.execute(
        'ALTER TABLE t_game ADD COLUMN IF NOT EXISTS flg_stats_loaded boolean NOT NULL DEFAULT FALSE',
      );
    } finally {
      try {
        await conn.execute("SET lock_timeout = '0'");
      } catch (_) {}
    }
  }

  static Future<bool> isLoaded(Connection conn, int gameId) async {
    if (gameId <= 0) return false;
    final rows = await conn.execute(
      'SELECT COALESCE(flg_stats_loaded, FALSE) AS loaded FROM t_game WHERE id = \$1::int LIMIT 1',
      parameters: [gameId],
    );
    if (rows.isEmpty) return false;
    return rows.first.toColumnMap()['loaded'] == true;
  }

  /// 終了試合なのに投手の勝・負・H・Sが未保存なら、出場成績を取り直す。
  static Future<bool> pitcherDecisionsMissing(Connection conn, int gameId) async {
    if (gameId <= 0) return false;
    final rows = await conn.execute(
      '''
        SELECT
          g.state LIKE '%試合終了%' AS finished,
          COALESCE(g.id_pitcher_win, 0) > 0 AS has_winner,
          EXISTS (
            SELECT 1
            FROM t_game_summary s
            WHERE s.id_game = g.id
              AND BTRIM(COALESCE(s.code_result_pitcher, '')) <> ''
          ) AS has_decision
        FROM t_game g
        WHERE g.id = \$1::int
        LIMIT 1
      ''',
      parameters: [gameId],
    );
    if (rows.isEmpty) return false;
    final map = rows.first.toColumnMap();
    bool flag(dynamic value) => value == true || '$value'.trim().toLowerCase() == 'true';
    return needsDecisionRefresh(
      finished: flag(map['finished']),
      hasWinner: flag(map['has_winner']),
      hasDecisionCode: flag(map['has_decision']),
    );
  }

  /// 終了試合に出場成績と打席があれば完了にする。
  static Future<void> markIfComplete(Connection conn, int gameId, {required bool finished}) async {
    if (gameId <= 0 || !finished) return;
    await conn.execute(
      '''
        UPDATE t_game g
        SET flg_stats_loaded = TRUE,
            updat = NOW()
        WHERE g.id = \$1::int
          AND COALESCE(g.flg_stats_loaded, FALSE) = FALSE
          AND NOT EXISTS (
            SELECT 1 FROM (VALUES (g.id_team_home), (g.id_team_away)) AS teams(id)
            WHERE NOT EXISTS (
              SELECT 1 FROM t_game_summary s JOIN m_player p ON p.id = s.id_player
              WHERE s.id_game = g.id AND p.id_team = teams.id AND s.int_batting > 0
            ) OR NOT EXISTS (
              SELECT 1 FROM t_game_summary s JOIN m_player p ON p.id = s.id_player
              WHERE s.id_game = g.id AND p.id_team = teams.id AND (s.int_pitch > 0 OR s.double_inning_pitch > 0)
            )
          )
          AND EXISTS (
            SELECT 1 FROM t_game_details d
            WHERE d.id_game = g.id
              AND COALESCE(BTRIM(d.code_result), '') <> ''
          )
          AND (
            COALESCE(g.id_pitcher_win, 0) = 0
            OR EXISTS (
              SELECT 1
              FROM t_game_summary s
              WHERE s.id_game = g.id
                AND BTRIM(COALESCE(s.code_result_pitcher, '')) <> ''
            )
          )
      ''',
      parameters: [gameId],
    );
  }
}
