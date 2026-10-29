/// Remove championship rows after the fourth win, including stale results
/// erroneously copied to a later date. The clinching game remains visible.
List<Map<String, dynamic>> championshipSchedule(List<Map<String, dynamic>> games) {
  String day(Map<String, dynamic> g) => '${g['date'] ?? g['date_game'] ?? g['datetime_start'] ?? ''}'.split(' ').first.split('T').first;
  String code(Map<String, dynamic> g) => '${g['code_game'] ?? ''}'.toUpperCase();
  bool finished(Map<String, dynamic> g) => g['finished'] == true || '${g['state']}'.contains('終了') || '${g['state']}'.toLowerCase() == 'final';
  String pair(Map<String, dynamic> g) {
    final ids = ['${g['id_team_home']}', '${g['id_team_away']}']..sort();
    return '${day(g).split('-').first}|${ids.join('|')}';
  }
  final series = <String, List<Map<String, dynamic>>>{};
  for (final game in games) {
    if (['JS', 'WS'].contains(code(game))) {
      series.putIfAbsent(pair(game), () => []).add(game);
    }
  }
  final decided = <String, String>{};
  for (final entry in series.entries) {
    final wins = <String, int>{};
    final ordered = [...entry.value]..sort((a,b) => day(a).compareTo(day(b)));
    for (final game in ordered) {
      if (!finished(game)) continue;
      final h = num.tryParse('${game['score_home']}');
      final a = num.tryParse('${game['score_away']}');
      if (h == null || a == null || h < 0 || a < 0 || h == a) continue;
      final winner = '${game[h > a ? 'id_team_home' : 'id_team_away']}';
      wins[winner] = (wins[winner] ?? 0) + 1;
      if (wins[winner]! >= 4) {
        decided[entry.key] = day(game);
        break;
      }
    }
  }
  return games.where((game) {
    final end = decided[pair(game)];
    if (end == null || day(game).compareTo(end) <= 0) return true;
    final state = '${game['state'] ?? ''}';
    if (state.contains('試合中') || RegExp(r'\d+\s*回|In Progress', caseSensitive: false).hasMatch(state)) return true;
    // Imported official schedules may have no code; regular-season games do not
    // belong to the championship even when the opponents happen to match.
    return !(['JS', 'WS'].contains(code(game)) || code(game).isEmpty && game['regular'] == false);
  }).toList();
}

/// The first fourth-win date, in the calendar's local (JST) date format.
Map<String, String> championshipEndDates(List<Map<String, dynamic>> games) {
  final ends = <String, String>{};
  final wins = <String, Map<String, int>>{};
  final seen = <String>{};
  final ordered = [...games]..sort((a, b) => '${a['date'] ?? a['date_game'] ?? a['datetime_start']}'.compareTo('${b['date'] ?? b['date_game'] ?? b['datetime_start']}'));
  for (final g in ordered) {
    final code = '${g['code_game'] ?? ''}'.trim().toUpperCase();
    if (!['JS', 'WS'].contains(code)) continue;
    final raw = '${g['date'] ?? g['date_game'] ?? g['datetime_start'] ?? ''}';
    if (raw.length < 10) continue;
    final date = raw.substring(0, 10);
    final key = '${date.substring(0,4)}|$code';
    if (ends.containsKey(key)) continue;
    if (!(g['finished'] == true || '${g['state']}'.contains('終了') || '${g['state']}'.toLowerCase() == 'final')) continue;
    final id = '${g['id_game'] ?? g['id'] ?? '$date|${g['id_team_home']}|${g['id_team_away']}'}';
    if (!seen.add('$key|$id')) continue;
    final h = num.tryParse('${g['score_home']}'), a = num.tryParse('${g['score_away']}');
    if (h == null || a == null || h < 0 || a < 0 || h == a) continue;
    final team = int.tryParse('${g[h > a ? 'id_team_home' : 'id_team_away']}');
    if (team == null || team <= 0) continue;
    final tally = wins.putIfAbsent(key, () => {});
    tally['$team'] = (tally['$team'] ?? 0) + 1;
    if (tally['$team']! >= 4) ends[key] = date;
  }
  return ends;
}
