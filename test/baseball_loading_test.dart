import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';

void main() {
  testWidgets('遠投は横長の領域に表示する', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(
      child: BaseballLoading(progress: .5, scene: BaseballLoadingScene.longThrow)))));
    expect(tester.getSize(find.byKey(const ValueKey('baseball-loading-area'))), const Size(800, 200));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'measured progress, estimated cap, reduced motion and tight spaces',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: BaseballLoading(progress: .42, scene: BaseballLoadingScene.fielding)))));
    expect(tester.getSize(find.byKey(const ValueKey('baseball-loading-area'))), const Size(420, 300));
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
    expect(find.text('Loading... 95%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(width: 18, height: 18, child: BaseballLoading()))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final scene in BaseballLoadingScene.values) {
    testWidgets('loading scene ${scene.name} handles progress and animation', (tester) async {
      for (final progress in [0.0, .42, 1.0]) {
        await tester.pumpWidget(MaterialApp(home: Center(child: BaseballLoading(
          scene: scene, progress: progress))));
        expect(find.bySemanticsLabel(scene.label), findsOneWidget);
        expect(find.text('${(progress * 100).floor()}%'), findsOneWidget);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('random scene stays fixed throughout the loading instance', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BaseballLoading()));
    final labels = BaseballLoadingScene.values.where((scene) => find.bySemanticsLabel(scene.label).evaluate().isNotEmpty).toList();
    expect(labels, hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    expect(find.bySemanticsLabel(labels.single.label), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('render baseball loading preview', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: RepaintBoundary(
                    key: key,
                    child: ColoredBox(
                        color: Color(0xFFF7F9FC),
                        child: Padding(
                            padding: EdgeInsets.all(28),
                            child: SizedBox(width: 560, child: Wrap(children: [for (final scene in BaseballLoadingScene.values) SizedBox(width: 280, height: 200, child: BaseballLoading(progress: .42, scene: scene))])))))))));
    await tester.pump(const Duration(milliseconds: 4800));
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
