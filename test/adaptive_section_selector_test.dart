import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/adaptive_section_selector.dart';
import 'package:Yakyuu_Japan/config/app_design.dart';

void main() {
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
