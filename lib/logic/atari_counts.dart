bool _isAtariFlag(dynamic value) {
  if (value == true) return true;
  if (value is num) return value != 0;
  final text = '$value'.trim().toLowerCase();
  return text == 'true' || text == 't' || text == '1';
}

/// 画面上の「当」と同じ数え方でスコアを出す。
/// - チーム順位: flg_atari_tateishi / flg_atari_ejima
/// - 個人成績: predict_player の flg_atari（現在1位と同じ選手を予想）
Map<String, int> computeAtariCounts({
  required List<Map<String, dynamic>> npbPlayerStats,
  required List<Map<String, dynamic>> standings,
  List<Map<String, dynamic>> npbPlayerStatsActual = const [],
  List<Map<String, dynamic>> predictions = const [],
}) {
  final counts = <String, int>{'1': 0, '2': 0};

  // チーム順位: 表示の黄ハイライトと同じフラグ
  for (final row in standings) {
    if (_isAtariFlag(row['flg_atari_tateishi'])) {
      counts['1'] = (counts['1'] ?? 0) + 1;
    }
    if (_isAtariFlag(row['flg_atari_ejima'])) {
      counts['2'] = (counts['2'] ?? 0) + 1;
    }
  }

  // 個人成績: Grid と同じ flg_atari（予想者行のみ）
  // 同一 league+stats で複数行あってもタイトル当は1回だけ数える
  final seen = <String>{};
  for (final row in npbPlayerStats) {
    final id = '${row['id_user'] ?? ''}';
    if (id != '1' && id != '2') continue;
    if (!_isAtariFlag(row['flg_atari'])) continue;
    final league = '${row['id_league'] ?? row['league_name'] ?? ''}';
    final stats = '${row['id_stats'] ?? row['title'] ?? ''}';
    final key = '$id|$league|$stats';
    if (!seen.add(key)) continue;
    counts[id] = (counts[id] ?? 0) + 1;
  }

  return counts;
}
