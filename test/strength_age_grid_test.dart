import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_age_grid.dart';
import 'package:Yakyuu_Japan/View/team_strength_board.dart';
import 'package:Yakyuu_Japan/View/player_detail_dialog.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  test('学年の境界は4月2日で、早生まれは前年度に属する', () {
    expect(playerSchoolYear('2000-04-01'), 1999);
    expect(playerSchoolYear('2000-04-02'), 2000);
    expect(playerSchoolYear('2001-01-10'), 2000);
    expect(playerSchoolYear('2001-04-01'), 2000);
    expect(playerSchoolYear(null), isNull);
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets('年齢タブで12球団を同学年ごとに表示する 幅$width', (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final teams = [for (var i = 1; i <= 12; i++) <String, dynamic>{
        'id_team': i, 'id_league': i <= 6 ? 1 : 2, 'name_team': '球団$i',
        'roster': [
          {'name': '同学年選手$i', 'date_birth': i.isOdd ? '2000-04-02' : '2001-04-01'},
          if (i == 1) {'name': '前学年選手', 'date_birth': '2000-04-01'},
          if (i == 1) {'name': '不明選手'},
        ],
      }];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TeamStrengthBoard(
        org: OrgConfig.npb, year: 2026, providedTeams: teams, initialView: 14,
      ))));
      await tester.pumpAndSettle();
      expect(find.byType(StrengthAgeGrid), findsOneWidget);
      for (var i = 1; i <= 12; i++) {
        expect(find.text('球団$i'), findsOneWidget);
      }
      final cohort = find.byKey(const ValueKey('strength-age-row-2000'));
      expect(find.descendant(of: cohort, matching: find.byType(PlayerNameLink)), findsNWidgets(12));
      expect(find.text('2000年度\n（26歳）'), findsOneWidget);
      expect(find.descendant(of: cohort, matching: find.text('前学年選手')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('strength-age-row-unknown')),
          matching: find.text('不明選手')), findsOneWidget);
      final headerY = tester.getTopLeft(find.text('球団1')).dy;
      await tester.drag(find.byKey(const ValueKey('strength-age-horizontal')), const Offset(-800, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('球団1')).dy, headerY);
      expect(tester.takeException(), isNull);
    });
  }
}
