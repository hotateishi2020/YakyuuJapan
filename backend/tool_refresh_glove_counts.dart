import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/SeasonAwards.dart';

Future<void> main() async {
  final client = http.Client();
  try {
    for (var year = 1972; year <= DateTime.now().year; year++) {
      final path = 'award/$year/glove.html';
      final response = await client
          .get(Uri.parse('https://npb.jp/$path'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) continue;
      final rows =
          parseSeasonAwardPage(utf8.decode(response.bodyBytes), path, year);
      if (!rows.any((r) => r['career_count'] != null)) continue;
      final data = SeasonAwards.read(year, refresh: false);
      final pages = Map<String, dynamic>.from(data['pages'] as Map? ?? {});
      pages[path] = rows;
      final file = SeasonAwards.file(year);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
          jsonEncode({...data, 'year': year, 'pages': pages}));
      stdout.writeln('$year: ${rows.length} awards');
    }
  } finally {
    client.close();
  }
}
