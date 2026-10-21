import 'app/AllStarPositions.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/AllStarHistory.dart';

Future<void> main(List<String> args) async {
  final last = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  final file = File('data/allstar_history.json');
  final old =
      file.existsSync() ? jsonDecode(file.readAsStringSync()) as Map : {};
  final rows = [
    for (final r in old['players'] as List? ?? [])
      Map<String, dynamic>.from(r as Map)
  ];
  final errors = <String>[];
  final client = http.Client();
  try {
    final years = [
      for (var year = 1951; year <= last; year++)
        if (year != 2020) year
    ];
    for (var i = 0; i < years.length; i += 3) {
      await Future.wait(years.skip(i).take(3).map((year) async {
        try {
          final cached = File(
              '/tmp/koko-allstar/${year < 2002 ? 'historical-' : ''}$year.html');
          String body;
          if (cached.existsSync() && year < DateTime.now().year) {
            body = cached.readAsStringSync();
          } else {
            final response = await client
                .get(Uri.parse(year < 2002
                    ? 'https://data-man.com/proyakyu/history/?format=players&type=allstar&y=$year'
                    : 'https://npb.jp/allstar/$year/roster.html'))
                .timeout(const Duration(seconds: 25));
            if (response.statusCode != 200) {
              throw StateError('HTTP ${response.statusCode}');
            }
            body = utf8.decode(response.bodyBytes);
            await cached.parent.create(recursive: true);
            await cached.writeAsString(body);
          }
          final found = year < 2002
              ? parseHistoricalAllStarRoster(body, year)
              : parseNpbAllStarRoster(body, year);
          if (found.length < 40 ||
              found.map((r) => r['league']).toSet().length != 2) {
            throw StateError('Incomplete roster: ${found.length}');
          }
          rows.removeWhere((r) => r['year'] == year);
          rows.addAll(found);
        } catch (e) {
          errors.add('$year: $e');
        }
      }));
    }
    await refreshAllStarPositions(rows);
    rows.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));
    final data = {
      'first_year':
          rows.map((r) => r['year'] as int).reduce((a, b) => a < b ? a : b),
      'through_year': last,
      'cancelled_years': [2020],
      'players': rows,
      'errors': errors
    };
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(file.path);
    print(
        '${rows.length} selections / ${rows.map((r) => r['year']).toSet().length} seasons; errors: $errors');
    if (errors.isNotEmpty) exitCode = 1;
  } finally {
    client.close();
  }
}
