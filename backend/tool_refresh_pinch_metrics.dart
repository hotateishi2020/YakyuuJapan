import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/StrengthUsage.dart';
import 'app/ClubData.dart';
import 'app/PinchMetrics.dart';
import 'app/RecentPlayerGames.dart';
import 'app/ExtendedPlayerMetrics.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first), client = http.Client();
  Future<String> get(String url) async {
    final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode} $url');
    return utf8.decode(r.bodyBytes);
  }

  try {
    final urls = <String>{};
    for (var m = 3; m <= 11; m++) {
      urls.addAll(npbSeasonGames(await get('https://npb.jp/games/$year/schedule_${m.toString().padLeft(2, '0')}_detail.html'), year));
    }
    final cache = readClubFile('npb-pinch-games-$year.json');
    final games = usageMap(cache['games']);
    final recent = usageMap(readClubFile('npb-recent-games-$year.json')['games']);
    final missing = urls.where((u) => !games.containsKey(u) ||
        needsNpbPitchingRefresh(recent[u])).toList();
    var cursor = 0, done = 0;
    await Future.wait(List.generate(4, (_) async {
      while (cursor < missing.length) {
        final url = missing[cursor++];
        try {
          final source = await get(url);
          games[url] = parseNpbPinch(source, url);
          final detail = parseNpbRecentGame(source, url);
          if (detail != null) recent[url] = detail;
        } catch (e) {
          stderr.writeln(e);
        }
        done++;
        if (done % 40 == 0) print('$done/${missing.length} games');
      }
    }));
    for (final url in games.keys.toList()) {
      games[url] = [
        for (final p in usageMaps(games[url])) {...p, ...classifyPinchResult('${p['play'] ?? ''}')}
      ];
    }
    await File('data/npb-recent-games-$year.json').writeAsString(jsonEncode({'year': year, 'games': recent}));
    final cacheFile = File('data/npb-pinch-games-$year.json');
    await cacheFile.writeAsString(jsonEncode({'year': year, 'games': games}));
    final aggregated = <String, Map<String, dynamic>>{};
    for (final url in urls)
      for (final p in usageMaps(games[url])) {
        final id = '${p['source_player_id']}';
        final a = aggregated.putIfAbsent(id, () => {'name': p['name'], 'games': 0, 'ab': 0, 'hits': 0, 'unknown': false});
        a['games']++;
        if (p['ab'] == null || p['hit'] == null) {
          a['unknown'] = true;
        } else {
          a['ab'] += p['ab'];
          a['hits'] += p['hit'];
        }
      }
    final file = File('data/player-metrics-$year.json'), data = readClubFile('player-metrics-$year.json');
    final players = usageMaps(data['players']);
    final coverage = 'NPB公式ボックススコア ${urls.where(games.containsKey).length}/${urls.length}試合取得。代打で出た最初の打席のみ集計。';
    for (final e in aggregated.entries) {
      final a = e.value;
      players.removeWhere((p) => p['org'] == 'npb' && p['pinch_only'] == true && p['source_player_id'] == e.key);
      players.add({
        'org': 'npb',
        'source_player_id': e.key,
        'name': a['name'],
        'pinch_only': true,
        'source': 'https://npb.jp/games/$year/schedule_03_detail.html',
        'metrics': [metric('代打起用数', a['games'], note: coverage), metric('代打打率', a['unknown'] == false && a['ab'] > 0 ? a['hits'] / a['ab'] : null, digits: 3, note: '$coverage ${a['hits']}安打/${a['ab']}打数${a['unknown'] == true ? '・未分類打席あり' : ''}')]
      });
    }
    data['players'] = players;
    data['checked_at'] = DateTime.now().toUtc().toIso8601String();
    await File('${file.path}.tmp').writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await File('${file.path}.tmp').rename(file.path);
    print('$coverage ${aggregated.length} players');
  } finally {
    client.close();
  }
}
