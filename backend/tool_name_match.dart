import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart';
import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute('''
      SELECT p.id, p.name_full, p.name_last, t.name_shortest, COALESCE(p.url,'') url
      FROM t_stats_player_latest tsp
      JOIN m_player p ON p.id=tsp.id_player
      JOIN m_team t ON t.id=p.id_team
      WHERE tsp.id_league IN (3,4) AND p.date_birth IS NULL
      GROUP BY p.id, p.name_full, p.name_last, t.name_shortest, p.url
      ORDER BY p.name_full LIMIT 8
    ''').timeout(const Duration(seconds: 20));
    for (final r in rows) stdout.writeln(r.toColumnMap());
  });
  final res = await http.get(Uri.parse('https://baseball.yahoo.co.jp/mlb/stats/batter?gameKindId=1001&type=hr'), headers: {'User-Agent':'Mozilla/5.0'});
  final doc = parse(res.body);
  for (final m in doc.querySelectorAll('p.bb-playerTable__member').take(8)) {
    stdout.writeln('rank: "${m.text.replaceAll(RegExp(r"\\s+"), " ").trim()}" href=${m.querySelector('a[href*="/mlb/player/"]')?.attributes['href']}');
  }
}
