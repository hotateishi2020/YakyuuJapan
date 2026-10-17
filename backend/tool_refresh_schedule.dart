import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'app/StrengthUsage.dart';
import 'app/ClubData.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first),
      client = http.Client();
  Future<String> get(String url) async {
    final r =
        await client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode} $url');
    return utf8.decode(r.bodyBytes);
  }

  final npb = <Map<String, dynamic>>[];
  try {
    for (var month = 3; month <= 11; month++) {
      final url =
          'https://npb.jp/games/$year/schedule_${month.toString().padLeft(2, '0')}_detail.html';
      final doc = html.parse(await get(url));
      for (final tr in doc.querySelectorAll('tr[id^="date"]')) {
        final h = tr.querySelector('.team1')?.text.trim(),
            a = tr.querySelector('.team2')?.text.trim();
        if (h == null || a == null) continue;
        final hc = clubKey({'name_team': h}), ac = clubKey({'name_team': a});
        if (hc.isEmpty || ac.isEmpty) continue;
        final date = '$year-${tr.id.substring(4, 6)}-${tr.id.substring(6, 8)}';
        final sh = int.tryParse(tr.querySelector('.score1')?.text.trim() ?? ''),
            sa = int.tryParse(tr.querySelector('.score2')?.text.trim() ?? '');
        final link =
            tr.querySelector('a[href*="/scores/"]')?.attributes['href'] ?? '';
        var regular = true;
        if (month >= 10 && link.isNotEmpty) {
          final game =
              html.parse(await get(Uri.parse(url).resolve(link).toString()));
          final title = game.querySelector('.game_tit h3')?.text ?? '';
          regular = title.isNotEmpty &&
              !RegExp('CS |クライマックス|日本シリーズ|オールスター|オープン戦').hasMatch(title);
        }
        npb.add({
          'date': date,
          'home_code': hc,
          'away_code': ac,
          'score_home': sh,
          'score_away': sa,
          'finished': sh != null && sa != null,
          'state': sh != null
              ? '試合終了'
              : tr.querySelector('.state')?.text.trim() ?? '予定',
          'time': tr.querySelector('.time')?.text.trim(),
          'regular': regular,
          'source': url,
          'stadium': tr.querySelector('.place')?.text.trim()
        });
      }
    }
    final teamData = usageMap(jsonDecode(await get(
        'https://statsapi.mlb.com/api/v1/teams?sportId=1&season=$year')));
    final codes = {
      for (final t in usageMaps(teamData['teams']))
        usageInt(t['id']): t['abbreviation']
    };
    final url =
        'https://statsapi.mlb.com/api/v1/schedule?sportId=1&season=$year';
    final schedule = usageMap(jsonDecode(await get(url))),
        mlb = <Map<String, dynamic>>[];
    for (final day in usageMaps(schedule['dates'])) {
      for (final game in usageMaps(day['games'])) {
        final ts = usageMap(game['teams']),
            h = usageMap(ts['home']),
            a = usageMap(ts['away']),
            status = usageMap(game['status']);
        mlb.add({
          'date': day['date'],
          'home_code': codes[usageInt(usageMap(h['team'])['id'])],
          'away_code': codes[usageInt(usageMap(a['team'])['id'])],
          'score_home': h['score'],
          'score_away': a['score'],
          'finished': status['abstractGameState'] == 'Final',
          'state': status['detailedState'],
          'time': game['gameDate'],
          'regular': game['gameType'] == 'R',
          'game_number': game['gameNumber'],
          'source': url,
          'stadium': usageMap(game['venue'])['name']
        });
      }
    }
    final file = File('data/schedule-$year.json.tmp');
    file.writeAsStringSync(jsonEncode({
      'checked_at': DateTime.now().toUtc().toIso8601String(),
      'npb': npb,
      'mlb': mlb
    }));
    file.renameSync('data/schedule-$year.json');
    print('NPB ${npb.length}, MLB ${mlb.length} games');
  } finally {
    client.close();
  }
}
