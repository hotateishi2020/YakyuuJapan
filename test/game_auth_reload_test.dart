import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/pages/prediction_page.dart';
import 'package:Yakyuu_Japan/widgets/app_section_tabs.dart';

void main() {
  testWidgets('login during anonymous games request refetches for both privileged accounts', (tester) async {
    final pending = Completer<void>();
    final requests = <http.Request>[];
    final session = AuthSession.instance;
    var failGames = false;
    Future<void> frames() async {
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PredictionPage())));
      await frames();
      expect(requests.any((r) => r.url.queryParameters['part'] == 'games'), isTrue);
      session.token = 'user-1';
      session.user = AuthUser.fromJson({'id': 1});
      await frames();
      pending.complete();
      await frames();
      for (final id in [1, 2]) {
        if (id == 2) {
          session.token = 'user-2';
          session.user = AuthUser.fromJson({'id': 2});
          await frames();
        }
        expect(requests.any((r) =>
            r.url.queryParameters['part'] == 'games' &&
            r.url.queryParameters['fresh'] == '1' &&
            r.headers['Authorization'] == 'Bearer user-$id'), isTrue);
      }
      // No live state is available, and a transient request fails. HOME must
      // still poll on every tick instead of waiting for known live data.
      final tabs = tester.widgetList<AppSectionTabs>(find.byType(AppSectionTabs))
          .firstWhere((w) => w.tabs.any((tab) => tab.$1.contains('HOME')));
      tabs.onSelected(4);
      await frames();
      failGames = true;
      requests.clear();
      await tester.pump(const Duration(seconds: 10));
      await frames();
      expect(requests.any((r) => r.url.queryParameters['part'] == 'games'), isTrue);
      failGames = false;
      requests.clear();
      await tester.pump(const Duration(seconds: 10));
      await frames();
      expect(requests.any((r) => r.url.queryParameters['part'] == 'games'), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 21));
      session.user = null;
      session.token = null;
    }, () => MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/predictions/part' &&
          request.url.queryParameters['part'] == 'games' &&
          !request.headers.containsKey('Authorization')) {
        await pending.future;
      }
      if (failGames && request.url.queryParameters['part'] == 'games') {
        return http.Response('{}', 503);
      }
      if (request.url.path == '/predictions/live-details') return http.Response('', 204);
      if (['/predictions/part', '/home', '/records'].contains(request.url.path)) {
        return http.Response(jsonEncode({'games': [], 'stats_team': [], 'stats_player': []}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{}', 401);
    }));
  });
}
