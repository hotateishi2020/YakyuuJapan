import '../tools/json_utils.dart';

/// Only verified game-day bench entries, excluding everyone who has appeared.
List<Map<String,dynamic>> unusedGameBench(Map<String,dynamic> game, int team) {
  String key(dynamic name) => '${name ?? ''}'.replaceAll(RegExp(r'[\s　・･]'), '');
  final appeared = <String>{};
  for (final row in listMapFromJson(game['lineup'])) {
    if ('${row['id_team']}' != '$team') continue;
    for (final p in listMapFromJson(row['players'])) { appeared.add(key(p['name'])); }
  }
  for (final row in listMapFromJson(game['summaries'])) {
    if ('${row['id_team_summary'] ?? row['id_team']}' == '$team') appeared.add(key(row['name_full_summary']));
  }
  for (final side in ['home','away']) {
    if ('${game['id_team_$side']}' == '$team') appeared.add(key(game['name_pitcher_$side']));
  }
  final result = <String,Map<String,dynamic>>{};
  for (final player in listMapFromJson(game['bench_players'])) {
    final name = key(player['name']);
    if ('${player['id_team']}' != '$team' || name.isEmpty || appeared.contains(name)) continue;
    result[name] = player;
  }
  return result.values.toList();
}
