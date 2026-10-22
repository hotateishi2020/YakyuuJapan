import 'package:Yakyuu_Japan/widgets/collapsible_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/club_records_board.dart';

void main() {
  for (final width in [375.0, 1366.0]) {
    testWidgets('幅$widthで12球団の記録と今季記録を上下に表示', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ClubRecordsBoard(data: {
        'year': 2026,
        'teams': [
          for (var id = 1; id <= 12; id++) {'id_team': id, 'name': '球団$id'}
        ],
        'metrics': const [
          {
            'label': '本塁打',
            'unit': '本',
            'cells': [
              {
                'id_team': 1,
                'record': [
                  {'name': '記録保持者', 'value': 50, 'year': 2000}
                ],
                'current': [
                  {'name': '今季選手', 'value': 40}
                ]
              },
            ]
          }
        ],
      }))));
      expect(find.text('あと10本'), findsOneWidget);
      expect(tester.widget<FractionallySizedBox>(find.byKey(const ValueKey('club-bar-本塁打-1-record-0'))).widthFactor, 1);
      expect(tester.widget<FractionallySizedBox>(find.byKey(const ValueKey('club-bar-本塁打-1-current-0'))).widthFactor, .8);
      expect(tester.getTopLeft(find.textContaining('記録保持者')).dx, tester.getTopLeft(find.textContaining('今季選手')).dx);
      expect(tester.getBottomLeft(find.byKey(const ValueKey('club-bar-本塁打-1-record-0'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('club-bar-本塁打-1-current-0'))).dy));
      expect(find.text('球団12'), findsOneWidget);
      expect(find.text('未取得'), findsWidgets);
      final left = tester.getTopLeft(find.text('本塁打'));
      await tester.drag(find.byType(SingleChildScrollView), const Offset(-500, 0));
      await tester.pump();
      expect(tester.getTopLeft(find.text('本塁打')), left);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('更新・同率・ゼロ・未取得でも共通スケールのゲージで比較する', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ClubRecordsBoard(data: {
      'year': 2026,
      'teams': [
        {'id_team': 1, 'name': '球団'}
      ],
      'metrics': [
        {
          'key': 'hr',
          'label': '本塁打',
          'unit': '本',
          'cells': [
            {
              'id_team': 1,
              'record': [
                {'name': '歴代', 'value': 40, 'year': 2000}
              ],
              'current': [
                {'name': '選手A', 'value': 50},
                {'name': '選手B', 'value': 50}
              ]
            },
          ]
        },
        {
          'key': 'sb',
          'label': '盗塁',
          'unit': '盗塁',
          'cells': [
            {
              'id_team': 1,
              'record': [],
              'current': [
                {'name': '選手C', 'value': 0}
              ]
            },
          ]
        },
      ],
    }))));
    double? ratio(String key) => tester.widget<FractionallySizedBox>(find.byKey(ValueKey(key))).widthFactor;
    expect(ratio('club-bar-hr-1-record-0'), .8);
    expect(ratio('club-bar-hr-1-current-0'), 1);
    expect(ratio('club-bar-hr-1-current-1'), 1);
    expect(ratio('club-bar-sb-1-current-0'), 0);
    expect(find.byKey(const ValueKey('club-bar-sb-1-record-0')), findsNothing);
    expect(find.text('球団記録更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('通算と連続の切り替えでゲージと項目が変わる', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClubRecordsBoard(data: {
      'year': 2026,
      'teams': const [
        {'id_team': 1, 'name': '球団'}
      ],
      'metrics': [
        for (final group in ['career', 'streak'])
          {
            'key': group,
            'group': group,
            'label': group == 'career' ? '通算安打' : '連続安打',
            'unit': '回',
            'cells': [
              {
                'id_team': 1,
                'record': [
                  {'name': '保持者', 'value': 20, 'year': 2000}
                ],
                'current': [
                  {'name': '今季', 'value': 10}
                ]
              }
            ]
          },
      ],
    }))));
    await t.tap(find.widgetWithText(ChoiceChip, '通算記録'));
    await t.pump();
    expect(find.text('通算安打'), findsOneWidget);
    expect(find.text('今季出場者の通算'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, '連続記録'));
    await t.pump();
    expect(find.text('連続安打'), findsOneWidget);
    expect(find.text('通算安打'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('縦画面の12球団タブは表示非表示バーの上で球団を切り替える', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MenuScope(child: Column(children: [
      const MenuBand(level: 2, child: Text('球団記録タブ')),
      Expanded(child: ClubRecordsBoard(data: {
        'year': 2026,
        'teams': [for (var id = 1; id <= 12; id++) {'id_team': id, 'name': '球団$id'}],
        'metrics': [for (final group in ['season', 'career']) {
          'group': group, 'label': '本塁打', 'unit': '本',
          'cells': [for (var id = 1; id <= 12; id++) {
            'id_team': id, 'current': [{'name': '選手$id', 'value': 10}],
          }],
        }],
      })),
    ])))));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('menu-visibility-toggle'));
    expect(toggle, findsOneWidget);
    for (var id = 1; id <= 12; id++) {
      final tab = find.byKey(ValueKey('club-records-team-$id'));
      expect(tab.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(tab).dy, greaterThanOrEqualTo(tester.getBottomLeft(find.text('球団記録タブ')).dy));
      expect(tester.getBottomLeft(tab).dy, lessThan(tester.getTopLeft(toggle).dy));
    }
    expect(find.text('選手1\n10本'), findsOneWidget);
    expect(find.text('選手12\n10本'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('club-records-team-12')));
    await tester.pumpAndSettle();
    expect(find.text('選手1\n10本'), findsNothing);
    expect(find.text('選手12\n10本'), findsOneWidget);
    await tester.tap(find.text('通算記録'));
    await tester.pumpAndSettle();
    expect(find.text('選手12\n10本'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('club-records-team-12')).hitTestable(), findsNothing);
    expect(find.text('選手12\n10本'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('club-records-team-12')), findsNothing);
    expect(find.text('選手1\n10本'), findsOneWidget);
    expect(find.text('選手12\n10本'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('選手1\n10本'), findsNothing);
    expect(find.text('選手12\n10本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
