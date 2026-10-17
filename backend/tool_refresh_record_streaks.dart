import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/StrengthUsage.dart';
import 'app/MlbRecordStreaks.dart';

/// Refresh current MLB game-level streaks from every season participant.
/// Fails atomically if any batch is missing; a partial pool cannot be a leader board.
Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  final client = http.Client();
  Future<Map<String, dynamic>> get(Uri uri) async {
    final r = await client.get(uri).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}');
    return usageMap(jsonDecode(utf8.decode(r.bodyBytes)));
  }

  try {
    final ids = <int>{};
    for (final group in ['hitting', 'pitching']) {
      final data = await get(Uri.https('statsapi.mlb.com', '/api/v1/stats', {'stats': 'season', 'group': group, 'season': '$year', 'sportIds': '1', 'playerPool': 'ALL', 'limit': '10000'}));
      for (final stat in usageMaps(data['stats'])) {
        final splits = usageMaps(stat['splits']);
        if (splits.isEmpty || usageInt(stat['totalSplits']) > splits.length) {
          throw StateError('Incomplete $group player list');
        }
        for (final s in splits) {
          ids.add(usageInt(usageMap(s['player'])['id']));
        }
      }
    }
    ids.remove(0);
    if (ids.isEmpty) throw StateError('No participants');
    final all = ids.toList(), people = <Map<String, dynamic>>[];
    for (var i = 0; i < all.length; i += 60) {
      final batches = [all.skip(i).take(30).toList(), all.skip(i + 30).take(30).toList()].where((b) => b.isNotEmpty);
      final results = await Future.wait(batches.map((batch) async {
        final data = await get(Uri.https('statsapi.mlb.com', '/api/v1/people', {'personIds': batch.join(','), 'hydrate': 'stats(group=[hitting,pitching],type=[gameLog],season=$year)'}));
        final p = usageMaps(data['people']);
        if (p.length != batch.length || p.any((p) => usageMaps(p['stats']).isEmpty)) {
          throw StateError('Incomplete game-log batch');
        }
        return p;
      }));
      for (final p in results) {
        people.addAll(p);
      }
      print('${people.length}/${all.length} players');
    }
    final records = mlbGameLogStreaks(people, year);
    final file = File('data/records.json'), data = usageMap(jsonDecode(file.readAsStringSync()));
    final org = usageMap(data['mlb']), snapshots = usageMap(org['current_streaks']);
    snapshots['$year'] = {
      'checked_at': DateTime.now().toUtc().toIso8601String(),
      'sources': ['https://statsapi.mlb.com/api/v1/people'],
      'records': records,
      'note': 'MLB公式の全シーズン出場選手の試合別成績。選択年度内の最長記録（連続出場は移籍前後を分けて集計）。'
    };
    org['current_streaks'] = snapshots;
    data['mlb'] = org;
    final temp = File('${file.path}.tmp');
    temp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    temp.renameSync(file.path);
    print('Saved ${records.length} current MLB streak categories for $year');
  } finally {
    client.close();
  }
}
