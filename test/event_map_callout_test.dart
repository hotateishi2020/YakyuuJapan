import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/today_event_map.dart';

void main() {
  testWidgets('吹き出しは端でも全文を収めて赤丸を開催地に残す', (tester) async {
    var taps = 0;
    for (final anchor in [const Offset(3, 3), const Offset(317, 3), const Offset(3, 397), const Offset(317, 397)]) {
      await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 320, height: 420,
        child: EventMapCallout(rows: const [{'kind': '試合', 'time': '18:00',
          'title': '長いイベント名でも省略せずに全文表示するソフトバンク対DeNA',
          'venue': 'みずほPayPayドーム福岡'}], accent: Colors.blue, anchor: anchor, onTap: () => taps++),
      ))));
      final bubble = find.byKey(const ValueKey('map-callout-bubble'));
      final callout = tester.getTopLeft(find.byType(EventMapCallout));
      final rect = tester.getRect(bubble).shift(-callout);
      expect(rect.left, greaterThanOrEqualTo(8));
      expect(rect.top, greaterThanOrEqualTo(8));
      expect(rect.right, lessThanOrEqualTo(312));
      expect(rect.bottom, lessThanOrEqualTo(396));
      final dot = find.byKey(const ValueKey('map-venue-dot'));
      expect(tester.getCenter(dot) - callout, anchor);
      for (final text in tester.widgetList<Text>(find.descendant(of: bubble, matching: find.byType(Text)))) {
        expect(text.maxLines, isNull);
        expect(text.overflow, isNull);
      }
      await tester.tap(bubble);
      expect(tester.takeException(), isNull);
    }
    expect(taps, 4);
  });

  test('短い内容は幅を縮め、隣の吹き出しを避ける', () {
    const rows = [{'kind': '試合', 'title': 'A vs B', 'venue': '東京'}];
    const size = Size(600, 420);
    const anchor = Offset(300, 200);
    final first = eventMapBubbleRect(rows, size, anchor, TextScaler.noScaling, TextDirection.ltr);
    final next = eventMapBubbleRect(rows, size, anchor, TextScaler.noScaling, TextDirection.ltr, [first]);
    expect(first.width, lessThan(100));
    expect(first.overlaps(next), isFalse);
    expect(first.bottom, anchor.dy - 24);
  });
}
