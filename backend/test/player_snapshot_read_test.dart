import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../app/AppSql.dart';
import '../app/DisplaySnapshot.dart';

class _ReadOnlyConnection implements Connection {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #execute) {
      throw StateError('Unexpected DB operation');
    }
    final sql = '${invocation.positionalArguments.first}'.trim();
    if (!sql.startsWith('SELECT') ||
        RegExp(r'\b(INSERT|DELETE|UPDATE|ALTER|CREATE|RANK)\b').hasMatch(sql) ||
        sql.contains('t_stats_player')) {
      throw StateError('初回表示で成績の再集計や登録を実行してはいけない');
    }
    calls++;
    expect(invocation.namedArguments[#parameters], [1999]);
    return Future<Result>.value(Result(
      rows: [], affectedRows: 0, schema: ResultSchema([]),
    ));
  }
}

void main() {
  test('未登録年も成績のSELECT一回だけで空データを返す', () async {
    final conn = _ReadOnlyConnection();
    final rows = await DisplaySnapshot.players(conn, 1999);
    expect(rows, isEmpty);
    expect(conn.calls, 1);
  });

  test('個人成績APIは単一SQLで読み、未登録年でも再集計しない', () async {
    final conn = _ReadOnlyConnection();
    final result = await DisplaySnapshot.playerPart(conn, 1999, [1, 2]);
    expect(result.stats, isEmpty);
    expect(result.predictions, isEmpty);
    expect(conn.calls, 1);
  });

  test('成績と予想の両方をDB側で団体別に絞る', () {
    final sql = AppSql.selectPlayerDisplay([4, 3, 3]);
    expect(sql, contains('FROM v_predict_stats'));
    expect(sql, contains('id_league IN (3, 4)'));
    expect(sql, isNot(contains('t_predict_player')));
    expect(sql, contains('LEFT JOIN m_player p'));
    expect(sql, contains("jsonb_build_object('id_player', p.merged_into_player_id)"));
    expect(sql, contains('ELSE s.payload END'));
    expect(sql, contains('FROM v_stats_player actual'));
    expect(sql, contains("'flg_rookie', actual.payload->'flg_rookie'"));
    expect(sql, contains("'flg_career_this_year', actual.payload->'flg_career_this_year'"));
    expect(sql, contains("actual.payload->>'title' = s.payload->>'title'"));
    expect(sql, contains("actual.payload->>'id_league' = s.payload->>'id_league'"));
    expect(AppSql.selectPlayerDisplay([]), contains('IN (NULL)'));
  });
}
