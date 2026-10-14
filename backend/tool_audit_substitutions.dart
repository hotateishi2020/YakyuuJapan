import 'dart:convert';
import 'dart:io';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  final counts = <String, Map<String, int>>{};
  var failures = 0;
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute(
        'SELECT code_org,payload FROM t_team_strength WHERE int_year=\$1',
        parameters: [year]);
    for (final row in rows) {
      final team =
          usageMap(row[1] is String ? jsonDecode(row[1] as String) : row[1]);
      final bands = usageMaps(team['substitutions']);
      final summary = counts.putIfAbsent('${row[0]}',
          () => {'teams': 0, 'team_games': 0, 'PH': 0, 'PR': 0, 'DEF': 0});
      summary['teams'] = summary['teams']! + 1;
      summary['team_games'] =
          summary['team_games']! + usageInt(team['substitution_game_count']);
      if (bands.length != 3 ||
          usageInt(team['substitution_game_count']) !=
              usageInt(team['pitching_game_count'])) failures++;
      for (final band in bands) {
        final players = usageMaps(band['players']);
        final total = players.fold<int>(0, (n, p) => n + usageInt(p['count']));
        if (total != usageInt(band['total']) ||
            players.map((p) => p['player_key']).toSet().length !=
                players.length) failures++;
        final role = '${band['slot']}';
        summary[role] = (summary[role] ?? 0) + total;
      }
    }
  });
  print(jsonEncode({'year': year, 'summary': counts, 'failures': failures}));
  exit(failures == 0 ? 0 : 1);
}
