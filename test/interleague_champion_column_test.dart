import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('通常順位の右に交流戦1〜12位を幅$widthで表示する', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
          RecordsBoard(org: OrgConfig.npb, year: 2026))));
        await tester.pumpAndSettle();
        expect(find.text('交流1位'), findsOneWidget);
        expect(find.text('交流12位'), findsOneWidget);
        expect(tester.getTopLeft(find.text('交流1位')).dx,
            greaterThan(tester.getTopLeft(find.text('6位')).dx));
        final eleventh = find.byKey(const ValueKey('interleague-rank-2025-11'));
        expect(find.descendant(of: eleventh, matching: find.byTooltip('読売ジャイアンツ')), findsOneWidget);
        expect(find.text('交流戦11位'), findsNothing);
        expect(find.text('交11位'), findsNothing);
        expect(find.byTooltip('福岡ソフトバンクホークス'), findsWidgets);
        expect(find.text('阿部慎之助'), findsNothing);
        final originalWidth = tester.getSize(find.byKey(const ValueKey('standings-year-2025'))).width;
        await tester.tap(find.byKey(const ValueKey('timeline-show-interleague')));
        await tester.pumpAndSettle();
        expect(find.text('交流12位'), findsNothing);
        expect(find.byKey(const ValueKey('interleague-rank-2025-11')), findsNothing);
        expect(tester.getSize(find.byKey(const ValueKey('standings-year-2025'))).width, lessThan(originalWidth));
        await tester.tap(find.byKey(const ValueKey('timeline-show-managers')));
        await tester.pumpAndSettle();
        expect(find.text('阿部慎之助'), findsOneWidget);
        final champion = find.byKey(const ValueKey('champion-team-2025-1'));
        if (champion.evaluate().isNotEmpty) {
          expect(find.descendant(of: champion, matching: find.text('阿部慎之助')), findsNothing);
        }
        await tester.tap(find.byKey(const ValueKey('timeline-show-interleague')));
        await tester.pumpAndSettle();
        expect(find.text('阿部慎之助'), findsNWidgets(2));
        await tester.tap(find.byKey(const ValueKey('timeline-show-managers')));
        await tester.pumpAndSettle();
        expect(find.text('阿部慎之助'), findsNothing);
        expect(tester.takeException(), isNull);
      }, () => MockClient((_) async => http.Response(jsonEncode({'standings': [
        {'year': 2025, 'interleague_champion': {'id_team': 7, 'name': '福岡ソフトバンクホークス'},
          'leagues': [{'id_league': 1, 'name': 'セ・リーグ', 'teams': [
            {'id_team': 1, 'name': '読売ジャイアンツ', 'champion': true, 'interleague_rank': 11, 'manager': '阿部慎之助'}
          ]}]},
      ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
    });
  }
}
