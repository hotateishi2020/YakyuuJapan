import '../tools/StringTool.dart';
import 'PlayLabel.dart';
import 'PlayerName.dart';

const _changeResults = {
  'PINCH_HITTER',
  'PINCH_RUNNER',
  'PINCH_FIELDER',
  'CHANGE_POSITION',
  'CHANGE_PITCHER',
  'EXIT',
  'STEAL_BASE_SAFE',
  'STEAL_BASE_OUT',
};

int _halfKey(Map<String, dynamic> row) {
  final inning = _asInt(row['int_inning']);
  return inning * 2 + (_asBool(row['flg_bottom']) ? 1 : 0);
}

bool _isBattingPlate(Map<String, dynamic> row) {
  final code = '${row['code_result'] ?? ''}'.trim();
  final order = _asInt(row['int_batting_order']);
  return !_changeResults.contains(code) && order >= 1 && order <= 9;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final text = '$value'.trim().toLowerCase();
  return text == 'true' || text == 't' || text == '1';
}

String _name(dynamic value) {
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return '';
  return text;
}

String _lineupCompact(String name) {
  return StringTool.noSpace(name).replaceAll(RegExp(r'[・･·]'), '');
}

/// ダスティン・ハリス ↔ ダスティンハリス、J.メリル ↔ ジャクソン・メリル を同一選手とみなす。
bool _sameLineupName(String left, String right) {
  final a = _lineupCompact(left);
  final b = _lineupCompact(right);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  return playerNameMatches(query: left, nameFull: right) ||
      playerNameMatches(query: right, nameFull: left);
}

/// 打順1〜9。各枠は先発打者から、代打・代走・代守で入った選手の順。
/// [pitchers] は「試合|チーム|選手名」。打席のなかった救援投手の代わりに代打が出たとき、その投手枠へつなぐ。
Map<int, List<Map<String, dynamic>>> battingLineupsOf(
  List<Map<String, dynamic>> rows, {
  required Map<String, String> plays,
  required Set<String> pitchers,
  Map<String, int> rbi = const {},
}) {
  final byGame = <int, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    byGame.putIfAbsent(_asInt(row['id_game']), () => []).add(row);
  }
  final lineups = <int, List<Map<String, dynamic>>>{};
  for (final entry in byGame.entries) {
    lineups[entry.key] = _lineupOf(entry.key, entry.value, plays: plays, pitchers: pitchers, rbi: rbi);
  }
  return lineups;
}

List<Map<String, dynamic>> _lineupOf(
  int gameId,
  List<Map<String, dynamic>> rows, {
  required Map<String, String> plays,
  required Set<String> pitchers,
  Map<String, int> rbi = const {},
}) {
  _fillBattingOrders(rows);
  final slots = <String, List<String>>{};
  final roles = <String, String>{};
  final positions = <String, String>{};
  final ordered = [...rows]..sort((a, b) {
      final half = _halfKey(a).compareTo(_halfKey(b));
      if (half != 0) return half;
      // 同じイニングでは打席結果を交代より先に置く。記録順が前後しても、代走のあとに元の打者が戻らない。
      final phase = (_isBattingPlate(a) ? 0 : 1).compareTo(_isBattingPlate(b) ? 0 : 1);
      if (phase != 0) return phase;
      return _asInt(a['id']).compareTo(_asInt(b['id']));
    });

  bool listed(int team, String name) {
    for (var order = 1; order <= 9; order++) {
      final slot = slots['$team|$order'];
      if (slot == null) continue;
      for (final existing in slot) {
        if (_sameLineupName(existing, name)) return true;
      }
    }
    return false;
  }

  void place(int team, int order, String name) {
    if (team <= 0 || order < 1 || order > 9 || name.isEmpty || listed(team, name)) return;
    final slot = slots.putIfAbsent('$team|$order', () => <String>[]);
    // 打順枠に後から入ったのに代打・代走の記録がない選手は、代守（守備交代後の打席）とみなす。
    if (slot.isNotEmpty) {
      roles.putIfAbsent('$team|$name', () => '代守');
    }
    slot.add(name);
  }

  int? occupiedBy(int team, String name) {
    for (var order = 1; order <= 9; order++) {
      final slot = slots['$team|$order'];
      if (slot != null && slot.isNotEmpty && _sameLineupName(slot.last, name)) return order;
    }
    return null;
  }

  bool listedPitcher(int team, String name) {
    if (name.isEmpty) return false;
    final prefix = '$gameId|$team|';
    for (final key in pitchers) {
      if (!key.startsWith(prefix)) continue;
      final full = key.substring(prefix.length);
      if (full == name || full.startsWith(name) || name.startsWith(full)) return true;
    }
    return false;
  }

  int pitcherSlot(int team) {
    for (var order = 9; order >= 1; order--) {
      final slot = slots['$team|$order'];
      if (slot == null) continue;
      for (final name in slot) {
        if (pitchers.contains('$gameId|$team|$name')) return order;
      }
    }
    return 9;
  }

  void pinch(int team, String exit, String enter, String role) {
    if (team <= 0 || enter.isEmpty) return;
    // すでに出場している選手の守備位置変更・同選手の別名は、代守にしない。
    if (_sameLineupName(enter, exit) || listed(team, enter)) return;
    if (role == '代打' || role == '代走') {
      roles['$team|$enter'] = role;
    }
    if (exit.isNotEmpty) {
      final order = occupiedBy(team, exit);
      if (order != null) {
        place(team, order, enter);
        return;
      }
      if (listedPitcher(team, exit)) {
        place(team, pitcherSlot(team), enter);
      }
    }
  }

  for (final row in ordered) {
    final bottom = _asBool(row['flg_bottom']);
    final home = _asInt(row['id_team_home']);
    final away = _asInt(row['id_team_away']);
    final battingTeam = bottom ? home : away;
    final fieldingTeam = bottom ? away : home;
    final code = '${row['code_result'] ?? ''}'.trim();
    final order = _asInt(row['int_batting_order']);
    final batter = _name(row['name_full']);
    final enter = _name(row['name_enter']);
    final exit = _name(row['name_exit']);

    if (code == 'PINCH_HITTER') {
      final who = enter.isNotEmpty ? enter : batter;
      if (who.isNotEmpty) roles['$battingTeam|$who'] = '代打';
      final replaced = exit.isNotEmpty ? occupiedBy(battingTeam, exit) : null;
      final slotOrder = replaced ?? (order >= 1 && order <= 9 ? order : null);
      if (slotOrder != null) {
        place(battingTeam, slotOrder, who);
      } else if (exit.isNotEmpty && listedPitcher(battingTeam, exit)) {
        place(battingTeam, pitcherSlot(battingTeam), who);
      }
      continue;
    }
    if (code == 'PINCH_RUNNER') {
      pinch(battingTeam, exit, enter.isNotEmpty ? enter : batter, '代走');
      continue;
    }
    if (code == 'PINCH_FIELDER') {
      pinch(fieldingTeam, exit, enter, '代守');
      continue;
    }
    if (code == 'CHANGE_POSITION' && enter.isNotEmpty && exit.isNotEmpty && !_sameLineupName(enter, exit)) {
      pinch(fieldingTeam, exit, enter, '代守');
      continue;
    }
    if (_changeResults.contains(code)) continue;
    final team = _asInt(row['id_team']);
    final batting = team > 0 ? team : battingTeam;
    final pos = _defenseLabel('${row['code_position_from'] ?? ''}');
    if (pos.isNotEmpty && batter.isNotEmpty) positions.putIfAbsent('$batting|$batter', () => pos);
    place(batting, order, batter);
  }

  final result = <Map<String, dynamic>>[];
  final teams = <int>{};
  for (final key in slots.keys) {
    final team = int.tryParse(key.split('|').first) ?? 0;
    if (team > 0) teams.add(team);
  }
  for (final team in teams) {
    for (var order = 1; order <= 9; order++) {
      final names = slots['$team|$order'];
      if (names == null || names.isEmpty) continue;
      result.add({
        'id_team': team,
        'order': order,
        'players': [
          for (final name in names)
            {
              'name': name,
              'role': roles['$team|$name'] ?? '',
              'pos': positions['$team|$name'] ?? '',
              'plays': plays[playPlayerKey(gameId, team, name)] ?? '',
              'rbi': rbi[playPlayerKey(gameId, team, name)] ?? 0,
            },
        ],
      });
    }
  }
  return result;
}

/// 打順が 0 の打席は、同じイニングの前後の打順から空いている番号を埋める。
/// 代打の行にも、その選手の打席と同じ番号を写す。
void _fillBattingOrders(List<Map<String, dynamic>> rows) {
  final groups = <int, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    groups.putIfAbsent(_halfKey(row), () => []).add(row);
  }
  for (final group in groups.values) {
    final ordered = _halfSequence(group);
    final used = <int>{};
    final byName = <String, int>{};
    int? knownOrder(String name) {
      final direct = byName[name];
      if (direct != null) return direct;
      for (final entry in byName.entries) {
        if (_sameLineupName(entry.key, name)) return entry.value;
      }
      return null;
    }

    var last = 0;
    for (final row in ordered) {
      final code = '${row['code_result'] ?? ''}'.trim();
      if (code.isEmpty || _changeResults.contains(code)) continue;
      final name = _name(row['name_full']);
      final order = _asInt(row['int_batting_order']);
      if (order >= 1 && order <= 9) {
        used.add(order);
        last = order;
        if (name.isNotEmpty) byName[name] = order;
        continue;
      }
      if (name.isEmpty) continue;
      final known = knownOrder(name);
      if (known != null) {
        row['int_batting_order'] = known;
        continue;
      }
      final open = _nextOpenOrder(last, used);
      row['int_batting_order'] = open;
      used.add(open);
      byName[name] = open;
      last = open;
    }
    for (final row in ordered) {
      final code = '${row['code_result'] ?? ''}'.trim();
      if (code != 'PINCH_HITTER' && code != 'PINCH_RUNNER') continue;
      if (_asInt(row['int_batting_order']) >= 1) continue;
      final name = _name(row['name_enter']).isNotEmpty ? _name(row['name_enter']) : _name(row['name_full']);
      final known = knownOrder(name);
      if (known != null) row['int_batting_order'] = known;
    }
  }
}

List<Map<String, dynamic>> _halfSequence(List<Map<String, dynamic>> rows) {
  int outsOf(Map<String, dynamic> row) => _asInt(row['cnt_out']);
  int orderOf(Map<String, dynamic> row) => _asInt(row['int_batting_order']);
  int runnersOf(Map<String, dynamic> row) {
    var count = 0;
    if (_asBool(row['flg_runner_first'])) count++;
    if (_asBool(row['flg_runner_second'])) count++;
    if (_asBool(row['flg_runner_third'])) count++;
    return count;
  }

  var start = 1;
  var bestOut = 99;
  var bestRunners = 99;
  for (final row in rows) {
    final order = orderOf(row);
    if (order < 1 || order > 9) continue;
    final outs = outsOf(row);
    final runners = runnersOf(row);
    if (outs < bestOut || (outs == bestOut && runners < bestRunners)) {
      bestOut = outs;
      bestRunners = runners;
      start = order;
    }
  }
  int distance(int order) {
    if (order < 1 || order > 9) return 100;
    return (order - start + 9) % 9;
  }

  final ordered = [...rows]..sort((a, b) {
      final byOut = outsOf(a).compareTo(outsOf(b));
      if (byOut != 0) return byOut;
      final byDistance = distance(orderOf(a)).compareTo(distance(orderOf(b)));
      if (byDistance != 0) return byDistance;
      return _asInt(a['id']).compareTo(_asInt(b['id']));
    });
  return ordered;
}

String _defenseLabel(String raw) {
  final text = raw.trim();
  const short = {'投', '捕', '一', '二', '三', '遊', '左', '中', '右', '指'};
  if (short.contains(text)) return text;
  return switch (text) {
    'P' || 'PITCHER' => '投',
    'C' || 'CATCHER' => '捕',
    'FIRST' => '一',
    'SECOND' => '二',
    'THIRD' => '三',
    'SS' => '遊',
    'LEFT' || 'LF' => '左',
    'CENTER' || 'CF' => '中',
    'RIGHT' || 'RF' => '右',
    'DH' => '指',
    _ => '',
  };
}

int _nextOpenOrder(int after, Set<int> used) {
  for (var step = 1; step <= 9; step++) {
    final order = ((after + step - 1) % 9) + 1;
    if (!used.contains(order)) return order;
  }
  return 1;
}

/// 登板した投手と、予告先発。キーは「試合|チーム|選手名」。
Set<String> pitcherKeysOf(List<Map<String, dynamic>> gameRows) {
  final keys = <String>{};
  for (final row in gameRows) {
    final gameId = _asInt(row['id_game']);
    if (gameId <= 0) continue;
    final pitcher = row['flg_pitcher'];
    final isPitcher = pitcher == true || '$pitcher'.trim().toLowerCase() == 'true' || '$pitcher'.trim() == 't';
    final name = _name(row['name_full_summary']);
    final team = _asInt(row['id_team_summary']);
    if (isPitcher && name.isNotEmpty && team > 0) {
      keys.add('$gameId|$team|$name');
    }
    void starter(String nameKey, String teamKey) {
      final starterName = _name(row[nameKey]);
      final starterTeam = _asInt(row[teamKey]);
      if (starterName.isNotEmpty && starterTeam > 0) {
        keys.add('$gameId|$starterTeam|$starterName');
      }
    }

    starter('name_pitcher_home', 'id_team_home');
    starter('name_pitcher_away', 'id_team_away');
  }
  return keys;
}
