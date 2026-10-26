import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_contracts.dart';

const salary = <String, dynamic>{
  'year': 2026, 'amount': 32000000, 'currency': 'USD', 'team': 'LAD',
  'team_shares': [
    {'team': 'DET', 'amount': 22193548, 'estimated': true},
    {'team': 'LAD', 'amount': 9806452, 'estimated': true},
  ],
};
void main() {
  test('日割り按分は負担確定額と区別し球団略称でも球団色を使う', () {
    expect(contractShareLabel(salary, {'team': 'LAD', 'amount': 9806452, 'estimated': true, 'method': 'tenure_estimate'}), 'LAD負担目安：約980.6万ドル');
    expect(contractTeamColor({'team': 'LAD'}, [{'name_team': 'ドジャース', 'color_back': 'blue'}]), const Color(0xff0000ff));
  });
  test('移籍した年度のみ負担額の比率で分割し前後の契約年を保持', () {
    final bands = contractTimelineBands([
      {'start_year': 2024, 'end_year': 2028, 'team': 'DET'}
    ], [salary]);
    expect(bands.where((b) => b['start_year'] == 2024).single['end_year'], 2025);
    expect(bands.where((b) => b['start_year'] == 2027).single['end_year'], 2028);
    final split = bands.where((b) => b['start_year'] == 2026).toList();
    expect(split.map((b) => b['team']), ['DET', 'LAD']);
    expect(split.first['width_fraction'], closeTo(22193548 / 32000000, 1e-9));
    expect(split.last['start_fraction'], split.first['width_fraction']);
    expect((split.first['width_fraction'] as double) + (split.last['width_fraction'] as double), closeTo(1, 1e-9));
    expect(contractSalaryShares({...salary, 'amount': 1}), isEmpty);
    expect(contractSalaryShares({'year': 2026, 'amount': 32000000}), isEmpty);
  });
  for (final size in [const Size(1400, 900), const Size(390, 844)]) {
    testWidgets('球団別負担額と比例ゲージを表示 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StrengthContracts(year: 2026, team: {
        'id_team': 40, 'id_league': 4, 'org': 'mlb', 'name_team': 'ドジャース',
        'contracts': [{'player_key': 'mlb:669373', 'name': 'スクバル', 'salary_history': [salary]}],
      }))));
      await tester.pumpAndSettle();
      expect(find.text('DET負担：約2219.3万ドル'), findsOneWidget);
      expect(find.text('LAD負担：約980.6万ドル'), findsOneWidget);
      final det = tester.getRect(find.byKey(const ValueKey('contract-band-mlb:669373-2026-DET')));
      final lad = tester.getRect(find.byKey(const ValueKey('contract-band-mlb:669373-2026-LAD')));
      expect(det.width / lad.width, closeTo(22193548 / 9806452, 1e-6));
      expect(det.right, closeTo(lad.left, .01));
      expect(tester.takeException(), isNull);
    });
  }
}
