import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  final catalog = jsonDecode(File('data/timeline-managers-npb.json').readAsStringSync());
  final years = catalog['clubs']['bu']['years'] as Map;
  if (years.length != 55) throw StateError('Expected 1950–2004 managers');
  await Postgres.withConnection((conn) async {
    await conn.runTx((tx) async {
      final pages = await tx.execute(r'''
        WITH revised AS (
          SELECT p.int_year, (
            SELECT jsonb_agg(jsonb_set(s.v, '{leagues}', (
              SELECT jsonb_agg(jsonb_set(l.v, '{teams}', (
                SELECT jsonb_agg(CASE
                  WHEN t.v->>'name' LIKE '%近鉄%'
                    AND $1::jsonb ? (s.v->>'year')
                  THEN jsonb_set(t.v, '{manager}', $1::jsonb -> (s.v->>'year'))
                  ELSE t.v END ORDER BY t.i)
                FROM jsonb_array_elements(l.v->'teams') WITH ORDINALITY t(v,i)
              )) ORDER BY l.i)
              FROM jsonb_array_elements(s.v->'leagues') WITH ORDINALITY l(v,i)
            )) ORDER BY s.i)
            FROM jsonb_array_elements(p.payload->'standings') WITH ORDINALITY s(v,i)
          ) AS standings
          FROM t_page_snapshot p WHERE p.kind='records' AND p.code_org='npb'
        ) UPDATE t_page_snapshot p
          SET payload=jsonb_set(p.payload,'{standings}',r.standings)
          FROM revised r WHERE p.kind='records' AND p.code_org='npb'
            AND p.int_year=r.int_year AND r.standings IS NOT NULL
            AND p.payload->'standings' IS DISTINCT FROM r.standings
          RETURNING p.int_year
      ''', parameters: [jsonEncode(years)]);
      print('近鉄の監督名を更新：年表 ${pages.length}件');
      final missing = await tx.execute(r'''
        SELECT count(*) FROM t_page_snapshot p
        CROSS JOIN LATERAL jsonb_array_elements(p.payload->'standings') s(v)
        CROSS JOIN LATERAL jsonb_array_elements(s.v->'leagues') l(v)
        CROSS JOIN LATERAL jsonb_array_elements(l.v->'teams') t(v)
        WHERE p.kind='records' AND p.code_org='npb'
          AND t.v->>'name' LIKE '%近鉄%' AND $1::jsonb ? (s.v->>'year')
          AND t.v->'manager' IS DISTINCT FROM ($1::jsonb -> (s.v->>'year'))
      ''', parameters: [jsonEncode(years)]);
      if (missing.single[0] != 0) throw StateError('Manager verification failed');
      print('保存済み年表の近鉄監督名：全件一致');
    });
  });
  exit(0);
}
