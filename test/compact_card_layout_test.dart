import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/compact_card_layout.dart';

void main() {
  testWidgets('短い列に続けて配置し画面幅の変更にも追従する', (tester) async {
    Widget layout(int columns) => MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 648, child: CompactCardLayout(columns: columns, children: [
        for (final height in [200.0, 60.0, 80.0])
          SizedBox(key: ValueKey(height), height: height),
      ])),
    )));
    await tester.pumpWidget(layout(2));
    final first = tester.getRect(find.byKey(const ValueKey(200.0)));
    final second = tester.getRect(find.byKey(const ValueKey(60.0)));
    final third = tester.getRect(find.byKey(const ValueKey(80.0)));
    expect(first.width, 320);
    expect(third.left, second.left);
    expect(third.top, second.bottom + 8);
    expect(tester.getSize(find.byType(CompactCardLayout)).height, 200);
    await tester.pumpWidget(layout(1));
    expect(tester.getRect(find.byKey(const ValueKey(80.0))).top, 276);
    expect(tester.takeException(), isNull);
  });
}
