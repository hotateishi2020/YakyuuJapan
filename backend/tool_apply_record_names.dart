import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';
Future<void> main() async {
 final plan=jsonDecode(File('data/mlb-title-name-localization.json').readAsStringSync()) as Map;
 await Postgres.withConnection((c) async {
 final rows=await c.execute(r'''WITH evidence AS (SELECT value p FROM jsonb_array_elements($1::jsonb))
 UPDATE m_player p SET name_ja=e.p->>'verified_name_ja',
 name_en=coalesce(nullif(p.name_en,''),p.name_full),
 name_patterns=ARRAY(SELECT DISTINCT n FROM unnest(coalesce(p.name_patterns,ARRAY[]::text[]) || ARRAY[p.name_full,p.name_en,e.p->>'verified_name_ja']) n WHERE n IS NOT NULL AND n<>''),updat=now()
 FROM evidence e WHERE p.id=(e.p->>'id')::int
 AND p.identity_sources->>'mlb'=e.p->'identity_sources'->>'mlb'
 AND coalesce(p.name_ja,'')='' AND NOT coalesce(p.flg_delete,false)
 RETURNING p.id''',parameters:[jsonEncode(plan['matches'])]);
 print('日本語名補完: ${rows.length}人（英語名・表記パターンは保持）');
 });exit(0);
}
