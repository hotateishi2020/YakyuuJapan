import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/club_hub_board.dart';
import 'package:Yakyuu_Japan/View/team_strength_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  testWidgets('スマホでは12球団の最短名が一行に収まる', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 800);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: TeamStrengthBoard(
        org: OrgConfig.npb, year: 2026, initialView: 8,
        providedTeams: [for (var i=1;i<=12;i++) {'id_team':i, 'name_team':'球団$i', 'name_shortest':'短$i'}],
      ))));
      await t.pumpAndSettle();
      final first = find.byKey(const ValueKey('team-tab-segment-1'));
      for (var i=1;i<=12;i++) {
        final segment = find.byKey(ValueKey('team-tab-segment-$i'));
        expect(t.getTopLeft(segment).dy, t.getTopLeft(first).dy);
        expect(t.getBottomRight(segment).dx, lessThanOrEqualTo(390));
        expect(find.descendant(of: segment, matching: find.text('短$i')), findsOneWidget);
      }
      final firstSection = find.byKey(const ValueKey('team-section-segment-0'));
      for (var i=0;i<7;i++) {
        final section = find.byKey(ValueKey('team-section-segment-$i'));
        expect(t.getTopLeft(section).dy, t.getTopLeft(firstSection).dy);
        expect(t.getBottomRight(section).dx, lessThanOrEqualTo(390));
      }
      expect(t.takeException(), isNull);
      t.view.physicalSize = const Size(1400, 900);
      await t.pumpAndSettle();
      for (var i=0;i<7;i++) {
        final section = find.byKey(ValueKey('team-section-segment-$i'));
        expect(t.getSize(section).width, lessThan(100));
        expect(t.getTopLeft(section).dy, t.getTopLeft(firstSection).dy);
        if (i > 0) {
          final previous = find.byKey(ValueKey('team-section-segment-${i-1}'));
          expect(t.getTopLeft(section).dx - t.getBottomRight(previous).dx, closeTo(2, .01));
        }
      }
      expect(t.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{"clubs":[]}', 200)));
  });
  for (final org in [OrgConfig.npb, OrgConfig.mlb]) {
    testWidgets('${org.label}チームは項目セグメントで選択した内容だけを表示する', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 800));
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 800);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await http.runWithClient(() async {
        await t.pumpWidget(MaterialApp(
            home: Scaffold(
                body: TeamStrengthBoard(
          org: org,
          year: 2026,
          initialView: 8,
          providedTeams: [
            {
              'id_team': 1,
              'name_team': '球団',
              'roster': [
                for (var i = 0; i < 50; i++)
                  {
                    'player_key': 'test:$i',
                    'name': '選手$i',
                    'position_group': '投手',
                    'throws': '右',
                    'bats': '右',
                    'birth_place': '佐賀',
                    'date_birth': '2000-01-01',
                    'career_history': [
                      {'category': '高校', 'team': 'テスト高校'}
                    ],
                  }
              ],
              'pitching_workload': const [
                {'name': '負担率選手', 'total_outs': 90}
              ],
            }
          ],
        ))));
        await t.pumpAndSettle();
        final hub = find.byType(ClubHubBoard);
        expect(find.byKey(const ValueKey('strength-view-1')), findsNothing);
        expect(find.descendant(of: hub, matching: find.text('選手起用')), findsOneWidget);
        expect(find.descendant(of: hub, matching: find.text('各投手の投球回・負担率')), findsNothing);
        expect(find.descendant(of: hub, matching: find.byType(ChoiceChip)), findsNWidgets(7));
        expect(find.byKey(const ValueKey('analysis-vertical-table')), findsOneWidget);
        expect(t.getSize(find.byKey(const ValueKey('analysis-vertical-table'))).width, lessThanOrEqualTo(390));
        final analysis = t.widget<Table>(find.byKey(const ValueKey('analysis-vertical-table')));
        expect(find.descendant(of: find.byKey(const ValueKey('analysis-vertical-table')), matching: find.text('球団')), findsNothing);
        for (final row in analysis.children) {
          expect(t.getSize(find.byWidget(row.children.first)).height,
              t.getSize(find.byWidget(row.children.last)).height);
        }

        expect(find.byKey(const ValueKey('team-section-horizontal-分析')), findsNothing);
        expect(find.byKey(const ValueKey('team-section-horizontal-主力選手')), findsNothing);
        await t.tap(find.byKey(const ValueKey('team-section-segment-2')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('analysis-vertical-table')), findsNothing);
        expect(find.byKey(const ValueKey('regular-vertical-table-true')), findsOneWidget);
        expect(find.text('1番'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('team-section-segment-5')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('team-section-horizontal-主力選手')), findsNothing);
        expect(find.byKey(const ValueKey('team-section-horizontal-選手一覧')), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, '年齢順'), findsOneWidget);
        expect(find.byKey(const ValueKey('team-section-segment-7')), findsNothing);
        expect(find.text('スポンサー・広告'), findsNothing);
        expect(t.takeException(), isNull);
      }, () => MockClient((_) async => http.Response(jsonEncode({'clubs': [], 'training_groups': []}), 200)));
    });
  }
}
