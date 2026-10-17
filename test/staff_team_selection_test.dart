import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/club_hub_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  for (final org in [OrgConfig.npb, OrgConfig.mlb]) {
    testWidgets('${org.label}首脳は選択球団だけ表示し再取得せず切り替える', (t) async {
      var requests = 0;
      await http.runWithClient(() async {
        await t.pumpWidget(MaterialApp(home: Scaffold(body: ClubHubBoard(
          org: org, year: 2026, teams: const [], view: 8,
          teamSection: (_, __) => const SizedBox.shrink(),
        ))));
        await t.pumpAndSettle();
        expect(find.text('A監督'), findsOneWidget);
        expect(find.text('B監督'), findsNothing);
        expect(find.text('Aスカウト'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('staff-team-selector')));
        await t.pumpAndSettle();
        await t.tap(find.text('球団B').last);
        await t.pumpAndSettle();
        expect(find.text('A監督'), findsNothing);
        expect(find.text('Aスカウト'), findsNothing);
        expect(find.text('B監督'), findsOneWidget);
        expect(find.text('Bスカウト'), findsOneWidget);
        expect(find.text('球団B　4軍'), findsOneWidget);
        expect(requests, 1);
        expect(t.takeException(), isNull);
      }, () => MockClient((_) async {
        requests++;
        return http.Response(jsonEncode({'clubs': [
          for (final key in ['A','B']) {'code':key,'name':'球団$key','staff':[
            {'name':'$key監督','role':'監督','category':'監督'},
            {'name':'$keyスカウト','role':'スカウト','category':'スカウト'},
          ]},
        ]}), 200, headers: {'content-type':'application/json; charset=utf-8'});
      }));
    });
  }
}
