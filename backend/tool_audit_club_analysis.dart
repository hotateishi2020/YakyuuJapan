import 'dart:convert';
import 'dart:io';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.isEmpty ? '2026' : args.first);
  final rows = await Postgres.withConnection((c) => c.execute(
    'SELECT code_org,payload FROM t_team_strength WHERE int_year=\$1', parameters: [year]));
  var missing = 0;
  for (final row in rows) {
    final team = usageMap(row[1] is String ? jsonDecode(row[1] as String) : row[1]);
    final batting = usageMaps(team['batting_stats']);
    final fielding = usageMaps(team['fielding_stats']);
    bool hasDefense(Set<String> positions) => fielding.where((p) => positions.contains(p['position'])).any((p) =>
      p['errors'] != null && p['putouts'] != null && p['assists'] != null && usageInt(p['putouts']) + usageInt(p['assists']) + usageInt(p['errors']) > 0);
    final running = batting.isNotEmpty && usageInt(team['game_count']) > 0 && batting.every((p) => p['stolen_bases'] != null && p['caught_stealing'] != null);
    final inner = hasDefense({'1B', '2B', '3B', 'SS'}), outer = hasDefense({'OF', 'LF', 'CF', 'RF'});
    if (!running || !inner || !outer) missing++;
    print('${row[0]} ${team['name_team']}: 走力=$running 内野=$inner 外野=$outer 守備記録=${fielding.length}');
  }
  print('球団数=${rows.length}, 評価用データ不足=$missing');
  exit(missing == 0 ? 0 : 1);
}
