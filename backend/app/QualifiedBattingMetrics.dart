/// Qualification uses season plate appearances, not at-bats with RISP.
/// Fractional required appearances are discarded (143 games -> 443 PA).
bool hasQualifiedBattingAppearances(Object? appearances, Object? games) {
  final pa = int.tryParse('$appearances');
  final played = int.tryParse('$games');
  return pa != null && played != null && played > 0 && pa >= played * 31 ~/ 10;
}

/// Keep only confirmed qualifiers and re-rank within each league after filtering.
void retainQualifiedRisp(List<Map<String, dynamic>> rows) {
  num? value(Map<String, dynamic> r) =>
      num.tryParse('${r['numeric_value'] ?? r['stats']}');
  rows.removeWhere((r) =>
      r['title'] == '得点圏打率' &&
      (!hasQualifiedBattingAppearances(r['cnt_play'], r['int_game']) ||
          value(r) == null ||
          !value(r)!.isFinite));
  final leagues = rows
      .where((r) => r['title'] == '得点圏打率')
      .map((r) => '${r['id_league']}')
      .toSet();
  for (final league in leagues) {
    final ranked = rows
        .where((r) => r['title'] == '得点圏打率' && '${r['id_league']}' == league)
        .toList()
      ..sort((a, b) => value(b)!.compareTo(value(a)!));
    num? previous;
    var rank = 0;
    for (var i = 0; i < ranked.length; i++) {
      final current = value(ranked[i])!;
      if (current != previous) rank = i + 1;
      ranked[i]['int_rank'] = rank;
      previous = current;
    }
  }
}
