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
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('draft-team-segment-all'))).selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('draft-team-segment-all')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('draft-team-segment-all'))).selected, isTrue);
  });
  testWidgets('draft filters display team picks and competition label', (tester) async {
    await tester.runAsync(() => rootBundle.loadString('backend/assets/data/draft_history.json'));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DraftHistoryBoard(year: 2025))));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 20)); });
    await tester.pumpAndSettle();
    expect(find.text('12球団・1位指名'), findsOneWidget);
    expect(find.text('2025年'), findsOneWidget);
    expect(find.text('2024年'), findsOneWidget);
    await tester.tap(find.text('12球団・1位指名'));
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
}
