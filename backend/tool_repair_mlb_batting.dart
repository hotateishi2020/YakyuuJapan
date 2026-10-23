import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart';
import 'tools/Postgres.dart';
import 'app/MlbProfileStats.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''
      SELECT s.id,s.id_player,s.id_stats,s.id_league,p.url,m.title
      FROM t_stats_player_latest s JOIN m_stats m ON m.id=s.id_stats
      JOIN m_player p ON p.id=s.id_player
      WHERE s.id_league IN (3,4) AND s.int_rank >= 1000
        AND NOT COALESCE(m.flg_pitcher,false)
    ''');
    final cache = <String, Map<String,double>>{};
    var updated = 0, removed = 0;
    for (final raw in rows) {
      final row = raw.toColumnMap();
      final url = '${row['url'] ?? ''}';
      if (!url.startsWith('https://baseball.yahoo.co.jp/mlb/player/')) continue;
      if (!cache.containsKey(url)) {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
        if (response.statusCode != 200) throw StateError('Profile fetch failed');
        final doc = parse(response.body);
        final batting = mlbProfileStats(doc, pitching: false);
        if (batting.isEmpty && mlbProfileStats(doc, pitching: true).isEmpty) throw StateError('Unrecognized profile');
        cache[url] = batting;
      }
      final values = cache[url]!;
      final value = values[mlbProfileStatLabel('${row['title']}')];
      // Unsupported derived metrics are not touched by this repair.
      if (values.isNotEmpty && value == null) continue;
      await conn.runTx((tx) async {
        if (value == null) {
          await tx.execute('DELETE FROM t_stats_player_latest WHERE id=\$1', parameters:[row['id']]);
          await tx.execute('''DELETE FROM t_stats_player WHERE id_player=\$1 AND id_stats=\$2 AND id_league=\$3
            AND int_rank>=1000 AND int_year=EXTRACT(YEAR FROM CURRENT_DATE)::int''', parameters:[row['id_player'],row['id_stats'],row['id_league']]);
          removed++;
        } else {
          final count = values['打席']?.toInt() ?? 0;
          await tx.execute('UPDATE t_stats_player_latest SET stats=\$1,cnt_play=\$2 WHERE id=\$3', parameters:[value,count,row['id']]);
          await tx.execute('''UPDATE t_stats_player SET stats=\$1,cnt_play=\$2 WHERE id_player=\$3 AND id_stats=\$4 AND id_league=\$5
            AND int_rank>=1000 AND int_year=EXTRACT(YEAR FROM CURRENT_DATE)::int''', parameters:[value,count,row['id_player'],row['id_stats'],row['id_league']]);
          updated++;
        }
      });
    }
    print('MLB batting repair: $updated corrected, $removed invalid entries removed.');
  });
  exit(0);
}
