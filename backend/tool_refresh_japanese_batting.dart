import 'dart:io';
import 'dart:convert';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'app/AppSql.dart';
import 'app/MlbProfileStats.dart';
import 'app/DB/t_stats_player.dart';
import 'app/DB/t_stats_player_latest.dart';
import 'tools/Postgres.dart';

/// Fill missing batting stats for the requested Japanese MLB players.
Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');
  final client = http.Client();
  try {
    await Postgres.withConnection((conn) async {
      final year = DateTime.now().year;
      final targets = (await conn.execute(AppSql.selectStatsPlayerNoRank(), parameters: [year]))
          .map((r) => r.toColumnMap()).where((r) => [5143,5142,5784].contains(r['id_player']) && r['flg_pitcher'] != true && {'打率','打席数','打数','最多安打','安打','本塁打','打点','盗塁','出塁率','長打率','OPS'}.contains(r['title']) && [3,4].contains(r['id_league']));
      final cache = <String, Map<String, double>>{};
      var count = 0;
      for (final target in targets) {
        final url = '${target['url'] ?? ''}'.replaceFirst(RegExp(r'/top/?$'), '/');
        final uri = Uri.tryParse(url);
        if (uri == null || uri.scheme != 'https' || uri.host != 'baseball.yahoo.co.jp' || !uri.path.startsWith('/mlb/player/')) continue;
        if (!cache.containsKey(url)) {
          final response = await client.get(uri).timeout(const Duration(seconds: 25));
          if (response.statusCode != 200) throw StateError('Profile fetch failed: $url');
          cache[url] = mlbProfileStats(parse(utf8.decode(response.bodyBytes)), pitching: false);
        }
        final values = cache[url]!;
        final whip = values[mlbProfileStatLabel('${target['title']}')], innings = values['打席'];
        if (whip == null || !whip.isFinite || whip < 0 || innings == null || innings <= 0) continue;
        print('${target['name_full']}: ${target['title']}=$whip PA=$innings');
        if (apply) {
          await conn.execute('BEGIN');
          try {
            final history = t_stats_player()
              ..id_player=target['id_player'] as int ..id_team=target['id_team'] as int
              ..id_league=target['id_league'] as int ..id_stats=target['id_stats'] as int
              ..int_year=year ..int_rank=1000 ..stats=whip ..cnt_play=innings.truncate();
            final latest = t_stats_player_latest()
              ..id_player=history.id_player ..id_team=history.id_team ..id_league=history.id_league
              ..id_stats=history.id_stats ..int_rank=1000 ..stats=whip ..cnt_play=history.cnt_play;
            final existing = await conn.execute('SELECT id FROM t_stats_player_latest WHERE id_player=\$1 AND id_stats=\$2 AND id_league=\$3', parameters: [history.id_player,history.id_stats,history.id_league]);
            if (existing.isEmpty) {
              await Postgres.insert(conn, history);
              await Postgres.insert(conn, latest);
              count++;
            }
            await conn.execute('COMMIT');
          } catch (_) { await conn.execute('ROLLBACK'); rethrow; }
        }
      }
      print('Inserted: $count (apply=$apply)');

    });
  } finally { client.close(); }
  exit(0);
}
