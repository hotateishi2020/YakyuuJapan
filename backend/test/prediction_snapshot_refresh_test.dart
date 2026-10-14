import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../app/PredictionSnapshot.dart';

class _RefreshConnection implements Connection {
  final calls = <({String sql, Object? params})>[];
  bool failPublish = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #execute) throw StateError('Unexpected DB method');
    final sql = '${invocation.positionalArguments.first}'.trim();
    calls.add((sql: sql, params: invocation.namedArguments[#parameters]));
    if (failPublish && sql.startsWith('INSERT INTO v_predict_group')) {
      return Future<Result>.error(StateError('publish failed'));
    }
    final schema = ResultSchema([ResultSchemaColumn(typeOid: 16, type: Type.boolean, columnName: 'ready')]);
    final List<List<Object?>> values;
    if (sql.contains('to_regclass')) {
      values = [[true]];
    } else if (sql.startsWith('SELECT int_year FROM t_predict_setting')) {
      values = [[2025]];
    } else if (sql.startsWith('SELECT unnest(ARRAY[2025]')) {
      values = [[2025]];
    } else if (sql.startsWith('SELECT EXTRACT(YEAR FROM CURRENT_DATE)::int')) {
      values = sql.contains('UNION') ? [[2025], [2026]] : [[2026]];
    } else {
      values = [];
    }
    return Future<Result>.value(Result(rows: [for (final row in values) ResultRow(values: row, schema: schema)], affectedRows: values.length, schema: schema));
  }
}

void main() {
  test('定期登録は当年度だけを置換し、グループと予想を同じコミットで公開する', () async {
    final conn = _RefreshConnection();
    await PredictionSnapshot.refresh(conn);
    final writes = conn.calls.where((call) => call.sql.startsWith('DELETE FROM v_predict_')).toList();
    expect(writes.where((call) => call.sql.contains('WHERE int_year = \$1')).map((call) => call.params), [[2026], [2026]]);
    expect(writes.singleWhere((call) => call.sql.contains('v_predict_group')).sql, contains('int_year IN (2026)'));
    expect(conn.calls.where((call) => call.sql == 'BEGIN'), hasLength(1));
    expect(conn.calls.last.sql, 'COMMIT');
    expect(conn.calls.any((call) => call.sql.contains('pg_advisory_xact_lock')), isTrue);
  });

  test('過年度の予想保存では対象設定の年だけを更新する', () async {
    final conn = _RefreshConnection();
    await PredictionSnapshot.refreshAfterSave(conn, {'id_setting': 8});
    final writes = conn.calls.where((call) => call.sql.startsWith('DELETE FROM v_predict_') && call.sql.contains('WHERE int_year = \$1'));
    expect(writes.map((call) => call.params), [[2025], [2025]]);
  });

  test('名称や招待の更新では過年度の大きい個人成績を再転送しない', () async {
    final conn = _RefreshConnection();
    await PredictionSnapshot.refreshAfterSave(conn, {'id': 1});
    expect(conn.calls.any((call) => call.sql.contains('FROM v_stats_player s')), isFalse);
    expect(conn.calls.any((call) => call.sql.startsWith('DELETE FROM v_predict_stats')), isFalse);
    expect(conn.calls.any((call) => call.sql.startsWith('DELETE FROM v_predict_team')), isFalse);
    expect(conn.calls.any((call) => call.sql.startsWith('INSERT INTO v_predict_group')), isTrue);
  });

  test('登録に失敗した場合は途中結果を公開せずrollbackする', () async {
    final conn = _RefreshConnection()..failPublish = true;
    await expectLater(PredictionSnapshot.refresh(conn), throwsStateError);
    expect(conn.calls.last.sql, 'ROLLBACK');
    expect(conn.calls.any((call) => call.sql == 'COMMIT'), isFalse);
  });
}
