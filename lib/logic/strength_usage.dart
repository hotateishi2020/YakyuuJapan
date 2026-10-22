import '../tools/json_utils.dart';

const usagePositions = <String, String>{
  'P': '投手',
  'C': '捕手',
  '1B': '一塁',
  '2B': '二塁',
  '3B': '三塁',
  'SS': '遊撃',
  'LF': '左翼',
  'CF': '中堅',
  'RF': '右翼',
  'DH': '指名打者',
};
int usageInt(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String usagePlayerKey(Map<String, dynamic> player) => '${player['player_key'] ?? player['source_player_id'] ?? player['name']}';

/// Resolve abbreviated lineup names using the roster's stable player ID.
String regularPlayerName(Map<String, dynamic> player, List<Map<String, dynamic>> roster) {
  final key = '${player['player_key'] ?? ''}'.trim();
  final id = '${player['source_player_id'] ?? ''}'.trim();
  final matches = roster.where((p) => key.isNotEmpty ? '${p['player_key'] ?? ''}' == key : id.isNotEmpty && '${p['source_player_id'] ?? ''}' == id).toList();
  if (matches.length == 1) {
    final name = '${matches.single['name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
  }
  for (final field in ['full_name', 'name_full', 'name']) {
    final name = '${player[field] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
  }
  return '';
}

String inningsLabel(int outs) => '${outs ~/ 3}${outs % 3 == 0 ? '' : ' ${outs % 3}/3'}回';

/// 起用率の高い組み合わせから確定し、確定済み選手・守備位置は再利用しない。
/// 同率は守備位置の表示順、選手キー順で安定させる。
Map<String, Map<String, dynamic>> selectRegulars(List<Map<String, dynamic>> positions) {
  final candidates = <Map<String, dynamic>>[];
  for (final group in positions) {
    final total = usageInt(group['total']);
    if (total <= 0) continue;
    final slot = '${group['slot']}';
    for (final player in listMapFromJson(group['players'])) {
      if (usageInt(player['count']) <= 0) continue;
      candidates.add({...player, 'position': slot, 'usage_rate': usageInt(player['count']) / total});
    }
  }
  candidates.sort((a, b) {
    final rate = (b['usage_rate'] as double).compareTo(a['usage_rate'] as double);
    if (rate != 0) return rate;
    final order = usagePositions.keys.toList().indexOf('${a['position']}').compareTo(usagePositions.keys.toList().indexOf('${b['position']}'));
    return order != 0 ? order : usagePlayerKey(a).compareTo(usagePlayerKey(b));
  });
  final result = <String, Map<String, dynamic>>{};
  final used = <String>{};
  for (final candidate in candidates) {
    final slot = '${candidate['position']}';
    if (result.containsKey(slot) || used.contains(usagePlayerKey(candidate))) {
      continue;
    }
    result[slot] = candidate;
    used.add(usagePlayerKey(candidate));
  }
  return result;
}

/// Primary regulars keep priority; additional regulars must reach 70% of
/// that position's season leader and may only appear at one position.
Map<String, List<Map<String, dynamic>>> selectRegularGroups(List<Map<String, dynamic>> positions) {
  final fielders = positions.where((p) => p['slot'] != 'P').toList();
  final primary = selectRegulars(fielders);
  final result = {
    for (final entry in primary.entries) entry.key: [entry.value]
  };
  final used = primary.values.map(usagePlayerKey).toSet();
  final candidates = <Map<String, dynamic>>[];
  for (final group in fielders) {
    final players = listMapFromJson(group['players']);
    final total = usageInt(group['total']);
    final maxStarts = players.fold<int>(0, (max, p) => usageInt(p['count']) > max ? usageInt(p['count']) : max);
    if (total <= 0 || maxStarts <= 0) continue;
    for (final player in players) {
      if (usageInt(player['count']) * 10 < maxStarts * 7) continue;
      candidates.add({...player, 'position': '${group['slot']}', 'usage_rate': usageInt(player['count']) / total});
    }
  }
  candidates.sort((a, b) {
    final rate = (b['usage_rate'] as double).compareTo(a['usage_rate'] as double);
    if (rate != 0) return rate;
    final position = usagePositions.keys.toList().indexOf('${a['position']}').compareTo(usagePositions.keys.toList().indexOf('${b['position']}'));
    return position != 0 ? position : usagePlayerKey(a).compareTo(usagePlayerKey(b));
  });
  for (final player in candidates) {
    if (!used.add(usagePlayerKey(player))) continue;
    result.putIfAbsent('${player['position']}', () => []).add(player);
  }
  return result;
}

List<Map<String, dynamic>> pitchingWorkloadBands(List<Map<String, dynamic>> pitchers) {
  final total = pitchers.fold<int>(0, (sum, p) => sum + usageInt(p['total_outs']));
  if (total == 0) return [];
  final result = <Map<String, dynamic>>[];
  for (final role in ['starter', 'relief']) {
    final players = [
      for (final p in pitchers)
        if (usageInt(p['${role}_outs']) > 0)
          {
            ...p,
            'count': usageInt(p['${role}_outs']),
            'role': role == 'starter' ? '先発' : '中継ぎ・抑え',
            'unit': 'outs',
          }
    ];
    players.sort((a, b) => usageInt(b['count']).compareTo(usageInt(a['count'])));
    final outs = players.fold<int>(0, (sum, p) => sum + usageInt(p['count']));
    result.add({'slot': role, 'label': role == 'starter' ? '先発負担率' : '中継負担率', 'total': total, 'role_outs': outs, 'unit': 'outs', 'players': players});
  }
  return result;
}

int? rosterAge(Map<String, dynamic> player, int year) {
  final birth = DateTime.tryParse('${player['date_birth']}');
  if (birth == null) return null;
  final now = DateTime.now();
  final date = year == now.year ? now : DateTime(year, 12, 31);
  return date.year - birth.year - ((date.month < birth.month || (date.month == birth.month && date.day < birth.day)) ? 1 : 0);
}

String? _recordedRosterPosition(Map<String, dynamic> player, Map<String, dynamic> team) {
  final key = usagePlayerKey(player);
  final pitching = listMapFromJson(team['pitching_workload']).where((p) => usagePlayerKey(p) == key).firstOrNull;
  if (pitching != null && player['position_group'] == '投手' && (usageInt(pitching['appearances']) > 0 || usageInt(pitching['total_outs']) > 0)) {
    final all = listMapFromJson(team['pitching_workload']);
    final mostSaves = all.fold<int>(0, (n, p) => usageInt(p['saves']) > n ? usageInt(p['saves']) : n);
    if (mostSaves > 0 && usageInt(pitching['saves']) == mostSaves) return '抑え';
    final starterOuts = usageInt(pitching['starter_outs']);
    final reliefOuts = usageInt(pitching['relief_outs']);
    if (starterOuts != reliefOuts) {
      return starterOuts > reliefOuts ? '先発' : '中継ぎ';
    }
    return usageInt(pitching['starts']) > usageInt(pitching['appearances']) - usageInt(pitching['starts']) ? '先発' : '中継ぎ';
  }
  String? position;
  var most = 0;
  for (final group in listMapFromJson(team['positions'])) {
    // DH is a batting role; place players by their actual defensive usage.
    if (group['slot'] == 'DH' || group['slot'] == 'P') continue;
    for (final p in listMapFromJson(group['players'])) {
      if (usagePlayerKey(p) == key && usageInt(p['count']) > most) {
        most = usageInt(p['count']);
        position = usagePositions['${group['slot']}'];
      }
    }
  }
  if (position != null) return position;
  // Prefer the highest level with actual usage, never a registration guess.
  final lower = player['lower_level_usage'];
  if (lower is Map) {
    for (final level in ['2', '3', '4']) {
      if (level == '4' && player['position_group'] == '内野手') continue;
      final record = lower[level];
      if (record is! Map) continue;
      if (player['position_group'] == '投手') {
        final starts = usageInt(record['starts']);
        final relief = usageInt(record['relief']);
        if (starts + relief > 0) return starts > relief ? '先発' : '中継ぎ';
      } else {
        final counts = record['positions'];
        if (counts is! Map) continue;
        String? best;
        var maximum = 0;
        for (final slot in ['C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF']) {
          // Infield fallback is checked through the third team only.
          if (level == '4' && !['LF', 'CF', 'RF'].contains(slot)) continue;
          if (usageInt(counts[slot]) > maximum) {
            maximum = usageInt(counts[slot]);
            best = usagePositions[slot];
          }
        }
        if (best != null) return best;
      }
    }
  }
  final registered = '${player['position_group'] ?? '不明'}';
  return ['捕手', '一塁', '二塁', '三塁', '遊撃', '左翼', '中堅', '右翼'].contains(registered) ? registered : null;
}

bool rosterUsageUnknown(Map<String, dynamic> player, Map<String, dynamic> team) => _recordedRosterPosition(player, team) == null;

String rosterPosition(Map<String, dynamic> player, Map<String, dynamic> team) =>
    _recordedRosterPosition(player, team) ??
    switch (player['position_group']) {
      '投手' => '中継ぎ',
      '外野手' => '右翼',
      '内野手' => '一塁',
      _ => '守備位置未確認',
    };

String rosterLevel(Map<String, dynamic> player) {
  final values = player['level_appearances'] is Map ? player['level_appearances'] as Map : {};
  var most = 0;
  final levels = <String>[];
  for (final entry in values.entries) {
    final count = usageInt(entry.value);
    if (count > most) {
      most = count;
      levels.clear();
    }
    if (count == most && count > 0) levels.add('${entry.key}軍');
  }
  if (levels.isEmpty) return '起用未確認';
  return '${levels.join('・')}中心';
}

/// Stronger position colors indicate the requested registration/usage priority.
double rosterCardTint(Map<String, dynamic> player) {
  final appearances = player['level_appearances'] is Map ? player['level_appearances'] as Map : {};
  final most = appearances.values.fold<int>(0, (max, count) => usageInt(count) > max ? usageInt(count) : max);
  if (most <= 0) return 0.08;
  final first = usageInt(appearances['1']) == most;
  final second = usageInt(appearances['2']) == most;
  if (player['registration'] == '支配下' && first) return 0.78;
  if (player['registration'] == '支配下' && second) return 0.32;
  if (player['registration'] == '育成' && second && !first) return 0.19;
  return 0.08;
}

/// Each card appears once, at its most-used level; ties prefer the higher level.
int rosterMainLevel(Map<String, dynamic> player) {
  if (player['new_arrival'] == true && usageInt(player['arrival_year']) > DateTime.now().year && player['departure_confirmed'] != true) return 1;
  final counts = player['level_appearances'];
  var level = 0, most = 0;
  if (counts is Map) {
    for (var n = 1; n <= 4; n++) {
      if (usageInt(counts['$n']) > most) {
        most = usageInt(counts['$n']);
        level = n;
      }
    }
  }
  if (level == 0 && player['lower_level_usage'] is Map) {
    final lower = player['lower_level_usage'] as Map;
    for (var n = 2; n <= 4; n++) {
      final p = lower['$n'];
      if (p is Map && usageInt(p['appearances']) > most) {
        most = usageInt(p['appearances']);
        level = n;
      }
    }
  }
  return level;
}

int? rosterWorkload(Map<String, dynamic> player, Map<String, dynamic> team, int level) {
  final pitcher = player['position_group'] == '投手';
  final levels = player['level_usage_metrics'];
  if (levels is Map && levels['$level'] is Map) {
    final value = (levels['$level'] as Map)[pitcher ? 'outs' : 'pa'];
    if (value != null) return usageInt(value);
  }
  if (level == 1) {
    for (final p in listMapFromJson(team[pitcher ? 'pitching_workload' : 'batting_stats'])) {
      if (usagePlayerKey(p) == usagePlayerKey(player)) {
        final value = p[pitcher ? 'total_outs' : 'pa'];
        if (value != null) return usageInt(value);
      }
    }
  }
  return null;
}

String rosterWorkloadLabel(Map<String, dynamic> p, Map<String, dynamic> team, int level) {
  final n = rosterWorkload(p, team, level);
  final pitcher = p['position_group'] == '投手';
  if (n == null) return pitcher ? '投球回未取得' : '打席数未取得';
  return pitcher ? '${n ~/ 3}${n % 3 == 0 ? '' : '.${n % 3}'}回' : '$n打席';
}

/// Confirmed departures only; free agency alone does not mean retirement or release.
String? rosterDepartureLabel(Map<String, dynamic> player) {
  if (player['retirement_confirmed'] == true) return '引退';
  if (player['transfer_confirmed'] == true) return '移籍';
  if (player['released_confirmed'] == true) return '戦力外';
  if (player['departure_confirmed'] != true) return null;
  final reason = '${player['departure_type'] ?? ''} ${player['departure_reason'] ?? ''}';
  if (RegExp('引退|retired|retirement').hasMatch(reason) || '${player['status_source']}'.contains('pn_retired')) {
    return '引退';
  }
  if (RegExp('移籍|transfer|trade').hasMatch(reason)) return '移籍';
  if (RegExp('戦力外|non.tender').hasMatch(reason)) return '戦力外';
  if ('${player['status_source']}'.contains('pn_released') || reason.contains('released')) {
    return '自由契約';
  }
  return '退団';
}

/// Confirmed routes and unsettled FA statuses are deliberately separate labels.
List<String> rosterMoveLabels(Map<String, dynamic> player, int year) {
  final labels = <String>[];
  if ([year - 1, year].contains(usageInt(player['move_method_year'])) && '${player['move_method'] ?? ''}'.isNotEmpty) {
    labels.add('${player['move_method']}');
  }
  if (player['departure_confirmed'] != true && usageInt(player['move_status_year']) == year && '${player['move_status'] ?? ''}'.isNotEmpty) {
    labels.add('${player['move_status']}');
  } else if (player['departure_confirmed'] != true && player['fa_eligible'] == true && labels.isEmpty) {
    labels.add('FA権保有');
  }
  return labels;
}

/// Relative to the displayed season. Winter spans the calendar-year boundary;
/// March–September is treated as the playing season, October–February as off.
String rosterMovePeriod(Map<String, dynamic> player, int year,
    {String? dateField, int? eventYear, bool offseason = false}) {
  final date = DateTime.tryParse(
      '${player[dateField ?? 'status_as_of'] ?? player['status_as_of'] ?? ''}');
  if (offseason) {
    return (eventYear ?? year) < year ? '昨オフ' : '今オフ';
  }
  if (date != null) {
    final arrivalYear = usageInt(player['arrival_year']);
    if (player['new_arrival'] == true && arrivalYear > date.year && date.month >= 9) {
      return arrivalYear <= year ? '昨オフ' : '今オフ';
    }
    if (date.month <= 2) return date.year <= year ? '昨オフ' : '今オフ';
    if (date.month >= 10) return date.year < year ? '昨オフ' : '今オフ';
    return date.year < year ? '昨季' : '今季';
  }
  return (eventYear ?? year) < year ? '昨季' : '今季';
}

String rosterTimedMoveLabel(String label, Map<String, dynamic> player, int year) {
  if (label == '外国人適用除外') return label;
  final method = label == player['move_method'];
  final offseason = !method && const [
    '国内FA', '海外FA', 'FA宣言', 'FA宣言（移籍先未定）',
    'ポスティング？', 'ポスティング容認',
  ].contains(label);
  final eventYear = usageInt(player[method ? 'move_method_year' : 'move_status_year']);
  final period = rosterMovePeriod(player, year,
      dateField: method ? 'move_method_as_of' : 'status_as_of',
      eventYear: eventYear > 0 ? eventYear : year, offseason: offseason);
  return '$period $label';
}
