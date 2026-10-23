import 'package:flutter/material.dart';
import 'package:Yakyuu_Japan/View/strength_vertical_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';
import 'package:Yakyuu_Japan/View/team_section_layout.dart';

void main() {
  testWidgets('横画面の守備位置・打順・代打代走代守で実際の列幅が一致する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TeamSectionLayout(
      child: StrengthRegularGrid(teams: [
        {'name_team': 'テスト'}
      ]),
    )))));
    await tester.pump();
    final widths = <double>[];
    for (final mode in ['false', 'true', 'bench']) {
      final table = tester.widget<Table>(find.byKey(ValueKey('regular-table-$mode')));
      widths.add(tester.getSize(find.byWidget(table.children.first.children.first)).width);
    }
    expect(widths[1], closeTo(widths[0], .01));
    expect(widths[2], closeTo(widths[0], .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('代打代走は独立グリッドで切り替え、守備位置に混在しない', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: const Scaffold(
            body: const StrengthRegularGrid(teams: const [
      {
        'name_team': '球団A',
        'positions': const [
          {
            'slot': 'C',
            'total': 10,
            'players': const [
              {'player_key': 'c', 'name': '捕手選手', 'count': 9}
            ]
          }
        ],
        'substitutions': const [
          {
            'slot': 'PH',
            'total': 10,
            'players': const [
              {'player_key': 'ph', 'name': '代打選手', 'bats': '左', 'count': 8}
            ]
          },
          {
            'slot': 'PR',
            'total': 10,
            'players': const [
              {'player_key': 'pr', 'name': '代走選手', 'count': 6}
            ]
          },
        ],
      }
    ]))));
    expect(find.text('内野代守'), findsNothing);
    expect(find.text('外野代守'), findsNothing);
    final positionWidth = (tester.widget<Table>(find.byKey(const ValueKey('regular-table-false'))).defaultColumnWidth as FixedColumnWidth).value;
    expect(find.text('左代打'), findsNothing);
    expect(find.text('代走選手'), findsNothing);
    await tester.tap(find.text('代打・代走・代守'));
    await tester.pumpAndSettle();
    expect(find.text('左代打'), findsOneWidget);
    expect(find.text('右代打'), findsOneWidget);
    expect(find.text('内野代守'), findsOneWidget);
    expect(find.text('外野代守'), findsOneWidget);
    expect((tester.widget<Table>(find.byKey(const ValueKey('regular-table-bench'))).defaultColumnWidth as FixedColumnWidth).value, positionWidth);
    expect(find.text('代走'), findsOneWidget);
    expect(find.text('代打選手'), findsOneWidget);
    expect(find.text('代走選手'), findsOneWidget);
    expect(find.text('捕手選手'), findsNothing);
    await tester.tap(find.text('守備位置別'));
    await tester.pumpAndSettle();
    expect(find.text('捕手選手'), findsOneWidget);
    expect(find.text('代打選手'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('チームの主力選手は守備位置と全打順を同時に表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final team = <String, dynamic>{
      'name_team': '球団A',
      'positions': [
        {
          'slot': 'C',
          'total': 10,
          'players': [
            {'player_key': 'c', 'name': '捕手選手', 'count': 9}
          ]
        }
      ],
      'batting_order': [
        for (var i = 1; i <= 9; i++)
          {
            'slot': i,
            'total': 10,
            'players': [
              {'player_key': 'b$i', 'name': '打者$i', 'count': 8}
            ]
          }
      ],
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: SingleChildScrollView(
          child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
            width: 390,
            child: TeamSectionLayout(
              child: StrengthRegularGrid(teams: [team]),
            )),
      )),
    )));
    await tester.pump();
    expect(find.text('守備位置別'), findsOneWidget);
    expect(find.text('打順別'), findsOneWidget);
    expect(find.text('代打・代走・代守'), findsOneWidget);
    final benchGrid = find.byWidgetPredicate((w) => w is StrengthRegularGrid && w.bench);
    expect(benchGrid, findsOneWidget);
    expect(find.descendant(of: benchGrid, matching: find.text('左代打')), findsOneWidget);
    expect(find.text('捕手選手'), findsOneWidget);
    for (var i = 1; i <= 9; i++) {
      expect(find.text('$i番'), findsOneWidget);
      expect(find.text('打者$i'), findsOneWidget);
    }
    expect(find.text('80.0%'), findsNWidgets(9));
    final battingGrid = find.byWidgetPredicate((w) => w is StrengthRegularGrid && w.battingOrder == true);
    expect(tester.getSize(battingGrid).width, 390);
    final table = tester.widget<Table>(find.descendant(of: battingGrid, matching: find.byType(Table)));
    expect(table.children.length, 9);
    for (final row in table.children) {
      final header = find.byWidget(row.children[0]);
      final cell = find.byWidget(row.children[1]);
      expect(tester.getTopLeft(header).dy, tester.getTopLeft(cell).dy);
      expect(tester.getTopLeft(cell).dx, tester.getTopLeft(header).dx + 80);
    }
    expect(find.byType(StrengthVerticalLabel), findsNothing);
    expect(find.text('球団'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
