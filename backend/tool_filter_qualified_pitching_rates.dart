import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
import 'app/StrengthUsage.dart' show usageMaps;
import 'app/QualifiedPitchingMetrics.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  await Postgres.withConnection((conn) async {
    final games = await readQualificationGames(conn, year);
    if (games.isEmpty) throw StateError('球団試合数を取得できないため更新を中止');
    final records = (await conn.execute("SELECT id_player,payload->'season_stats' AS stats FROM t_player_detail_snapshot WHERE int_year=\$1", parameters: [year])).map((r) => r.toColumnMap()).toList();
    final byPlayer = <int, List<Map<String, dynamic>>>{};
    var before = 0;
    for (final r in records) {
      final raw = r['stats'];
      final stats = usageMaps(raw is String ? jsonDecode(raw) : raw);
      before += stats.where((s) => qualifiedPitchingRateTitles.contains(s['title'])).length;
      retainQualifiedPitchingRates(stats, games);
      byPlayer[r['id_player'] as int] = stats;
    }
    final all = byPlayer.values.expand((v) => v).toList();
    rankQualifiedPitchingRates(all);
    final updates = [
      for (final e in byPlayer.entries) {'id': e.key, 'stats': e.value}
    ];
    for (var i = 0; i < updates.length; i += 100) {
      await conn.execute("UPDATE t_player_detail_snapshot d SET payload=jsonb_set(payload,'{season_stats}',u.stats) FROM jsonb_to_recordset(\$1::jsonb) AS u(id int,stats jsonb) WHERE d.int_year=\$2 AND d.id_player=u.id", parameters: [jsonEncode(updates.skip(i).take(100).toList()), year]);
    }
    print({'year': year, 'teams': games.length, 'players': updates.length, 'rate_rows_before': before, 'rate_rows_after': all.where((s) => qualifiedPitchingRateTitles.contains(s['title'])).length});
  });
  exit(0);
}
