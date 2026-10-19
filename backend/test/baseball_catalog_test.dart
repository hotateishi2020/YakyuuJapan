import 'package:test/test.dart';
import '../app/BaseballCatalog.dart';

void main() {
  test('uniform history deduplicates seasons but keeps 0 and 00 distinct', () {
    final rows = uniformGroups([
      {
        'id_team': 1,
        'number': '0',
        'name': '山田 太郎',
        'first_year': 2020,
        'last_year': 2022
      },
      {
        'id_team': 1,
        'number': '0',
        'name': '山田太郎',
        'first_year': 2023,
        'last_year': 2024
      },
      {
        'id_team': 1,
        'number': '0',
        'name': '新選手',
        'first_year': 2025,
        'last_year': 2026
      },
      {
        'id_team': 1,
        'number': '00',
        'name': '山田太郎',
        'first_year': 2018,
        'last_year': 2019
      },
      {
        'id_team': 1,
        'number': '300',
        'name': '未来選手',
        'first_year': 2027,
        'last_year': 2027
      },
    ], year: 2026);
    expect(rows.length, 3);
    expect(rows.first['name'], '新選手');
    expect(rows[1]['period'], '2020–2024年');
    expect(rows.last['number'], '00');
  });
  test(
      'membership estimates rank by pace, exclude members, retain unknown pace last',
      () {
    final rows = membershipCandidates([
      {
        'key': 'hits',
        'label': '安打',
        'leaders': [
          {'name': 'A', 'status': 'active', 'value': 1900},
          {'name': 'B', 'status': 'active', 'value': 1800},
          {'name': 'C', 'status': 'active', 'value': 1990},
          {'name': 'D', 'status': 'active', 'value': 1999},
          {'name': 'E', 'status': 'retired', 'value': 1999},
        ]
      },
    ], [
      {'name': 'A', 'id_stats': 2, 'value': 50},
      {'name': 'B', 'id_stats': 2, 'value': 150},
      {'name': 'B', 'id_stats': 2, 'value': 100},
    ], {
      'C'
    });
    expect(rows.map((r) => r['name']), ['B', 'A', 'D']);
    expect(rows.first['estimate'], .8);
    expect(rows.last['estimate'], isNull);
  });
}
