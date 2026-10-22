import 'package:Yakyuu_Japan/widgets/collapsible_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/additional_records_board.dart';

void main() {
  testWidgets('20位タイまで掲載し同率による順位の空行を詰める', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: CountRecordsBoard(records: [
      {
        'label': '打率3割',
        'leaders': [
          {'rank': 1, 'name': '首位選手', 'value': 15},
          {'rank': 20, 'name': '同率A', 'value': 3},
          {'rank': 20, 'name': '同率B', 'value': 3},
          {'rank': 20, 'name': '2回の選手', 'value': 2},
          {'rank': 20, 'name': '対象外', 'value': 1},
        ]
      },
      {
        'label': '首位打者',
        'leaders': [
          {'rank': 1, 'name': 'タイトル選手', 'value': 7},
        ]
      },
    ]))));
    expect(tester.getCenter(find.text('順位')).dx,
        lessThan(tester.getCenter(find.text('打率3割')).dx));
    expect(find.text('2位'), findsOneWidget);
    expect(find.text('3位'), findsNothing);
    expect(find.text('20位'), findsNothing);
    expect(find.text('同率A　3回'), findsOneWidget);
    expect(find.text('同率B　3回'), findsOneWidget);
    expect(find.text('対象外　1回'), findsNothing);
    expect(find.text('2回の選手　2回'), findsNothing);
    expect(find.text('21位'), findsNothing);
    expect(tester.getCenter(find.text('首位選手　15回')).dy,
        tester.getCenter(find.text('タイトル選手　7回')).dy);
    final rankX = tester.getTopLeft(find.text('順位')).dx;
    await tester.dragFrom(const Offset(300, 200), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('順位')).dx, rankX);
    expect(tester.getCenter(find.text('順位')).dx,
        lessThan(tester.getCenter(find.text('首位打者')).dx));
    expect(tester.takeException(), isNull);
  });
  testWidgets('縦スクロールは順位と記録で連動しヘッダーは固定', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CountRecordsBoard(records: [
      {
        'label': '記録',
        'leaders': [
          for (var rank = 1; rank <= 20; rank++)
            {'rank': rank, 'name': '選手$rank', 'value': 30 - rank},
        ]
      },
    ]))));
    final headerY = tester.getTopLeft(find.text('順位')).dy;
    await tester.drag(find.byKey(const ValueKey('count-records-body')),
        const Offset(0, -250));
    await tester.pumpAndSettle();
    final ranks = tester
        .widget<ListView>(find.byKey(const ValueKey('count-records-ranks')))
        .controller!;
    final body = tester
        .widget<ListView>(find.byKey(const ValueKey('count-records-body')))
        .controller!;
    expect(body.offset, greaterThan(0));
    expect(ranks.offset, body.offset);
    expect(tester.getTopLeft(find.text('順位')).dy, headerY);
    await tester.drag(find.byKey(const ValueKey('count-records-ranks')),
        const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(ranks.offset, body.offset);
    expect(tester.takeException(), isNull);
  });
  testWidgets('縦画面は表示非表示バーの上のPickerで1項目ずつ切り替える', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MenuScope(
      child: Column(children: [
        MenuBand(level: 2, child: Text('回数記録')),
        Expanded(child: CountRecordsBoard(records: [
          {'label': '打率3割', 'leaders': [{'rank': 1, 'name': '打率選手', 'value': 5}]},
          {'label': '首位打者', 'leaders': [{'rank': 1, 'name': 'タイトル選手', 'value': 4}]},
          {'label': '新人王', 'leaders': [{'rank': 1, 'name': '除外選手', 'value': 3}]},
        ])),
      ]),
    ))));
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('count-records-picker'));
    final toggle = find.byKey(const ValueKey('menu-visibility-toggle'));
    expect(toggle, findsOneWidget);
    expect(tester.getBottomLeft(picker).dy, lessThan(tester.getTopLeft(toggle).dy));
    expect(find.text('打率選手　5回'), findsOneWidget);
    expect(find.text('タイトル選手　4回'), findsNothing);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('新人王'), findsNothing);
    await tester.tap(find.text('首位打者').last);
    await tester.pumpAndSettle();
    expect(find.text('打率選手　5回'), findsNothing);
    expect(find.text('タイトル選手　4回'), findsOneWidget);
    final horizontal = tester.stateList<ScrollableState>(find.byType(Scrollable))
        .where((state) => state.axisDirection == AxisDirection.right);
    expect(horizontal.every((state) => state.position.maxScrollExtent == 0), isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(picker.hitTestable(), findsNothing);
    expect(find.text('タイトル選手　4回'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<String>>(picker).value, '首位打者');
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(picker, findsNothing);
    expect(find.text('打率選手　5回'), findsOneWidget);
    expect(find.text('タイトル選手　4回'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<String>>(picker).value, '首位打者');
    expect(tester.takeException(), isNull);
  });

}
