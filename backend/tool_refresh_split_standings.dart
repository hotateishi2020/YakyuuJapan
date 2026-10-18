import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/HistoricalBaseballImporter.dart';

/// Official ranked spring/fall seasons. 1936 used tournament results instead.
Future<void> main() async {
  final client = http.Client();
  try {
    final seasons = <Map<String, dynamic>>[];
    for (final year in [1937, 1938]) {
      for (final phase in ['spring', 'fall']) {
        final suffix = phase == 'spring' ? 's' : 'f';
        final url = 'https://npb.jp/bis/yearly/yakyuremmei_$year$suffix.html';
        final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) throw StateError('Failed: $url');
        final body = utf8.decode(response.bodyBytes);
        HistoricalBaseballImporter.validateNpbSeason(body, year);
        final page = HistoricalBaseballImporter.parseNpbYearPage(body, year: year, leagueId: 1, phase: phase);
        if (page.standings.length < 8) throw StateError('Incomplete: $url');
        seasons.add({'year': year, 'phase': phase, 'source': url, 'teams': [
          for (final entry in page.standings.indexed) {
            'name': entry.$2.teamName, 'rank': entry.$1 + 1,
            'wins': entry.$2.wins, 'losses': entry.$2.losses, 'draws': entry.$2.draws,
          }
        ]});
        print('$year $phase: ${page.standings.first.teamName}, ${page.standings.length} teams');
      }
    }
    await File('data/npb_split_standings.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(seasons)}\n');
  } finally { client.close(); }
}
