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

/// 1 = リーグ内最高、-1 = 最低。全チーム同率・勝敗なしは強調しない。
int scheduleOpponentExtreme(List<Map<String, dynamic>> teams,
    List<Map<String, dynamic>> games, Map<String, dynamic> team, dynamic opponent) {
  String league(Map<String, dynamic> row) => '${row['source_league_id'] ?? row['id_league']}';
  double? rate(Map<String, dynamic> row) {
    if ('${row['id_team']}' == '$opponent') return null;
    final record = scheduleRecord(games, row['id_team'], opponent: opponent);
    return record.wins + record.losses == 0 ? null : record.wins / (record.wins + record.losses);
  }
  final value = rate(team);
  if (value == null) return 0;
  final rates = teams.where((row) => league(row) == league(team)).map(rate).whereType<double>().toList()..sort();
  if (rates.length < 2 || rates.first == rates.last) return 0;
  return value == rates.last ? 1 : value == rates.first ? -1 : 0;
}

String starterWorkloadLabel(dynamic value) {
  final rate = num.tryParse('$value');
  return rate == null || !rate.isFinite || rate < 0 || rate > 1 ? '—' : '${(rate * 100).toStringAsFixed(1)}%';
}

/// 1: league maximum, -1: minimum; missing or all-equal values stay neutral.
int starterWorkloadExtreme(List<Map<String, dynamic>> teams, Map<String, dynamic> team) {
  double? rate(Map<String, dynamic> row) {
    final value = double.tryParse('${row['starter_workload_rate']}');
    return value != null && value.isFinite && value >= 0 && value <= 1 ? value : null;
  }
  final value = rate(team);
  if (value == null || team['id_league'] == null) return 0;
  final values = teams.where((row) => '${row['id_league']}' == '${team['id_league']}')
      .map(rate).whereType<double>().toList()..sort();
  if (values.length < 2 || values.first == values.last) return 0;
  return value == values.last ? 1 : value == values.first ? -1 : 0;
}
