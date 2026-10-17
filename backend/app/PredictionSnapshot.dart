import 'ScheduledLog.dart';
import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../tools/Postgres.dart';
import 'AppSql.dart';
import 'PlayerDisplay.dart';
import 'PlayerDetail.dart';
import 'PredictGroup.dart';

/// 予想の表示結果を登録する。画面の読出しはこのテーブルの SELECT だけ。
class PredictionSnapshot {
  static bool _ready = false;
  static const _lockKey = 1640749321;

  static Future<void> ensureSchema(Connection conn) async {
    if (_ready) return;
    final present = await conn.execute('''
      SELECT to_regclass('public.v_predict_team') IS NOT NULL
        AND to_regclass('public.v_predict_stats') IS NOT NULL
        AND to_regclass('public.v_predict_group') IS NOT NULL
        AND to_regclass('public.v_predict_catalog') IS NOT NULL
    ''');
    if (present.isNotEmpty && present.first[0] == true) {
      _ready = true;
      return;
    }
    for (final table in ['v_predict_team', 'v_predict_stats']) {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS $table (
          int_year integer NOT NULL,
          kind text NOT NULL,
          id_league integer NOT NULL,
          row_no integer NOT NULL,
          payload jsonb NOT NULL,
          updated_at timestamptz NOT NULL DEFAULT NOW(),
          PRIMARY KEY (int_year, kind, id_league, row_no)
        )
      ''');
    }
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS v_predict_group (
        id_predict_group integer NOT NULL,
        id_setting integer NOT NULL,
        int_year integer,
        payload jsonb NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT NOW(),
        PRIMARY KEY (id_predict_group, id_setting)
      )
    ''');
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS v_predict_catalog (
        id integer PRIMARY KEY CHECK (id = 1),
        payload jsonb NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT NOW()
      )
    ''');
    _ready = true;
  }

  /// 定期処理/保存完了時だけ呼ぶ。集計から置換までを直列化し、古い結果の上書きを防ぐ。
  /// トランザクション単位のロックは接続断でも自動的に解放される。
  static Future<void> refresh(Connection conn,
      {bool allYears = false, Set<int>? years, bool groupsOnly = false}) async {
    final watch = Stopwatch()..start();
    var aggregateMs = 0;
    var playerReadMs = 0;
    var publishMs = 0;
    await ensureSchema(conn);
    await PredictGroup.ensureSchema(conn);
    await Postgres.transactionCommit(conn, () async {
      await conn
          .execute('SELECT pg_advisory_xact_lock(\$1)', parameters: [_lockKey]);
      final selectedYears = years?.where((year) => year > 0).toList();
      final yearRows = await conn.execute(selectedYears != null
          ? 'SELECT unnest(ARRAY[${selectedYears.join(', ')}]::int[])'
          : allYears
              ? '''
        SELECT EXTRACT(YEAR FROM CURRENT_DATE)::int AS int_year
        UNION SELECT int_year FROM v_stats_player
        UNION SELECT int_year FROM v_predict_stats
        UNION SELECT year FROM t_predict_player WHERE year IS NOT NULL
        UNION SELECT int_year FROM t_predict_team WHERE int_year IS NOT NULL
        UNION SELECT int_year FROM t_predict_setting WHERE COALESCE(flg_delete, FALSE) = FALSE
      '''
              : 'SELECT EXTRACT(YEAR FROM CURRENT_DATE)::int');
      final targetYears = [for (final row in yearRows) _int(row[0])]
          .where((year) => year > 0)
          .toSet()
          .toList()
        ..sort();
      final groupStart = watch.elapsedMilliseconds;
      final groupRows = await PredictGroup.aggregate(conn,
          years: allYears ? null : targetYears.toSet());
      final titleRows = await PredictGroup.aggregateTitleCatalog(conn);
      aggregateMs = watch.elapsedMilliseconds - groupStart;
      for (final year in groupsOnly ? const <int>[] : targetYears) {
        final readStart = watch.elapsedMilliseconds;
        final teamRows = Postgres.toJson(await Postgres.execute(
            conn, AppSql.selectPredictNPBTeams(),
            data: [year]));
        final raw = await conn.execute(
            AppSql.selectPlayerDisplaySource([1, 2, 3, 4]),
            parameters: [year]);
        final stats = <Map<String, dynamic>>[];
        final picks = <Map<String, dynamic>>[];
        for (final row in raw) {
          (row[0] == 'stats' ? stats : picks).add(_decode(row[2]));
        }
        final display = buildPlayerDisplay(stats, picks);
        playerReadMs += watch.elapsedMilliseconds - readStart;
        final publishStart = watch.elapsedMilliseconds;
        await _replaceYear(
            conn, 'v_predict_team', year, {'prediction': teamRows});
        await _replaceYear(conn, 'v_predict_stats', year,
            {'stats': display.stats, 'prediction': display.predictions});
        publishMs += watch.elapsedMilliseconds - publishStart;
      }
      // グループの削除や年度変更も同じコミットで反映する。
      final groupPublishStart = watch.elapsedMilliseconds;
      await conn.execute(allYears
          ? 'DELETE FROM v_predict_group'
          : 'DELETE FROM v_predict_group WHERE int_year IN (${targetYears.join(', ')}) OR int_year IS NULL');
      await conn.execute('''
        INSERT INTO v_predict_group (id_predict_group, id_setting, int_year, payload)
        SELECT (item->>'id')::int, (item->>'id_setting')::int,
               (item->>'int_year')::int, item
        FROM jsonb_array_elements(\$1::jsonb) AS rows(item)
      ''', parameters: [jsonEncode(groupRows)]);
      await conn.execute('''
        INSERT INTO v_predict_catalog (id, payload) VALUES (1, \$1::jsonb)
        ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, updated_at = NOW()
      ''', parameters: [jsonEncode(titleRows)]);
      publishMs += watch.elapsedMilliseconds - groupPublishStart;
      print('予想スナップショット登録: ${targetYears.length}年度、${groupRows.length}グループ年度');
    });
    print('予想スナップショット登録時間: ${watch.elapsedMilliseconds}ms '
        '(グループ集計 ${aggregateMs}ms, 予想読取 ${playerReadMs}ms, 登録 ${publishMs}ms)');
  }

  /// 予想入力は対象年度だけ、名称/招待/投票はグループ表示だけ更新する。
  static Future<void> refreshAfterSave(
      Connection conn, Map<String, dynamic> result) async {
    final settingId = _int(result['id_setting']);
    if (settingId > 0) {
      final rows = await conn.execute(
          'SELECT int_year FROM t_predict_setting WHERE id = \$1',
          parameters: [settingId]);
      if (rows.isNotEmpty) {
        await refresh(conn, years: {_int(rows.first[0])});
        return;
      }
    }
    await refresh(conn, allYears: true, groupsOnly: true);
  }

  static Future<void> _replaceYear(Connection conn, String table, int year,
      Map<String, List<Map<String, dynamic>>> parts) async {
    final rows = [
      for (final part in parts.entries)
        for (final row in part.value.indexed)
          {
            'kind': part.key,
            'id_league': _int(row.$2['id_league']),
            'row_no': row.$1,
            'payload': row.$2
          },
    ];
    await conn
        .execute('DELETE FROM $table WHERE int_year = \$1', parameters: [year]);
    await conn.execute('''
      INSERT INTO $table (int_year, kind, id_league, row_no, payload)
      SELECT \$1, kind, id_league, row_no, payload
      FROM jsonb_to_recordset(\$2::jsonb) AS row(kind text, id_league integer, row_no integer, payload jsonb)
    ''', parameters: [year, jsonEncode(rows)]);
  }

  static Future<List<Map<String, dynamic>>> teams(
      Connection conn, int year, List<int> leagueIds) async {
    final rows = await conn.execute('''
      SELECT payload FROM v_predict_team
      WHERE int_year = \$1 AND id_league IN (${_leagues(leagueIds)})
      ORDER BY row_no
    ''', parameters: [year]);
    return [for (final row in rows) _decode(row[0])];
  }

  static Future<PlayerDisplay> players(
      Connection conn, int year, List<int> leagueIds) async {
    final rows = await conn
        .execute(AppSql.selectPlayerDisplay(leagueIds), parameters: [year]);
    final stats = <Map<String, dynamic>>[];
    final picks = <Map<String, dynamic>>[];
    for (final row in rows) {
      (row[0] == 'stats' ? stats : picks).add(_decode(row[2]));
    }
    final positions = {for (final r in await conn.execute('SELECT p.id,p.txt_position FROM m_player p JOIN m_team t ON t.id=p.id_team WHERE t.id_league=ANY(\$1::int[])',parameters:[leagueIds])) '${r[0]}': r[1]};
    for (final row in stats) {
      if ('${row['txt_position'] ?? ''}'.trim().isEmpty || row['txt_position'] == '不明') row['txt_position'] = positions['${row['id_player']}'];
    }
    stats.addAll(await extraStatRows(conn, year, leagueIds));
    addMissingRequestedMetrics(stats);
    return PlayerDisplay(stats: stats, predictions: picks);
  }

  static String get _groupSelect => '''
    SELECT v.payload FROM v_predict_group v
    JOIN t_predict_group g ON g.id = v.id_predict_group
      AND COALESCE(g.flg_delete, FALSE) = FALSE
    WHERE EXISTS (
      SELECT 1 FROM t_predict_group_user mem
      WHERE mem.id_predict_group = v.id_predict_group
        AND mem.id_user = \$1::int AND COALESCE(mem.flg_delete, FALSE) = FALSE
    ) AND (v.id_setting = 0 OR EXISTS (
      SELECT 1 FROM t_predict_setting s
      WHERE s.id = v.id_setting AND s.id_predict_group = v.id_predict_group
        AND COALESCE(s.flg_delete, FALSE) = FALSE
    ))
  ''';

  static Future<List<Map<String, dynamic>>> groups(Connection conn,
      {required int userId}) async {
    if (userId <= 0) return [];
    final rows = await conn.execute(
        '$_groupSelect ORDER BY v.int_year DESC NULLS LAST, g.txt_name, g.id',
        parameters: [userId]);
    return [for (final row in rows) _decode(row[0])];
  }

  static Future<List<Map<String, dynamic>>> catalog(Connection conn) async {
    final rows = await conn
        .execute('SELECT payload FROM v_predict_catalog WHERE id = 1');
    if (rows.isEmpty) return [];
    return _decodeList(rows.first[0]);
  }

  /// グループと編集用タイトルを同一往復で読む。匿名要求はグループを返さない。
  static Future<Map<String, dynamic>> groupPayload(Connection conn,
      {required int? userId}) async {
    final rows = await conn.execute('''
      SELECT 'group' AS kind, payload FROM ($_groupSelect) AS groups
      UNION ALL
      SELECT 'catalog' AS kind, payload FROM v_predict_catalog WHERE id = 1
    ''', parameters: [userId ?? 0]);
    final groups = <Map<String, dynamic>>[];
    var titles = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row[0] == 'group') {
        groups.add(_decode(row[1]));
      } else {
        titles = _decodeList(row[1]);
      }
    }
    groups.sort((a, b) {
      final year = _int(b['int_year']).compareTo(_int(a['int_year']));
      if (year != 0) return year;
      final name = '${a['txt_name']}'.compareTo('${b['txt_name']}');
      return name != 0 ? name : _int(a['id']).compareTo(_int(b['id']));
    });
    return {'groups': groups, 'title_catalog': titles};
  }

  static String _leagues(List<int> ids) {
    final values = ids.where((id) => id > 0).toSet().toList()..sort();
    return values.isEmpty ? 'NULL' : values.join(', ');
  }

  static int _int(Object? value) => int.tryParse('$value') ?? 0;
  static Map<String, dynamic> _decode(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  static List<Map<String, dynamic>> _decodeList(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    return decoded is List ? [for (final row in decoded) _decode(row)] : [];
  }
}

/// サーバーの起動や GET 要求は集計を待たない。登録済みデータを5分ごとに更新する。
class PredictionSnapshotSchedule {
  static const interval = Duration(minutes: 5);
  static Timer? _timer;
  static bool _busy = false;

  static void start({required void Function() onUpdated}) {
    _timer?.cancel();
    _timer =
        Timer.periodic(interval, (_) => unawaited(tick(onUpdated: onUpdated)));
  }

  static Future<void> tick({required void Function() onUpdated}) async {
    if (_busy) return;
    _busy = true;
    try {
      await ScheduledLog.run('prediction_snapshot',
          () => Postgres.withConnection(PredictionSnapshot.refresh));
      onUpdated();
    } catch (e, st) {
      print('予想スナップショット定期登録失敗: $e\n$st');
    } finally {
      _busy = false;
    }
  }
}
