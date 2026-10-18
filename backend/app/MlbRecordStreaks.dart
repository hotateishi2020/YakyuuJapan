import 'StrengthUsage.dart';

Map<String, List<Map<String, dynamic>>> mlbGameLogStreaks(
    List<Map<String, dynamic>> people, int year) {
  const keys = [
    'wins',
    'saves',
    'holds',
    'scoreless_games',
    'hit_games',
    'onbase_games',
    'hr_games',
    'appearances'
  ];
  final teamGames = <int, Map<int, Map<String, dynamic>>>{};
  final appearances = <int, Map<int, Map<String, dynamic>>>{};
  for (final person in people) {
    for (final group in usageMaps(person['stats'])) {
      for (final row in usageMaps(group['splits'])) {
        if (row['gameType'] != 'R') continue;
        final game = usageInt(usageMap(row['game'])['gamePk']),
            team = usageInt(usageMap(row['team'])['id']);
        if (game <= 0 || team <= 0) continue;
        teamGames.putIfAbsent(team, () => {})[game] = row;
        appearances.putIfAbsent(usageInt(person['id']), () => {})[game] = row;
      }
    }
  }
  final orders = <int, Map<int, int>>{};
  int compareGames(Map<String, dynamic> a, Map<String, dynamic> b) {
    final date = '${a['date']}'.compareTo('${b['date']}');
    return date != 0
        ? date
        : usageInt(usageMap(a['game'])['gameNumber'])
            .compareTo(usageInt(usageMap(b['game'])['gameNumber']));
  }

  for (final entry in teamGames.entries) {
    final games = entry.value.values.toList()..sort(compareGames);
    orders[entry.key] = {
      for (var i = 0; i < games.length; i++)
        usageInt(usageMap(games[i]['game'])['gamePk']): i
    };
  }
  final best = {for (final k in keys) k: <Map<String, dynamic>>[]};
  for (final person in people) {
    final peak = {for (final k in keys) k: 0};
    for (final group in usageMaps(person['stats'])) {
      final pitching = usageMap(group['group'])['displayName'] == 'pitching';
      final runs = {for (final k in keys) k: 0};
      final rows =
          usageMaps(group['splits']).where((s) => s['gameType'] == 'R').toList()
            ..sort((a, b) {
              final date = '${a['date']}'.compareTo('${b['date']}');
              return date != 0
                  ? date
                  : usageInt(usageMap(a['game'])['gameNumber'])
                      .compareTo(usageInt(usageMap(b['game'])['gameNumber']));
            });
      void add(String k, bool success, {bool skip = false}) {
        if (skip) return;
        final n = success ? runs[k]! + 1 : 0;
        runs[k] = n;
        if (n > peak[k]!) peak[k] = n;
      }

      for (final row in rows) {
        final s = usageMap(row['stat']);
        if (pitching) {
          add('wins', usageInt(s['wins']) > 0,
              skip: usageInt(s['wins']) + usageInt(s['losses']) == 0);
          add('saves', usageInt(s['saves']) > 0);
          add('holds', usageInt(s['holds']) > 0);
          add('scoreless_games', usageInt(s['runs']) == 0);
        } else {
          final hits = usageInt(s['hits']),
              walks = usageInt(s['baseOnBalls']) + usageInt(s['hitByPitch']);
          add('hit_games', hits > 0,
              skip: hits == 0 &&
                  usageInt(s['atBats']) == 0 &&
                  usageInt(s['sacFlies']) == 0);
          add('onbase_games', hits + walks > 0,
              skip: usageInt(s['plateAppearances']) == 0);
          add('hr_games', usageInt(s['homeRuns']) > 0);
        }
      }
    }
    final games = (appearances[usageInt(person['id'])] ?? {}).values.toList()
      ..sort(compareGames);
    int previousTeam = 0, previousIndex = -2, run = 0;
    for (final row in games) {
      final team = usageInt(usageMap(row['team'])['id']),
          game = usageInt(usageMap(row['game'])['gamePk']);
      final index = orders[team]![game]!;
      run = team == previousTeam && index == previousIndex + 1 ? run + 1 : 1;
      if (run > peak['appearances']!) peak['appearances'] = run;
      previousTeam = team;
      previousIndex = index;
    }
    for (final k in keys) {
      final n = peak[k]!;
      if (n <= 0) continue;
      final leaders = best[k]!;
      final max = leaders.isEmpty ? 0 : usageInt(leaders.first['value']);
      if (n < max) continue;
      if (n > max) leaders.clear();
      leaders.add({
        'name': person['fullName'],
        'player_id': person['id'],
        'value': n,
        'year': year,
        'source':
            'https://statsapi.mlb.com/api/v1/people/${person['id']}/stats?stats=gameLog&group=hitting,pitching&season=$year',
        'status': person['active'] == true
            ? 'active'
            : person['active'] == false
                ? 'retired'
                : 'unknown'
      });
    }
  }
  return best;
}
