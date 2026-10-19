import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../tools/Postgres.dart';
import 'AppSql.dart';
import 'PlayerDisplay.dart';
import 'PostseasonForm.dart';
import 'PredictionSnapshot.dart';
import 'Value.dart';

/// 初期表示用の集計結果。スクレイピング登録のあとで埋め、画面はここだけ読む。
class DisplaySnapshot {
  static bool _ensured = false;
  static Future<void> _tail = Future<void>.value();

  static Future<T> _queue<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  static Future<void> ensure(Connection conn) async {
    if (_ensured) return;
    // IF NOT EXISTS 付きの ALTER でも排他ロックを取る。
    // scrape のトランザクションがスナップショット更新を待っていると、
    // この ALTER と更新キューが互いを待ち、画面の SELECT まで止まる。
    final schema = await conn.execute('''
      SELECT
        to_regclass('public.t_player_season_usage') IS NOT NULL
        AND to_regclass('public.v_stats_player') IS NOT NULL
        AND to_regclass('public.v_stats_teams') IS NOT NULL
        AND to_regclass('public.v_games_details') IS NOT NULL
        AND to_regclass('public.v_games_details_date') IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 't_game'
            AND column_name = 'txt_lineup_announced'
        ) AS ready
    ''');
    if (schema.isNotEmpty && schema.first[0] == true) {
      _ensured = true;
      return;
    }
    // 未作成の環境でも、DDL のロック待ちを無期限にしない。
    final previous = await conn.execute('SHOW lock_timeout');
    await conn.execute("SET lock_timeout = '2s'");
    try {
      await conn.execute('CREATE TABLE IF NOT EXISTS t_player_season_usage(int_year integer,id_player integer,groups jsonb NOT NULL,PRIMARY KEY(int_year,id_player))');
      await conn.execute('''
      CREATE TABLE IF NOT EXISTS v_stats_player (
        int_year integer NOT NULL,
        row_no integer NOT NULL,
        payload jsonb NOT NULL,
        PRIMARY KEY (int_year, row_no)
      )
    ''');
      await conn.execute('''
      CREATE TABLE IF NOT EXISTS v_stats_teams (
        int_year integer NOT NULL,
        row_no integer NOT NULL,
        payload jsonb NOT NULL,
        PRIMARY KEY (int_year, row_no)
      )
    ''');
      await conn.execute('''
      CREATE TABLE IF NOT EXISTS v_games_details (
        int_year integer NOT NULL,
        code text NOT NULL,
        row_no integer NOT NULL,
        date_game date,
        id_game integer,
        payload jsonb NOT NULL,
        PRIMARY KEY (int_year, code, row_no)
      )
    ''');
      await conn.execute('''
      CREATE INDEX IF NOT EXISTS v_games_details_date
      ON v_games_details (int_year, code, date_game)
    ''');
      await conn.execute("ALTER TABLE t_game ADD COLUMN IF NOT EXISTS txt_lineup_announced TEXT NOT NULL DEFAULT ''");
      _ensured = true;
    } finally {
      try {
        await conn.execute("SELECT set_config('lock_timeout', \$1, false)", parameters: ['${previous.first[0]}']);
      } catch (_) {
        // 呼び出し元のトランザクションが中断された場合は、その rollback が復元する。
      }
    }
  }

  static Future<void> refreshPlayers(Connection conn, int year) {
    return _queue(() => _refreshPlayers(conn, year));
  }

  static Future<void> _refreshPlayers(Connection conn, int year) async {
    await ensure(conn);
    final rows = Postgres.toJson(await Postgres.execute(conn, AppSql.selectStatsPlayer(), data: [year]));
    for (final row in rows) {
      if (_asInt(row['int_rank']) != 1) {
        row.remove('prediction_name');
        row.remove('flg_pitcher');
        row.remove('league_name');
      }
    }
    await _atomic(conn, () async {
      await conn.execute('DELETE FROM v_stats_player WHERE int_year = \$1', parameters: [year]);
      await _insertPayloads(conn, 'v_stats_player', year, rows);
    });
    print('初期表示スナップショット: 個人成績 $year ${rows.length}件');
  }

  static Future<void> refreshTeams(Connection conn, int year) {
    return _queue(() => _refreshTeams(conn, year));
  }

  static Future<void> _refreshTeams(Connection conn, int year) async {
    await ensure(conn);
    final rows = Postgres.toJson(await Postgres.execute(conn, AppSql.selectStatsTeam(), data: [year]));
    // 起用データが未作成の環境でも順位表の更新は継続する。
    final pitchingTable = await conn.execute("SELECT to_regclass('t_strength_pitching') IS NOT NULL");
    if (pitchingTable.first.first == true) {
      final workloads = Postgres.toJson(await conn.execute('''SELECT id_team,
        SUM(starter_outs)::double precision / NULLIF(SUM(total_outs), 0) AS starter_workload_rate
        FROM t_strength_pitching WHERE int_year = \$1 GROUP BY id_team''', parameters: [year]));
      final byTeam = {for (final value in workloads) '${value['id_team']}': value['starter_workload_rate']};
      for (final row in rows) {
        row['starter_workload_rate'] = byTeam['${row['id_team']}'];
      }
    }
    await _atomic(conn, () async {
      await conn.execute('DELETE FROM v_stats_teams WHERE int_year = \$1', parameters: [year]);
      await _insertPayloads(conn, 'v_stats_teams', year, rows);
    });
    print('初期表示スナップショット: チーム成績 $year ${rows.length}件');
  }

  /// 初期表示の日付幅、または指定期間の試合集計を入れ直す。
  static Future<void> refreshGames(Connection conn, int year, {String? from, String? to}) {
    return _queue(() => _refreshGames(conn, year, from: from, to: to));
  }

  static Future<void> _refreshGames(Connection conn, int year, {String? from, String? to}) async {
    await ensure(conn);
    final window = (from != null && to != null) ? (from: from, to: to) : await sourceWindow(conn, year);
    final data = <Object>[year, window.from, window.to];
    final games = Postgres.toJson(await Postgres.execute(conn, AppSql.selectGames(ranged: true), data: data));
    final plays = Postgres.toJson(await Postgres.execute(conn, AppSql.selectGamePlayRows(ranged: true), data: data));
    final batting = Postgres.toJson(await Postgres.execute(conn, AppSql.selectBattingLines(ranged: true), data: data));
    final postseason = Postgres.toJson(await Postgres.execute(conn, AppSql.selectPostseasonGames(), data: [year]));
    final board = Postgres.toJson(await Postgres.execute(
      conn,
      AppSql.selectPostseasonBoard(),
      data: [
        Value.SystemCode.Code.ADMIN,
        Value.SystemCode.Key.DATE_FINAL_GAME,
        Value.SystemCode.Key.DATE_OPEN_GAME,
      ],
    ));
    final forms = <int, Map<String, dynamic>>{
      for (final game in games) _asInt(game['id_game']): Map<String, dynamic>.from(game),
    }.values.toList();
    await attachPostseasonForm(conn, forms, year);
    final formRows = [for (final game in forms) {
      'id_game': game['id_game'], 'date_game': game['date_game'],
      'postseason_form': game['postseason_form'] ?? [],
      'player_hands': game['player_hands'] ?? [],
    }];
    final dates = <int, String>{
      for (final game in games) _asInt(game['id_game']): _ymd('${game['date_game'] ?? ''}'),
    };
    await _atomic(conn, () async {
      // 複数プロセスの定期登録でもrow_noの採番と置換を直列化する。
      // SHARE ROW EXCLUSIVEは画面からの通常SELECTを妨げない。
      await conn.execute('LOCK TABLE v_games_details IN SHARE ROW EXCLUSIVE MODE');
      await conn.execute(
        '''
          DELETE FROM v_games_details
          WHERE int_year = \$1
            AND code IN ('game', 'play', 'batting', 'form')
            AND date_game BETWEEN \$2::date AND \$3::date
        ''',
        parameters: [year, window.from, window.to],
      );
      await _insertGameRows(conn, year, 'form', formRows, (row) => (_ymd('${row['date_game'] ?? window.from}'), _asInt(row['id_game'])));
      await _insertGameRows(conn, year, 'game', games, (row) => (_ymd('${row['date_game'] ?? window.from}'), _asInt(row['id_game'])));
      await _insertGameRows(conn, year, 'play', plays, (row) {
        final id = _asInt(row['id_game']);
        return (dates[id] ?? window.from, id);
      });
      await _insertGameRows(conn, year, 'batting', batting, (row) {
        final id = _asInt(row['id_game']);
        return (dates[id] ?? window.from, id);
      });
      await conn.execute(
        "DELETE FROM v_games_details WHERE int_year = \$1 AND code IN ('postseason', 'board')",
        parameters: [year],
      );
      await _insertGameRows(conn, year, 'postseason', postseason, (row) => (_ymd('${row['date_game'] ?? ''}'), _asInt(row['id_game'])));
      await _insertGameRows(conn, year, 'board', board, (_) => ('', 0));
      await _rememberSpan(conn, year, window.from, window.to);
    });
    print('初期表示スナップショット: 試合 ${window.from}〜${window.to} 試合${games.length} 打席${plays.length}');
  }

  static Future<List<Map<String, dynamic>>> players(Connection conn, int year) async {
    // 読み出しで再集計や登録は行わない。未登録年は空のまま返す。
    return _readYear(conn, 'v_stats_player', year);
  }

  static Future<PlayerDisplay> playerPart(Connection conn, int year, List<int> leagueIds) {
    return PredictionSnapshot.players(conn, year, leagueIds);
  }

  static Future<List<Map<String, dynamic>>> teams(Connection conn, int year) async {
    // Workload and standings refresh independently. Join the saved pitching totals
    // on every read so an older standings snapshot does not hide newer workload.
    final available = await conn.execute("SELECT to_regclass('public.t_strength_pitching') IS NOT NULL");
    if (available.first.first != true) return _readYear(conn, 'v_stats_teams', year);
    final rows = await conn.execute('''
      WITH workload AS (
        SELECT id_team, SUM(starter_outs)::double precision / NULLIF(SUM(total_outs), 0) AS rate
        FROM t_strength_pitching WHERE int_year = \$1 GROUP BY id_team
      )
      SELECT s.payload || CASE WHEN w.id_team IS NULL THEN '{}'::jsonb
        ELSE jsonb_build_object('starter_workload_rate', w.rate) END
      FROM v_stats_teams s LEFT JOIN workload w ON w.id_team = (s.payload->>'id_team')::integer
      WHERE s.int_year = \$1 ORDER BY s.row_no
    ''', parameters: [year]);
    return [for (final row in rows) _decode(row[0])];
  }

  static Future<DisplayGames> games(Connection conn, int year, {String? from, String? to}) async {
    await ensure(conn);
    final window = (from != null && to != null) ? (from: from, to: to) : await sourceWindow(conn, year);
    final spans = await _spans(conn, year);
    if (!spansCover(spans, window.from, window.to)) {
      await refreshGames(conn, year, from: window.from, to: window.to);
    }
    // 同じスナップショットの読み取りをまとめ、遠隔DBとの5往復を避ける。
    final rows = await conn.execute(
      """
        SELECT code, payload FROM v_games_details
        WHERE int_year = \$1 AND (
          (code IN ('game', 'play', 'batting', 'form')
            AND date_game BETWEEN \$2::date AND \$3::date)
          OR code IN ('postseason', 'board')
        )
        ORDER BY code, row_no
      """,
      parameters: [year, window.from, window.to],
    );
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      grouped.putIfAbsent('${row[0]}', () => []).add(_decode(row[1]));
    }
    return DisplayGames(
      games: grouped['game'] ?? [],
      forms: grouped['form'] ?? [],
      plays: grouped['play'] ?? [],
      batting: grouped['batting'] ?? [],
      postseason: grouped['postseason'] ?? [],
      board: grouped['board'] ?? [],
      from: window.from,
      to: window.to,
    );
  }

  static Future<({String from, String to})> sourceWindow(Connection conn, int year) async {
    final rows = await conn.execute(
      '''
        SELECT
          CASE
            WHEN \$1::int = EXTRACT(YEAR FROM CURRENT_DATE)::int
              THEN (CURRENT_DATE - ${AppSql.gamesPastDays})::text
            ELSE COALESCE(
              (SELECT (MAX(gw.datetime_start)::date - 10)::text FROM t_game gw
               WHERE EXTRACT(YEAR FROM gw.datetime_start) = \$1
                 AND COALESCE(gw.flg_delete, FALSE) = FALSE),
              make_date(\$1, 10, 1)::text
            )
          END,
          CASE
            WHEN \$1::int = EXTRACT(YEAR FROM CURRENT_DATE)::int
              THEN (CURRENT_DATE + ${AppSql.gamesFutureDays})::text
            ELSE COALESCE(
              (SELECT MAX(gw.datetime_start)::date::text FROM t_game gw
               WHERE EXTRACT(YEAR FROM gw.datetime_start) = \$1
                 AND COALESCE(gw.flg_delete, FALSE) = FALSE),
              make_date(\$1, 10, 31)::text
            )
          END
      ''',
      parameters: [year],
    );
    final from = _ymd('${rows.first[0]}');
    final to = _ymd('${rows.first[1]}');
    return from.compareTo(to) <= 0 ? (from: from, to: to) : (from: to, to: from);
  }

  static Future<void> _atomic(Connection conn, Future<void> Function() body) async {
    try {
      await conn.execute('SAVEPOINT display_snapshot');
    } catch (_) {
      await Postgres.transactionCommit(conn, body);
      return;
    }
    try {
      await body();
      await conn.execute('RELEASE SAVEPOINT display_snapshot');
    } catch (e) {
      try {
        await conn.execute('ROLLBACK TO SAVEPOINT display_snapshot');
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> _insertPayloads(Connection conn, String table, int year, List<Map<String, dynamic>> rows) async {
    const size = 40;
    for (var i = 0; i < rows.length; i += size) {
      final end = i + size < rows.length ? i + size : rows.length;
      final values = <String>[];
      final params = <Object?>[];
      var p = 1;
      for (var j = i; j < end; j++) {
        values.add('(\$$p, \$${p + 1}, \$${p + 2}::jsonb)');
        params.addAll([year, j, jsonEncode(rows[j])]);
        p += 3;
      }
      await conn.execute(
        'INSERT INTO $table (int_year, row_no, payload) VALUES ${values.join(', ')}',
        parameters: params,
      );
    }
  }

  static Future<void> _insertGameRows(
    Connection conn,
    int year,
    String code,
    List<Map<String, dynamic>> rows,
    (String, int) Function(Map<String, dynamic> row) meta,
  ) async {
    if (rows.isEmpty) return;
    final maxRow = await conn.execute(
      'SELECT COALESCE(MAX(row_no), -1) FROM v_games_details WHERE int_year = \$1 AND code = \$2',
      parameters: [year, code],
    );
    var rowNo = _asInt(maxRow.first[0]) + 1;
    const size = 40;
    for (var i = 0; i < rows.length; i += size) {
      final end = i + size < rows.length ? i + size : rows.length;
      final values = <String>[];
      final params = <Object?>[];
      var p = 1;
      for (var j = i; j < end; j++) {
        final pair = meta(rows[j]);
        final date = pair.$1.length >= 10 ? pair.$1.substring(0, 10) : null;
        values.add('(\$$p, \$${p + 1}, \$${p + 2}, \$${p + 3}::date, \$${p + 4}, \$${p + 5}::jsonb)');
        params.addAll([year, code, rowNo, date, pair.$2 == 0 ? null : pair.$2, jsonEncode(rows[j])]);
        rowNo++;
        p += 6;
      }
      await conn.execute(
        '''
          INSERT INTO v_games_details (int_year, code, row_no, date_game, id_game, payload)
          VALUES ${values.join(', ')}
        ''',
        parameters: params,
      );
    }
  }

  static Future<void> _rememberSpan(Connection conn, int year, String from, String to) async {
    final spans = await _spans(conn, year);
    if (spansCover(spans, from, to) && spans.any((span) => span.from == from && span.to == to)) {
      return;
    }
    final maxRow = await conn.execute(
      "SELECT COALESCE(MAX(row_no), -1) FROM v_games_details WHERE int_year = \$1 AND code = 'span'",
      parameters: [year],
    );
    await conn.execute(
      '''
        INSERT INTO v_games_details (int_year, code, row_no, payload)
        VALUES (\$1, 'span', \$2, \$3::jsonb)
      ''',
      parameters: [
        year,
        _asInt(maxRow.first[0]) + 1,
        jsonEncode({'from': from, 'to': to})
      ],
    );
  }

  static Future<List<({String from, String to})>> _spans(Connection conn, int year) async {
    final rows = await conn.execute(
      "SELECT payload FROM v_games_details WHERE int_year = \$1 AND code = 'span'",
      parameters: [year],
    );
    final spans = <({String from, String to})>[];
    for (final row in rows) {
      final payload = _decode(row[0]);
      final from = _ymd('${payload['from'] ?? ''}');
      final to = _ymd('${payload['to'] ?? ''}');
      if (from.isEmpty || to.isEmpty) continue;
      spans.add((from: from, to: to));
    }
    return spans;
  }

  static Future<List<Map<String, dynamic>>> _readYear(Connection conn, String table, int year) async {
    final rows = await conn.execute(
      'SELECT payload FROM $table WHERE int_year = \$1 ORDER BY row_no',
      parameters: [year],
    );
    return [for (final row in rows) _decode(row[0])];
  }

  static Map<String, dynamic> _decode(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return {};
  }
}

class DisplayGames {
  final List<Map<String, dynamic>> games;
  final List<Map<String, dynamic>> forms;
  final List<Map<String, dynamic>> plays;
  final List<Map<String, dynamic>> batting;
  final List<Map<String, dynamic>> postseason;
  final List<Map<String, dynamic>> board;
  final String from;
  final String to;

  const DisplayGames({
    required this.games,
    this.forms = const [],
    required this.plays,
    required this.batting,
    required this.postseason,
    required this.board,
    required this.from,
    required this.to,
  });
}

/// [from] から [to] まで（両端を含む）が、登録済み期間のどれかに入っているか。
bool spansCover(List<({String from, String to})> spans, String from, String to) {
  if (from.isEmpty || to.isEmpty) return false;
  var day = from;
  var guard = 0;
  while (day.compareTo(to) <= 0 && guard < 400) {
    final covered = spans.any((span) => span.from.compareTo(day) <= 0 && span.to.compareTo(day) >= 0);
    if (!covered) return false;
    if (day == to) return true;
    day = nextYmd(day);
    guard++;
  }
  return day.compareTo(to) > 0;
}

String nextYmd(String ymd) {
  final parts = ymd.split('-');
  if (parts.length != 3) return ymd;
  final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  final next = date.add(const Duration(days: 1));
  final month = next.month.toString().padLeft(2, '0');
  final day = next.day.toString().padLeft(2, '0');
  return '${next.year}-$month-$day';
}

int _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

String _ymd(String raw) {
  final text = raw.trim();
  if (text.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)) {
    return text.substring(0, 10);
  }
  return '';
}
