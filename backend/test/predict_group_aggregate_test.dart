import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../app/PredictGroup.dart';

class _AggregateConnection implements Connection {
  final Map<String, List<Map<String, dynamic>>> sources;
  String aggregateSql = '';
  _AggregateConnection(this.sources);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #execute) throw StateError('Unexpected DB operation');
    final sql = '${invocation.positionalArguments.first}';
    if (sql.contains("SELECT 'settings' AS kind")) {
      aggregateSql = sql;
      final schema = ResultSchema([]);
      return Future<Result>.value(Result(rows: [
        for (final source in sources.entries) ResultRow(values: [source.key, source.value], schema: schema),
      ], affectedRows: sources.length, schema: schema));
    }
    final schema = ResultSchema([ResultSchemaColumn(typeOid: 16, type: Type.boolean, columnName: 'ready')]);
    return Future<Result>.value(Result(rows: [if (sql.contains('to_regclass')) ResultRow(values: [true], schema: schema)], affectedRows: 0, schema: schema));
  }
}

void main() {
  test('別グループの同じユーザーの的中数を混ぜず、同率首位の文字色を名前順に保存する', () async {
    final conn = _AggregateConnection({
      'settings': [
        {'id': 10, 'id_setting': 1, 'int_year': 2026, 'txt_name': 'A'},
        {'id': 20, 'id_setting': 2, 'int_year': 2026, 'txt_name': 'B'},
        {'id': 10, 'id_setting': 3, 'int_year': 2025, 'txt_name': 'A'},
      ],
      'users': [
        {'id_predict_group': 10, 'id_user': 9, 'name_last': '予想者'},
        {'id_predict_group': 20, 'id_user': 9, 'name_last': '予想者'},
      ],
      'leaders': [
        {'int_year': 2026, 'id_league': 1, 'id_stats': 5, 'id_player': 100, 'player_name': '一位A', 'color_back': 'navy', 'color_font': 'white'},
        {'int_year': 2026, 'id_league': 1, 'id_stats': 5, 'id_player': 101, 'player_name': '一位B', 'color_back': 'yellow', 'color_font': 'black'},
      ],
      'players': [
        {'int_year': 2026, 'id_predict_setting': 1, 'id_user': 9, 'id_league': 1, 'id_stats': 5, 'id_player': 100, 'player_name': '一位A', 'title': '打率'},
        {'int_year': 2026, 'id_predict_setting': 2, 'id_user': 9, 'id_league': 1, 'id_stats': 5, 'id_player': 102, 'player_name': '別選手', 'title': '打率'},
      ],
    });
    final groups = await PredictGroup.aggregate(conn, years: {2026});
    expect(groups, hasLength(2));
    expect((groups[0]['users'] as List).single['hits'], 1);
    expect((groups[1]['users'] as List).single['hits'], 0);
    final current = (groups[0]['players'] as List).single;
    expect(current['current'], '一位A、一位B');
    expect(current['color_backs'], ['navy', 'yellow']);
    expect(current['color_fonts'], ['white', 'black']);
    expect(conn.aggregateSql, contains('p.year IN (2025, 2026)'));
    expect(conn.aggregateSql, contains('p.int_year IN (2025, 2026)'));
    expect(conn.aggregateSql, contains('st.year IN (2025, 2026)'));
  });

  test('MVPなど未予想タイトルの同率首位にも背景・文字色を揃えて保存する', () async {
    final conn = _AggregateConnection({
      'settings': [{'id': 10, 'id_setting': 1, 'int_year': 2026}],
      'titles': [{'id_predict_setting': 1, 'id_stats': 6, 'txt_title': 'MVP'}],
      'leaders': [
        {'int_year': 2026, 'id_league': 1, 'id_stats': 6, 'player_name': '選手A', 'color_back': 'navy', 'color_font': 'white'},
        {'int_year': 2026, 'id_league': 1, 'id_stats': 6, 'player_name': '選手B', 'color_back': 'gold', 'color_font': 'black'},
      ],
    });
    final groups = await PredictGroup.aggregate(conn, years: {2026});
    final current = (groups.single['players'] as List).first;
    expect(current['current'], '選手A、選手B');
    expect(current['color_fonts'], ['white', 'black']);
  });
}
