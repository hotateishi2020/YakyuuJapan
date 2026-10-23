import 'dart:io';
import 'app/FetchURL.dart';
import 'app/AppSql.dart';
import 'app/GameStatsLoad.dart';
import 'tools/Postgres.dart';

Future<void> main() async {
  await Postgres.withConnection((conn) async {
    await FetchURL.ensureAppColumns(conn);
    // 新しい速報列を含む実際の表示クエリが実行できることを確認する。
    final today = DateTime.now();
    final from = today.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    final to = today.toIso8601String().substring(0, 10);
    final result = await conn.execute(AppSql.selectGames(ranged: true), parameters: [today.year, from, to]);
    await conn.execute('BEGIN');
    try {
      await GameStatsLoad.markIfComplete(conn, 2147483647, finished: true);
    } finally {
      await conn.execute('ROLLBACK');
    }
    print('速報列の準備完了、表示クエリ確認: ${result.length}行');
  });
  exit(0);
}
