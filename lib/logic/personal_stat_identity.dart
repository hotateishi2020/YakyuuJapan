/// Known MLB abbreviated imports refer to the same player as the full-name row.
/// Keep league/team/stat boundaries and prefer ranked results over supplements.
List<Map<String, dynamic>> canonicalMlbPersonalStats(List<Map<String, dynamic>> rows) {
  String clean(dynamic value) => '${value ?? ''}'
      .replaceAll(RegExp(r'\([^)]*\)|（[^）]*）|[\s　]'), '');
  const names = {'大谷': '大谷翔平', '大谷翔平': '大谷翔平',
    '山本': '山本由伸', '山本由伸': '山本由伸'};
  String? identity(Map<String, dynamic> r) {
    if (![3,4].contains(int.tryParse('${r['id_league']}'))) return null;
    final name = names[clean(r['name_full'] ?? r['name_player'])];
    if (name == null) return null;
    final team = r['id_team'] ?? r['name_team'];
    if (team == null || '$team'.isEmpty) return null;
    return '${r['id_league']}:$team:$name';
  }
  final fullIds = <String, dynamic>{};
  for (final row in rows) {
    final key = identity(row), name = clean(row['name_full'] ?? row['name_player']);
    if (key != null && names[name] == name && row['id_player'] != null) fullIds[key] = row['id_player'];
  }
  bool ranked(Map<String, dynamic> r) {
    final n = int.tryParse('${r['int_rank']}') ?? 1000;
    return n > 0 && n < 1000;
  }
  num count(Map<String, dynamic> r) => num.tryParse('${r['cnt_play']}') ?? 0;
  final result = <Map<String, dynamic>>[];
  final positions = <String, int>{};
  for (final source in rows) {
    final person = identity(source);
    if (person == null) { result.add(source); continue; }
    final rawName = '${source['name_player'] ?? source['name_full'] ?? ''}';
    final name = names[clean(source['name_full'] ?? rawName)]!;
    final suffix = RegExp(r'\([^)]*\)|（[^）]*）').firstMatch(rawName)?.group(0) ?? '';
    final row = <String,dynamic>{...source,
      if (fullIds[person] != null) 'id_player':fullIds[person],
      'name_player':'$name$suffix',
    };
    final key = '$person:${source['id_stats'] ?? source['title']}';
    final index = positions[key];
    if (index == null) {
      positions[key] = result.length;
      result.add(row);
      continue;
    }
    final previous = result[index];
    final prefer = ranked(row) && !ranked(previous) ||
        ranked(row) == ranked(previous) && count(row) > count(previous);
    final chosen = <String,dynamic>{...(prefer ? row : previous)};
    for (final field in ['id_users','colors_user']) {
      final values = <String>{for (final r in [previous,row])
        ...'${r[field] ?? ''}'.split('/').where((v)=>v.isNotEmpty)};
      if (values.isNotEmpty) chosen[field] = values.join('/');
    }
    result[index] = chosen;
  }
  return result;
}
