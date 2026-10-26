import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/career_regions.dart';
import 'package:Yakyuu_Japan/logic/strength_analytics.dart';
import 'package:Yakyuu_Japan/logic/achievement_priority.dart';
import 'package:Yakyuu_Japan/View/strength_careers.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';

void main() {
  test('地域は国・地方・県・市の順、学年は4月2日境界', () {
    expect(careerRegionPath({'birth_place': '佐賀県佐賀市'}),
        ['日本', '九州', '佐賀県', '佐賀市']);
    expect(careerRegionPath({'birth_place': '佐賀'}), ['日本', '九州', '佐賀県']);
    expect(careerRegionPath({}), isEmpty);
    expect(careerSchoolYear({'date_birth': '2000-04-01'}), 1999);
    expect(careerSchoolYear({'date_birth': '2000-04-02'}), 2000);
    expect(careerSchoolYear({'date_birth': '2001-03-31'}), 2000);
  });
  test('左右の割合が逆転しても左・両・右の順を保つ', () {
    for (final left in [1, 99]) {
      final band = handednessBand({
        'batting_stats': [
          {'player_key': 'r', 'bats': '右', 'pa': 100 - left},
          {'player_key': 'l', 'bats': '左', 'pa': left},
          {'player_key': 's', 'bats': '両', 'pa': 3},
        ]
      }, pitching: false);
      expect(
          (band['players'] as List).map((p) => p['name']), ['左打', '両打', '右打']);
    }
  });
  test('先発割合は投球回でなく先発試合数を使う', () {
    final band = pitcherStartsBand({
      'pitching_workload': [
        {'name': 'A', 'starts': 10, 'total_outs': 300},
        {'name': 'B', 'starts': 20, 'total_outs': 100},
        {'name': 'C', 'starts': 0, 'total_outs': 400},
      ]
    });
    expect(band['total'], 30);
    expect((band['players'] as List).map((p) => p['name']), ['B', 'A']);
  });
  test('種類によって評価が違っても同名功績は離れない', () {
    final honors = groupAchievementHonors([
      {'label': '同じ賞', 'kind': 'title', 'year': 2020},
      {'label': '別の賞', 'kind': 'title', 'year': 2021},
      {'label': '同じ賞', 'kind': 'record', 'year': 2022},
    ]);
    final indices = [
      for (var i = 0; i < honors.length; i++)
        if (honors[i]['label'] == '同じ賞') i
    ];
    expect(indices.last - indices.first, 1);
  });
  testWidgets('経歴は同学年が同じ行、所属1人は共通枠、球団で絞れる', (t) async {
    Map<String, dynamic> player(String name, String school, String birth) => {
          'name': name,
          'player_key': name,
          'date_birth': birth,
          'career_history': [
            {'category': '高校', 'team': school}
          ]
        };
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthCareers(teams: [
      {
        'id_team': 1,
        'name_team': '球団A',
        'roster': [
          player('A', '甲高校', '2000-05-01'),
          player('B', '甲高校', '1998-05-01'),
          player('C', '乙高校', '2000-06-01'),
          player('D', '乙高校', '1999-05-01')
        ]
      },
      {
        'id_team': 2,
        'name_team': '球団B',
        'roster': [player('E', '丙高校', '2000-05-01')]
      },
    ]))));
    expect(t.getTopLeft(find.text('A')).dy, t.getTopLeft(find.text('C')).dy);
    expect(find.text('所属1人の出身元  1人'), findsOneWidget);
    await t.tap(find.text('エリア順'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('A')).dy, t.getTopLeft(find.text('C')).dy);
    await t.tap(find.text('全球団'));
    await t.pumpAndSettle();
    await t.tap(find.text('球団A').last);
    await t.pumpAndSettle();
    expect(find.text('E'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('打順全体で同じ選手は一度だけ表示', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthRegularGrid(teams: [
      {
        'name_team': 'A',
        'batting_order': [
          for (var i = 1; i <= 9; i++)
            {
              'slot': i,
              'total': 10,
              'players': [
                {'player_key': 'p', 'name': '選手', 'count': 8}
              ]
            }
        ]
      }
    ]))));
    await t.tap(find.text('打順別'));
    await t.pumpAndSettle();
    expect(find.text('選手'), findsOneWidget);
    expect(find.text('80.0%'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
