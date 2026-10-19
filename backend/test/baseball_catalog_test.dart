import 'package:test/test.dart';
import '../app/BaseballCatalog.dart';

void main() {
  test('新背番号は前年の別選手から引き継いだ当年着用者のみ', () {
    final rows = uniformGroups([
      {
        'id_team': 1,
        'number': '12',
        'name': '以前の選手',
        'first_year': 2020,
        'last_year': 2025
      },
      {
        'id_team': 1,
        'number': '12',
        'name': '新選手',
        'first_year': 2026,
        'last_year': 2026
      },
      {
        'id_team': 1,
        'number': '13',
        'name': '継続選手',
        'first_year': 2025,
        'last_year': 2026
      },
      {
        'id_team': 1,
        'number': '14',
        'name': '初使用',
        'first_year': 2026,
        'last_year': 2026
      },
      {
        'id_team': 2,
        'number': '12',
        'name': '他球団',
        'first_year': 2026,
        'last_year': 2026
      },
      {
        'id_team': 1,
        'number': '15',
        'name': '復帰選手',
        'first_year': 2020,
        'last_year': 2023
      },
      {
        'id_team': 1,
        'number': '15',
        'name': '中間選手',
        'first_year': 2024,
        'last_year': 2025
      },
      {
        'id_team': 1,
        'number': '15',
        'name': '復帰選手',
        'first_year': 2026,
        'last_year': 2026
      },
    ], year: 2026);
    expect(
        rows
            .where((r) => r['new_uniform_number'] == true)
            .map((r) => r['name'])
            .toSet(),
        {'新選手', '復帰選手'});
  });
  test('現役区分と球団・背番号ごとの当年着用を分ける', () {
    final rows = uniformGroups([
      {
        'id_team': 1,
        'number': '12',
        'name': '移籍選手',
        'status': 'active',
        'first_year': 2020,
        'last_year': 2025
      },
      {
        'id_team': 2,
        'number': '12',
        'name': '移籍選手',
        'status': 'active',
        'first_year': 2026,
        'last_year': 2026,
        'current_roster': true
      },
      {
        'id_team': 2,
        'number': '00',
        'name': '変更選手',
        'status': 'active',
        'first_year': 2023,
        'last_year': 2025
      },
      {
        'id_team': 2,
        'number': '0',
        'name': '変更選手',
        'status': 'active',
        'first_year': 2026,
        'last_year': 2026,
        'current_roster': true
      },
    ], year: 2026);
    expect(rows.every((r) => r['status'] == 'active'), isTrue);
    expect(
        rows
            .where((r) => r['worn_in_selected_year'] == true)
            .map((r) => '${r['id_team']}:${r['number']}')
            .toSet(),
        {'2:12', '2:0'});
    expect(
        rows
            .where((r) => r['worn_in_selected_year'] == false)
            .map((r) => '${r['id_team']}:${r['number']}')
            .toSet(),
        {'1:12', '2:00'});
  });
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
