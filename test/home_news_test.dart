import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/pages/prediction_page.dart';

void main() {
  testWidgets('HOME先頭のNewsは5行の枠内で末尾までスクロールできる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PredictionPage())));
      for (var i = 0; i < 12; i++) { await tester.pump(); }
      expect(find.byIcon(Icons.newspaper), findsNothing);
      await tester.tap(find.byKey(const ValueKey('navigation-picker-0')));
      await tester.pump();
      await tester.tap(find.text('🏠HOME').last);
      for (var i = 0; i < 12; i++) { await tester.pump(); }
      final news = find.byKey(const ValueKey('home-news'));
      final scroll = find.byKey(const ValueKey('home-news-scroll'));
      expect(news, findsOneWidget);
      final score = find.text('予想対決のスコア');
      expect(score, findsOneWidget);
      expect(tester.getRect(news).bottom, lessThan(tester.getRect(score).top));
      final navigation = find.byKey(const ValueKey('navigation-picker-0'));
      expect(find.descendant(of: navigation, matching: find.byType(DropdownButton<int>)), findsNothing);
      final tabs = ['🏠HOME', '🎯予想対決', '🇯🇵NPB', '🇺🇸MLB', '⚾️その他'];
      final top = tester.getRect(find.text(tabs.first)).top;
      for (final label in tabs) {
        expect(find.text(label), findsOneWidget);
        expect(tester.getRect(find.text(label)).top, closeTo(top, .1));
      }

      expect(tester.getSize(scroll).height, closeTo(110, .1));
      expect(tester.getRect(news).bottom,
          lessThan(tester.getRect(find.textContaining('HOME  ')).top));
      expect(find.text('ニュース1').hitTestable(), findsOneWidget);
      expect(find.text('ニュース6').hitTestable(), findsNothing);
      expect(find.text('ニュース12').hitTestable(), findsNothing);
      await tester.drag(scroll, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('ニュース12').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 21));
    }, () => MockClient((request) async {
      if (request.url.path == '/predictions/part' || request.url.path == '/home') {
        return http.Response(jsonEncode({
          'notification': [for (var i = 1; i <= 12; i++)
            {'title': 'ニュース$i', 'tag_main_title': 'MLB', 'tag_sub_title': '試合'}],
          'today': '2026-10-24',
        }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{}', 401);
    }));
  });
}
