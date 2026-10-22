import 'dart:io';
import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await conn.runTx((tx) async {
      final identity = await tx.execute("UPDATE m_team_season_identity SET name_short='近畿日本',updated_at=now() WHERE int_year=1944 AND name_full='近畿日本' RETURNING id_franchise");
      if (identity.length != 1) throw StateError('Expected exactly one 1944 identity');
      final pages = await tx.execute(r'''WITH targets AS (
        SELECT p.int_year, ARRAY['standings',(s.i-1)::text,'leagues',(l.i-1)::text,'teams',(t.i-1)::text,'short_name'] AS path
        FROM t_page_snapshot p
        CROSS JOIN LATERAL jsonb_array_elements(p.payload->'standings') WITH ORDINALITY s(v,i)
        CROSS JOIN LATERAL jsonb_array_elements(s.v->'leagues') WITH ORDINALITY l(v,i)
        CROSS JOIN LATERAL jsonb_array_elements(l.v->'teams') WITH ORDINALITY t(v,i)
        WHERE p.kind='records' AND p.code_org='npb'
          AND s.v->>'year'='1944' AND t.v->>'name'='近畿日本'
          AND t.v->>'short_name' IS DISTINCT FROM '近畿日本'
      ) UPDATE t_page_snapshot p
        SET payload=jsonb_set(p.payload,t.path,to_jsonb('近畿日本'::text))
        FROM targets t WHERE p.kind='records' AND p.code_org='npb' AND p.int_year=t.int_year
        RETURNING p.int_year''');
      print('1944年の名称を修正：球団設定 ${identity.length}件、年表 ${pages.length}件');
    });
    final check=await conn.execute("SELECT name_full,name_short FROM m_team_season_identity WHERE int_year=1944 AND name_full='近畿日本'");
    print(check.map((r)=>r.toColumnMap()).toList());
  });
  exit(0);
}
