import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/today_event_map.dart';
import 'package:Yakyuu_Japan/tools/home_data_cache.dart';

void main() {
  setUp(HomeDataCache.clear);
  testWidgets('スクロール・再訪・時間経過で再取得せず、更新ボタンだけ再取得する', (tester) async {
    var requests = 0;
    final scroll = ScrollController();
    Widget page() => MaterialApp(home: Scaffold(body: ListView(
      controller: scroll,
      children: const [TodayEventMap(key: ValueKey('map')), SizedBox(height: 2000)],
    )));
    await http.runWithClient(() async {
      await tester.pumpWidget(page());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('map-venue-dot')), findsNWidgets(2));
      expect(find.byTooltip('拡大'), findsNothing);
      expect(find.byTooltip('縮小'), findsNothing);
      final state = tester.state(find.byType(TodayEventMap));
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
      final zoom = map.camera.zoom + 1;
      map.move(map.camera.center, zoom);
      scroll.jumpTo(1600);
      await tester.pump();
      scroll.jumpTo(0);
      await tester.pump();
      expect(tester.state(find.byType(TodayEventMap)), same(state));
      expect(map.camera.zoom, closeTo(zoom, .001));
      await tester.pump(const Duration(minutes: 6));
      expect(requests, 1);
      await tester.tap(find.byTooltip('開催情報を更新'));
      await tester.pump();
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pump();
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((request) async {
      if (request.url.path == '/today-map') {
        requests++;
        return http.Response(jsonEncode({'date': '2026-10-28', 'games': [
          {'date_game': '2026-10-28', 'name_team_home': 'ソフトバンク', 'name_team_away': 'DeNA',
            'latitude': 33, 'longitude': 130, 'name_stadium': '福岡'},
          {'date_game': '2026-10-28', 'name_team_home': 'ホーム', 'name_team_away': 'ビジター',
            'latitude': 28, 'longitude': -82, 'name_stadium': '米国'},
        ], 'events': []}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response.bytes(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='), 200,
          headers: {'content-type': 'image/png'});
    }));
    scroll.dispose();
  });
}
