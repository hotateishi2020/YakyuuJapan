import 'package:http/http.dart' as http;
import 'package:html/parser.dart';
import 'dart:convert';
import 'tools/Postgres.dart';

String decode(http.Response res) {
  try {
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  } catch (_) {
    return res.body;
  }
}

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final teams = await conn.execute('''
      SELECT id, id_league, name_short, name_shortest, name_full
      FROM m_team WHERE id_league IN (3,4) ORDER BY id
    ''').timeout(const Duration(seconds: 20));
    print('MLB teams ${teams.length}:');
    for (final r in teams) {
      print(r.toColumnMap());
    }

    final career = await conn.execute('''
      SELECT COUNT(*) AS n,
             COUNT(*) FILTER (WHERE c.int_year < EXTRACT(YEAR FROM CURRENT_DATE)) AS prior,
             COUNT(DISTINCT c.id_player) AS players
      FROM m_player_career c
      JOIN m_team t ON t.id = c.id_team AND t.id_league IN (3,4)
      WHERE COALESCE(c.flg_delete,FALSE)=FALSE
    ''').timeout(const Duration(seconds: 20));
    print('mlb career: ${career.first.toColumnMap()}');

    final sample = await conn.execute('''
      SELECT p.id, p.name_full, p.url,
        (SELECT COUNT(*) FROM m_player_career c JOIN m_team t ON t.id=c.id_team AND t.id_league IN (3,4)
         WHERE c.id_player=p.id AND COALESCE(c.flg_delete,FALSE)=FALSE) AS mlb_years
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id = tsp.id_player
      WHERE tsp.id_league IN (3,4) AND COALESCE(p.url,'')<>''
      ORDER BY mlb_years ASC, p.id
      LIMIT 8
    ''').timeout(const Duration(seconds: 30));
    print('sample players:');
    for (final r in sample) {
      print(r.toColumnMap());
    }

    final withUrl = sample.isNotEmpty ? '${sample.first.toColumnMap()['url']}' : '';
    if (withUrl.isNotEmpty) {
      final url = withUrl.replaceFirst(RegExp(r'/top/?$'), '/');
      print('fetch $url');
      final res = await http.get(Uri.parse(url));
      final doc = parse(decode(res));
      for (final id in ['year_b', 'year_p', 'tablefix_b', 'tablefix_p']) {
        final t = doc.querySelector('#$id');
        print('table #$id: ${t != null}');
      }
      final yearB = doc.querySelector('#year_b');
      if (yearB != null) {
        var n = 0;
        for (final tr in yearB.querySelectorAll('tbody tr')) {
          if (n >= 8) break;
          final year = tr.querySelector('.bb-playerStatsTable__dataLabel')?.text.trim();
          final team = tr.querySelector('.bb-playerStatsTable__data--team')?.text.trim();
          final cells = tr.querySelectorAll('td.bb-playerStatsTable__data').map((e) => e.text.trim()).toList();
          print('year_b row: year=$year team=$team cells=${cells.length} sample=${cells.take(8).toList()}');
          n++;
        }
      } else {
        // dump any table ids mentioning year/stats
        final ids = doc.querySelectorAll('[id]').map((e) => e.id).where((id) => id.contains('year') || id.contains('table') || id.contains('Stats')).take(40);
        print('candidate ids: $ids');
        final links = doc.querySelectorAll('a[href*="stats"], a[href*="year"]').map((a) => a.attributes['href']).take(20);
        print('stat links: $links');
      }
    }
  });
}
