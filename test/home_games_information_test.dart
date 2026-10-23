import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/pages/prediction_page.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/View/home_board.dart';
import 'package:Yakyuu_Japan/widgets/navigation_picker.dart';

void main() {
  testWidgets('試合情報はHOMEのカレンダーと順位の間でNPB・MLBを切り替える', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final requests = <Uri>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PredictionPage())));
      for (var i = 0; i < 20; i++) { await tester.pump(const Duration(milliseconds: 20)); }
      expect(tester.widgetList<NavigationPicker>(find.byType(NavigationPicker))
          .any((picker) => picker.labels.values.any((label) => label.contains('試合情報'))), isFalse);
      await tester.tap(find.byKey(const ValueKey('navigation-picker-0')));
      await tester.pump();
      await tester.tap(find.text('🏠HOME').last);
      for (var i = 0; i < 20; i++) { await tester.pump(const Duration(milliseconds: 20)); }
      final home = tester.widget<HomeBoard>(find.byType(HomeBoard));
      expect(home.gameInformation, isNotNull);
      expect(tester.getTopLeft(find.text('今週のカレンダー（NPB・MLB）')).dy,
          lessThan(tester.getTopLeft(find.text('試合情報')).dy));
      final mlb = find.byKey(const ValueKey('home-games-mlb'));
      await tester.ensureVisible(mlb);
      await tester.pump();
      expect(tester.widget<BothLeagueGameDay>(find.byType(BothLeagueGameDay)).leagues.map((l) => l.id), [1, 2]);
      await tester.tap(mlb);
      for (var i = 0; i < 20; i++) { await tester.pump(const Duration(milliseconds: 20)); }
      expect(find.byType(HomeBoard), findsOneWidget);
      expect(tester.widget<ChoiceChip>(mlb).selected, isTrue);
      expect(tester.widget<BothLeagueGameDay>(find.byType(BothLeagueGameDay)).leagues.map((l) => l.id), [3, 4]);
      expect(requests.any((uri) => uri.queryParameters['org'] == 'mlb' && uri.queryParameters['part'] == 'games'), isTrue);
      await tester.tap(find.byKey(const ValueKey('home-games-npb')));
      for (var i = 0; i < 20; i++) { await tester.pump(const Duration(milliseconds: 20)); }
      expect(tester.widget<BothLeagueGameDay>(find.byType(BothLeagueGameDay)).leagues.map((l) => l.id), [1, 2]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 21));
    }, () => MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/predictions/part' || request.url.path == '/home') {
        return http.Response(jsonEncode({'today': '2026-10-24', 'games': [], 'stats_team': []}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{}', 401);
    }));
  });
}
