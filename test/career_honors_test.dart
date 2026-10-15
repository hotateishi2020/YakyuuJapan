import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_careers.dart';
import 'package:Yakyuu_Japan/View/strength_research.dart';
import 'package:Yakyuu_Japan/logic/player_honors.dart';
import 'package:Yakyuu_Japan/logic/achievement_priority.dart';

final teams = <Map<String, dynamic>>[
  {
    'id_team': 1,
    'name_team': '球団A',
    'color_back': '#ff8800',
    'roster': [
      {
        'player_key': 'a',
        'name': '選手A',
        'career_history': [
          {'category': '高校', 'team': '甲高校', 'source_url': 'https://npb.jp/'},
          {'category': '高校', 'team': '甲高校', 'source_url': 'https://npb.jp/'},
          {'category': '大学', 'team': '乙大学', 'source_url': 'https://npb.jp/'},
        ]
      },
      {
        'player_key': 'b',
        'name': '選手B',
        'career_history': [
          {'category': '高校', 'team': '甲高校'}
        ]
      },
      {
        'player_key': 'c',
        'name': '選手C',
        'career_history': [
          {'category': '高校', 'team': '丙高校'}
        ]
      },
      {
        'player_key': 'r',
        'name': '引退選手',
        'departure_confirmed': true,
        'departure_type': 'retired',
        'career_history': [
          {'category': '高校', 'team': '甲高校'}
        ]
      },
    ]
  }
];
void main() {
  test('経歴は現役・カテゴリ別で重複を除き人数順', () {
    final grouped = careerGroups(teams, '高校');
    expect(grouped.map((g) => g['name']), ['甲高校', '丙高校']);
    expect((grouped.first['players'] as List).length, 2);
    expect(careerGroups(teams, '大学').single['name'], '乙大学');
    expect(careerGroups(teams, '社会人'), isEmpty);
  });
  test('追加功績を統合し賞の表記揺れを重複計上しない', () {
    final result = playerHonors({
      'achievements': [
        {'year': 2021, 'label': '沢村栄治賞'},
        {'year': 2023, 'label': 'WBC優勝レギュラー'},
        {'year': 2024, 'label': 'NL Cy Young'},
      ],
      'additional_achievements': [
        {'year': 2021, 'label': '沢村賞'},
        {'year': 2023, 'label': 'WBC優勝メンバー（レギュラー級）'},
      ],
    });
    expect(result.length, 3);
    expect(result.last['label'], 'ナ・リーグ サイ・ヤング賞');
    expect(achievementValue({'label': 'サイ・ヤング賞'}), 100);
    expect(
        achievementValue({'label': '侍ジャパン招集', 'kind': 'callup'}),
        lessThan(
            achievementValue({'label': '侍ジャパン代表選出', 'kind': 'national_team'})));
  });
  for (final width in [375.0, 1200.0]) {
    testWidgets('経歴の切替と根拠表示 幅$width', (t) async {
      t.view.physicalSize = Size(width, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
          MaterialApp(home: Scaffold(body: StrengthCareers(teams: teams))));
      expect(find.text('甲高校  2人'), findsOneWidget);
      await t.tap(find.text('大学'));
      await t.pumpAndSettle();
      expect(find.text('乙大学  1人'), findsOneWidget);
      expect(find.text('選手B'), findsNothing);
      await t.tap(find.text('選手A'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('大学：乙大学'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('追加受賞を功績アイコンと詳細に表示する', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthAchievements(year: 2026, team: {
      'roster': [
        {
          'name': '選手',
          'player_key': 'a',
          'additional_achievements': [
            {
              'label': '沢村賞',
              'year': 2025,
              'kind': 'title',
              'source': 'https://npb.jp/',
              'detail': '公式受賞'
            },
          ]
        }
      ],
    }))));
    await t.tap(find.byTooltip('2025年 沢村賞\n公式受賞'));
    await t.pumpAndSettle();
    expect(find.textContaining('公式受賞'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
