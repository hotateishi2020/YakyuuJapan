import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/StrengthUsage.dart';
import 'app/TeamStrength.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  final org = args.length > 1 ? args[1] : 'npb';
  if (!['npb', 'mlb'].contains(org)) throw ArgumentError('npb|mlb');
  final client = http.Client();
  try {
    final games = org == 'npb'
        ? await StrengthUsage.npbGames(client, year)
        : await StrengthUsage.mlbGames(
            client,
            year,
            usageMap(jsonDecode(await StrengthUsage.get(client,
                'https://statsapi.mlb.com/api/v1/schedule?sportId=1&season=$year&gameTypes=R'))));
    await Postgres.withConnection((conn) async {
      final teams = await conn.execute(
          "SELECT id_team,payload FROM t_team_strength WHERE code_org=\$2 AND int_year=\$1",
          parameters: [year, org]);
      for (final row in teams) {
        final team =
            usageMap(row[1] is String ? jsonDecode(row[1] as String) : row[1]);
        final code = org == 'npb'
            ? npbStrengthSources['${team['name_team']}']?.$2
            : '${team['source_team_id']}';
        if (code == null) throw StateError('球団コードなし: ${row[0]}');
        final bands = substitutionBands(games, code, org: org);
        final count = games
            .where((g) =>
                usageMaps(g['players']).any((p) => p['team_code'] == code))
            .length;
        if (count != usageInt(team['pitching_game_count']))
          throw StateError('試合数不一致: ${row[0]} $count');
        await conn.execute(
            "UPDATE t_team_strength SET payload=payload || \$1::jsonb, updated_at=NOW() WHERE code_org=\$4 AND int_year=\$2 AND id_team=\$3",
            parameters: [
              jsonEncode({
                'substitutions': bands,
                'defense_substitutions': defenseSubstitutionBands(bands),
                'substitution_game_count': count
              }),
              year,
              row[0],
              org
            ]);
        print(
            '${team['name_team']} $count試合 ${bands.map((b) => "${b['label']}:${b['total']}").join(' ')}');
      }
    });
    exit(0);
  } catch (e) {
    stderr.writeln(e);
    exit(1);
  } finally {
    client.close();
  }
}
