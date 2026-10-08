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
  final res = await http.get(Uri.parse('https://npb.jp/bis/players/31735137.html'));
  final doc = parse(decode(res));
  print('=== all th/td ===');
  for (final tr in doc.querySelectorAll('tr')) {
    final th = tr.querySelector('th')?.text.replaceAll(RegExp(r'\\s+'), ' ').trim() ?? '';
    final td = tr.querySelector('td')?.text.replaceAll(RegExp(r'\\s+'), ' ').trim() ?? '';
    if (th.isNotEmpty) print('$th => $td');
  }

  await Postgres.withConnection((conn) async {
    final teams = await conn.execute("SELECT id, name_shortest, url_npb_players FROM m_team WHERE id_league IN (3,4) AND COALESCE(url_npb_players,'')<>'' LIMIT 5");
    for (final r in teams) {
      print(r.toColumnMap());
    }
    final p = await conn.execute('''
      SELECT id, name_full, url FROM m_player WHERE id_team BETWEEN 13 AND 42 AND COALESCE(url,'')<>'' LIMIT 5
    ''');
    print('mlb players with url:');
    for (final r in p) {
      print(r.toColumnMap());
    }
  });
}
