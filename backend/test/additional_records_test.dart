import 'package:test/test.dart';
import '../app/AdditionalRecords.dart';
import '../app/BaseballCatalog.dart';

void main() {
  test('historical regular lineups merge without replacing current snapshots',
      () {
    final rows = mergeRegularHistory([
      {
        'year': 2025,
        'id_team': 1,
        'name_team': '巨人',
        'batting_stats': [],
        'positions': [
          {
            'slot': 'C',
            'players': [
              {'name': 'snapshot'}
            ]
          }
        ]
      },
    ], [
      {
        'year': 1981,
        'club_name': '巨人',
        'positions': [
          {'slot': 'C'}
        ]
      },
      {
        'year': 2025,
        'club_name': '巨人',
        'positions': [
          {'slot': 'P'}
        ],
        'batting_order': [
          {'slot': 1}
        ],
        'batting_stats': [
          {'name': '公式成績', 'ops': 0.8}
        ],
      },
      {'year': 2004, 'club_name': '近鉄'},
      {'year': 2026, 'club_name': '巨人'},
    ], [
      {'id_team': 1, 'name_team': '巨人'}
    ], 2025);
    expect(rows.map((r) => r['year']), [2025, 2004, 1981]);
    expect(rows.first['positions'], [
      {
        'slot': 'C',
        'players': [
          {'name': 'snapshot'}
        ]
      }
    ]);
    expect(rows.first['batting_order'], [
      {'slot': 1}
    ]);
    expect(rows.first['batting_stats'], [
      {'name': '公式成績', 'ops': 0.8}
    ]);
    expect(rows.last['id_team'], 1);
    expect(rows[1]['id_team'], 'historical-近鉄');
  });

  test('official age ranking preserves precision and selected-year cutoff', () {
    final rows = milestoneAgeRecords([
      {
        'label': '100本塁打',
        'name': 'A',
        'year': 2000,
        'age_months': 240,
        'age_order': '【1】'
      },
      {
        'label': '100本塁打',
        'name': 'B',
        'year': 1999,
        'age_months': 240,
        'age_order': '【2】'
      },
      {
        'label': '100本塁打',
        'name': 'C',
        'year': 2001,
        'age_months': 480,
        'age_order': '（1）'
      },
    ], 2000);
    expect(rows.where((r) => r['youngest'] == 1).single['name'], 'A');
    expect(rows.any((r) => r['name'] == 'C'), false);
  });

  test('HR-SB uses minimum and excludes missing stats', () {
    final r = buildHrStealRecord([
      {'name': 'A', 'hr': 50, 'sb': 10, 'year': 2026},
      {'name': 'B', 'hr': 20, 'sb': 20, 'year': 2026},
      {'name': 'C', 'hr': 60, 'year': 2026}
    ], 2026);
    expect((r['leaders'] as List).first['name'], 'B');
    expect((r['leaders'] as List).length, 2);
  });
  test('current HR-SB requires both totals to reach ten', () {
    final result = buildHrStealRecord([
      {'name': '境界', 'hr': 10, 'sb': 10, 'year': 2026},
      {'name': '盗塁不足', 'hr': 30, 'sb': 9, 'year': 2026},
      {'name': 'HR不足', 'hr': 9, 'sb': 30, 'year': 2026},
      {'name': '過去年', 'hr': 40, 'sb': 40, 'year': 2025},
    ], 2026);
    expect((result['current'] as List).map((r) => r['name']), ['境界']);
    expect(result['leaders'], hasLength(4));
  });
  test('qualified PA rounds down; duplicates do not inflate season counts', () {
    final seasons = <Map<String, dynamic>>[
      {
        'name': 'A',
        'id_player': 1,
        'year': 2025,
        'team_games': 143,
        'pa': 443,
        'ab': 400,
        'hits': 120,
        'hr': 30,
        'sb': 0
      }
    ];
    final r = buildCountRecords([...seasons, ...seasons], [], npb: true);
    expect(
        (r.firstWhere((r) => r['label'] == '規定打席到達')['leaders'] as List)
            .single['value'],
        1);
    expect(r.any((r) => r['label'] == '打率3割（規定打席）'), true);
  });
  test(
      'developmental zero-prefixed numbers and numbers over 300 remain separate',
      () {
    final rows = uniformGroups([
      for (final n in ['1', '001', '400'])
        {
          'id_team': 1,
          'number': n,
          'name': n,
          'first_year': 2026,
          'last_year': 2026
        }
    ], year: 2026);
    expect(rows.map((r) => r['number']).toSet(), {'1', '001', '400'});
  });
}
