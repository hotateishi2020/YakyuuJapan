import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';
import 'package:Yakyuu_Japan/View/team_section_layout.dart';

void main() {
  for (final size in [const Size(1440, 900), const Size(900, 600)]) {
    testWidgets('主力選手の横画面でDHまで収まり全グリッドの列幅が揃う $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: SingleChildScrollView(child: TeamSectionLayout(
          child: StrengthRegularGrid(teams: [{'name_team': 'ドジャース'}]),
        )),
      )));
      await tester.pumpAndSettle();
      final position = tester.getRect(find.byKey(const ValueKey('regular-table-false')));
      final order = tester.getRect(find.byKey(const ValueKey('regular-table-true')));
      final bench = tester.getRect(find.byKey(const ValueKey('regular-table-bench')));
      expect(position.left, 0);
      expect(position.width, closeTo(size.width, .01));
      expect(order.left, position.left);
      expect(bench.left, position.left);
      expect(order.width / 9, closeTo(position.width / 14, .01));
      expect(bench.width / 5, closeTo(position.width / 14, .01));
      expect(tester.getRect(find.text('指名打者')).right, lessThanOrEqualTo(size.width));
      expect(tester.takeException(), isNull);
    });
  }
}
