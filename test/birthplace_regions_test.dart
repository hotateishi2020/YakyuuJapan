import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_careers.dart';

void main() {
  final teams = <Map<String, dynamic>>[
    {
      'id_team': 1,
      'name_team': 'テスト球団',
      'roster': [
        {'name': '福岡選手', 'player_key': '1', 'birth_place': '福岡'},
        {
          'name': '佐賀選手',
          'player_key': '2',
          'birth_place': 'Saga',
          'birth_country': 'Japan'
        },
        {
          'name': '米国選手',
          'player_key': '3',
          'birth_country': 'USA',
          'birth_state': 'California'
        },
        {
          'name': '引退選手',
          'player_key': '4',
          'birth_place': '福岡',
          'active': false
        },
      ],
    }
  ];
  for (final width in [390.0, 1200.0]) {
    testWidgets('出身地は地域枠の中に都道府県と選手を配置する 幅$width', (t) async {
      await t.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
          MaterialApp(home: Scaffold(body: StrengthCareers(teams: teams))));
      await t.tap(find.text('出身地'));
      await t.pump();
      final kyushu = find.byKey(const ValueKey('birth-region-九州'));
      expect(find.descendant(of: kyushu, matching: find.text('福岡県  1人')),
          findsOneWidget);
      expect(find.descendant(of: kyushu, matching: find.text('佐賀県  1人')),
          findsOneWidget);
      expect(find.descendant(of: kyushu, matching: find.text('福岡選手')),
          findsOneWidget);
      expect(find.descendant(of: kyushu, matching: find.text('佐賀選手')),
          findsOneWidget);
      expect(find.text('引退選手'), findsNothing);
      expect(find.byKey(const ValueKey('birth-region-アメリカ')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
