import 'dart:io';
import 'app/InjuryList.dart';
import 'tools/Postgres.dart';
Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await conn.execute("SET lock_timeout = '20s'");
    final count = await InjuryList.sync(conn);
    final rows = await InjuryList.read(conn, leagueIds: [1,2]);
    print('更新: $count件 / 表示対象: ${rows.length}人 / 内容あり: ${rows.where((r) => '${r['injury'] ?? ''}'.isNotEmpty).length}人');
  });
  exit(0);
}
