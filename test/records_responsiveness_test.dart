import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  testWidgets('151年度でも表示範囲だけを描画し、再訪時に再取得しない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(3200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final requests = <Uri>[];
    final titles = [for (var year = 2026; year >= 1876; year--)
      {'year': year, 'league': 'ア・リーグ', 'categories': [
        {'label': '本塁打王', 'players': [
          {'name': '年度$yearの選手', 'team': 'Yankees', 'value': 50, 'unit': '本'}
        ]}
      ]}
    ];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: RecordsBoard(org: OrgConfig.mlb, year: 2026))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('records-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('年度2026の選手'), findsOneWidget);
      expect(find.text('年度1876の選手'), findsNothing);
      expect(requests.any((uri) => uri.queryParameters['section'] == 'record_titles'), isTrue);
      final body = tester.widget<ListView>(find.byKey(const ValueKey('title-body-scroll')));
      body.controller!.jumpTo(150 * 60);
      await tester.pumpAndSettle();
      expect(find.text('年度1876の選手'), findsOneWidget);
      expect(find.byKey(const ValueKey('title-fixed-year-1876')), findsOneWidget);
      final count = requests.length;
      await tester.tap(find.byKey(const ValueKey('records-tab-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('records-tab-1')));
      await tester.pumpAndSettle();
      expect(requests.length, count);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async {
      requests.add(request.url);
      return http.Response(jsonEncode({'titles': titles}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
}
