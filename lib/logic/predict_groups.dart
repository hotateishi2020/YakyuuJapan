/// 日本時間の日付が期限の翌日以降なら、その予想は変更できない。期限が空なら締めていない。
bool predictDeadlinePassed(String? ymd, {DateTime? today}) {
  final raw = '${ymd ?? ''}'.trim();
  if (raw.length < 10) return false;
  final day = raw.substring(0, 10);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return false;
  final now = today ?? DateTime.now().toUtc().add(const Duration(hours: 9));
  final todayText = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return todayText.compareTo(day) > 0;
}

String _predictYmd(DateTime day) {
  return '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

/// NPB公式の行事日程。開幕・終了はその日自体。期限は前日にする。
const _npbCalendar = <int, Map<String, String>>{
  2021: {
    'op_first': '2021-03-02',
    'op_last': '2021-03-21',
    'nm_first': '2021-03-26',
    'ex_first': '2021-05-25',
    'ex_last': '2021-06-13',
    'as_first': '2021-07-16',
    'as_last': '2021-07-17',
  },
  2022: {
    'op_first': '2022-02-23',
    'op_last': '2022-03-21',
    'nm_first': '2022-03-25',
    'ex_first': '2022-05-24',
    'ex_last': '2022-06-12',
    'as_first': '2022-07-26',
    'as_last': '2022-07-27',
  },
  2023: {
    'op_first': '2023-02-23',
    'op_last': '2023-03-26',
    'nm_first': '2023-03-30',
    'ex_first': '2023-05-30',
    'ex_last': '2023-06-18',
    'as_first': '2023-07-19',
    'as_last': '2023-07-20',
  },
  2024: {
    'op_first': '2024-02-23',
    'op_last': '2024-03-24',
    'nm_first': '2024-03-29',
    'ex_first': '2024-05-28',
    'ex_last': '2024-06-16',
    'as_first': '2024-07-23',
    'as_last': '2024-07-24',
  },
  2025: {
    'op_first': '2025-02-22',
    'op_last': '2025-03-23',
    'nm_first': '2025-03-28',
    'ex_first': '2025-06-03',
    'ex_last': '2025-06-22',
    'as_first': '2025-07-23',
    'as_last': '2025-07-24',
  },
  2026: {
    'op_first': '2026-02-21',
    'op_last': '2026-03-22',
    'nm_first': '2026-03-27',
    'ex_first': '2026-05-26',
    'ex_last': '2026-06-18',
    'as_first': '2026-07-28',
    'as_last': '2026-07-29',
  },
};

/// 期限の候補。開幕前・終了前はその前日、月中はその月末。
List<({String label, String date})> predictDeadlineOptions(int year, [Map<String, dynamic>? marks]) {
  final merged = <String, String>{..._npbCalendar[year] ?? const {}};
  if (marks != null) {
    for (final entry in marks.entries) {
      final match = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch('${entry.value ?? ''}'.trim());
      if (match != null) merged['${entry.key}'] = match.group(0)!;
    }
  }
  String? before(String key) {
    final day = DateTime.tryParse(merged[key] ?? '');
    if (day == null) return null;
    return _predictYmd(DateTime(day.year, day.month, day.day).subtract(const Duration(days: 1)));
  }

  String monthEnd(int month) => _predictYmd(DateTime(year, month + 1, 0));

  final specs = <(String, String?)>[
    ('オープン戦開幕前', before('op_first')),
    ('オープン戦終了前', before('op_last')),
    ('シーズン開幕前', before('nm_first')),
    ('4月中', monthEnd(4)),
    ('交流戦開幕前', before('ex_first')),
    ('交流戦終了前', before('ex_last')),
    ('5月中', monthEnd(5)),
    ('6月中', monthEnd(6)),
    ('オールスター開始前', before('as_first')),
    ('オールスター終了前', before('as_last')),
    ('7月中', monthEnd(7)),
    ('8月中', monthEnd(8)),
    ('9月中', monthEnd(9)),
  ];
  return [
    for (final spec in specs)
      if (spec.$2 != null) (label: spec.$1, date: spec.$2!),
  ];
}

/// ログイン中の本人で、その区分の期限前だけ修正できる。
bool predictCanEditSlot({required int? viewerId, required int ownerId, required bool closed}) {
  return viewerId != null && viewerId > 0 && viewerId == ownerId && !closed;
}

/// ウェーバーの次の一手。昨年の当数が少ない人から、同じ手数の人を先にする。
int? predictWaiverTurnUser({
  required List<int> userIds,
  required Map<int, int> lastYearHits,
  required Map<int, int> pickCounts,
}) {
  final order = [...userIds]..sort((a, b) {
      final hits = (lastYearHits[a] ?? 0).compareTo(lastYearHits[b] ?? 0);
      if (hits != 0) return hits;
      return a.compareTo(b);
    });
  if (order.isEmpty) return null;
  var least = pickCounts[order.first] ?? 0;
  for (final id in order) {
    final count = pickCounts[id] ?? 0;
    if (count < least) least = count;
  }
  for (final id in order) {
    if ((pickCounts[id] ?? 0) == least) return id;
  }
  return order.first;
}

/// シーズンが終わっていない年は「現在」、それ以外は「結果」。
String predictSeasonHeader(int? year, {DateTime? today}) {
  final now = today ?? DateTime.now();
  if (year != null && year >= now.year) return '現在';
  return '結果';
}

/// 予想グループを年度ごとにまとめる。新しい年を先にする。年度のないグループは最後。
List<({int? year, List<Map<String, dynamic>> groups})> predictGroupsByYear(List<Map<String, dynamic>> rows) {
  final buckets = <int?, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final raw = row['int_year'];
    final year = raw == null || '$raw'.trim().isEmpty ? null : int.tryParse('$raw');
    final name = '${row['txt_name'] ?? row['name'] ?? ''}'.trim();
    final id = int.tryParse('${row['id'] ?? ''}') ?? 0;
    final list = buckets.putIfAbsent(year, () => []);
    if (list.any((item) => item['id'] == id && '${item['txt_name']}' == name)) continue;
    list.add({
      'id': id,
      'txt_name': name,
      'int_year': year,
      'date_limit': row['date_limit'],
      'date_limit_team': row['date_limit_team'],
      'date_limit_player': row['date_limit_player'],
      'proposal': row['proposal'],
      'users': row['users'] ?? const [],
      'titles': row['titles'] ?? const [],
      'players': row['players'] ?? const [],
      'teams': row['teams'] ?? const [],
      'champions': row['champions'] ?? const [],
      'japan': row['japan'],
      'season_marks': row['season_marks'],
      'delete_approvals': row['delete_approvals'] ?? const [],
      'waiver': row['waiver'],
    });
  }
  final years = buckets.keys.toList()
    ..sort((a, b) {
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    });
  return [for (final year in years) (year: year, groups: buckets[year]!)];
}

/// 同じグループの年度を一つにまとめる。年度は新しい順。
List<({int id, String name, List<Map<String, dynamic>> years})> predictGroupClusters(List<Map<String, dynamic>> rows) {
  final order = <String>[];
  final buckets = <String, List<Map<String, dynamic>>>{};
  final names = <String, String>{};
  final ids = <String, int>{};
  for (final row in rows) {
    final id = int.tryParse('${row['id'] ?? ''}') ?? 0;
    final rawName = '${row['txt_name'] ?? row['name'] ?? ''}'.trim();
    final key = '$id|$rawName';
    if (!buckets.containsKey(key)) order.add(key);
    names[key] = rawName.isEmpty ? '名称未設定' : rawName;
    ids[key] = id;
    final rawYear = row['int_year'];
    final year = rawYear == null || '$rawYear'.trim().isEmpty ? null : int.tryParse('$rawYear');
    final list = buckets.putIfAbsent(key, () => []);
    if (list.any((item) => item['int_year'] == year)) continue;
    list.add({
      'id': id,
      'txt_name': names[key],
      'int_year': year,
      'id_setting': int.tryParse('${row['id_setting'] ?? ''}') ?? 0,
      'date_limit': row['date_limit'],
      'date_limit_team': row['date_limit_team'],
      'date_limit_player': row['date_limit_player'],
      'proposal': row['proposal'],
      'code_select': '${row['code_select'] ?? 'FREE'}',
      'int_same_player_limit': int.tryParse('${row['int_same_player_limit'] ?? '1'}') ?? 1,
      'code_point': '${row['code_point'] ?? 'SINGLE'}',
      'users': row['users'] ?? const [],
      'titles': row['titles'] ?? const [],
      'players': row['players'] ?? const [],
      'teams': row['teams'] ?? const [],
      'champions': row['champions'] ?? const [],
      'japan': row['japan'],
      'season_marks': row['season_marks'],
      'delete_approvals': row['delete_approvals'] ?? const [],
      'waiver': row['waiver'],
    });
  }
  for (final list in buckets.values) {
    list.sort((a, b) {
      final ay = a['int_year'] as int?;
      final by = b['int_year'] as int?;
      if (ay == null) return 1;
      if (by == null) return -1;
      return by.compareTo(ay);
    });
  }
  return [for (final key in order) (id: ids[key]!, name: names[key]!, years: buckets[key]!)];
}
