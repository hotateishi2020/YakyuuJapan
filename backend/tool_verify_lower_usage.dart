import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/LowerLevelUsage.dart';
import 'app/StrengthUsage.dart';
import 'app/TeamStrength.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.first);
  final client = http.Client();
  final rows = await Postgres.withConnection((c) => c.execute(
      'SELECT payload FROM t_strength_lower_games WHERE int_year=\$1',
      parameters: [year]));
  final games = [
    for (final r in rows)
      usageMap(r[0] is String ? jsonDecode(r[0] as String) : r[0])
  ];
  final teamRows = await Postgres.withConnection((c) => c.execute(
      "SELECT payload FROM t_team_strength WHERE code_org='npb' AND int_year=\$1",
      parameters: [year]));
  final teams = [
    for (final r in teamRows)
      usageMap(r[0] is String ? jsonDecode(r[0] as String) : r[0])
  ];
  var checked = 0;
  var mismatch = 0;
  for (final team in teams) {
    final code = npbStrengthSources[team['name_team']]!.$2;
    final actual = aggregateLowerUsage(games, code);
    final official = parseUsageAppearances(
        await StrengthUsage.get(
            client, 'https://npb.jp/bis/$year/stats/idp2_$code.html'),
        pitcher: true);
    for (final p in usageMaps(team['roster'])
        .where((p) => p['position_group'] == '投手')) {
      final expected = official[usageName('${p['name']}')];
      if (expected == null) continue;
      final value = actual[p['player_key']];
      final count = usageInt(value?['starts']) + usageInt(value?['relief']);
      checked++;
      if (count != expected) {
        mismatch++;
        print('${team['name_team']} ${p['name']}: 集計$count / 公式$expected');
      }
    }
  }
  print('2軍投手$checked人の公式登板数と照合: 不一致$mismatch件');
  client.close();
  exit(mismatch == 0 ? 0 : 1);
}
