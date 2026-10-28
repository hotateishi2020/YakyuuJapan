import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/HighSchoolSchedule.dart';

/// Refresh the bundled fallback as well as the live server snapshot.
Future<void> main(List<String> args) async {
  final current = HighSchoolSchedule.snapshot();
  final tournament = (current['calendar']['tournaments'] as List)
      .singleWhere((t) => t['id'] == 'autumn-kyushu-2026');
  final source = '${tournament['source_url']}';
  final String body;
  if (args.length == 2 && args[0] == '--source-file') {
    body = await File(args[1]).readAsString();
  } else {
    final response =
        await http.get(Uri.parse(source)).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200)
      throw HttpException('HTTP ${response.statusCode}');
    body = utf8.decode(response.bodyBytes);
  }
  final next = updateHighSchoolSchedule(
      current, parseHighSchoolResults(body, 2026), source, DateTime.now());
  final prefix = Directory('backend/assets').existsSync() ? 'backend/' : '';
  const encoder = JsonEncoder.withIndent('  ');
  for (final entry in {
    'calendar': 'high_school_calendar',
    'kyushu': 'autumn_kyushu_2026'
  }.entries) {
    await File('${prefix}assets/data/${entry.value}.json')
        .writeAsString('${encoder.convert(next[entry.key])}\n');
  }
  stdout.writeln('高校野球の日程・勝ち上がりを更新しました。');
}
