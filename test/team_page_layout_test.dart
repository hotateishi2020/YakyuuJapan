import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/club_hub_board.dart';
import 'package:Yakyuu_Japan/View/team_strength_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  for (final org in [OrgConfig.npb, OrgConfig.mlb]) {
    testWidgets('${org.label}チームは全項目を展開し全体だけでスクロールする', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await http.runWithClient(() async {
        await t.pumpWidget(MaterialApp(home: Scaffold(body: TeamStrengthBoard(
          org: org, year: 2026, initialView: 8, providedTeams: [{
            'id_team': 1, 'name_team': '球団',
            'roster': [for (var i=0; i<50; i++) {
              'player_key': 'test:$i', 'name': '選手$i', 'position_group': '投手', 'throws': '右', 'bats': '右',
              'birth_place': '佐賀', 'date_birth': '2000-01-01',
              'career_history': [{'category': '高校', 'team': 'テスト高校'}],
            }],
            'pitching_workload': [{'name': '負担率選手', 'total_outs': 90}],
          }],
        ))));
        await t.pumpAndSettle();
        final hub = find.byType(ClubHubBoard);
        expect(find.byKey(const ValueKey('strength-view-1')), findsNothing);
        expect(find.descendant(of: hub, matching: find.text('選手起用')), findsOneWidget);
        expect(find.descendant(of: hub, matching: find.text('各投手の投球回・負担率')), findsNothing);
        expect(find.descendant(of: hub, matching: find.text('契約')), findsNothing);
        expect(find.descendant(of: hub, matching: find.text('ドラフト')), findsNothing);
        expect(find.descendant(of: hub, matching: find.byType(ChoiceChip)), findsNothing);
        expect(find.descendant(of: hub, matching: find.byType(ExpansionTile)), findsNothing);
        expect(find.descendant(of: hub, matching: find.byType(Scrollable)), findsNWidgets(2));
        expect(find.descendant(of: hub, matching: find.text('選手49')), findsWidgets);
        expect(find.descendant(of: hub, matching: find.text('経歴')), findsNothing);
        expect(find.descendant(of: hub, matching: find.text('自主トレ')), findsNothing);
        expect(find.descendant(of: hub, matching: find.byType(DataTable)), findsOneWidget);
        expect(find.descendant(of: hub, matching: find.text('出身地')), findsNothing);
        final scroll = t.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('team-page-vertical-scroll')), matching: find.byType(Scrollable)).first);
        expect(scroll.position.maxScrollExtent, greaterThan(800));
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await t.pump();
        expect(find.text('スポンサー・広告'), findsOneWidget);
        expect(t.takeException(), isNull);
      }, () => MockClient((_) async => http.Response(jsonEncode({'clubs': [], 'training_groups': []}), 200)));
    });
  }
}
