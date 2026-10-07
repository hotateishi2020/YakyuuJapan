import 'tools/Postgres.dart';

/// 使い方:
///   cd backend
///   dart run tool_sql.dart
///
/// SQL を変えたいときは下の query を編集して再実行する。
Future<void> main(List<String> args) async {
  final query = args.isNotEmpty
      ? args.join(' ')
      : '''
UPDATE m_user SET flg_read_news = TRUE;
''';

  print('--- SQL ---');
  print(query.trim());
  print('-----------');

  await Postgres.withConnection((conn) async {
    final rows = await conn.execute(query).timeout(const Duration(seconds: 30));
    if (rows.isEmpty) {
      print('(0 rows)');
      return;
    }
    print('${rows.length} rows');
    for (final r in rows) {
      print(r.toColumnMap());
    }
  });
}
