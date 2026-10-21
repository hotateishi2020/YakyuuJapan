import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/season_schedule_board.dart';
import 'package:Yakyuu_Japan/View/season_titles_board.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  for (final entry in <String,Widget>{
    'schedule': SeasonScheduleLoader(org: OrgConfig.npb, year: 2026, builder: (_) => const SizedBox()),
    'titles': const SeasonTitlesBoard(org: OrgConfig.npb, year: 2026),
    'timeline': const RecordsBoard(org: OrgConfig.npb, year: 2026),
  }.entries) {
    testWidgets('${entry.key}の未集計状態は準備中と再読み込みを表示する', (t) async {
      await http.runWithClient(() async {
        await t.pumpWidget(MaterialApp(home: Scaffold(body: entry.value)));
        await t.pumpAndSettle();
        expect(find.text('表示データを準備中'), findsOneWidget);
        expect(find.text('再読み込み'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }, () => MockClient((request) async {
        if (entry.key != 'schedule') expect(request.url.queryParameters['section'], entry.key);
        return http.Response(jsonEncode({'pending': true, 'message': '表示データを準備中'}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
      }));
    });
  }
}
