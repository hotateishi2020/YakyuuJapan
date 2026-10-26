import 'app/RecordPlayerNames.dart';
import 'dart:convert';
import 'dart:io';
import 'app/PlayerIdentity.dart';
import 'tools/Postgres.dart';
Future<void> main() async {
 await Postgres.withConnection((c) async {
  final rows=await c.execute("SELECT int_year,payload->'titles' FROM t_page_snapshot WHERE kind='records' AND code_org='mlb'");
  final input=[for(final r in rows) {'year':r[0],'titles':r[1] is String?jsonDecode(r[1] as String):r[1]}];
  final localized=await PlayerIdentity.localize(c,input) as List;
  for(final row in localized) { row['titles']=localizeRecordTitleNames(row['titles']); }
  await c.execute(r'''WITH localized AS (SELECT value p FROM jsonb_array_elements($1::jsonb))
   UPDATE t_page_snapshot s SET payload=jsonb_set(s.payload,'{titles}',l.p->'titles'),updated_at=now()
   FROM localized l WHERE s.kind='records' AND s.code_org='mlb' AND s.int_year=(l.p->>'year')::int''',parameters:[jsonEncode(localized)]);
  final missing=<String>{};
  for(final row in localized) {for(final season in row['titles'] as List? ?? []) {for(final cat in season['categories'] as List? ?? []) {for(final p in cat['players'] as List? ?? []) {
    if(!RegExp('[ぁ-んァ-ヶ一-龯]').hasMatch('${p['name']}'))missing.add('${p['name']}');
  }}}}
  File('/tmp/mlb-title-untranslated.json').writeAsStringSync(jsonEncode(missing.toList()..sort()));
  print('個人タイトル表示更新: ${rows.length}年度、英語名残り${missing.length}種類');
 });exit(0);
}
