import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';

void main() {
  testWidgets(
      'measured progress, estimated cap, reduced motion and tight spaces',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: BaseballLoading(progress: .42)))));
    expect(find.text('42%'), findsOneWidget);
    expect(find.bySemanticsLabel('ノックを受けて捕球・送球する守備練習'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 420));
      expect(tester.takeException(), isNull);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(disableAnimations: true),
                child: Center(
                    child: BaseballLoading(key: ValueKey('estimate')))))));
    await tester.pump(const Duration(seconds: 600));
    expect(find.text('目安 95%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(width: 18, height: 18, child: BaseballLoading()))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('render baseball loading preview', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: RepaintBoundary(
                    key: key,
                    child: const ColoredBox(
                        color: Color(0xFFF7F9FC),
                        child: Padding(
                            padding: EdgeInsets.all(28),
                            child: BaseballLoading(progress: .42))))))));
    await tester.pump(const Duration(milliseconds: 800));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/koko-baseball-loading.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });
}
