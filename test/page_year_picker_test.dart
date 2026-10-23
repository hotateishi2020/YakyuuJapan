import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/pages/prediction_page.dart';
import 'package:Yakyuu_Japan/widgets/navigation_picker.dart';
import 'package:Yakyuu_Japan/View/season_titles_board.dart';

void main() {
  for (final width in [375.0, 1400.0]) {
    testWidgets('年度pickerは階層行の右端に固定し各画面の年度を変更する width=$width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <Uri>[];
      Future<void> frames() async {
        for (var i = 0; i < 15; i++) { await tester.pump(const Duration(milliseconds: 20)); }
      }
      NavigationPicker pickerWith(String text) => tester.widgetList<NavigationPicker>(find.byType(NavigationPicker))
          .firstWhere((picker) => picker.labels.values.any((label) => label.contains(text)));
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PredictionPage())));
        await frames();
        var selectedYear = DateTime.now().year;
        for (final org in ['npb', 'mlb']) {
          pickerWith('HOME').onChanged(org == 'npb' ? 1 : 2);
          await frames();
          for (final tab in [1, 2, 8]) {
            pickerWith('チーム順位').onChanged(tab);
            await frames();
            final control = find.byKey(const ValueKey('page-year-picker'));
            final row = find.byKey(const ValueKey('page-navigation-row'));
            expect(control, findsOneWidget);
            expect(tester.getRect(control).right, closeTo(tester.getRect(row).right, .01));
            expect(tester.getCenter(control).dy, closeTo(tester.getCenter(row).dy, .01));
            expect(tester.getRect(control).right, lessThanOrEqualTo(width));
            requests.clear();
            selectedYear--;
            await tester.tap(control);
            await tester.pumpAndSettle();
            final item = find.byWidgetPredicate((w) => w is PopupMenuItem<int> && w.value == selectedYear);
            await tester.ensureVisible(item);
            await tester.tap(item);
            await frames();
            expect(find.descendant(of: control, matching: find.text('$selectedYear')), findsOneWidget);
            if (tab == 8) {
              expect(requests.any((uri) => uri.path == '/records' &&
                  uri.queryParameters['org'] == org && uri.queryParameters['year'] == '$selectedYear' &&
                  uri.queryParameters['section'] == 'titles'), isTrue);
              expect(tester.widget<SeasonTitlesBoard>(find.byType(SeasonTitlesBoard)).year, selectedYear);
            } else {
              expect(requests.any((uri) => uri.path == '/predictions/part' &&
                  uri.queryParameters['org'] == org && uri.queryParameters['year'] == '$selectedYear' &&
                  uri.queryParameters['part'] == (tab == 1 ? 'standings' : 'players')), isTrue);
            }
            expect(tester.takeException(), isNull);
          }
        }
        pickerWith('HOME').onChanged(4);
        await frames();
        expect(find.byKey(const ValueKey('page-year-picker')), findsNothing);
        expect(find.byTooltip('年度を選択'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 21));
      }, () => MockClient((request) async {
        requests.add(request.url);
        if (['/predictions/part', '/home', '/records'].contains(request.url.path)) {
          return http.Response(jsonEncode({'games': [], 'stats_team': [], 'stats_player': []}), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('{}', 401);
      }));
    });
  }
}
