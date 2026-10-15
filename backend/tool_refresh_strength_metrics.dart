import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/StrengthUsage.dart';
import 'app/StrengthMetrics.dart';
import 'app/TeamStrength.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  final client = http.Client();
  var errors = 0;
  final teams = await Postgres.withConnection((c) async => c.execute(
      'SELECT code_org,id_team,payload FROM t_team_strength WHERE int_year=\$1',
      parameters: [year]));
  for (final row in teams) {
    try {
      final team =
          usageMap(row[2] is String ? jsonDecode(row[2] as String) : row[2]);
      final metrics = await fetchStrengthMetrics(
          client, team, year, '${row[0]}',
          npbCode: npbStrengthSources['${team['name_team']}']?.$2);
      await Postgres.withConnection((c) => c.execute(
          'UPDATE t_team_strength SET payload=payload || \$1::jsonb,updated_at=NOW() WHERE code_org=\$2 AND int_year=\$3 AND id_team=\$4',
          parameters: [jsonEncode(metrics), row[0], year, row[1]]));
      print(
          '${team['name_team']}: 打者${usageMaps(metrics['batting_stats']).length} 投手${usageMaps(metrics['pitching_stats']).length}');
    } catch (e) {
      errors++;
      stderr.writeln('${row[1]}: $e');
    }
  }
  client.close();
  exit(errors == 0 ? 0 : 1);
}
