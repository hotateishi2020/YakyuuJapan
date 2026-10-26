import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import '../app/PageSnapshot.dart';
import '../app/OrgLeague.dart';

class FakeConnection implements Connection {
  final queries = <String>[];
  final params = <Object?>[];
  List<List<Object?>> saved = [];
  bool locked = true;
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName != #execute) throw StateError('Unexpected call');
    final sql = '${call.positionalArguments.first}';
    queries.add(sql);
    params.add(call.namedArguments[#parameters]);
    final values = sql.contains('pg_try_advisory_lock') ? [[locked]] :
      sql.contains('SELECT payload') ? saved : <List<Object?>>[];
    final schema = ResultSchema([]);
    return Future.value(Result(rows: [for (final v in values) ResultRow(values: v, schema: schema)],
      affectedRows: values.length, schema: schema));
  }
}
void main() {
  test('歴代タイトルは全年度を保ち無関係な大型データを転送しない', () async {
    final conn = FakeConnection();
    await PageSnapshot.read(conn, kind: 'records', org: OrgKind.mlb,
        year: 2026, section: 'record_titles');
    expect(conn.queries, hasLength(1));
    expect(conn.queries.single, contains("payload->'titles'"));
    expect(conn.queries.single, isNot(contains("payload->'standings'")));
    expect(conn.queries.single, isNot(contains("payload->'career'")));
    expect(conn.queries.single, isNot(contains('jsonb_path_query_array')));
  });
  test('古いMLB日程にもワールドシリーズ期間帯を補完し既存の変更は優先する', () async {
    final conn=FakeConnection()..saved=[[{'games':[{'id':7}],'events':[]},'2026-10-21']];
    final data=await PageSnapshot.read(conn,kind:'schedule',org:OrgKind.mlb,year:2026);
    final events=data['events'] as List;
    expect(events.single['title_event'],'ワールドシリーズ');
    expect(events.single['date_from_temp'],'2026-10-24');
    expect(events.single['date_to'],'2026-11-01');
    expect(data['games'],[{'id':7}]);
    expect(conn.queries,hasLength(1));
    conn.saved=[[{'events':[{...events.single as Map,'date_to':'2026-11-02'}]},'2026-10-22']];
    final updated=await PageSnapshot.read(conn,kind:'schedule',org:OrgKind.mlb,year:2026);
    expect(updated['events'],hasLength(1));
    expect((updated['events'] as List).single['date_to'],'2026-11-02');
  });

  test('日程と記録は保存JSONを1回のSELECTだけで返す', () async {
    for (final kind in ['schedule','records']) {
      final conn = FakeConnection()..saved = [[{'games': [{'id': 7}], 'titles': []}, '2026-10-21']];
      final data = await PageSnapshot.read(conn, kind: kind, org: OrgKind.npb, year: 2026);
      expect(data['games'], [{'id': 7}]);
      expect(data['updated_at'], '2026-10-21');
      expect(conn.queries, hasLength(1));
      expect(conn.queries.single.trim(), startsWith('SELECT payload'));
      expect(conn.params.single, [kind,'npb',2026]);
    }
  });
  test('タイトルは選択年度、年表は履歴を保存JSONから取得する', () async {
    final conn = FakeConnection();
    await PageSnapshot.read(conn, kind: 'records', org: OrgKind.npb, year: 2026, section: 'titles');
    expect(conn.queries.single, contains('jsonb_path_query_array'));
    expect(conn.queries.single, contains('int_year'));
    expect(conn.queries.single, isNot(contains('t_game')));
    conn.queries.clear();
    await PageSnapshot.read(conn, kind: 'records', org: OrgKind.npb, year: 2026, section: 'timeline');
    expect(conn.queries.single, contains("payload->'timeline'"));
    expect(conn.queries.single, isNot(contains('jsonb_path_query_array')));
  });
  test('初回未登録でも要求内で集計や書き込みをしない', () async {
    final conn = FakeConnection();
    final data = await PageSnapshot.read(conn, kind: 'records', org: OrgKind.mlb, year: 2000);
    expect(data['pending'], true);
    expect(conn.queries, hasLength(1));
  });
  test('集計失敗時は既存JSONを変更せずロックを解放する', () async {
    final conn = FakeConnection();
    await expectLater(PageSnapshot.refresh(conn, kind: 'records', org: OrgKind.npb, year: 2026,
      build: () async => throw StateError('source failed')), throwsStateError);
    expect(conn.queries.any((sql) => sql.contains('INSERT') || sql.contains('DELETE')), false);
    expect(conn.queries.last, contains('pg_advisory_unlock'));
  });
  test('集計成功後に1回のupsertで公開し重複実行を防ぐ', () async {
    final conn = FakeConnection();
    var builds = 0;
    Future<Map<String,dynamic>> build() async { builds++; return {'titles': [1]}; }
    await PageSnapshot.refresh(conn, kind: 'records', org: OrgKind.npb, year: 2026, build: build);
    expect(conn.queries.where((s) => s.contains('INSERT')), hasLength(1));
    expect(conn.queries[1], contains('ON CONFLICT'));
    conn.locked = false;
    await PageSnapshot.refresh(conn, kind: 'records', org: OrgKind.npb, year: 2026, build: build);
    expect(builds, 1);
  });
}
