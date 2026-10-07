import 'package:intl/intl.dart';
import 'package:postgres/postgres.dart';

import 'GameFetchSchedule.dart';

/// t_game.flg_stats_loaded — 終了試合の選手成績（出場成績＋打席）を取り終えたか。
class GameStatsLoad {
  /// 進行中は毎回取る。完了済みは取らない。
  static bool needsRefresh({required bool live, required bool loaded}) {
    if (live) return true;
    return !loaded;
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
          AND EXISTS (
            SELECT 1 FROM t_game_summary s WHERE s.id_game = g.id
          )
          AND EXISTS (
            SELECT 1 FROM t_game_details d
            WHERE d.id_game = g.id
              AND COALESCE(BTRIM(d.code_result), '') <> ''
          )
      ''',
      parameters: [gameId],
    );
  }
}
