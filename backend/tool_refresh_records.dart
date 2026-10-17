import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/RecordCatalog.dart';
import 'app/RecordSources.dart';

/// Refresh verified official record baselines. No database writes.
Future<void> main(List<String> args) async {
  final client = http.Client();
  final file = File('data/records.json');
  final data = file.existsSync() ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic> : <String, dynamic>{};
  final errors = <String>[];
  try {
    for (final org in ['npb', 'mlb']) {
      data.putIfAbsent(org, () => <String, dynamic>{});
      for (final section in ['career', 'season']) {
        if (args.contains('--career-only') && section != 'career') continue;
        final rows = <Map<String, dynamic>>[];
        for (final metric in recordMetrics) {
          if (org == 'mlb' && metric.mlb.isEmpty) continue;
          final career = section == 'career';
          if (org == 'npb' && career && metric.key == 'obp') continue;
          final existing = (data[org][section] as List? ?? []).where((r) => r['key'] == metric.key);
          if (args.contains('--missing') && existing.isNotEmpty) {
            rows.addAll(existing.map((r) => Map<String, dynamic>.from(r)));
            continue;
          }
          final url = org == 'npb'
              ? 'https://npb.jp/bis/history/${career ? 'lt' : 'ss'}${metric.npb}.html'
              : Uri.https('statsapi.mlb.com', '/api/v1/stats', {
                  'stats': career ? 'career' : 'statsSingleSeason',
                  'group': metric.group,
                  'sportIds': '1',
                  'playerPool': metric.unit.isEmpty ? 'QUALIFIED' : 'ALL',
                  'sortStat': metric.mlb,
                  'order': metric.lower ? 'asc' : 'desc',
                  'limit': career ? '1000' : '50',
                  'hydrate': 'person',
                }).toString();
          try {
            final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
            if (response.statusCode != 200) {
              throw StateError('HTTP ${response.statusCode}');
            }
            final body = utf8.decode(response.bodyBytes);
            final leaders = org == 'npb' ? parseNpbRecord(body, career: career) : parseMlbRecord(jsonDecode(body), metric, career: career);
            rows.add({
              'key': metric.key,
              'label': metric.label,
              'unit': metric.unit,
              'stat_id': metric.statId,
              'leaders': leaders,
              'sources': [url],
              'checked_at': DateTime.now().toUtc().toIso8601String(),
              'note': metric.unit.isEmpty ? '公式の規定条件を満たした選手。' : '公式戦記録。ポストシーズンは含まない。'
            });
            print('$org $section ${metric.key}: ${leaders.length}');
          } catch (e) {
            errors.add('$org $section ${metric.key}: $e');
            final old = (data[org][section] as List? ?? []).where((r) => r['key'] == metric.key);
            rows.addAll(old.map((r) => Map<String, dynamic>.from(r)));
          }
        }
        data[org][section] = rows;
      }
    }
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.tmp');
    temp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    temp.renameSync(file.path);
    for (final error in errors) {
      stderr.writeln(error);
    }
    if (errors.isNotEmpty) exitCode = 1;
  } finally {
    client.close();
  }
}
