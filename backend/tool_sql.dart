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
INSERT INTO t_nortification ( 
    title, 
    text_main, 
    id_user, 
    flg_read, 
    code_tag_main, 
    code_tag_sub, 
    url,
    crtby,
    crtpgm,
    crtenv,
    updby,
    updpgm,
    updenv
) VALUES 
('ゲーム差を視覚的に表現する図を表示するようにしました。', 'ゲーム差を視覚的に表現する図を表示するようにしました。', 1, false, 'SYS', 'UPD', '', 0, 'SQLCreator', 'SQLCreator', 0, 'SQLCreator', 'SQLCreator') 
RETURNING id;
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
