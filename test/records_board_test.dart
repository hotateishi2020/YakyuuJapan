import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

final fixture = {
  'standings': [
    {
      'year': 2025,
      'champion': '優勝球団',
      'leagues': [
        {
          'name': 'セ・リーグ',
          'teams': [
            {
              'rank': 1,
              'name': '優勝球団',
              'wins': 90,
              'losses': 50,
              'draws': 3,
              'champion': true,
              'postseason': true
            }
          ]
        }
      ]
    }
  ],
  'titles': [
    {
      'year': 2025,
      'league': 'セ・リーグ',
      'categories': [
        {
          'label': '本塁打王',
          'players': [
            {'name': 'タイトル選手', 'value': 40, 'status': 'active'}
          ]
        },
        {
          'label': 'MVP',
          'players': [
            {'name': 'MVP選手', 'value': '受賞', 'status': 'active'}
          ]
        }
      ]
    }
  ],
  'season': [
    {
      'label': '本塁打',
      'unit': '本',
      'leaders': [
        {'name': '歴代選手', 'value': 60, 'status': 'retired'}
      ],
      'current': [
        {'name': '今季選手', 'value': 40, 'status': 'active'}
      ]
    }
  ],
  'career': [
    {
      'label': '安打',
      'unit': '安打',
      'leaders': [
        {'name': '引退選手', 'value': 3000, 'status': 'retired'},
        {'name': '現役選手', 'value': 2000, 'status': 'active'}
      ]
    }
  ],
  'streaks': [
    {
      'label': '連続安打（打席）',
      'unit': '打席',
      'leaders': [
        {'name': '歴代選手', 'value': 11, 'status': 'retired'}
      ],
      'current': [
        {'name': '今季選手', 'value': 5, 'status': 'active'}
      ],
      'current_note': '取得済み試合の確認範囲'
    }
  ],
};
void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('記録の全タブ・比較表示は幅$widthで収まる', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var requests = 0;
      final client = MockClient((r) async {
        requests++;
        return http.Response(jsonEncode(fixture), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
            home:
                Scaffold(body: RecordsBoard(org: OrgConfig.npb, year: 2026))));
        await tester.pumpAndSettle();
        expect(recordTabs, ['優勝チーム', '個人タイトル', 'シーズン記録', '通算記録', '連続記録', '功績']);
        expect(find.text('日本一：優勝球団'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('records-tab-1')));
        await tester.pumpAndSettle();
        expect(find.text('タイトル選手'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('records-tab-2')));
        await tester.pumpAndSettle();
        expect(find.text('歴代選手'), findsOneWidget);
        expect(find.text('今季選手'), findsOneWidget);
        expect(tester.getTopLeft(find.text('歴代選手')).dx,
            lessThan(tester.getTopLeft(find.text('今季選手')).dx));
        await tester.tap(find.byKey(const ValueKey('records-tab-3')));
        await tester.pumpAndSettle();
        expect(find.text('現役'), findsOneWidget);
        expect(find.text('引退'), findsOneWidget);
        final active = find
            .ancestor(of: find.text('現役選手'), matching: find.byType(Container))
            .first;
        final retired = find
            .ancestor(of: find.text('引退選手'), matching: find.byType(Container))
            .first;
        expect(tester.widget<Container>(active).color,
            isNot(tester.widget<Container>(retired).color));
        await tester.tap(find.byKey(const ValueKey('records-tab-4')));
        await tester.pumpAndSettle();
        expect(find.text('取得済み試合の確認範囲'), findsOneWidget);
        expect(requests, 1);
        expect(tester.takeException(), isNull);
      }, () => client);
    });
  }
  testWidgets('記録の取得失敗は再読み込みできる', (tester) async {
    var count = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: RecordsBoard(org: OrgConfig.mlb, year: 2026))));
      await tester.pumpAndSettle();
      expect(find.text('再読み込み'), findsOneWidget);
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('WS優勝：優勝球団'), findsOneWidget);
    },
        () => MockClient((_) async => ++count == 1
            ? http.Response('error', 500)
            : http.Response(jsonEncode(fixture), 200,
                headers: {'content-type': 'application/json; charset=utf-8'})));
  });
  testWidgets('団体変更前の遅延応答が新しい表示を上書きしない', (tester) async {
    final first = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: RecordsBoard(org: OrgConfig.npb, year: 2026))));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: RecordsBoard(org: OrgConfig.mlb, year: 2025))));
      await tester.pumpAndSettle();
      first.complete(http.Response(jsonEncode({'standings': []}), 200));
      await tester.pumpAndSettle();
      expect(find.text('WS優勝：優勝球団'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((r) async => r.url.queryParameters['org'] == 'npb'
            ? first.future
            : http.Response(jsonEncode(fixture), 200,
                headers: {'content-type': 'application/json; charset=utf-8'})));
  });
}
