import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/RecentPlayerGames.dart';
import 'app/ClubData.dart';
import 'app/StrengthUsage.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.first);
  final cache = readClubFile('npb-recent-games-$year.json');
  final games = usageMap(cache['games']);
  final urls = games.keys.where((u) => needsNpbPitchingRefresh(games[u])).toList();
  var next = 0, done = 0, failed = 0;
  final client = http.Client();
  try {
    await Future.wait(List.generate(6, (_) async {
      while (next < urls.length) {
        final url = urls[next++];
        try {
          final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
          if (response.statusCode != 200) throw StateError('HTTP ${response.statusCode}');
          final parsed = parseNpbRecentGame(utf8.decode(response.bodyBytes), url);
          if (parsed == null) throw StateError('No finished game');
          games[url] = parsed;
        } catch (_) { failed++; }
        done++;
        if (done % 100 == 0) print('$done/${urls.length} 試合');
      }
    }));
    await File('data/npb-recent-games-$year.json').writeAsString(jsonEncode({...cache, 'games': games}));
    print('出場記録更新：${done - failed}試合、失敗：$failed');
  } finally { client.close(); }
}
