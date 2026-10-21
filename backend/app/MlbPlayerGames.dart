import 'dart:convert';
import 'package:http/http.dart' as http;
import 'StrengthUsage.dart';

final _recentMlbCache = <String, ({DateTime expires, Future<List<Map<String, dynamic>>> value})>{};
Future<List<Map<String, dynamic>>> mlbRecentGames(String id, int year) {
  final now = DateTime.now();
  _recentMlbCache.removeWhere((_, entry) => !entry.expires.isAfter(now));
  final key = '$id:$year', old = _recentMlbCache[key];
  if (old != null && old.expires.isAfter(DateTime.now())) return old.value;
  while (_recentMlbCache.length >= 32) {
    _recentMlbCache.remove(_recentMlbCache.keys.first);
  }
  final value = _fetch(id, year);
  _recentMlbCache[key] = (expires: DateTime.now().add(const Duration(minutes: 15)), value: value);
  return value;
}

Future<List<Map<String, dynamic>>> _fetch(String id, int year) async {
  if (!RegExp(r'^\d+$').hasMatch(id)) return [];
  final client = http.Client(), games = <String, Map<String, dynamic>>{};
  Future<Map<String, dynamic>> get(String url) async {
    final r = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw StateError('MLB HTTP ${r.statusCode}');
    return usageMap(jsonDecode(utf8.decode(r.bodyBytes)));
  }

  try {
    await Future.wait([
      for (final type in ['R', 'F', 'D', 'L', 'W'])
        () async {
          final url = 'https://statsapi.mlb.com/api/v1/people/$id/stats?stats=gameLog&group=hitting,pitching&season=$year&gameType=$type';
          final data = await get(url);
          for (final group in usageMaps(data['stats']))
            for (final row in usageMaps(group['splits'])) {
              final stat = usageMap(row['stat']), pk = '${usageMap(row['game'])['gamePk']}', home = row['isHome'] == true, team = usageMap(row['team'])['name'], opponent = usageMap(row['opponent'])['name'];
              final g = games.putIfAbsent(pk, () => {'game_pk': pk, 'opponent': opponent, 'code_game': const {'R':'NM','F':'WC','D':'DS','L':'LCS','W':'WS'}[type], 'game_number': usageMap(row['game'])['gameNumber'] ?? 1, 'datetime_start': row['date'], 'home': home ? team : opponent, 'away': home ? opponent : team, 'outcome': row['isWin'] == true ? '勝' : '敗', 'source': url, 'lines': <Map<String, dynamic>>[], 'plays': []});
              (g['lines'] as List).add(usageMap(group['group'])['displayName'] == 'pitching' ? {'starter': usageInt(stat['gamesStarted']) > 0, 'int_runs': stat['runs'], 'int_four': stat['baseOnBalls'], 'int_dead_pitching': stat['hitBatsmen'], 'double_inning_pitch': stat['inningsPitched'], 'int_pitch': stat['numberOfPitches'], 'int_hit': stat['hits'], 'int_strike_out': stat['strikeOuts'], 'int_runs_earned': stat['earnedRuns']} : {'int_batting': stat['atBats'], 'int_hit1': stat['hits'], 'int_homerun': stat['homeRuns'], 'int_rbi': stat['rbi'], 'int_fourball': stat['baseOnBalls'], 'int_dead_batting': stat['hitByPitch'], 'int_steal_base': stat['stolenBases']});
            }
        }()
    ]);
    final result = games.values.toList()
      ..sort((a, b) {
        final date = '${b['datetime_start']}'.compareTo('${a['datetime_start']}');
        return date != 0 ? date : usageInt(b['game_number']).compareTo(usageInt(a['game_number']));
      });
    final recent = result.take(25).toList();
    if (recent.isNotEmpty) {
      try {
        final schedule = await get('https://statsapi.mlb.com/api/v1/schedule?gamePks=${recent.map((g) => g['game_pk']).join(',')}');
        for (final date in usageMaps(schedule['dates']))
          for (final g in usageMaps(date['games'])) {
            final target = recent.where((r) => r['game_pk'] == '${g['gamePk']}').firstOrNull;
            if (target == null) continue;
            final teams = usageMap(g['teams']);
            target['score_home'] = usageMap(teams['home'])['score'];
            target['score_away'] = usageMap(teams['away'])['score'];
          }
      } catch (_) {}
    }
    return recent;
  } finally {
    client.close();
  }
}
