Map<String, int> computeAtariCounts({
  required List<Map<String, dynamic>> npbPlayerStats,
  required List<Map<String, dynamic>> npbPlayerStatsActual,
  required List<Map<String, dynamic>> predictions,
  required List<Map<String, dynamic>> standings,
}) {
  final counts = <String, int>{'1': 0, '2': 0};

  void addFromPlayer(List<Map<String, dynamic>> src) {
    for (final r in src) {
      final id = '${r['id_user'] ?? ''}';
      if (!counts.containsKey(id)) continue;
      if (r['flg_atari'] == true) counts[id] = (counts[id] ?? 0) + 1;
    }
  }

  addFromPlayer(npbPlayerStats);
  addFromPlayer(npbPlayerStatsActual);

  bool teamHit(Map<String, dynamic>? pred, List<Map<String, dynamic>> curGroup) {
    if (pred == null || pred.isEmpty || curGroup.isEmpty) return false;
    final prdId = int.tryParse('${pred['id_team']}') ?? -1;
    final prdName = (pred['name_team_short']?.toString() ?? pred['name_team']?.toString() ?? '').trim();
    for (final cur in curGroup) {
      final curId = int.tryParse('${cur['id_team']}') ?? -1;
      final curName = (cur['name_team']?.toString() ?? '').trim();
      if ((prdId >= 0 && curId >= 0 && prdId == curId) || (prdName.isNotEmpty && curName == prdName)) {
        return true;
      }
    }
    return false;
  }

  for (final leagueId in [1, 2]) {
    final curRows = standings.where((e) => int.tryParse('${e['id_league']}') == leagueId).toList();
    final pred1 = predictions.where((e) => '${e['id_user']}' == '1' && (int.tryParse('${e['id_league']}') ?? 0) == leagueId).toList();
    final pred2 = predictions.where((e) => '${e['id_user']}' == '2' && (int.tryParse('${e['id_league']}') ?? 0) == leagueId).toList();
    for (int rk = 1; rk <= 6; rk++) {
      final curGroup = curRows.where((e) => int.tryParse('${e['int_rank']}') == rk).toList();
      final p1 = pred1.firstWhere((e) => int.tryParse('${e['int_rank']}') == rk, orElse: () => {});
      final p2 = pred2.firstWhere((e) => int.tryParse('${e['int_rank']}') == rk, orElse: () => {});
      if (teamHit(p1.isNotEmpty ? p1 : null, curGroup)) counts['1'] = (counts['1'] ?? 0) + 1;
      if (teamHit(p2.isNotEmpty ? p2 : null, curGroup)) counts['2'] = (counts['2'] ?? 0) + 1;
    }
  }

  return counts;
}
