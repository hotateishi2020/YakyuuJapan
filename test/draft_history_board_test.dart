import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/draft_history_board.dart';

void main() {
  test('historical data covers all completed drafts and preserves split rounds', () {
    final years = jsonDecode(File('backend/assets/data/draft_history.json').readAsStringSync())['years'] as Map;
    expect(years.length, 61);
    for (final entry in years.entries) {
      final picks = entry.value['picks'] as List;
      expect(picks.map((p) => p['team']).toSet().length, entry.key == '1978' ? 11 : 12, reason: '${entry.key}');
    }
    expect((years['1966']['picks'] as List).map((p) => p['type']).toSet(), containsAll(['1','2']));
    expect((years['2025']['picks'] as List).any((p) => p['type'] == '育成'), true);
    final ishigaki = (years['2025']['picks'] as List).singleWhere((p) => p['name'] == '石垣 元気');
    expect(ishigaki['competition'], 2);
  });
  for (final width in [1366.0, 375.0]) {
    testWidgets('幅$widthで12球団の配置と見出し固定', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() => rootBundle.loadString('backend/assets/data/draft_history.json'));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DraftHistoryBoard(year: 2025))));
      await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 20)); });
      await tester.pumpAndSettle();
      final header = find.byKey(const ValueKey('draft-header-11'));
      final top = tester.getTopLeft(header).dy;
      final horizontal = tester.stateList<ScrollableState>(find.byType(Scrollable)).singleWhere((s) => s.axisDirection == AxisDirection.right);
      if (width > 1000) {
        expect(horizontal.position.maxScrollExtent, 0);
        expect(tester.getBottomRight(header).dx, lessThanOrEqualTo(width));
      } else {
        final yearX = tester.getTopLeft(find.byKey(const ValueKey('draft-year-header'))).dx;
        horizontal.position.jumpTo(300);
        await tester.pump();
        expect(tester.getTopLeft(find.byKey(const ValueKey('draft-year-header'))).dx, yearX);
      }
      final vertical = tester.stateList<ScrollableState>(find.byType(Scrollable)).singleWhere((s) => s.axisDirection == AxisDirection.down);
      vertical.position.jumpTo(500);
      await tester.pump();
      expect(tester.getTopLeft(header).dy, top);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('all teams opens even with a favorite team', (tester) async {
    AuthSession.instance.user = AuthUser.fromJson({'id': 1, 'name_team_fav': '東京ヤクルトスワローズ'});
    AuthSession.instance.token = 'test';
    addTearDown(() {AuthSession.instance.user = null; AuthSession.instance.token = null;});
    await tester.runAsync(() => rootBundle.loadString('backend/assets/data/draft_history.json'));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DraftHistoryBoard(year: 2025))));
    await tester.runAsync(() async {await Future<void>.delayed(const Duration(milliseconds: 20));});
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('draft-mode-0'))).selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('draft-mode-0')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('draft-mode-0'))).selected, isTrue);
  });
  testWidgets('draft filters display team picks and competition label', (tester) async {
    await tester.runAsync(() => rootBundle.loadString('backend/assets/data/draft_history.json'));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DraftHistoryBoard(year: 2025))));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 20)); });
    await tester.pumpAndSettle();
    expect(find.text('12球団1位指名'), findsOneWidget);
    expect(find.text('2025年'), findsOneWidget);
    expect(find.text('2024年'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('draft-mode-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('draft-team-segment-ヤクルト')));
    await tester.pumpAndSettle();
    final selectedChip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('draft-team-segment-ヤクルト')));
    expect(selectedChip.selected, isTrue);
    expect(selectedChip.selectedColor, const Color(0xFF006633));
    expect(selectedChip.backgroundColor, Color.lerp(const Color(0xFF006633), Colors.white, .86));
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('松下 歩叶'), findsOneWidget);
    expect(find.text('松川 玲央'), findsOneWidget);
    expect(tester.getTopLeft(find.text('松川 玲央')).dx, greaterThan(tester.getTopLeft(find.text('松下 歩叶')).dx));
    expect(tester.getTopLeft(find.text('2024年')).dy, greaterThan(tester.getTopLeft(find.text('2025年')).dy));
    expect(find.text('石垣 元気　2球団競合'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('年度選択で12球団の育成まで表示し切り替えられる', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 800);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(() => rootBundle.loadString('backend/assets/data/draft_history.json'));
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: DraftHistoryBoard(year: 2025))));
    await t.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 20)); });
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('draft-mode-2')));
    await t.pumpAndSettle();
    expect(t.widget<DropdownButton<int>>(find.byKey(const ValueKey('draft-year-picker'))).value, 2025);
    expect(find.text('育成 1位'), findsOneWidget);
    final grid = find.byKey(const ValueKey('draft-annual-grid'));
    expect(find.descendant(of: grid, matching: find.text('松下 歩叶')), findsOneWidget);
    t.widget<DropdownButton<int>>(find.byKey(const ValueKey('draft-year-picker'))).onChanged!(2024);
    await t.pumpAndSettle();
    expect(find.text('松下 歩叶'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('現役ドラフトは2022年から複数獲得も表示する', (t) async {
    await t.runAsync(() => rootBundle.loadString('backend/assets/data/active_draft_history.json'));
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: DraftHistoryBoard(year: 2026, activeDraft: true))));
    await t.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 20)); });
    await t.pumpAndSettle();
    expect(find.text('松浦 慶斗'), findsOneWidget);
    expect(find.textContaining('へ移籍'), findsNothing);
    final former = find.byKey(const ValueKey('active-draft-former-2025-松浦 慶斗'));
    expect((t.widget<Container>(former).decoration as BoxDecoration).color, const Color(0xFF0067A5));
    expect(t.widget<Text>(find.descendant(of: former, matching: find.text('日本ハム'))).style!.color, Colors.white);

    expect(find.text('山足 達也'), findsOneWidget);
    expect(find.text('鈴木 健矢'), findsOneWidget);
    expect(find.text('2026年'), findsNothing);
    expect(find.text('2022年'), findsOneWidget);
    expect(find.byKey(const ValueKey('draft-mode-0')), findsNothing);
    expect(t.takeException(), isNull);
  });

}
