import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/additional_records_board.dart';

void main() {
  testWidgets(
      'historical regulars load independently and retain year/position/order',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(3200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: RegularHistoryLoader(org: 'npb', year: 2026))));
      await tester.pumpAndSettle();
      expect(find.text('1981年'), findsOneWidget);
      expect(find.text('昔の投手'), findsOneWidget);
      expect(find.text('昔の捕手'), findsOneWidget);
      await tester.tap(find.text('打順'));
      await tester.pumpAndSettle();
      expect(find.text('昔の一番'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              expect(request.url.path, endsWith('/regular-history'));
              return http.Response(
                  jsonEncode({
                    'regular_history': [
                      {
                        'id_team': 1,
                        'name_team': '巨人',
                        'year': 1981,
                        'source_label': 'スタメンデータベース',
                        'positions': [
                          {
                            'slot': 'P',
                            'total': 130,
                            'players': [
                              {'name': '昔の投手', 'count': 30}
                            ]
                          },
                          {
                            'slot': 'C',
                            'total': 130,
                            'players': [
                              {'name': '昔の捕手', 'count': 100}
                            ]
                          },
                        ],
                        'batting_order': [
                          {
                            'slot': 1,
                            'total': 130,
                            'players': [
                              {'name': '昔の一番', 'count': 100}
                            ]
                          }
                        ]
                      }
                    ]
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
  });
}
