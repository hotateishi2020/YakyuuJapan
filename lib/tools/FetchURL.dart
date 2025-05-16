import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

class FetchURL {

  static Future<List<Map<String, dynamic>>> fetchNPBStandings() async {
  final url = Uri.parse('https://baseball.yahoo.co.jp/npb/standings/');
  final res = await http.get(url);

  if (res.statusCode != 200) {
    throw Exception('Failed to fetch standings');
  }

  final document = parse(res.body);
  final cards = document.querySelectorAll('table.bb-rankTable');
  final result = <Map<String, dynamic>>[];
  var cnt = 0;

  for (final card in cards) {

    final teams = <Map<String, String>>[];
    final rows = card.querySelectorAll('tbody tr');
    
    if (cnt == 2) {
        break;
     }

    for (final row in rows) {

      final cells = row.querySelectorAll('td');
      if (cells.length >= 3) {
        teams.add({
          'rank': cells[0].text.trim(),
          'team': cells[1].text.trim(),
          'win_loss': cells[2].text.trim(),
        });
      }
    }

    result.add({
      'league': cnt == 0 ? 'セ・リーグ' : 'パ・リーグ',
      'teams': teams,
    });

    cnt++;
  }

  return result;
}

}