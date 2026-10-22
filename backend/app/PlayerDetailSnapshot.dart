import 'dart:async';
import 'dart:convert';
import 'package:postgres/postgres.dart';
import '../tools/Postgres.dart';
import 'PlayerDetail.dart';
import 'PlayerArt.dart';
import 'ScheduledLog.dart';
import 'SnapshotWork.dart';

/// Request path reads one indexed JSON snapshot. All aggregation and upstream
/// requests belong to refresh(), never to opening a player dialog.
class PlayerDetailSnapshot {
  static Timer? _timer;
  static Timer? _pendingTimer;
  static final _requestedPlayers = <int, Set<int>>{};
  static void _request(int year, Map<String, dynamic> identity) {
    final id = int.tryParse('${identity['id_player']}') ?? 0;
    if (id > 0) _requestedPlayers.putIfAbsent(year, () => <int>{}).add(id);
  }
  static Future<void> _fillRequested() async {
    if (_busy) return;
    for (final year in _requestedPlayers.keys.toList()) {
      final ids = _requestedPlayers[year]!.take(20).toSet();
      if (ids.isEmpty) continue;
      final result = await refresh(year, playerIds: ids);
      if (result['skipped'] != true && result['failed'] == 0) {
        _requestedPlayers[year]?.removeAll(ids);
      }
      break;
    }
  }
  static bool _busy = false;
  static bool _ready = false;
  static Future<void> ensure(Connection conn) async {
    await conn.execute('''CREATE TABLE IF NOT EXISTS t_player_detail_snapshot (
      int_year int NOT NULL, id_player int NOT NULL, id_league int NOT NULL,
      id_team int NOT NULL, source_player_id text, normalized_name text NOT NULL,
      payload jsonb NOT NULL, updated_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (int_year,id_player))''');
    await conn.execute(
        'CREATE INDEX IF NOT EXISTS player_detail_source_idx ON t_player_detail_snapshot(int_year,source_player_id)');
    await conn.execute(
        'CREATE INDEX IF NOT EXISTS player_detail_name_idx ON t_player_detail_snapshot(int_year,normalized_name,id_team)');
    _ready = true;
  }

  static Future<Map<String, dynamic>> read(Connection conn,
      {required int year,
      required List<int> leagues,
      required Map<String, dynamic> identity}) async {
    if (!_ready) {
      _ready = (await conn.execute(
                  "SELECT to_regclass('public.t_player_detail_snapshot') IS NOT NULL"))
              .first[0] ==
          true;
    }
    if (!_ready) {
      _request(year, identity);
      final art = leagues.any((league) => league == 1 || league == 2)
          ? await PlayerArt.official(conn, identity)
          : null;
      if (art != null) return art;
      return {
        'found': false,
        'pending': true,
        'message': '選手情報を事前集計しています。しばらくしてから再度開いてください。'
      };
    }
    final id = int.tryParse('${identity['id_player']}') ?? 0;
    final source = '${identity['source_player_id'] ?? ''}';
    final name = normalizedPlayerName(identity['name'] ?? '');
    final team = int.tryParse('${identity['id_team']}');
    final rows = await conn.execute(
        '''SELECT payload,updated_at::text FROM t_player_detail_snapshot
      WHERE int_year=\$1 AND id_league=ANY(\$2::int[])
      AND (CASE WHEN \$3::int>0 THEN id_player=\$3
        WHEN \$4::text<>'' THEN source_player_id=\$4
        ELSE normalized_name=\$5 END)
      AND (\$3::int>0 OR \$6::int IS NULL OR id_team=\$6)
      LIMIT 2''',
        parameters: [year, leagues, id, source, name, team]);
    if (rows.length != 1) {
      if (rows.isEmpty) _request(year, identity);
      if (rows.isEmpty && leagues.any((league) => league == 1 || league == 2)) {
        final art = await PlayerArt.official(conn, identity);
        if (art != null) return art;
      }
      return {
        'found': false,
        'pending': rows.isEmpty,
        'message': rows.isEmpty
            ? '選手情報の事前集計はまだ完了していません。更新後に再度開いてください。'
            : '選手を一意に特定できませんでした。'
      };
    }
    final payload = detailMap(rows.single[0]);
    final playerId = int.tryParse('${detailMap(payload['profile'])['id']}');
    return {
      ...payload,
      'updated_at': rows.single[1],
      if (playerId != null)
        'character_image': await PlayerArt.read(conn, playerId,
            sourceId: officialPlayerId(detailMap(payload['profile'])))
    };
  }

  static Future<Map<String, dynamic>> refresh(int year,
      {Set<int>? playerIds, int? maxPlayers}) async {
    if (_busy || !SnapshotWork.tryStart()) return {'skipped': true};
    _busy = true;
    var count = 0, failed = 0;
    try {
      final people = await Postgres.withConnection((conn) async {
        await ensure(conn);
        return (await conn.execute(
                '''SELECT p.id,t.id_league,d.updated_at::text AS snapshot_updated FROM m_player p JOIN m_team t ON t.id=p.id_team
          LEFT JOIN t_player_detail_snapshot d ON d.id_player=p.id AND d.int_year=\$1
          WHERE t.id_league IN (1,2,3,4) AND NOT COALESCE(p.flg_delete,false)
          AND (CASE WHEN \$2::int[] IS NOT NULL THEN p.id=ANY(\$2::int[]) ELSE
            (COALESCE(p.year_retire,0)=0 OR p.year_retire>\$1)
            AND (EXISTS(SELECT 1 FROM m_player_career c WHERE c.id_player=p.id AND c.int_year=\$1 AND NOT COALESCE(c.flg_delete,false))
            OR EXISTS(SELECT 1 FROM v_stats_player s WHERE s.int_year=\$1 AND (s.payload->>'id_player')::int=p.id)
            OR EXISTS(SELECT 1 FROM t_team_strength ts CROSS JOIN LATERAL jsonb_array_elements(COALESCE(ts.payload->'roster','[]'::jsonb)) r
              WHERE ts.int_year=\$1 AND ts.id_team=p.id_team AND regexp_replace(r->>'name','[[:space:]　]','','g')=regexp_replace(p.name_full,'[[:space:]　]','','g'))
            )
          END)
          ORDER BY d.updated_at NULLS FIRST,p.id''',
                parameters: [year, playerIds?.toList()]))
            .map((r) => r.toColumnMap())
            .toList();
      });
      // Explicit IDs allow maintenance of retired players; automatic refresh
      // keeps their saved snapshots and only loads current-season candidates.
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      final selected = people
          .where((p) =>
              playerIds != null ||
              DateTime.tryParse('${p['snapshot_updated']}')?.isAfter(cutoff) !=
                  true)
          .take(maxPlayers ?? people.length).toList();
      if (selected.isEmpty) {
        return {
          'year': year,
          'updated': 0,
          'failed': 0,
          'fresh': people.isNotEmpty
        };
      }
      print('選手詳細: 対象 ${selected.length} 人、共通データ読込');
      final batch = await Postgres.withConnection((conn) =>
          PlayerDetailBatch.load(conn, year,
              playerIds: selected.map((p) => p['id'] as int).toList()));
      // Never retain all players' career and game JSON at once on the web server.
      for (var offset = 0; offset < selected.length; offset += 20) {
        final group = selected.skip(offset).take(20).toList();
        await Postgres.withConnection((conn) async {
          await batch.loadPlayerGroup(
              conn, year, group.map((p) => p['id'] as int).toList());
          final records = <Map<String, dynamic>>[];
          Future<void> prepare(Map<String, dynamic> person) async {
            try {
              final data = await readPlayerDetail(conn,
                  year: year,
                  leagues: (person['id_league'] as int) <= 2 ? [1, 2] : [3, 4],
                  identity: {'id_player': person['id']},
                  batch: batch);
              if (data['found'] != true) return;
              final p = detailMap(data['profile']);
              records.add({
                'int_year': year,
                'id_player': person['id'],
                'id_league': p['id_league'],
                'id_team': p['id_team'],
                'source_player_id': officialPlayerId(p),
                'normalized_name': normalizedPlayerName(p['name_full']),
                'payload': data
              });
            } catch (e) {
              failed++;
              print('選手詳細事前集計 ${person['id']}: $e');
            }
          }

          // Shared season/game inputs mean prepare() performs no DB queries.
          for (final person in group) {
            await prepare(person);
          }
          await conn.execute('''INSERT INTO t_player_detail_snapshot
            (int_year,id_player,id_league,id_team,source_player_id,normalized_name,payload)
            SELECT int_year,id_player,id_league,id_team,source_player_id,normalized_name,payload
            FROM jsonb_to_recordset(\$1::jsonb) AS x(int_year int,id_player int,id_league int,id_team int,source_player_id text,normalized_name text,payload jsonb)
            ON CONFLICT (int_year,id_player) DO UPDATE SET id_league=excluded.id_league,id_team=excluded.id_team,
            source_player_id=excluded.source_player_id,normalized_name=excluded.normalized_name,
            payload=excluded.payload,updated_at=now()''',
              parameters: [jsonEncode(records)]);
          count += records.length;
        });
        print('選手詳細: $count 人保存済み');
      }
      return {'year': year, 'updated': count, 'failed': failed};
    } finally {
      _busy = false;
      SnapshotWork.finish();
    }
  }

  static void start() {
    _timer?.cancel();
    _pendingTimer?.cancel();
    _pendingTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      try {
        if (_requestedPlayers.values.any((ids) => ids.isNotEmpty)) {
          await ScheduledLog.run('player_detail_missing', _fillRequested);
        }
      } catch (e) { print('選手詳細の未集計補完: $e'); }
    });
    Future<void> tick() async {
      try {
        await ScheduledLog.run(
            'player_detail_snapshot', () => refresh(DateTime.now().year, maxPlayers: 20));
      } catch (e) {
        print('選手詳細定期集計: $e');
      }
    }

    // Keep stored data available while the background worker fills missing / stale players.
    Timer(const Duration(minutes: 2), () => unawaited(tick()));
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(tick()));
  }
}
