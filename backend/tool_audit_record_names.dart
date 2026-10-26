import 'dart:convert';
import 'dart:io';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((c) async {
    final rows = await c.execute("""SELECT DISTINCT p.id,p.date_birth::text,p.name_full,p.name_en,p.name_ja,p.name_patterns,p.identity_sources
 FROM m_player p JOIN (SELECT id_player FROM t_stats_player WHERE id_league IN(3,4) AND int_rank=1 AND id_stats IN (1,2,3,4,5,9,10,11,19) AND NOT coalesce(flg_delete,false)
 UNION SELECT id_player FROM t_stats_player_latest WHERE id_league IN(3,4) AND int_rank=1 AND id_stats IN (1,2,3,4,5,9,10,11,19)) s ON s.id_player=p.id
 WHERE NOT coalesce(p.flg_delete,false)""");
    final data = rows.map((r) => r.toColumnMap()).toList();
    File('/tmp/mlb-title-players.json').writeAsStringSync(jsonEncode(data));
    final missing = data.where((p) => '${p['name_ja'] ?? ''}'.isEmpty && !RegExp('[ぁ-んァ-ヶ一-龯]').hasMatch('${p['name_full']}')).toList();
    print('全${data.length}人 / 日本語名未登録${missing.length}人');
    print(missing.take(25).map((p) => '${p['id']} ${p['name_full']} ${p['name_en']} ${p['identity_sources']}').join('\n'));
  });
  exit(0);
}
