import 'package:Yakyuu_Japan/widgets/navigation_picker.dart';
import 'package:Yakyuu_Japan/View/home_board.dart';
import 'dart:async';
import 'package:Yakyuu_Japan/View/Headers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/pages/prediction_page.dart';

void main() {
  testWidgets('API応答前にヘッダー配下の団体・情報タブを描画する', (tester) async {
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PredictionPage())));
      await tester.pump(const Duration(milliseconds: 1));
      final orgPicker = find.byKey(const ValueKey('navigation-picker-0'));
      final boardPicker = find.byKey(const ValueKey('navigation-picker-1'));
      expect(orgPicker, findsOneWidget);
      expect(boardPicker, findsOneWidget);
      expect(tester.widgetList<NavigationPicker>(find.byType(NavigationPicker)).any((picker) => picker.labels.values.contains('📅日程')), isFalse);
      expect(tester.getCenter(orgPicker).dy, tester.getCenter(boardPicker).dy);
      expect(find.byKey(const ValueKey('menu-visibility-toggle')), findsNothing);
      expect(pending.isCompleted, isFalse);
      expect(find.byType(HeaderAuthAction), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(orgPicker);
      await tester.pump();
      expect(tester.getTopLeft(find.text('🏠HOME').last).dy, lessThan(tester.getTopLeft(find.text('🇯🇵NPB').last).dy));
      await tester.tap(find.text('🏠HOME').last);
      await tester.pump();
      await tester.pump();
      expect(find.byType(HomeBoard), findsOneWidget);
      expect(find.byKey(const ValueKey('navigation-picker-1')), findsNothing);
      await tester.tap(orgPicker);
      await tester.pump();
      await tester.tap(find.text('⚾️その他').last);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('navigation-picker-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('navigation-picker-2')), findsOneWidget);
      expect(find.text('高校野球'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(http.Response('{}', 200));
      await tester.pump(const Duration(seconds: 21));
    }, () => MockClient((_) => pending.future));
  });
}
