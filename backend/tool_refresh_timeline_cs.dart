import 'dart:convert';
import 'dart:io';
import 'app/HistoricalBaseballImporter.dart';
import 'app/TimelineCs.dart';
import 'tools/Postgres.dart';

Future<void> main(List<String> args) async {
  if (!args.contains('--snapshots-only')) {
    final importer = HistoricalBaseballImporter();
    final selectedYears = args.where((a) => int.tryParse(a) != null).map(int.parse).toList();
    for (final year in selectedYears.isEmpty ? [for (var y = 2004; y <= DateTime.now().year; y++) y] : selectedYears) {
      final result = await importer.importNpbClimax(year);
      print('$year: ${result.status}, ${result.rowCount}試合');
      if (result.status != 'complete' && year != DateTime.now().year) {
        throw StateError('$year の公式記録が取得できませんでした');
      }
      if (result.status != 'complete') print('当年度の公式結果は未取得のため、収録済みの確定試合のみ使用します');
    }
  }
  await Postgres.withConnection((conn) async {
    final results = await conn.execute('''
      SELECT DISTINCT ON (g.datetime_start::date,g.id_team_home,g.id_team_away,g.code_game)
        EXTRACT(YEAR FROM g.datetime_start)::int AS year,
        g.id_team_home,g.id_team_away,g.score_home,g.score_away,g.state,g.code_game
      FROM t_game g JOIN m_team t ON t.id=g.id_team_home
      WHERE t.id_league IN (1,2) AND g.code_game IN ('CS1','CSF','CS2','CS','JS')
        AND g.datetime_start >= '2004-01-01' AND NOT COALESCE(g.flg_delete,false)
      ORDER BY g.datetime_start::date,g.id_team_home,g.id_team_away,g.code_game,g.updat DESC NULLS LAST,g.id DESC
    ''');
    final games = results.map((r) => r.toColumnMap()).toList();
    final pages = await conn.execute("SELECT int_year FROM t_page_snapshot WHERE kind='records' AND code_org='npb' AND int_year>=2004 ORDER BY int_year DESC");
    for (final page in pages) {
      await conn.execute('BEGIN');
      try {
        final saved = await conn.execute("SELECT payload->'standings' FROM t_page_snapshot WHERE kind='records' AND code_org='npb' AND int_year=\$1 FOR UPDATE", parameters:[page[0]]);
        final raw = saved.single[0];
        final seasons = ((raw is String ? jsonDecode(raw) : raw) as List).map((r) => Map<String,dynamic>.from(r)).toList();
        addTimelineCs(seasons,games);
        await conn.execute("UPDATE t_page_snapshot SET payload=jsonb_set(payload,'{standings}',\$1::jsonb) WHERE kind='records' AND code_org='npb' AND int_year=\$2",parameters:[jsonEncode(seasons),page[0]]);
        await conn.execute('COMMIT');
        print('${page[0]}年選択時の年表を更新');
      } catch (_) {await conn.execute('ROLLBACK');rethrow;}
    }
  });
  exit(0);
}
