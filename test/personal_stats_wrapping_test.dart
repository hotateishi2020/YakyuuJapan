import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';

void main() {
  final rows = [
    for (final title in ['本塁打', '打点', '盗塁'])
      for (var rank = 1; rank <= 30; rank++)
        <String, dynamic>{'title': title, 'int_rank': rank,
          'name_player': '山田太郎$rank', 'name_team': '巨', 'stats': '${31-rank}'},
  ];
  Widget app(double width) => MaterialApp(home: Scaffold(body: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, child: SingleChildScrollView(
      child: ScrollLeaguePersonalStats(rows: rows, batting: true))),
  )));

  testWidgets('折り返しても各スタッツは10人を固定表示する', (tester) async {
    await tester.pumpWidget(app(650));
    final first = find.byKey(const ValueKey('personal-stat-panel-本塁打'));
    final second = find.byKey(const ValueKey('personal-stat-panel-打点'));
    final third = find.byKey(const ValueKey('personal-stat-panel-盗塁'));
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
    expect(tester.getTopLeft(third).dy, greaterThan(tester.getTopLeft(first).dy));
    for (final panel in [first, second, third]) {
      expect(tester.getSize(panel).width, 280);
      expect(find.descendant(of: panel, matching: find.byType(PlayerStatCell)), findsNWidgets(10));
      expect(find.descendant(of: panel, matching: find.byType(Scrollable)), findsNothing);
      expect(find.descendant(of: panel, matching: find.text('山田太郎11')), findsNothing);
    }
    await tester.pumpWidget(app(360));
    expect(tester.getTopLeft(second).dy, greaterThan(tester.getTopLeft(first).dy));
    expect(tester.getSize(first).width, 360);
    expect(tester.takeException(), isNull);
  });

  testWidgets('右端のボタンから全順位を開き末尾までスクロールできる', (tester) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(1000));
    final first = find.byKey(const ValueKey('personal-stat-panel-本塁打'));
    expect(tester.getSize(first).width, 280);
    await tester.tap(find.byTooltip('本塁打の全ランキング'));
    await tester.pumpAndSettle();
    expect(find.text('本塁打 ランキング'), findsOneWidget);
    final ranking = find.byKey(const ValueKey('personal-stat-ranking-本塁打'));
    final list = tester.widget<ListView>(ranking);
    expect((list.childrenDelegate as SliverChildBuilderDelegate).childCount, 30);
    final state = tester.state<ScrollableState>(find.descendant(
        of: ranking, matching: find.byType(Scrollable)));
    expect(state.position.maxScrollExtent, greaterThan(0));
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.descendant(of: ranking, matching: find.text('山田太郎30')), findsOneWidget);
    await tester.tap(find.byTooltip('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.descendant(of: first, matching: find.byType(PlayerStatCell)), findsNWidgets(10));
    expect(tester.takeException(), isNull);
  });
}
