/// Overlay the current registered injury flags without changing roster snapshots.
List<Map<String, dynamic>> withRosterInjuries(
    List<Map<String, dynamic>> teams, List<Map<String, dynamic>> players) {
  String name(dynamic value) => '${value ?? ''}'.replaceAll(RegExp(r'[\s　]+'), '').replaceAll('髙', '高').replaceAll('﨑', '崎');
  final byId = {for (final p in players) '${p['id_player']}': p};
  final byTeamName = <String, List<Map<String, dynamic>>>{};
  for (final p in players) {
    byTeamName.putIfAbsent('${p['id_team']}:${name(p['name_player'])}', () => []).add(p);
  }
  return [for (final team in teams) {
    ...team,
    'roster': [for (final raw in team['roster'] as List? ?? []) (() {
      final player = Map<String, dynamic>.from(raw as Map);
      final id = player['id_player'];
      Map<String, dynamic>? match;
      if (id != null) {
        match = byId['$id'];
      } else {
        final candidates = byTeamName['${team['id_team']}:${name(player['name'])}'] ?? [];
        // Duplicate master rows are common; agreeing flags are unambiguous.
        if (candidates.isNotEmpty && candidates.every((p) => p['flg_injury'] == true)) {
          match = candidates.first;
        } else if (candidates.length == 1) {
          match = candidates.single;
        }
      }
      return <String, dynamic>{...player, 'flg_injury': match?['flg_injury'] == true};
    })()],
  }];
}
