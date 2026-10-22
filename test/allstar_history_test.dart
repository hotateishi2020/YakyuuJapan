import 'package:Yakyuu_Japan/widgets/collapsible_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/allstar_history_board.dart';

void main() {
  final data = <String, dynamic>{
    'first_year': 2002,
    'cancelled_years': [2020],
    'players': [
      {
        'year': 2026,
        'league': 'セ・リーグ',
        'position': '先発投手',
        'name': '選手 A',
        'team': '阪神',
        'selections': ['ファン投票', '選手間投票'],
        'withdrawn': true
      },
      {
        'year': 2026,
        'league': 'パ・リーグ',
        'position': '捕手',
        'name': '選手 B',
        'team': '西武',
        'selections': ['監督選抜']
      },
      {
        'year': 2025,
        'league': 'セ・リーグ',
        'position': '内野手',
        'display_position': '二塁手',
        'name': '選手 C',
        'team': '中日',
        'selections': ['プラスワン投票']
      },
    ]
  };
  test('years, leagues, positions and cancellation remain separate', () {
    final rows = allStarYearRows(data, 2025, 'セ・リーグ');
    expect(rows.map((r) => r['year']), [2025, 2020]);
    expect(rows.first['players'], hasLength(1));
    expect(rows.last['cancelled'], true);
  });
  testWidgets('PC幅では全列が横スクロールなしで表示幅を使い切る', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [1200.0, 1920.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AllStarHistoryGrid(data: data, throughYear: 2026))));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right));
      expect(scrollable.position.maxScrollExtent, 0);
      expect(tester.getTopLeft(find.text('投手')).dx,
          greaterThan(tester.getTopLeft(find.text('年度')).dx));
      final horizontal = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('allstar-horizontal')));
      expect(tester.getSize(find.byWidget(horizontal.child!)).width,
          closeTo(width - 24 - 80, .01));
      expect(find.text('内野手'), findsNothing);
      expect(find.text('オールスター'), findsNothing);
      expect(find.text('ファン投票'), findsOneWidget);
      expect(find.text('選手間投票'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('dense pitching roster expands and scrolls with the year column',
      (tester) async {
    final roster = {
      'players': [
        for (final year in [2026, 2025, 2024])
          for (final league in ['セ・リーグ', 'パ・リーグ'])
            for (var i = 0; i < 26; i++)
              {
                'year': year,
                'league': league,
                'position': '投手',
                'name': '$year$league投手$i',
                'team': '球団'
              }
      ]
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AllStarHistoryGrid(data: roster, throughYear: 2026))));
    expect(find.text('2026セ・リーグ投手25'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    await tester.dragFrom(const Offset(300, 450), const Offset(0, -350));
    await tester.pumpAndSettle();
    final yearList =
        tester.widget<ListView>(find.byKey(const ValueKey('allstar-years')));
    final bodyList =
        tester.widget<ListView>(find.byKey(const ValueKey('allstar-body')));
    expect(yearList.controller!.offset, bodyList.controller!.offset);
    expect(bodyList.controller!.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets('縦画面は年度とリーグで切り替え年度ヘッダーを表示しない',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: AllStarHistoryGrid(data: data, throughYear: 2026))));
    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('両リーグ'), findsNothing);
    expect(find.text('選手 A'), findsOneWidget);
    expect(find.text('選手 B'), findsNothing);
    expect(find.text('選手 C'), findsNothing);
    expect(find.text('投手'), findsOneWidget);
    expect(find.text('先発投手'), findsNothing);
    await tester.tap(find.text('ファン投票')); 
    await tester.pumpAndSettle();
    expect(find.textContaining('ファン投票\n選手間投票\n出場辞退'), findsOneWidget);
    Tooltip.dismissAllToolTips();
    await tester.pumpAndSettle();
    expect(find.text('年度'), findsNothing);
    expect(find.byKey(const ValueKey('allstar-horizontal')), findsNothing);
    await tester.tap(find.text('パ・リーグ').first);
    await tester.pumpAndSettle();
    expect(find.text('選手 B'), findsOneWidget);
    expect(find.text('選手 A'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('allstar-year-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025年').last);
    await tester.pumpAndSettle();
    expect(find.text('選手 B'), findsNothing);
    expect(find.text('この年度・リーグの名簿は未取得です'), findsOneWidget);
    await tester.tap(find.text('セ・リーグ').first);
    await tester.pumpAndSettle();
    expect(find.text('選手 C'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('allstar-position-二塁手')),
      matching: find.text('選手 C')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('allstar-year-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2020年').last);
    await tester.pumpAndSettle();
    expect(find.text('開催中止'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('縦画面は守備位置見出しの下に4列で選手を配置する', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MenuScope(child:
      AllStarHistoryGrid(throughYear: 2026, data: {'players': [
        for (var i = 0; i < 5; i++) {'year': 2026, 'league': 'セ・リーグ',
          'position': '投手', 'name': '投手$i', 'selections': ['監督選抜']},
        {'year': 2026, 'league': 'セ・リーグ', 'position': '捕手', 'name': '捕手選手'},
      ]}),
    ))));
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('allstar-year-picker'));
    final central = find.byKey(const ValueKey('allstar-league-セ・リーグ'));
    final pacific = find.byKey(const ValueKey('allstar-league-パ・リーグ'));
    expect(tester.getRect(picker).right, lessThanOrEqualTo(tester.getRect(central).left));
    expect(tester.getRect(central).right, lessThanOrEqualTo(tester.getRect(pacific).left));
    expect(tester.getBottomLeft(central).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('menu-visibility-toggle'))).dy));
    final first = tester.getTopLeft(find.text('投手0'));
    for (var i = 1; i < 4; i++) {
      expect(tester.getTopLeft(find.text('投手$i')).dy, first.dy);
      expect(tester.getTopLeft(find.text('投手$i')).dx, greaterThan(first.dx));
    }
    expect(tester.getTopLeft(find.text('投手4')).dx, first.dx);
    expect(tester.getTopLeft(find.text('投手4')).dy, greaterThan(first.dy));
    expect(tester.getTopLeft(find.text('捕手')).dy,
      greaterThan(tester.getBottomLeft(find.text('投手4')).dy));
    expect(tester.takeException(), isNull);
  });

}
