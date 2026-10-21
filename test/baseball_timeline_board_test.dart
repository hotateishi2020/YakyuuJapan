import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('年表の追加5列を幅$widthで表示する', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
            home:
                Scaffold(body: RecordsBoard(org: OrgConfig.npb, year: 2026))));
        await tester.pumpAndSettle();
        expect(find.text('交流1位'), findsOneWidget);
        expect(find.byTooltip('福岡ソフトバンクホークス'), findsWidgets);
        expect(recordTabs.first, '🗓️年表');
        for (final title in ['日本\nシリーズ\n進出', 'FINAL\nSTAGE\n敗退', '1st\nSTAGE\n敗退']) {
          expect(find.text(title), findsOneWidget);
        }
        final finalColumn = find.byKey(const ValueKey('timeline-cs_final_winner-2025-1'));
        final firstColumn = find.byKey(const ValueKey('timeline-cs_final_loser-2025-1'));
        final lostColumn = find.byKey(const ValueKey('timeline-cs_first_loser-2025-1'));
        expect(find.descendant(of: finalColumn, matching: find.byTooltip('横浜DeNAベイスターズ')), findsOneWidget);
        expect(find.descendant(of: firstColumn, matching: find.byTooltip('読売ジャイアンツ')), findsOneWidget);
        expect(find.descendant(of: lostColumn, matching: find.byTooltip('阪神タイガース')), findsOneWidget);
        expect(find.descendant(of: finalColumn, matching: find.text('横浜DeNAベイスターズ')), findsNothing);
        expect(find.descendant(of: firstColumn, matching: find.text('読売ジャイアンツ')), findsNothing);
        expect(tester.getTopLeft(finalColumn).dx, lessThan(tester.getTopLeft(firstColumn).dx));
        expect(tester.getTopLeft(firstColumn).dx, lessThan(tester.getTopLeft(lostColumn).dx));
        expect(find.byKey(const ValueKey('interleague-rank-2025-11')), findsOneWidget);
        expect(find.text(width < 600 ? '交11位' : '交流戦11位'), findsNothing);
        final csToggle = find.byKey(const ValueKey('timeline-show-cs'));
        final rankX = tester.getTopLeft(find.byKey(const ValueKey('interleague-rank-2025-1'))).dx;
        await tester.tap(csToggle);
        await tester.pumpAndSettle();
        for (final column in [finalColumn, firstColumn, lostColumn]) {
          expect(column, findsNothing);
        }
        for (final title in ['日本\nシリーズ\n進出', 'FINAL\nSTAGE\n敗退', '1st\nSTAGE\n敗退']) {
          expect(find.text(title), findsNothing);
        }
        expect(tester.getTopLeft(find.byKey(const ValueKey('interleague-rank-2025-1'))).dx,
            lessThan(rankX));
        await tester.tap(csToggle);
        await tester.pumpAndSettle();
        for (final column in [finalColumn, firstColumn, lostColumn]) {
          expect(column, findsOneWidget);
        }
        expect(tester.getTopLeft(find.byKey(const ValueKey('interleague-rank-2025-1'))).dx,
            closeTo(rankX, .01));
        final rowBefore = tester.getSize(find.byKey(const ValueKey('standings-year-2025'))).height;
        await tester.tap(find.byKey(const ValueKey('timeline-show-events')));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byKey(const ValueKey('standings-year-2025'))).height, lessThan(rowBefore));
        expect(find.byKey(const ValueKey('interleague-rank-2025-11')), findsOneWidget);
        expect(find.text(width < 600 ? '交11位' : '交流戦11位'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('timeline-show-events')));
        await tester.pumpAndSettle();
        final scroll =
            find.byKey(const ValueKey('standings-horizontal-scroll'));
        final fixedYear = find.byKey(const ValueKey('timeline-fixed-year-2025'));
        final yearX = tester.getTopLeft(fixedYear).dx;
        final yearY = tester.getTopLeft(fixedYear).dy;
        await tester.drag(scroll, const Offset(-1800, 0));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(fixedYear).dx, closeTo(yearX, .01));
        expect(tester.getTopLeft(fixedYear).dy, closeTo(yearY, .01));

        await tester.pumpAndSettle();
        for (final title in ['ルール変更', '選手採用規約', '記録', '事件', '国際大会結果']) {
          expect(find.text(title), findsOneWidget);
        }
        expect(find.byKey(const ValueKey('timeline-2025-records')),
            findsOneWidget);
        expect(
            tester
                .getSize(find.byKey(const ValueKey('standings-year-2025')))
                .height,
            tester
                .getSize(find.byKey(const ValueKey('standings-year-2024')))
                .height);
        final cell =
            find.byKey(const ValueKey('timeline-cell-scroll-2025-records'));
        await Scrollable.ensureVisible(tester.element(cell), alignment: .5);
        await tester.pumpAndSettle();
        await tester.drag(cell, const Offset(0, -40));
        await tester.pumpAndSettle();
        final cellScroll = tester.state<ScrollableState>(
            find.descendant(of: cell, matching: find.byType(Scrollable)));
        expect(cellScroll.position.pixels, greaterThan(0));
        final outer = tester.state<ScrollableState>(find.descendant(
            of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
        outer.position.jumpTo(outer.position.maxScrollExtent / 2);
        await tester.pump();
        final headerY = tester.getTopLeft(find.text('年度')).dy;
        outer.position.jumpTo(outer.position.pixels + 100);
        await tester.pump();
        expect(tester.getTopLeft(find.text('年度')).dy, headerY);
        expect(tester.getTopLeft(find.text('1位')).dy, headerY);
        outer.position.jumpTo(outer.position.maxScrollExtent);
        await tester.pump();
        final oldHeader = find.byKey(const ValueKey('timeline-header-2025'));
        expect(oldHeader, findsOneWidget);
        expect(find.byKey(const ValueKey('interleague-rank-2000-12')), findsOneWidget);
        final oldRank = find.byKey(const ValueKey('interleague-rank-2000-1'));
        final interleagueHeaderCell = find.ancestor(of: find.descendant(of: oldHeader, matching: find.text('交流1位')), matching: find.byType(Container)).first;
        expect(tester.getTopLeft(oldRank).dx, closeTo(tester.getTopLeft(interleagueHeaderCell).dx, .01));
        expect(find.descendant(of: oldHeader, matching: find.text('交流1位')), findsOneWidget);
        expect(find.descendant(of: oldHeader, matching: find.text('6位')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
          () => MockClient((_) async => http.Response(
              jsonEncode({
                'timeline': [
                  for (final category in [
                    'rules',
                    'recruitment',
                    'records',
                    'incidents',
                    'international'
                  ])
                    {
                      'year': 2025,
                      'category': category,
                      'text': '年度別の出来事と出典を表示。' * 8,
                      'source': 'https://npb.jp/'
                    }
                ],
                'standings': [
                  {
                    'year': 2025,
                    'interleague_champion': {
                      'id_team': 7,
                      'name': '福岡ソフトバンクホークス'
                    },
                    'leagues': [
                      {
                        'id_league': 1,
                        'name': 'セ・リーグ',
                        'cs_final_winner': 3,
                        'cs_final_loser': 1,
                        'cs_first_winner': 3,
                        'cs_first_loser': 2,
                        'teams': [
                          {'id_team': 3, 'name': '横浜DeNAベイスターズ'},
                          {'id_team': 2, 'name': '阪神タイガース'},
                          {'id_team': 1, 'name': '読売ジャイアンツ', 'champion': true, 'interleague_rank': 11}
                        ]
                      }
                    ]
                  },
                  for (var pastYear = 2024; pastYear >= 2000; pastYear--)
                  {
                    'year': pastYear,
                    'leagues': [
                      {
                        'id_league': 1,
                        'name': 'セ・リーグ',
                        'teams': [
                          {'id_team': 1, 'name': '読売ジャイアンツ'},
                        ]
                      }
                    ]
                  },
                ]
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'})));
    });
  }
}
