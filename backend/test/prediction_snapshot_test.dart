import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../app/Auth.dart';
import '../app/DisplaySnapshot.dart';
import '../app/PredictGroup.dart';
import '../app/PredictionSnapshot.dart';

class _ReadConnection implements Connection {
  final List<String> queries = [];
  final List<Object?> parameters = [];
  List<List<Object?>> values = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #execute) throw StateError('Unexpected DB method');
    final sql = '${invocation.positionalArguments.first}'.trim();
    expect(sql, startsWith('SELECT'));
    expect(sql, isNot(matches(r'\b(INSERT|UPDATE|DELETE|ALTER|CREATE|BEGIN|COMMIT|RANK)\b')));
    expect(sql, isNot(contains('t_stats_')));
    expect(sql, isNot(contains('to_regclass')));
    queries.add(sql);
    parameters.add(invocation.namedArguments[#parameters]);
    final schema = ResultSchema([]);
    return Future<Result>.value(Result(
      rows: [for (final value in values) ResultRow(values: value, schema: schema)],
      affectedRows: values.length,
      schema: schema,
    ));
  }
}

void main() {
  test('未登録のグループとタイトルは1回のSELECTで空を返し、DDLや再集計をしない', () async {
    final conn = _ReadConnection();
    expect(await PredictionSnapshot.groupPayload(conn, userId: 7), {
      'groups': [], 'title_catalog': [],
    });
    expect(conn.queries, hasLength(1));
    expect(conn.parameters.single, [7]);
    expect(conn.queries.single, contains('FROM v_predict_group'));
    expect(conn.queries.single, contains('FROM v_predict_catalog'));
  });

  test('グループ読出しは現在のメンバー/グループ/年度設定の有効性を検証する', () async {
    final conn = _ReadConnection();
    await PredictGroup.list(conn, userId: 9);
    expect(conn.queries.single, contains('mem.id_user = \$1::int'));
    expect(conn.queries.single, contains('mem.id_predict_group = v.id_predict_group'));
    expect(conn.queries.single, contains('COALESCE(mem.flg_delete, FALSE) = FALSE'));
    expect(conn.queries.single, contains('COALESCE(g.flg_delete, FALSE) = FALSE'));
    expect(conn.queries.single, contains('s.id = v.id_setting'));
    expect(conn.queries.single, contains('COALESCE(s.flg_delete, FALSE) = FALSE'));
    expect(conn.parameters.single, [9]);
  });

  test('匿名要求にグループ用ユーザーIDを流用しない', () async {
    final conn = _ReadConnection();
    expect(await PredictGroup.list(conn, userId: 0), isEmpty);
    expect(conn.queries, isEmpty);
    await PredictionSnapshot.groupPayload(conn, userId: null);
    expect(conn.parameters.single, [0]);
  });

  test('保存された的中数・同率首位・年・色を集計し直さずそのまま返す', () async {
    final stored = {'id': 2, 'id_setting': 8, 'int_year': 2025, 'users': [{'id': 9, 'hits': 3}],
      'players': [{'current': 'A、B', 'color_backs': ['navy', 'red'], 'color_fonts': ['white', 'black']}]};
    final conn = _ReadConnection()..values = [
      ['group', stored],
      ['catalog', [{'id': 1, 'title': '打率', 'pitcher': false}]],
    ];
    final data = await PredictionSnapshot.groupPayload(conn, userId: 9);
    expect(data['groups'], [stored]);
    expect(data['title_catalog'], [{'id': 1, 'title': '打率', 'pitcher': false}]);
  });

  test('チーム予想のSELECTは年と団体で絞り、空でも再集計しない', () async {
    final conn = _ReadConnection();
    expect(await PredictionSnapshot.teams(conn, 1999, [4, 3, 4]), isEmpty);
    expect(conn.queries.single, contains('FROM v_predict_team'));
    expect(conn.queries.single, contains('id_league IN (3, 4)'));
    expect(conn.parameters.single, [1999]);
  });

  test('チーム成績も空年で初回再登録しない', () async {
    final conn = _ReadConnection();
    expect(await DisplaySnapshot.teams(conn, 1999), isEmpty);
    expect(conn.queries, hasLength(1));
    expect(conn.queries.single, contains('FROM v_stats_teams'));
  });

  test('予想画面の認証は有効セッションのSELECTだけでスキーマ更新しない', () async {
    final conn = _ReadConnection();
    final request = Request('GET', Uri.parse('https://example.test/predict-groups'),
      headers: {'authorization': 'Bearer invalid-test-token'});
    expect(await Auth.readOnlyUserIdOf(conn, request), isNull);
    expect(conn.queries, hasLength(1));
    expect(conn.queries.single, contains('s.expire_at > NOW()'));
    expect(conn.queries.single, contains('COALESCE(u.flg_delete, FALSE) = FALSE'));
  });
}
