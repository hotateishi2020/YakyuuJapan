String interleagueClubKey(Object? value) {
  final name = '$value'.replaceAll(r'\u3000', '').replaceAll(RegExp(r'[\s　・]'), '');
  const aliases = {
    'g': ['巨人', '読売'],
    't': ['阪神'],
    'db': ['横浜', 'DeNA'],
    'c': ['広島'],
    'd': ['中日'],
    's': ['ヤクルト'],
    'h': ['ソフトバンク'],
    'f': ['日本ハム'],
    'm': ['ロッテ'],
    'l': ['西武'],
    'e': ['楽天'],
    'b': ['オリックス'],
  };
  for (final entry in aliases.entries) {
    if (entry.value.any(name.contains)) return entry.key;
  }
  return name;
}

/// Official table order includes the season's tie-breaking rules.
void attachInterleagueRanks(Map<String, dynamic> season, Map<String, dynamic> result) {
  final year = int.tryParse('${season['year']}') ?? 0;
  if (year < 2005 || year == 2020) return;
  final ranks = <String, int>{};
  for (final row in result['standings'] as List? ?? const []) {
    final rank = int.tryParse('${row['rank']}');
    if (rank != null && rank >= 1 && rank <= 12) {
      ranks[interleagueClubKey(row['name'])] = rank;
    }
  }
  for (final league in season['leagues'] as List? ?? const []) {
    for (final team in league['teams'] as List? ?? const []) {
      final rank = ranks[interleagueClubKey(team['name'])];
      if (rank != null) {
        team['interleague_rank'] = rank;
        team['interleague_source'] = result['source'];
      }
    }
  }
}
