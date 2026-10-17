import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/ClubDefense.dart';
import 'app/ClubData.dart';
import 'app/StrengthUsage.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? DateTime.now().year : int.parse(args.first);
  final notes = readClubFile('club-defense-evidence-$year.json');
  final rows = await Postgres.withConnection((c) => c.execute(
    'SELECT code_org,id_team,payload FROM t_team_strength WHERE int_year=\$1', parameters: [year]));
  final client = http.Client();
  var count = 0;
  try {
    for (final row in rows) {
      final team = usageMap(row[2] is String ? jsonDecode(row[2] as String) : row[2]);
      final update = <String, dynamic>{};
      if (row[0] == 'mlb') update['defense_analysis'] = await fetchTeamDefense(client, year, team['source_team_id']);
      final note = notes['${row[0]}:${clubKey(team)}'];
      if (note != null) update['defense_note'] = note;
      if (update.isEmpty) continue;
      await Postgres.withConnection((c) => c.execute(
        'UPDATE t_team_strength SET payload=payload || \$1::jsonb, updated_at=NOW() WHERE code_org=\$2 AND id_team=\$3 AND int_year=\$4',
        parameters: [jsonEncode(update), row[0], row[1], year]));
      print('${team['name_team']}: ${update.keys.join(', ')}');
      count++;
    }
  } finally { client.close(); }
  print('更新 $count 球団');
  exit(0);
}
