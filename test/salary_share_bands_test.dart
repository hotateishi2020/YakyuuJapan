import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_contracts.dart';

void main() {
  Map<String, dynamic> player(int id, int? amount, {int year = 2026, String currency = 'JPY'}) => {
    'id_player': id, 'name': '選手$id',
    'salary_history': [{'year': year, 'amount': amount, 'currency': currency}],
  };
  final team = <String, dynamic>{'id_team': 1, 'name_team': 'テスト球団', 'color_back': '#FFCC00', 'contracts': [
    player(1, 300000000), player(2, 100000000), player(1, 300000000),
    player(3, null), player(4, 900000000, year: 2025), player(5, 2000000, currency: 'USD'),
  ]};
  test('年度・通貨別に重複と未取得を除いて割合を計算する', () {
    final groups = teamSalaryShares(team, 2026);
    expect(groups['JPY']!.length, 2);
    expect(groups['JPY']!.map((p) => p['share']), [.75, .25]);
    expect(groups['USD']!.single['share'], 1);
    expect(teamSalaryShares(team, 2024), isEmpty);
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets('$width幅で帯と内訳を表示できる', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TeamSalaryShareBands(teams: [team, {'id_team': 2, 'name_team': '半額球団', 'contracts': [player(6, 200000000)]}], year: 2026)))));
      expect(tester.takeException(), isNull);
      final fullWidth = tester.getSize(find.byKey(const ValueKey('salary-share-band-1-JPY'))).width;
      final halfWidth = tester.getSize(find.byKey(const ValueKey('salary-share-band-2-JPY'))).width;
      final fullNote = tester.getSize(find.byKey(const ValueKey('salary-banknote-1-JPY')));
      final halfNote = tester.getSize(find.byKey(const ValueKey('salary-banknote-2-JPY')));
      expect(fullNote, const Size(58, 64));
      expect(halfNote, fullNote);
      expect(halfWidth - halfNote.width, closeTo((fullWidth - fullNote.width) / 2, .01));
      expect(find.text('75.0%'), findsOneWidget);
      await tester.tap(find.text('75.0%'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('選手2'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
