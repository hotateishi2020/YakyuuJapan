import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app/SeasonUsageEvidence.dart';
import 'app/StrengthUsage.dart';
import 'app/TeamStrength.dart';
import 'app/DisplaySnapshot.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  final year = int.parse(args.first), client = http.Client();
  try {
    if (!args.contains('--apply-only'))
      for (final org in ['npb', 'mlb']) {
        final rows = await Postgres.withConnection((c) => c.execute(
            'SELECT payload FROM t_team_strength WHERE int_year=\$1 AND code_org=\$2',
            parameters: [year, org]));
        final teams = [
          for (final r in rows)
            usageMap(r[0] is String ? jsonDecode(r[0] as String) : r[0])
        ];
        await enrichSeasonEvidence(client, year, org, teams,
            {for (final e in npbStrengthSources.entries) e.key: e.value.$2});
      }
    await Postgres.withConnection((c) async {
      await c.execute(
          '''UPDATE t_team_strength t SET payload=jsonb_set(payload,'{roster}',
    (SELECT jsonb_agg(p || COALESCE((SELECT s.payload FROM t_strength_player_status s WHERE s.int_year=t.int_year AND s.code_org=t.code_org AND s.id_team=t.id_team AND s.player_key=p->>'player_key'),'{}'::jsonb)) FROM jsonb_array_elements(t.payload->'roster') p)) WHERE int_year=\$1''',
          parameters: [year]);
      await c.execute(
          '''CREATE TABLE IF NOT EXISTS t_player_season_usage(int_year integer,id_player integer,groups jsonb NOT NULL,PRIMARY KEY(int_year,id_player))''');
      final teams = await c.execute(
          'SELECT id_team,code_org,payload FROM t_team_strength WHERE int_year=\$1',
          parameters: [year]);
      final players = await c.execute(
          "SELECT id,id_team,name_full,date_birth::date::text FROM m_player WHERE COALESCE(flg_delete,FALSE)=FALSE");
      final mappings = <Map<String, dynamic>>[];
      for (final t in teams) {
        final roster = usageMaps(usageMap(
            t[2] is String ? jsonDecode(t[2] as String) : t[2])['roster']);
        final local = players.where((p) => p[1] == t[0]).toList();
        for (final p in roster) {
          if (p['season_position_groups'] is! List) continue;
          final matches = local
              .where((m) => t[1] == 'npb'
                  ? usageName('${m[2]}') == usageName('${p['name']}')
                  : p['date_birth'] != null &&
                      '${m[3]}' == '${p['date_birth']}')
              .toList();
          if (matches.length != 1) continue;
          if (t[1] == 'mlb' &&
              roster.where((r) => r['date_birth'] == p['date_birth']).length !=
                  1) continue;
          mappings.add(
              {'id': matches.single[0], 'groups': p['season_position_groups']});
        }
      }
      await c.execute(
          '''INSERT INTO t_player_season_usage(int_year,id_player,groups)
    SELECT \$1,(p->>'id')::integer,p->'groups' FROM jsonb_array_elements(\$2::jsonb) p
    ON CONFLICT(int_year,id_player) DO UPDATE SET groups=EXCLUDED.groups''',
          parameters: [year, jsonEncode(mappings)]);
      print('個人成績のポジション対応: ${mappings.length}人');
      await DisplaySnapshot.refreshPlayers(c, year);
    });
    print('出場位置と起用順データを反映しました');
    exit(0);
  } catch (e) {
    stderr.writeln(e);
    exit(1);
  } finally {
    client.close();
  }
}
