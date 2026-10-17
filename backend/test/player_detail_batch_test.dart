import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import '../app/PlayerDetail.dart';

class _GroupConnection implements Connection {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #execute) throw StateError('Unexpected operation');
    calls++;
    final params = invocation.namedArguments[#parameters] as List;
    final ids = params[0] as List<int>;
    final sql = '${invocation.positionalArguments.first}';
    final schema = ResultSchema([]);
    return Future.value(Result(rows: [
      if (sql.contains('FROM m_player_career'))
        for (final id in ids)
          ResultRow(values: [{'id_player':id,'int_year':2025}],schema:schema),
    ],affectedRows:0,schema:schema));
  }
}

void main() {
  test('次の選手群へ進むと前の経歴・試合を保持しない', () async {
    final batch = PlayerDetailBatch([], [], [], [], []);
    final conn = _GroupConnection();
    await batch.loadPlayerGroup(conn, 2026, [1,2]);
    expect(batch.careers.map((r)=>r['id_player']), [1,2]);
    batch.games![1] = [{'id':99}];
    await batch.loadPlayerGroup(conn, 2026, [3]);
    expect(batch.careers.map((r)=>r['id_player']), [3]);
    expect(batch.games, isEmpty);
    final before = conn.calls;
    await batch.loadPlayerGroup(conn, 2026, []);
    expect(batch.careers,isEmpty);
    expect(batch.games,isEmpty);
    expect(conn.calls,before);
  });
}
