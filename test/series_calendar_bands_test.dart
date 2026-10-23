import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/EventCalendar.dart';
void main() {
  for (final weekly in [true, false]) {
    testWidgets('シリーズ期間帯を${weekly ? '週' : '月'}表示で描く', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: EventCalendar(
        initialMonth: DateTime(2026,11),
        weekStart: weekly ? DateTime(2026,10,25) : null,
        events: [for (final title in ['日本シリーズ','ワールドシリーズ']) {
          'title_event':title, 'date_from_temp':'2026-10-24', 'date_to':'2026-11-01',
        }],
      ))));
      for (final title in ['日本シリーズ','ワールドシリーズ']) {
        expect(find.text(title),findsOneWidget);
        final bar=find.ancestor(of:find.text(title),matching:find.byType(Positioned));
        expect(tester.widget<Positioned>(bar).width, greaterThan(weekly ? 700 : 90));
      }
      expect(tester.takeException(),isNull);
    });
  }
}
