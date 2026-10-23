import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/season_schedule_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  setUp(HomeCalendarCache.clear);
  tearDown(HomeCalendarCache.clear);

  testWidgets('HOMEは週・月で取得を共有しタイマー・復帰・再表示でも再取得しない', (tester) async {
    final requests=<String>[];
    await http.runWithClient(() async {
      Widget calendars(int year) => MaterialApp(home: Scaffold(body: Column(children:[
        Expanded(child: HomeSeasonCalendar(year:year,weekStart:DateTime(year,10,18))),
        Expanded(child: HomeSeasonCalendar(year:year)),
      ])));
      await tester.pumpWidget(calendars(2026));
      await tester.pumpAndSettle();
      expect(requests.length,2);
      await tester.pump(const Duration(minutes:3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(requests.length,2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(calendars(2026));
      await tester.pumpAndSettle();
      expect(requests.length,2);
      await tester.pumpWidget(calendars(2027));
      await tester.pumpAndSettle();
      expect(requests.length,4);
      await tester.pumpWidget(calendars(2026));
      await tester.pumpAndSettle();
      expect(requests.length,4);
      expect(requests.toSet(),hasLength(4));
      expect(tester.takeException(),isNull);
    },()=>MockClient((request) async {
      requests.add(request.url.query);
      return http.Response(jsonEncode({'games':[],'events':[]}),200);
    }));
  });

  testWidgets('HOMEの取得失敗や集計待ちは保存せず再試行する', (tester) async {
    var requests=0;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:SeasonScheduleLoader(
        org:OrgConfig.npb,year:2026,reuseLoaded:true,builder:(_)=>const SizedBox(),
      ))));
      await tester.pumpAndSettle();
      expect(find.text('再読み込み'),findsOneWidget);
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('集計待ち'),findsOneWidget);
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(requests,3);
      expect(find.text('再読み込み'),findsNothing);
      expect(HomeCalendarCache.contains(OrgConfig.npb,2026),isTrue);
    },()=>MockClient((_) async {
      requests++;
      if(requests==1)return http.Response('',500);
      return http.Response(jsonEncode(requests==2?{'pending':true,'message':'集計待ち'}:{'games':[],'events':[]}),200,
        headers:{'content-type':'application/json; charset=utf-8'});
    }));
  });

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
