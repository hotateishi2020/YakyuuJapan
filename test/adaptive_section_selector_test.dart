import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/adaptive_section_selector.dart';
import 'package:Yakyuu_Japan/config/app_design.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';

void main() {
  for (final width in [390.0, 1200.0, 1920.0]) {
    testWidgets('記録の全タブは幅$widthに合わせて表示する', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        AdaptiveSectionSelector(
          fitLabels: true, labels: {for (var i = 0; i < recordTabs.length; i++) i: recordTabs[i]},
          value: selected, onChanged: (value) => selected = value,
          background: Colors.red, foreground: Colors.white,
        ))));
      expect(find.byType(DropdownButton<int>), width < 1000 ? findsOneWidget : findsNothing);
      if (width >= 1000) {
        for (final label in recordTabs) {
          expect(find.text(label).hitTestable(), findsOneWidget);
          final text = tester.widget<Text>(find.text(label));
          expect(text.style!.fontSize, inInclusiveRange(11, 12));
        }
        await tester.tap(find.text(recordTabs.last));
        expect(selected, recordTabs.length - 1);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('狭い幅のpickerは丸い形で文字を上下中央に表示し選択を反映する',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Center(child: SizedBox(width: 180, child: StatefulBuilder(
        builder: (context, setState) => AdaptiveSectionSelector(
          pickerKey: const ValueKey('picker'),
          labels: const {0: '殿堂入り・名球会', 1: 'シーズン記録', 2: 'レギュラー'},
          value: selected,
          onChanged: (value) => setState(() => selected = value),
          background: Colors.red,
          foreground: Colors.white,
        ),
      ))),
    )));
    final picker = find.byKey(const ValueKey('picker'));
    final shell = find.ancestor(of: picker, matching: find.byType(Container)).first;
    final container = tester.widget<Container>(shell);
    expect((container.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(TAB_RADIUS));
    final label = find.text('殿堂入り・名球会').hitTestable();
    expect(tester.getCenter(label).dy,
        closeTo(tester.getCenter(shell).dy, 1));
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('シーズン記録').last);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.widget<DropdownButton<int>>(picker).value, 1);
    expect(tester.takeException(), isNull);
  });
}
