import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart';
import 'app/BirthPlaceRegistry.dart';
import 'tools/Postgres.dart';
import 'tools/StringTool.dart';

Future<void> main() async {
  print('backfill start');
  await Postgres.withConnection((conn) async {
    final res = await http.get(Uri.parse('https://baseball.yahoo.co.jp/mlb/japanese/players/'))
        .timeout(const Duration(seconds: 30));
    final doc = parse(utf8.decode(res.bodyBytes, allowMalformed: true));
    final hrefs = <String>{};
    for (final a in doc.querySelectorAll('a[href*="/mlb/player/"]')) {
      final h = a.attributes['href']?.trim() ?? '';
      if (h.isNotEmpty) hrefs.add(h.startsWith('http') ? h : 'https://baseball.yahoo.co.jp$h');
    }
    print('jp links: ${hrefs.length}');
    var updated = 0;
    for (final url in hrefs) {
      try {
        final pr = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
        if (pr.statusCode != 200) continue;
        final pdoc = parse(utf8.decode(pr.bodyBytes, allowMalformed: true));
        final ruby = pdoc.querySelector('ruby.bb-profile__ruby')?.text ?? '';
        final name = StringTool.noSpace(ruby.split('（').first.trim());
        if (name.isEmpty) continue;
        final birth = BirthPlaceRegistry.extractFromProfile(pdoc) ?? '日本';
        final players = await conn.execute('''
          SELECT id FROM m_player
          WHERE (
            name_full = \$1::text
            OR name_last = \$1::text
            OR COALESCE(name_last,'') || COALESCE(name_first,'') = \$1::text
            OR name_full LIKE '%' || \$1::text || '%'
          )
          AND id_team IN (SELECT id FROM m_team WHERE id_league IN (3,4))
          LIMIT 5
        ''', parameters: [name]).timeout(const Duration(seconds: 15));
        if (players.isEmpty) {
          print('no player row: $name');
          continue;
        }
        for (final row in players) {
          final id = row.toColumnMap()['id'] as int;
          await BirthPlaceRegistry.applyToPlayer(conn, id, birth);
          await conn.execute('''
            UPDATE m_player SET url = CASE WHEN COALESCE(url,'')='' THEN \$1::text ELSE url END, updat=NOW()
            WHERE id=\$2::int
          ''', parameters: [url, id]);
          updated++;
          print('ok $name id=$id birth=$birth');
        }
      } catch (e) {
        print('skip $url $e');
      }
    }
    print('updated=$updated');
  });
  print('done');
}
