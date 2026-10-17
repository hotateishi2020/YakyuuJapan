import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((c) async {
    final rows = await c.execute('''SELECT code_org,count(*) players,
   count(*) FILTER(WHERE jsonb_array_length(p->'season_position_groups')>1) multi_position,
   count(*) FILTER(WHERE p->'level_usage_metrics'->'2' IS NOT NULL) farm_metrics,
   sum(jsonb_array_length(p->'achievements')) achievements
   FROM t_team_strength CROSS JOIN LATERAL jsonb_array_elements(payload->'roster') p WHERE int_year=2026 GROUP BY code_org''');
    for (final r in rows) {
      print(r.toColumnMap());
    }
    final counts = await c.execute('''SELECT a->>'kind' kind,count(*) FROM t_team_strength
   CROSS JOIN LATERAL jsonb_array_elements(payload->'roster') p
   CROSS JOIN LATERAL jsonb_array_elements(p->'achievements') a WHERE int_year=2026 GROUP BY 1''');
    for (final r in counts) {
      print(r.toColumnMap());
    }
    final flags = await c.execute("SELECT count(*) FROM v_stats_player WHERE int_year=2026 AND jsonb_array_length(payload->'season_position_groups')>1");
    print('複数ポジションの個人成績スナップショット: ${flags.first[0]}');
    final medals = await c.execute("SELECT DISTINCT p->>'name' AS name FROM t_team_strength CROSS JOIN LATERAL jsonb_array_elements(payload->'roster') p CROSS JOIN LATERAL jsonb_array_elements(p->'achievements') a WHERE int_year=2026 AND a->>'label'='WBC優勝レギュラー'");
    print('WBC主力: ${medals.map((r) => r[0]).join(', ')}');
  });
  exit(0);
}
