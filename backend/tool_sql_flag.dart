import 'app/AppSql.dart';
import 'tools/DateTimeTool.dart';
import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    final rows = await conn.execute(AppSql.selectStatsPlayer(), parameters: [DateTimeTool.getThisYear()])
        .timeout(const Duration(seconds: 60));
    final maps = Postgres.toMap(rows);
    final jp = maps.where((r) => r['flg_japan'] == true || '${r['flg_japan']}' == 'true').toList();
    print('total=${maps.length} japan=${jp.length}');
    for (final r in jp.take(10)) {
      print('${r['name_player']} | ${r['emoji_country']} | league=${r['id_league']} | ${r['title']}');
    }
  });
}
