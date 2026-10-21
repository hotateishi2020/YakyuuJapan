import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/baseball_catalog_boards.dart';

void main() {
  testWidgets('会員を候補から除外し100%超はオレンジ、90%以上は黄色にする', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = {
      'hall': [
        {'name': '新しい殿堂', 'year': 2025},
        {'name': '古い殿堂', 'year': 1959},
        {'name': '平岡 熈 【※「熈」は臣の左がにすい】', 'year': 1959},
      ],
      'members': [
        {'name': '髙橋 会員'},
        {'name': '新しい会員', 'joined_date': '2020-09-01'},
        {'name': '古い会員', 'joined_date': '2020-05-01'},
        {'name': '創設会員', 'membership_sort_date': '1978-07-24'},
        {'name': '特例会員', 'joined_date': '2022-12-09', 'membership_sort_date': '2018-07-20'},
      ],
      'candidates': [
        for (final entry in [
          ('高橋　会員', 2100),
          ('超過', 2001),
          ('達成', 2000),
          ('九割', 1800),
          ('未到達', 1799)
        ])
          {
            'name': entry.$1,
            'value': entry.$2,
            'target': 2000,
            'label': '安打',
            'remaining': 0
          },
      ],
    };
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: HallOfFameBoard(org: 'npb', year: 2026))));
      await tester.pumpAndSettle();
      expect(find.text('髙橋 会員'), findsOneWidget);
      expect(find.text('平岡 熈'), findsOneWidget);
      expect(find.textContaining('臣の左がにすい'), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('hall-card-hall-0')), matching: find.text('古い殿堂')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('hall-card-members-0')), matching: find.text('創設会員')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('hall-card-members-1')), matching: find.text('古い会員')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('hall-card-members-3')), matching: find.text('特例会員')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('hall-card-members-4')), matching: find.text('髙橋 会員')), findsOneWidget);
      expect(find.text('高橋　会員'), findsNothing);
      Color? cardColor(String name) => (tester
              .widget<Container>(find
                  .ancestor(
                      of: find.text(name),
                      matching: find.byWidgetPredicate((w) =>
                          w is Container && w.decoration is BoxDecoration))
                  .first)
              .decoration as BoxDecoration)
          .color;
      expect(cardColor('超過'), Colors.orange.shade100);
      expect(cardColor('達成'), Colors.yellow.shade100);
      expect(cardColor('九割'), Colors.yellow.shade100);
      expect(cardColor('未到達'), Colors.white);
      expect(cardColor('髙橋 会員'), Colors.white);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((_) async => http.Response(jsonEncode(data), 200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
  });
}
