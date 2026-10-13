import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/pages/prediction_page.dart';

void main() {
  testWidgets('順位の初回応答を待たずに個人成績を取得する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final standings = Completer<http.Response>();
    final parts = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/predictions/part') {
        final part = request.url.queryParameters['part']!;
        parts.add(part);
        if (part == 'standings' && !standings.isCompleted) return standings.future;
        return http.Response('{}', 200);
      }
      return http.Response('{}', 401);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PredictionPage())));
      await tester.pump();
      await tester.pump();
      expect(standings.isCompleted, isFalse);
      expect(parts, contains('players'));
      expect(parts.where((part) => part == 'players'), hasLength(1));
      standings.complete(http.Response('{}', 200));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 21));
    }, () => client);
  });

  for (final delayedPart in ['games', 'info']) {
    testWidgets('$delayedPart の初回取得と描画が終わるまで定期取得・復帰時の再取得を待つ', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<http.Response>();
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/predictions/ready') {
          return http.Response('', 204);
        }
        if (request.url.path == '/predictions/part') {
          if (request.url.queryParameters['part'] == delayedPart && !pending.isCompleted) {
            return pending.future;
          }
          return http.Response('{}', 200);
        }
        return http.Response('{}', 401);
      });
      Iterable<Uri> notifications() => requests.where((uri) => uri.path == '/predictions/ready');
      Iterable<Uri> polls() => requests.where((uri) =>
          uri.queryParameters['part'] == 'games' && uri.queryParameters['fresh'] == '1');

      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PredictionPage())));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 61));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(notifications(), isEmpty);
        expect(polls(), isEmpty);

        pending.complete(http.Response('{}', 200));
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump();
        }
        expect(notifications(), hasLength(1));
        expect(polls(), isEmpty);
        await tester.pump(const Duration(seconds: 61));
        await tester.pump();
        expect(polls(), hasLength(1));
        expect(notifications(), hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 21));
      }, () => client);
    });
  }

  testWidgets('試合の応答が遅くても順位と個人成績を取得してタブを表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final games = Completer<http.Response>();
    final requested = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/predictions/part') {
        final part = request.url.queryParameters['part']!;
        requested.add(part);
        if (part == 'games') return games.future;
        return http.Response(jsonEncode({
          'predict_team': [],
          'stats_team': [],
          'predict_player': [],
          'stats_player': [],
          'events': [],
          'notification': [],
        }), 200);
      }
      return http.Response('{}', 401);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PredictionPage())));
      await tester.pump();
      await tester.pump();

      expect(games.isCompleted, isFalse);
      expect(requested, containsAll(['games', 'standings', 'players', 'info']));
      expect(requested.where((part) => part == 'standings'), hasLength(1));
      expect(find.text('チーム順位'), findsOneWidget);
      expect(find.text('個人成績'), findsOneWidget);
      await tester.tap(find.text('チーム順位'));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 遅い試合取得が失敗しても、既に表示した順位タブは残す。
      games.complete(http.Response('{}', 503));
      await tester.pump();
      expect(find.text('チーム順位'), findsOneWidget);
      expect(find.text('HTTPエラー: 503'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 21));
    }, () => client);
  });
}
