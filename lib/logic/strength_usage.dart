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
int usageInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String usagePlayerKey(Map<String, dynamic> player) =>
    '${player['player_key'] ?? player['source_player_id'] ?? player['name']}';

/// Resolve abbreviated lineup names using the roster's stable player ID.
String regularPlayerName(
    Map<String, dynamic> player, List<Map<String, dynamic>> roster) {
  final key = '${player['player_key'] ?? ''}'.trim();
  final id = '${player['source_player_id'] ?? ''}'.trim();
  final matches = roster
      .where((p) => key.isNotEmpty
          ? '${p['player_key'] ?? ''}' == key
          : id.isNotEmpty && '${p['source_player_id'] ?? ''}' == id)
      .toList();
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

String inningsLabel(int outs) =>
    '${outs ~/ 3}${outs % 3 == 0 ? '' : ' ${outs % 3}/3'}回';

/// 起用率の高い組み合わせから確定し、確定済み選手・守備位置は再利用しない。
/// 同率は守備位置の表示順、選手キー順で安定させる。
Map<String, Map<String, dynamic>> selectRegulars(
    List<Map<String, dynamic>> positions) {
  final candidates = <Map<String, dynamic>>[];
  for (final group in positions) {
    final total = usageInt(group['total']);
    if (total <= 0) continue;
    final slot = '${group['slot']}';
    for (final player in listMapFromJson(group['players'])) {
      if (usageInt(player['count']) <= 0) continue;
      candidates.add({
        ...player,
        'position': slot,
        'usage_rate': usageInt(player['count']) / total
      });
    }
  }
  candidates.sort((a, b) {
    final rate =
        (b['usage_rate'] as double).compareTo(a['usage_rate'] as double);
    if (rate != 0) return rate;
    final order = usagePositions.keys
        .toList()
        .indexOf('${a['position']}')
        .compareTo(usagePositions.keys.toList().indexOf('${b['position']}'));
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
Map<String, List<Map<String, dynamic>>> selectRegularGroups(
    List<Map<String, dynamic>> positions) {
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
    final maxStarts = players.fold<int>(
        0, (max, p) => usageInt(p['count']) > max ? usageInt(p['count']) : max);
    if (total <= 0 || maxStarts <= 0) continue;
    for (final player in players) {
      if (usageInt(player['count']) * 10 < maxStarts * 7) continue;
      candidates.add({
        ...player,
        'position': '${group['slot']}',
        'usage_rate': usageInt(player['count']) / total
      });
    }
  }
  candidates.sort((a, b) {
    final rate =
        (b['usage_rate'] as double).compareTo(a['usage_rate'] as double);
    if (rate != 0) return rate;
    final position = usagePositions.keys
        .toList()
        .indexOf('${a['position']}')
        .compareTo(usagePositions.keys.toList().indexOf('${b['position']}'));
    return position != 0
        ? position
        : usagePlayerKey(a).compareTo(usagePlayerKey(b));
  });
  for (final player in candidates) {
    if (!used.add(usagePlayerKey(player))) continue;
    result.putIfAbsent('${player['position']}', () => []).add(player);
  }
  return result;
}

List<Map<String, dynamic>> pitchingWorkloadBands(
    List<Map<String, dynamic>> pitchers) {
  final total =
      pitchers.fold<int>(0, (sum, p) => sum + usageInt(p['total_outs']));
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
    players
        .sort((a, b) => usageInt(b['count']).compareTo(usageInt(a['count'])));
    final outs = players.fold<int>(0, (sum, p) => sum + usageInt(p['count']));
    result.add({
      'slot': role,
      'label': role == 'starter' ? '先発負担率' : '中継負担率',
      'total': total,
      'role_outs': outs,
      'unit': 'outs',
      'players': players
    });
  }
  return result;
}

int? rosterAge(Map<String, dynamic> player, int year) {
  final birth = DateTime.tryParse('${player['date_birth']}');
  if (birth == null) return null;
  final now = DateTime.now();
  final date = year == now.year ? now : DateTime(year, 12, 31);
  return date.year -
      birth.year -
      ((date.month < birth.month ||
              (date.month == birth.month && date.day < birth.day))
          ? 1
          : 0);
}

String rosterPosition(Map<String, dynamic> player, Map<String, dynamic> team) {
  final key = usagePlayerKey(player);
  final pitching = listMapFromJson(team['pitching_workload'])
      .where((p) => usagePlayerKey(p) == key)
      .firstOrNull;
  if (pitching != null && player['position_group'] == '投手') {
    final all = listMapFromJson(team['pitching_workload']);
    final mostSaves = all.fold<int>(
        0, (n, p) => usageInt(p['saves']) > n ? usageInt(p['saves']) : n);
    if (mostSaves > 0 && usageInt(pitching['saves']) == mostSaves) return '抑え';
    final starterOuts = usageInt(pitching['starter_outs']);
    final reliefOuts = usageInt(pitching['relief_outs']);
    if (starterOuts != reliefOuts) {
      return starterOuts > reliefOuts ? '先発' : '中継ぎ';
    }
    return usageInt(pitching['starts']) >
            usageInt(pitching['appearances']) - usageInt(pitching['starts'])
        ? '先発'
        : '中継ぎ';
  }
  String? position;
  var most = 0;
  for (final group in listMapFromJson(team['positions'])) {
    // DH is a batting role; place players by their actual defensive usage.
    if (group['slot'] == 'DH') continue;
    for (final p in listMapFromJson(group['players'])) {
      if (usagePlayerKey(p) == key && usageInt(p['count']) > most) {
        most = usageInt(p['count']);
        position = usagePositions['${group['slot']}'];
      }
    }
  }
  if (position != null) return position;
  final registered = '${player['position_group'] ?? '不明'}';
  return registered == '指名打者' ? '守備位置未確認' : registered;
}

String rosterLevel(Map<String, dynamic> player) {
  final values = player['level_appearances'] is Map
      ? player['level_appearances'] as Map
      : {};
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
  final appearances = player['level_appearances'] is Map
      ? player['level_appearances'] as Map
      : {};
  final most = appearances.values.fold<int>(
      0, (max, count) => usageInt(count) > max ? usageInt(count) : max);
  if (most <= 0) return 0.08;
  final first = usageInt(appearances['1']) == most;
  final second = usageInt(appearances['2']) == most;
  if (player['registration'] == '支配下' && first) return 0.78;
  if (player['registration'] == '支配下' && second) return 0.32;
  if (player['registration'] == '育成' && second && !first) return 0.19;
  return 0.08;
}
