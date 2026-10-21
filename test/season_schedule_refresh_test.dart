import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/season_schedule_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  testWidgets('開いた日程を1分ごとに再取得して変更を表示する', (tester) async {
    var requests = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SeasonScheduleLoader(
        org: OrgConfig.npb, year: 2026,
        builder: (_) => const SizedBox(),
        calendarBuilder: (games, events) => Column(children: [Text(games.isEmpty ? '' : '${games.first['time']}'), for (final e in events) Text('${e['title_event']}')]),
      ))));
      await tester.pumpAndSettle();
      expect(find.text('18:00'), findsOneWidget);
      expect(find.text('WBC チケット発売'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('19:00'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(find.text('19:00'), findsNothing);
      expect(find.text('WBC チケット発売'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
      expect(requests, 3);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async {
      requests++;
      return http.Response(jsonEncode({'events': requests >= 3 ? [] : [{'title_event':'WBC チケット発売'}], 'games': requests >= 3 ? [] : [{'time': requests == 1 ? '18:00' : '19:00'}]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
}
