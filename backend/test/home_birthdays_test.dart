import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import '../app/HomeBirthdays.dart';

class BirthdayConnection implements Connection {
  List<List<Object?>> values = [];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #execute) throw StateError('Unexpected DB access');
    final sql = invocation.positionalArguments.first.toString();
    expect(sql, contains('EXTRACT(MONTH FROM p.date_birth)'));
    expect(sql, contains('EXTRACT(DAY FROM p.date_birth)'));
    expect(sql, contains('p.merged_into_player_id IS NULL'));
    expect(sql, contains('NOT COALESCE(p.flg_delete, false)'));
    expect(sql, contains('p.year_retire'));
    expect(invocation.namedArguments[#parameters], ['2026-10-27']);
    final schema = ResultSchema([]);
    return Future.value(Result(rows: [for (final row in values) ResultRow(values: row, schema: schema)], affectedRows: values.length, schema: schema));
  }
}

void main() {
  test('birthday response preserves player identity and NPB/MLB detail scope', () async {
    final conn = BirthdayConnection()..values = [
      [10, '対象選手', '阪神', 1, 1, 25],
      [20, 'MLB選手', 'LAD', 2, 3, 30],
    ];
    final result = await homeBirthdays(conn, '2026-10-27');
    expect(result.map((r) => r['org']), ['npb', 'mlb']);
    expect(result.map((r) => r['age']), [25, 30]);
    expect(result.map((r) => r['id_player']), [10, 20]);
    expect(result.first['name_team'], '阪神');
  });
  test('no matching birthday returns an empty list', () async {
    expect(await homeBirthdays(BirthdayConnection(), '2026-10-27'), isEmpty);
  });
}
