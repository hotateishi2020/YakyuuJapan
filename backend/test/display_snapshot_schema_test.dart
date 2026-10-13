import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../app/DisplaySnapshot.dart';

class _ExistingSchemaConnection implements Connection {
  int reads = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #execute) {
      final sql = '${invocation.positionalArguments.first}'.trim();
      if (!sql.startsWith('SELECT')) {
        throw StateError('既存DBへのDDLは試合テーブルのロック待ちを起こす: $sql');
      }
      reads++;
      final schema = ResultSchema([]);
      return Future<Result>.value(Result(
        rows: [
          ResultRow(values: [true], schema: schema)
        ],
        affectedRows: 1,
        schema: schema,
      ));
    }
    throw StateError('Unexpected DB operation: ${invocation.memberName}');
  }
}

class _GamesConnection implements Connection {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #execute) {
      throw StateError('Unexpected operation');
    }
    final sql = '${invocation.positionalArguments.first}';
    final schema = ResultSchema([]);
    List<List<Object?>> values;
    if (sql.contains('to_regclass')) {
      values = [[true]];
    } else if (sql.contains("code = 'span'")) {
      values = [[{'from': '2026-10-01', 'to': '2026-10-31'}]];
    } else if (sql.contains('SELECT code, payload')) {
      expect(invocation.namedArguments[#parameters],
          [2026, '2026-10-10', '2026-10-23']);
      values = [
        ['batting', {'id_game': 1, 'hits': 2}],
        ['board', {'show': true}],
        ['game', {'id_game': 1}],
        ['game', {'id_game': 2}],
        ['play', '{"id_game":1,"inning":1}'],
        ['play', {'id_game': 1, 'inning': 2}],
        ['postseason', {'id_game': 3}],
      ];
    } else {
      throw StateError('Unexpected SQL: $sql');
    }
    return Future<Result>.value(Result(
      rows: [for (final row in values) ResultRow(values: row, schema: schema)],
      affectedRows: values.length,
      schema: schema,
    ));
  }
}

void main() {
  test('作成済みスナップショットの初期化ではDDLも排他ロックも不要', () async {
    final conn = _ExistingSchemaConnection();
    await DisplaySnapshot.ensure(conn);
    await DisplaySnapshot.ensure(conn);
    expect(conn.reads, 1);
  });
  test('まとめて読み出しても各データ種別と行順序を維持する', () async {
    final result = await DisplaySnapshot.games(_GamesConnection(), 2026,
        from: '2026-10-10', to: '2026-10-23');
    expect(result.games.map((row) => row['id_game']), [1, 2]);
    expect(result.plays.map((row) => row['inning']), [1, 2]);
    expect(result.batting.single['hits'], 2);
    expect(result.postseason.single['id_game'], 3);
    expect(result.board.single['show'], true);
    expect(result.from, '2026-10-10');
    expect(result.to, '2026-10-23');
  });


}
