/// 保存済み成績と、その時点の予想を組み合わせた表示データ。
class PlayerDisplay {
  final List<Map<String, dynamic>> stats;
  final List<Map<String, dynamic>> predictions;

  const PlayerDisplay({required this.stats, required this.predictions});
}

/// 成績の順位は再集計せず、登録済みの1位と最新の予想を照合する。
/// 入力のリスト・行は変更しない。
PlayerDisplay buildPlayerDisplay(
  List<Map<String, dynamic>> statsRows,
  List<Map<String, dynamic>> predictionRows,
) {
  final predictionsByStat = <String, List<Map<String, dynamic>>>{};
  for (final row in predictionRows) {
    predictionsByStat.putIfAbsent(_statKey(row), () => []).add(row);
  }

  final leadersByStat = <String, List<Map<String, dynamic>>>{};
  final current = <Map<String, dynamic>>[];
  final stats = <Map<String, dynamic>>[];
  for (final row in statsRows) {
    final key = _statKey(row);
    final picks = predictionsByStat[key] ?? const <Map<String, dynamic>>[];
    final matching = picks.where((pick) => _samePlayer(row, pick));
    final stat = <String, dynamic>{
      ...row,
      'id_users': _slashList(matching.map((pick) => pick['id_user'])),
      'colors_user': _slashList(matching.map((pick) => pick['code_color'])),
    };
    // 現在行の合成用メタデータは成績セルに渡さない。
    // 成績セルは規定到達率を含む既存の name_player を表示する。
    stat.remove('prediction_name');
    stat.remove('league_name');
    stat.remove('flg_pitcher');
    stats.add(stat);
    if (_asInt(row['int_rank']) != 1) continue;

    final leaders = leadersByStat.putIfAbsent(key, () => []);
    // 同じ首位選手が複数行になっていても「現在」列は一度だけ表示する。
    if (leaders.any((leader) => _sameSnapshotPlayer(leader, row))) continue;
    leaders.add(row);
    final metadata = picks.isEmpty ? const <String, dynamic>{} : picks.first;
    current.add({
      'id_user': 0,
      'username': '現在',
      'id_league': row['id_league'],
      'id_stats': row['id_stats'],
      'id_player': row['id_player'],
      'id_team': row['id_team'],
      'league_name': row['league_name'] ?? metadata['league_name'] ?? '',
      'title': row['title'] ?? metadata['title'] ?? '',
      'player_name': _displayName(row),
      'flg_atari': false,
      'color_today': '',
      'code_color': null,
      'int_index': row['int_index'] ?? metadata['int_index'],
      'flg_pitcher': row['flg_pitcher'] ?? metadata['flg_pitcher'] ?? false,
      'color_back': row['color_back'],
      'color_font': row['color_font'],
    });
  }

  final predictions = <Map<String, dynamic>>[
    ...current,
    for (final row in predictionRows)
      {
        ...row,
        'flg_atari':
            (leadersByStat[_statKey(row)] ?? const <Map<String, dynamic>>[])
                .any((leader) => _samePlayer(leader, row)),
      },
  ];
  // 旧APIと同じ並び。同率首位など同一キー内の登録順は維持する。
  final ordered = predictions.indexed.toList()
    ..sort((a, b) {
      for (final key in ['id_user', 'id_league', 'int_index']) {
        final result = _asInt(a.$2[key]).compareTo(_asInt(b.$2[key]));
        if (result != 0) return result;
      }
      return a.$1.compareTo(b.$1);
    });
  return PlayerDisplay(
    stats: stats,
    predictions: [for (final entry in ordered) entry.$2],
  );
}

String _statKey(Map<String, dynamic> row) =>
    '${_asInt(row['id_league'])}|${_asInt(row['id_stats'])}';

bool _samePlayer(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> prediction,
) {
  final snapshotId = _asInt(snapshot['id_player']);
  final predictionId = _asInt(prediction['id_player']);
  if (snapshotId > 0) return predictionId > 0 && snapshotId == predictionId;
  // 旧スナップショットはID未登録。姓だけで一致させない。
  final name = _normalizedName(snapshot['name_player']);
  final fullName = _normalizedName(prediction['full_name']);
  return name.isNotEmpty && fullName.isNotEmpty && name == fullName;
}

bool _sameSnapshotPlayer(
  Map<String, dynamic> first,
  Map<String, dynamic> second,
) {
  final firstId = _asInt(first['id_player']);
  final secondId = _asInt(second['id_player']);
  if (firstId > 0 && secondId > 0) return firstId == secondId;
  final firstName =
      _normalizedName(first['name_player'] ?? first['player_name']);
  final secondName =
      _normalizedName(second['name_player'] ?? second['player_name']);
  return firstName.isNotEmpty && firstName == secondName;
}

String _displayName(Map<String, dynamic> row) {
  final display = '${row['prediction_name'] ?? row['player_name'] ?? ''}'.trim();
  return display.isNotEmpty ? display : _normalizedName(row['name_player']);
}

String _normalizedName(dynamic value) => '${value ?? ''}'
    .replaceAll(RegExp(r'[\s　]+'), '')
    .replaceFirst(RegExp(r'(?:\(\d+(?:\.\d+)?%\)|（\d+(?:\.\d+)?%）)$'), '');

String _slashList(Iterable<dynamic> values) {
  final unique = values
      .where((value) => value != null)
      .map((value) => '$value'.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return unique.isEmpty ? '' : '/${unique.join('/')}/';
}

int _asInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
