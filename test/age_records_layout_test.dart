import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/additional_records_board.dart';

void main() {
  testWidgets('年齢記録は最年少と最年長を色分けし、狭い画面でも列を維持する', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [1400.0, 390.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: AgeRecordsBoard(rows: [
          for (final name in ['若手A', '若手B']) {'label': '100本塁打', 'name': name, 'youngest': 1, 'age_label': '23歳100日', 'date': '2020-06-01'},
          const {'label': '100本塁打', 'name': 'ベテラン', 'oldest': 1, 'age_label': '40歳100日', 'date': '2025-06-01'},
        ]),
      )));
      await tester.pumpAndSettle();
      expect(find.text('若手A'), findsOneWidget);
      expect(find.text('若手B'), findsOneWidget);
      Color? background(String label) => (tester.widget<Container>(find.ancestor(of: find.text(label), matching: find.byType(Container)).first).decoration as BoxDecoration).color;
      expect(background('最年少・選手名'), const Color(0xff176c88));
      expect(background('最年長・選手名'), const Color(0xff925e25));
      final grid = find.byKey(const ValueKey('age-records-grid'));
      if (width == 1400) {
        expect(tester.getSize(grid).width, lessThan(1000));
        expect(tester.getCenter(grid).dx, closeTo(width / 2, 1));
      } else {
        final scroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right);
        await tester.drag(scroll, const Offset(-400, 0));
        await tester.pumpAndSettle();
        expect(tester.state<ScrollableState>(scroll).position.pixels, greaterThan(0));
      }
      expect(tester.takeException(), isNull);
    }
  });
}
