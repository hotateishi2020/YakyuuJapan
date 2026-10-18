import 'StrengthUsage.dart';

/// Box-score streaks in verified contiguous game coverage. Missing games reset
/// affected runs conservatively: never join two observed runs across a gap.
Map<String, List<Map<String, dynamic>>> buildSummaryStreaks(List<Map<String, dynamic>> games, List<Map<String, dynamic>> summaries, int year) {
  const supported = ['wins', 'saves', 'holds', 'scoreless_games', 'hit_games', 'onbase_games', 'hr_games'];
  final runs = {for (final k in supported) k: <int, int>{}};
  final best = {for (final k in supported) k: <int, int>{}};
  final names = <int, String>{};
  final possibleTeams = <int, Set<int>>{};
  final byGame = <int, List<Map<String, dynamic>>>{};
  for (final row in summaries) {
    byGame.putIfAbsent(usageInt(row['id_game']), () => []).add(row);
  }
  void add(String key, int id, bool success, {bool skip = false}) {
    if (skip) return;
    final count = success ? (runs[key]![id] ?? 0) + 1 : 0;
    runs[key]![id] = count;
    if (count > (best[key]![id] ?? 0)) best[key]![id] = count;
  }

  for (final game in games) {
    final rows = byGame[usageInt(game['id'])];
    if (game['flg_stats_loaded'] != true || rows == null || rows.isEmpty) {
      for (final run in runs.values) {
        final affected = {usageInt(game['id_team_home']), usageInt(game['id_team_away'])};
        run.removeWhere((id, _) => affected.contains(0) || possibleTeams[id] == null || possibleTeams[id]!.any(affected.contains));
      }
      continue;
    }
    for (final row in rows) {
      final id = usageInt(row['id_player']);
      if (id <= 0) continue;
      names[id] = '${row['name'] ?? ''}';
      // Summary rows lack historical team IDs. Retain both possible teams
      // rather than assuming a player's current club also applies here.
      possibleTeams[id] = {usageInt(game['id_team_home']), usageInt(game['id_team_away'])};
      final decision = '${row['code_result_pitcher'] ?? ''}';
      final pitched = usageInt(row['int_pitch']) > 0 || (double.tryParse('${row['double_inning_pitch']}') ?? 0) > 0 || decision.isNotEmpty;
      if (pitched) {
        add('wins', id, decision == 'WIN', skip: !['WIN', 'LOSE'].contains(decision));
        add('saves', id, decision == 'SAVE');
        add('holds', id, decision == 'HOLD');
        add('scoreless_games', id, usageInt(row['int_runs']) == 0);
      }
      final hits = usageInt(row['int_hit1']) + usageInt(row['int_hit2']) + usageInt(row['int_hit3']) + usageInt(row['int_homerun']);
      final ab = usageInt(row['int_batting']), walks = usageInt(row['int_fourball']) + usageInt(row['int_dead_batting']);
      // Sacrifice flies and bunts share one field. Do not infer the official
      // hit-game continuation rule where that distinction is unavailable.
      final ambiguous = ab == 0 && hits == 0 && usageInt(row['int_sacrifice']) > 0;
      final batting = ab > 0 || hits > 0 || walks > 0 || usageInt(row['int_sacrifice']) > 0;
      if (batting) {
        add('hit_games', id, hits > 0, skip: ab == 0 && walks > 0 && !ambiguous);
        add('onbase_games', id, hits + walks > 0);
        add('hr_games', id, usageInt(row['int_homerun']) > 0);
      }
    }
  }
  return {
    for (final k in supported)
      k: [
        for (final entry in best[k]!.entries)
          if (entry.value > 0 && !best[k]!.values.any((v) => v > entry.value)) {'id_player': entry.key, 'name': names[entry.key], 'value': entry.value, 'year': year, 'status': 'unknown'}
      ]
  };
}

/// Plate-appearance streaks use the event's actual batter / stealing runner,
/// not the batter who happened to be at the plate during a steal.
Map<String, List<Map<String, dynamic>>> buildEventStreaks(List<Map<String, dynamic>> games, List<Map<String, dynamic>> summaries, List<Map<String, dynamic>> events, int year) {
  const keys = ['hit_pa', 'hr_pa', 'onbase_pa', 'outs', 'strikeouts', 'steals', 'appearances'];
  const hits = {'HIT1', 'HIT2', 'HIT3', 'HOMERUN'};
  const reach = {...hits, 'WALK', 'WALK_DEAD'};
  const retired = {'OUT_FLY', 'OUT_GROUND', 'OUT_POP_UP', 'OUT_LINE_DRIVE', 'OUT_DOUBLE_PLAY', 'SACRIFICE_BUNT', 'SACRIFICE_FLY', 'SQUEEZE', 'STRIKE_OUT'};
  const plate = {...reach, ...retired, 'DROPPED_THIRD', 'ERROR', 'ERROR_FIELDING', 'INTERFERENCE_BATTING', 'FIELDERS_CHOICE'};
  final runs = {for (final k in keys) k: <int, int>{}}, best = {for (final k in keys) k: <int, int>{}};
  final names = <int, String>{}, teams = <int, int>{};
  final byGame = <int, List<Map<String, dynamic>>>{}, boxes = <int, List<Map<String, dynamic>>>{};
  for (final row in summaries) {
    boxes.putIfAbsent(usageInt(row['id_game']), () => []).add(row);
    names[usageInt(row['id_player'])] = '${row['name'] ?? ''}';
  }
  for (final e in events) {
    byGame.putIfAbsent(usageInt(e['id_game']), () => []).add(e);
  }
  void add(String key, int id, bool success) {
    if (id <= 0) return;
    final count = success ? (runs[key]![id] ?? 0) + 1 : 0;
    runs[key]![id] = count;
    if (count > (best[key]![id] ?? 0)) best[key]![id] = count;
  }

  for (final game in games) {
    final id = usageInt(game['id']), rows = byGame[id] ?? [], box = boxes[id] ?? [];
    final home = usageInt(game['id_team_home']), away = usageInt(game['id_team_away']);
    // Require the recorded PA count to match box scores for both teams.
    final expected = box.fold<int>(0, (n, r) => n + usageInt(r['int_batting']) + usageInt(r['int_fourball']) + usageInt(r['int_dead_batting']) + usageInt(r['int_sacrifice']));
    final actual = rows.where((e) => plate.contains(e['code_result'])).length;
    if (game['flg_stats_loaded'] != true || expected == 0 || actual != expected) {
      for (final run in runs.values) {
        run.removeWhere((player, _) => home <= 0 || away <= 0 || teams[player] == null || teams[player] == home || teams[player] == away);
      }
      continue;
    }
    final observedTeams = <int, int>{};
    for (final e in rows) {
      final batting = e['flg_bottom'] == true ? home : away, pitching = e['flg_bottom'] == true ? away : home;
      final batter = usageInt(e['id_batter']), pitcher = usageInt(e['id_pitcher']), runner = usageInt(e['id_player_enter']);
      if (batter > 0) observedTeams[batter] = batting;
      if (pitcher > 0) observedTeams[pitcher] = pitching;
      final code = '${e['code_result']}';
      if (code == 'STEAL_BASE_SAFE' || code == 'STEAL_BASE_OUT') {
        if (runner > 0) {
          observedTeams[runner] = batting;
          add('steals', runner, code == 'STEAL_BASE_SAFE');
        } else {
          runs['steals']!.removeWhere((player, _) => (observedTeams[player] ?? teams[player]) == null || (observedTeams[player] ?? teams[player]) == batting);
        }
      }
      if (!plate.contains(code)) continue;
      add('hr_pa', batter, code == 'HOMERUN');
      add('hit_pa', batter, hits.contains(code));
      add('onbase_pa', batter, reach.contains(code));
      add('outs', pitcher, retired.contains(code));
      add('strikeouts', pitcher, code == 'STRIKE_OUT');
    }
    teams.addAll(observedTeams);
    final present = {for (final r in box) usageInt(r['id_player'])};
    for (final entry in teams.entries) {
      if (entry.value == home || entry.value == away) {
        add('appearances', entry.key, present.contains(entry.key));
      }
    }
  }
  return {
    for (final key in keys)
      key: [
        for (final e in best[key]!.entries)
          if (e.value > 0 && !best[key]!.values.any((n) => n > e.value)) {'id_player': e.key, 'name': names[e.key] ?? '選手ID ${e.key}', 'value': e.value, 'year': year, 'status': 'unknown'}
      ]
  };
}
