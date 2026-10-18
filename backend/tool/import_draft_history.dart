import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart';

Future<void> main(List<String> args) async {
  final last = args.isEmpty ? DateTime.now().year - 1 : int.parse(args.first);
  final cache = Directory('.dart_tool/draft-source');
  await cache.create(recursive: true);
  final years = <String, dynamic>{};
  final client = http.Client();
  try {
    for (var year = 1965; year <= last; year++) {
      final url = 'https://www.my-favorite-giants.net/npb/draft/list$year.htm';
      final file = File('${cache.path}/$year.html');
      if (!await file.exists()) {
        final response = await client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200)
          throw StateError('$year: HTTP ${response.statusCode}');
        await file.writeAsBytes(response.bodyBytes);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      final doc = parse(await file.readAsString());
      final picks = <Map<String, dynamic>>[];
      for (final row in doc.querySelectorAll('#draft tr').skip(1)) {
        final cells = row.children
            .map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim())
            .toList();
        if (cells.length != 8 || cells[3].isEmpty) continue;
        final competition = RegExp(r'[○〇](1[0-2]|[2-9])').firstMatch(cells[7]);
        picks.add({
          'team': cells[0],
          'type': cells[1],
          'rank': cells[2],
          'name': cells[3],
          'position': cells[4],
          'from': cells[5],
          'status': cells[6],
          'note': cells[7],
          'competition':
              competition == null ? null : int.parse(competition.group(1)!)
        });
      }
      if (picks.length < 12 ||
          picks.map((p) => p['team']).toSet().length !=
              (year == 1978 ? 11 : 12))
        throw StateError('$year: incomplete (${picks.length})');
      years['$year'] = {'source': url, 'picks': picks};
      print('$year: ${picks.length}');
    }
    await File('assets/data/draft_history.json').writeAsString(jsonEncode({
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'years': years
    }));
  } finally {
    client.close();
  }
}
