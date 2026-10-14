/// 投手・交代済み選手も含め、試合の個人守備成績から失策を取り出す。
/// 打席数や現在の守備位置では絞らず、同じ成績の重複は加算しない。
Map<int, List<Map<String, dynamic>>> fieldingErrorsByGame(
    List<Map<String, dynamic>> rows) {
  final byGame = <int, Map<String, Map<String, dynamic>>>{};
  for (final row in rows) {
    final game = _int(row['id_game']);
    final team = _int(row['id_team']);
    final name = '${row['name_full'] ?? ''}'.trim();
    final count = _int(row['int_error']);
    if (game <= 0 || team <= 0 || name.isEmpty || count <= 0) continue;
    final players = byGame.putIfAbsent(game, () => {});
    final key = '$team|${name.replaceAll(RegExp(r'[\s　]+'), '')}';
    final existing = players[key];
    if (existing == null || count > _int(existing['count'])) {
      players[key] = {'id_team': team, 'name': name, 'count': count};
    }
  }
  return {
    for (final game in byGame.entries) game.key: game.value.values.toList()
  };
}

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
