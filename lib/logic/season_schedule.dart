String scheduleDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
List<DateTime> scheduleWindow(DateTime today) => [for (var i = -10; i <= 10; i++) DateTime(today.year, today.month, today.day + i)];
bool scheduleHasTeam(Map<String, dynamic> g, dynamic id) => '${g['id_team_home']}' == '$id' || '${g['id_team_away']}' == '$id';
String scheduleOutcome(Map<String, dynamic> g, dynamic id) {
  if (g['finished'] != true) return '';
  final h = num.tryParse('${g['score_home']}'), a = num.tryParse('${g['score_away']}');
  if (h == null || a == null) return '';
  final diff = '${g['id_team_home']}' == '$id' ? h - a : a - h;
  return diff > 0
      ? '○'
      : diff < 0
          ? '●'
          : '△';
}

String scheduleMatchup(Map<String, dynamic> g, {dynamic teamId}) {
  final h = '${g['name_home'] ?? g['home_code'] ?? ''}', a = '${g['name_away'] ?? g['away_code'] ?? ''}';
  final score = g['finished'] == true ? '${g['score_home'] ?? '—'}–${g['score_away'] ?? '—'}' : 'vs';
  final state = '${g['state'] ?? ''}';
  final cancelled = RegExp('中止|延期|Cancelled|Postponed', caseSensitive: false).hasMatch(state);
  if (teamId == null) return '$h $score $a${cancelled ? '（中止・延期）' : ''}';
  final home = '${g['id_team_home']}' == '$teamId', opponent = home ? a : h;
  if (cancelled) return '$opponent 中止・延期';
  final result = scheduleOutcome(g, teamId);
  if (result.isNotEmpty) {
    return '$result$opponent ${home ? g['score_home'] : g['score_away']}–${home ? g['score_away'] : g['score_home']}';
  }
  final time = '${g['time'] ?? g['datetime_start'] ?? ''}';
  final parsed = DateTime.tryParse(time.replaceFirst(' ', 'T'))?.toLocal();
  final label = parsed != null
      ? '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}'
      : RegExp(r'^\d{1,2}:\d{2}$').hasMatch(time)
          ? time
          : '';
  return '${home ? 'H' : 'A'} $opponent${label.isEmpty ? '' : ' $label'}';
}

({int wins, int losses, int draws}) scheduleRecord(Iterable<Map<String, dynamic>> games, dynamic id, {dynamic opponent}) {
  var w = 0, l = 0, d = 0;
  for (final g in games) {
    if (g['regular'] != true || !scheduleHasTeam(g, id) || opponent != null && !scheduleHasTeam(g, opponent)) {
      continue;
    }
    switch (scheduleOutcome(g, id)) {
      case '○':
        w++;
      case '●':
        l++;
      case '△':
        d++;
    }
  }
  return (wins: w, losses: l, draws: d);
}

List<Map<String, dynamic>> interleagueStandings(List<Map<String, dynamic>> teams, List<Map<String, dynamic>> games) {
  final inter = games.where((g) => g['league_home'] != null && g['league_away'] != null && g['league_home'] != g['league_away']);
  final result = [
    for (final t in teams)
      (() {
        final r = scheduleRecord(inter, t['id_team']);
        return <String, dynamic>{...t, 'wins': r.wins, 'losses': r.losses, 'draws': r.draws, 'pct': r.wins + r.losses > 0 ? r.wins / (r.wins + r.losses) : null};
      })()
  ];
  result.sort((a, b) => ((b['pct'] as double?) ?? -1).compareTo((a['pct'] as double?) ?? -1));
  return result;
}
