import 'dart:io';
import 'tools/Postgres.dart';
Future<void> main(List<String> args) async {
  final year=args.isEmpty ? DateTime.now().year : int.parse(args.first);
  await Postgres.withConnection((conn) async {
    final detail=await conn.execute('SELECT id_league,count(*) AS players,max(updated_at)::text AS latest FROM t_player_detail_snapshot WHERE int_year=\$1 GROUP BY id_league ORDER BY id_league',parameters:[year]);
    print({'detail_snapshots':detail.map((r)=>r.toColumnMap()).toList()});
    final birthplace=await conn.execute("SELECT code_org,count(*) AS roster_entries,count(*) FILTER(WHERE NULLIF(p->>'birth_country','') IS NOT NULL) AS with_country,count(*) FILTER(WHERE NULLIF(p->>'birth_place','') IS NOT NULL) AS with_place FROM t_team_strength CROSS JOIN LATERAL jsonb_array_elements(payload->'roster') p WHERE int_year=\$1 GROUP BY code_org",parameters:[year]);
    print({'birthplaces':birthplace.map((r)=>r.toColumnMap()).toList()});
  });
  exit(0);
}
