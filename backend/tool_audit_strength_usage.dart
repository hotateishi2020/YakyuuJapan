import 'dart:convert';
import 'dart:io';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  var failures = 0;
  await Postgres.withConnection((conn) async {
    final records = await conn.execute(
        'SELECT code_org,id_team,payload FROM t_team_strength WHERE int_year=\$1 ORDER BY code_org,id_team',
        parameters: [year]);
    final summary = <String, Map<String, int>>{};
    for (final row in records) {
      final team =
          usageMap(row[2] is String ? jsonDecode(row[2] as String) : row[2]);
      final players = usageMaps(team['pitching_workload']);
      final roster = usageMaps(team['roster']);
      final org = '${row[0]}';
      final counts = summary.putIfAbsent(
          org,
          () => {
                'teams': 0,
                'team_games': 0,
                'pitchers': 0,
                'outs': 0,
                'roster': 0,
                'development': 0,
                'departure_marks': 0,
                'unresolved_positions': 0
              });
      counts['teams'] = counts['teams']! + 1;
      counts['team_games'] =
          counts['team_games']! + usageInt(team['pitching_game_count']);
      counts['pitchers'] = counts['pitchers']! + players.length;
      counts['roster'] = counts['roster']! + roster.length;
      counts['development'] = counts['development']! +
          roster.where((p) => p['registration'] == '育成').length;
      counts['departure_marks'] = counts['departure_marks']! +
          roster.where((p) => p['departure_confirmed'] == true).length;
      counts['unresolved_positions'] = counts['unresolved_positions']! +
          usageMaps(team['positions'])
              .expand((g) => usageMaps(g['players']))
              .where((p) => '${p['player_key']}'.contains(':name:'))
              .length;
      final outs =
          players.fold<int>(0, (n, p) => n + usageInt(p['total_outs']));
      counts['outs'] = counts['outs']! + outs;
      final stored = await conn.execute(
          'SELECT count(*),COALESCE(sum(total_outs),0) FROM t_strength_pitching WHERE code_org=\$1 AND int_year=\$2 AND id_team=\$3',
          parameters: [org, year, row[1]]);
      final error = players.isEmpty ||
          roster.isEmpty ||
          players.any((p) =>
              usageInt(p['total_outs']) !=
              usageInt(p['starter_outs']) + usageInt(p['relief_outs'])) ||
          stored.first[0] != players.length ||
          usageInt(stored.first[1]) != outs;
      if (error) {
        failures++;
        print(
            'FAIL ${team['name_team']} pitchers=${players.length} roster=${roster.length}');
      }
    }
    print(jsonEncode(summary));
  });
  print('検証エラー: $failures');
  exit(failures == 0 ? 0 : 1);
}
