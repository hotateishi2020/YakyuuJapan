import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_research.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('功績の面積比・上詰め配置・二段階ポップアップ 幅$width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StrengthAchievements(
        year: 2026,
        team: {'id_team': 1, 'name_team': '球団', 'roster': [
          {'player_key': 'small', 'name': '小選手', 'achievements': [
            {'year': 2025, 'label': 'AL MVP', 'kind': 'title', 'detail': '受賞の説明'},
          ]},
          {'player_key': 'large', 'name': '大選手', 'achievements': [
            {'year': 2025, 'label': 'トリプルスリー', 'kind': 'record'},
          ]},
        ]},
      ))));
      final large = find.byKey(const ValueKey('achievement-player-1-large'));
      final small = find.byKey(const ValueKey('achievement-player-1-small'));
      final largeRect = tester.getRect(large), smallRect = tester.getRect(small);
      expect(largeRect.width, largeRect.height);
      expect(smallRect.width, smallRect.height);
      expect(largeRect.width * largeRect.height / (smallRect.width * smallRect.height), closeTo(4, .001));
      expect(largeRect.top, smallRect.top);
      expect(largeRect.overlaps(smallRect), isFalse);
      expect(smallRect.right, lessThanOrEqualTo(width));
      await tester.tap(small);
      await tester.pumpAndSettle();
      final dialog = find.byKey(const ValueKey('achievement-player-dialog'));
      expect(tester.getSize(dialog), Size(width, 800));
      await tester.tap(find.byTooltip('2025年 AL MVP\n受賞の説明'));
      await tester.pumpAndSettle();
      expect(find.text('小選手：AL MVP'), findsOneWidget);
      expect(find.textContaining('受賞の説明'), findsWidgets);
      expect(tester.getSize(find.ancestor(of: find.text('小選手：AL MVP'), matching: find.byType(Material)).first).width, lessThan(width));
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(tester.getRect(small), smallRect);
      expect(tester.takeException(), isNull);
    });
  }
}
