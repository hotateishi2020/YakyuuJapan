import 'dart:async';
import 'dart:convert';
import 'package:postgres/postgres.dart';
import '../tools/Postgres.dart';
import 'ClubData.dart';
import 'DisplaySnapshot.dart';
import 'OrgLeague.dart';
import 'Records.dart';
import 'ScheduledLog.dart';
import 'SnapshotWork.dart';

/// Persistent, atomically published page results. HTTP readers never aggregate.
class PageSnapshot {
  static Timer? _timer;
  static bool _busy = false;
  static final _requested = <(String, String, int)>{};

  static Future<void> ensure(Connection conn) async {
    await conn.execute('''CREATE TABLE IF NOT EXISTS t_page_snapshot (
      kind text NOT NULL, code_org text NOT NULL, int_year int NOT NULL,
      payload jsonb NOT NULL, updated_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY(kind,code_org,int_year))''');
  }

  static Future<Map<String, dynamic>> read(Connection conn,
      {required String kind, required OrgKind org, required int year, String? section}) async {
    const sections = {
      'timeline': ['org', 'year', 'standings', 'timeline', 'championship_summary'],
      'titles': ['org', 'year', 'season_awards', 'season_award_supplement', 'titles', 'minor_title_leaders', 'standings', 'season'],
    };
    final fields = sections[section];
    String valueFor(String key) {
      // Filter saved JSON only; do not scan or aggregate source tables.
      if (section == 'titles' && ['titles', 'standings'].contains(key)) {
        return "jsonb_path_query_array(payload, '\$.$key[*] ? (@.year == \$year)', jsonb_build_object('year',int_year))";
      }
      return "payload->'$key'";
    }
    final projection = fields == null ? 'payload' :
        "jsonb_build_object(${fields.map((key) => "'$key',${valueFor(key)}").join(',')})";
    final rows = await conn.execute('''SELECT $projection,updated_at::text
      FROM t_page_snapshot WHERE kind=\$1 AND code_org=\$2 AND int_year=\$3''',
      parameters: [kind, org.code, year]);
    if (rows.isEmpty) {
      // Only enqueue locally. The timer owns DB writes and expensive work.
      _requested.add((kind, org.code, year));
      return {'org': org.code, 'year': year, 'pending': true,
        'message': '表示データを事前集計しています。少し待って再読み込みしてください。'};
    }
    final raw = rows.single[0];
    return {...Map<String,dynamic>.from(raw is String ? jsonDecode(raw) : raw as Map),
      'updated_at': rows.single[1]};
  }

  static Duration interval(String kind, int year, int currentYear) =>
      year < currentYear ? const Duration(days: 1) :
      kind == 'records' ? const Duration(minutes: 30) : const Duration(minutes: 5);

  static Future<void> refresh(Connection conn,
      {required String kind, required OrgKind org, required int year,
      Future<Map<String, dynamic>> Function()? build}) async {
    final key = 'page:$kind:${org.code}:$year';
    final lock = await conn.execute('SELECT pg_try_advisory_lock(hashtext(\$1))', parameters: [key]);
    if (lock.first[0] != true) return;
    try {
      final data = build != null ? await build() : switch (kind) {
        'schedule' => await readSeasonSchedule(conn, org, year),
        'records' => await Records.read(conn, org: org, year: year, force: true),
        _ => throw ArgumentError.value(kind),
      };
      // A failed build leaves the previous good result untouched.
      await conn.execute('''INSERT INTO t_page_snapshot(kind,code_org,int_year,payload)
        VALUES(\$1,\$2,\$3,\$4::jsonb)
        ON CONFLICT(kind,code_org,int_year) DO UPDATE
        SET payload=excluded.payload,updated_at=now()''',
        parameters: [kind, org.code, year, jsonEncode(data)]);
    } finally {
      await conn.execute('SELECT pg_advisory_unlock(hashtext(\$1))', parameters: [key]);
    }
  }

  static Future<void> tick() async {
    if (_busy || !SnapshotWork.tryStart()) return;
    _busy = true;
    try {
      final year = DateTime.now().toUtc().add(const Duration(hours: 9)).year;
      final saved = await Postgres.withConnection((conn) async {
        await ensure(conn);
        return await conn.execute('SELECT kind,code_org,int_year,updated_at::text FROM t_page_snapshot');
      });
      final dates = <(String,String,int),DateTime>{for (final r in saved)
        ('${r[0]}','${r[1]}',r[2] as int): DateTime.parse('${r[3]}')};
      final targets = <(String,String,int)>{
        for (final org in ['npb','mlb']) for (final kind in ['schedule','records']) (kind,org,year),
        ..._requested,
        ...dates.keys,
      };
      // Prepare historical seasons gradually, without flooding the DB on startup.
      final years = await Postgres.withConnection((conn) => conn.execute('''
        SELECT DISTINCT year FROM t_stats_team WHERE year IS NOT NULL
        UNION SELECT DISTINCT EXTRACT(YEAR FROM datetime_start)::int FROM t_game
        WHERE datetime_start IS NOT NULL ORDER BY year DESC'''));
      for (final r in years) {
        final y = r[0] as int;
        if (y < 1876 || y > year + 1) continue;
        for (final org in ['npb','mlb']) {
          if (org == 'npb' && y < 1936) continue;
          for (final kind in ['schedule','records']) { targets.add((kind,org,y)); }
        }
      }
      var updated = 0;
      for (final key in targets) {
        final at = dates[key];
        if (at != null && DateTime.now().difference(at) < interval(key.$1, key.$3, year)) continue;
        try {
          await ScheduledLog.run('page_${key.$1}_${key.$2}', () => Postgres.withConnection((conn) =>
            refresh(conn, kind: key.$1, org: OrgKind.parse(key.$2), year: key.$3)));
          _requested.remove(key);
        } catch (e) { print('表示用集計 $key: $e'); }
        if (++updated >= 6) break;
      }
      // Workload is now calculated only here / when source standings are saved.
      await ScheduledLog.run('standings_snapshot', () => Postgres.withConnection((conn) => DisplaySnapshot.refreshTeams(conn, year)));
    } finally { _busy = false; SnapshotWork.finish(); }
  }

  static void start() {
    _timer?.cancel();
    Future<void> run() async {
      try { await tick(); } catch (e) { print('表示用スナップショット更新: $e'); }
    }
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => unawaited(run()));
    unawaited(run());
  }
}
