import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_contracts.dart';
import 'package:Yakyuu_Japan/View/team_section_layout.dart';

void main() {
  testWidgets('スマホの球団契約は名前列80pxと当年列のみ表示', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 800);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: TeamSectionLayout(child: StrengthContracts(year: 2026, team: {
        'id_team': 1, 'name_team': '球団', 'id_league': 1,
        'contracts': [{'player_key': 'test', 'name': '契約選手', 'salary_history': [
          {'year': 2024, 'amount': 10000000}, {'year': 2026, 'amount': 20000000}
        ]}]
      })),
    ))));
    await t.pumpAndSettle();
    final scroll = t.widget<SingleChildScrollView>(find.byKey(const ValueKey('contract-horizontal-scroll'))).controller!;
    expect(scroll.offset, 0);
    expect(t.getSize(find.byKey(const ValueKey('contract-name-1-test'))).width, 80);
    expect(find.byKey(const ValueKey('contract-year-2026')), findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('contract-year-2026'))).width, 310);
    expect(t.getBottomRight(find.byKey(const ValueKey('contract-year-2026'))).dx, 390);
    expect(scroll.position.maxScrollExtent, 0);
    expect(find.byKey(const ValueKey('contract-year-2024')), findsNothing);
    expect(find.text('生涯年俸'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '生涯年俸順'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
