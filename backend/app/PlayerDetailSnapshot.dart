import 'dart:async';
import 'dart:convert';
import 'package:postgres/postgres.dart';
import '../tools/Postgres.dart';
import 'PlayerDetail.dart';
import 'ScheduledLog.dart';
import 'StrengthUsage.dart' show usageMaps;

/// Request path reads one indexed JSON snapshot. All aggregation and upstream
/// requests belong to refresh(), never to opening a player dialog.
class PlayerDetailSnapshot {
  static Timer? _startup, _timer;
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
      _ready = (await conn.execute("SELECT to_regclass('public.t_player_detail_snapshot') IS NOT NULL")).first[0] == true;
    }
    if (!_ready) {
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
    if (rows.length != 1)
      return {
        'found': false,
        'pending': rows.isEmpty,
        'message': rows.isEmpty
            ? '選手情報の事前集計はまだ完了していません。更新後に再度開いてください。'
            : '選手を一意に特定できませんでした。'
      };
    return {...detailMap(rows.single[0]), 'updated_at': rows.single[1]};
  }

  static Future<Map<String, dynamic>> refresh(int year,
      {Set<int>? playerIds}) async {
    if (_busy) return {'skipped': true};
    _busy = true;
    var count = 0, failed = 0;
    try {
      final people = await Postgres.withConnection((conn) async {
        await ensure(conn);
        return (await conn.execute(
                '''SELECT p.id,t.id_league,d.updated_at::text AS snapshot_updated FROM m_player p JOIN m_team t ON t.id=p.id_team
          LEFT JOIN t_player_detail_snapshot d ON d.id_player=p.id AND d.int_year=\$1
          WHERE t.id_league IN (1,2,3,4) AND NOT COALESCE(p.flg_delete,false)
          ORDER BY d.updated_at NULLS FIRST,p.id''',
                parameters: [year]))
            .map((r) => r.toColumnMap())
            .toList();
      });
      print('選手詳細: 対象 ${people.length} 人、共通データ読込');
      final batch = await Postgres.withConnection(
          (conn) => PlayerDetailBatch.load(conn, year));
      final activeIds = <int>{
        for (final r in batch.stats)
          if (r['id_player'] is int) r['id_player'] as int,
        for (final r in batch.careers)
          if (r['int_year'] == year && r['id_player'] is int)
            r['id_player'] as int,
      };
      for (final team in batch.teams) {
        final candidates =
            batch.people.where((p) => p['id_team'] == team['id_team']).toList();
        for (final r in usageMaps(team['roster'])) {
          final p = matchPlayer(
              {'name': r['name'], 'id_team': team['id_team']}, candidates);
          if (p != null) activeIds.add(p['id'] as int);
        }
      }
      print('選手詳細: 共通データ読込完了、今季対象 ${activeIds.length} 人');
      final selected = people
          .where((p) => (playerIds ?? activeIds).contains(p['id']))
          .where((p) => playerIds != null || (DateTime.tryParse('${p['snapshot_updated']}')?.isAfter(DateTime.now().subtract(const Duration(hours:1))) != true))
          .toList();
      await Postgres.withConnection((conn) => batch.loadRecentGames(
          conn, year, selected.map((p) => p['id'] as int).toList()));
      for (var offset = 0; offset < selected.length; offset += 20) {
        final group = selected.skip(offset).take(20).toList();
        await Postgres.withConnection((conn) async {
          final records = <Map<String,dynamic>>[];
          Future<void> prepare(Map<String,dynamic> person) async {
            try {
              final data = await readPlayerDetail(conn,year:year,
                leagues:(person['id_league'] as int)<=2 ? [1,2] : [3,4],
                identity:{'id_player':person['id']},batch:batch);
              if(data['found'] != true) return;
              final p=detailMap(data['profile']);
              records.add({'int_year':year,'id_player':person['id'],'id_league':p['id_league'],
                'id_team':p['id_team'],'source_player_id':officialPlayerId(p),
                'normalized_name':normalizedPlayerName(p['name_full']),'payload':data});
            } catch(e) { failed++; print('選手詳細事前集計 ${person['id']}: $e'); }
          }
          // Shared season/game inputs mean prepare() performs no DB queries.
          for(var i=0;i<group.length;i+=4) await Future.wait(group.skip(i).take(4).map(prepare));
          await conn.execute('''INSERT INTO t_player_detail_snapshot
            (int_year,id_player,id_league,id_team,source_player_id,normalized_name,payload)
            SELECT int_year,id_player,id_league,id_team,source_player_id,normalized_name,payload
            FROM jsonb_to_recordset(\$1::jsonb) AS x(int_year int,id_player int,id_league int,id_team int,source_player_id text,normalized_name text,payload jsonb)
            ON CONFLICT (int_year,id_player) DO UPDATE SET id_league=excluded.id_league,id_team=excluded.id_team,
            source_player_id=excluded.source_player_id,normalized_name=excluded.normalized_name,
            payload=excluded.payload,updated_at=now()''',parameters:[jsonEncode(records)]);
          count+=records.length;
        });
        print('選手詳細: $count 人保存済み');
      }
      return {'year': year, 'updated': count, 'failed': failed};
    } finally {
      _busy = false;
    }
  }

  static void start() {
    _startup?.cancel();
    _timer?.cancel();
    Future<void> tick() async {
      try {
        await ScheduledLog.run(
            'player_detail_snapshot', () => refresh(DateTime.now().year));
      } catch (e) {
        print('選手詳細定期集計: $e');
      }
    }

    _startup = Timer(const Duration(seconds: 30), tick);
    _timer = Timer.periodic(const Duration(hours: 6), (_) => unawaited(tick()));
  }
}
