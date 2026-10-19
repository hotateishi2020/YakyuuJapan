import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';

void main() {
  testWidgets('狭い画面で戦力外は白、新戦力は前所属色とラベルを表示', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final team = <String, dynamic>{
      'id_team': 3,
      'name_team': '中日',
      'roster': [
        {
          'name': '退団選手',
          'player_key': 'old',
          'position_group': '外野手',
          'bats': '左',
          'departure_confirmed': true,
          'departure_type': 'non_tender'
        },
        {
          'name': 'ウォード',
          'player_key': 'ward',
          'position_group': '外野手',
          'bats': '左',
          'new_arrival': true,
          'arrival_year': 2026,
          'previous_team': {
            'name': 'ドジャース',
            'label': 'LAD',
            'color_back': '#005A9C',
            'color_font': '#FFFFFF'
          }
        },
      ]
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StrengthRosterGrid(team: team, year: 2026))));
    expect(find.text('新戦力'), findsOneWidget);
    expect(find.text('LAD'), findsOneWidget);
    final card =
        tester.widget<Container>(find.byKey(const ValueKey('roster-card-old')));
    expect((card.decoration as BoxDecoration).color, Colors.white);
    final labels = tester.widgetList<Container>(
        find.ancestor(of: find.text('LAD'), matching: find.byType(Container)));
    expect(labels.any((c) => c.color == const Color(0xFF005A9C)), true);
    expect(tester.takeException(), isNull);
  });
}
