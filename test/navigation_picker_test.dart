import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/widgets/navigation_picker.dart';
import 'package:Yakyuu_Japan/widgets/app_section_tabs.dart';
import 'package:Yakyuu_Japan/widgets/collapsible_menu.dart';
import 'package:Yakyuu_Japan/View/adaptive_section_selector.dart';
import 'package:Yakyuu_Japan/View/retained_tab_body.dart';

void main() {
  for (final mlb in [false, true]) {
    for (final scoped in [false, true]) {
      testWidgets('団体直下は広い画面でもpicker MLB=$mlb scope=$scoped', (t) async {
        await t.binding.setSurfaceSize(const Size(1800, 700));
        addTearDown(() => t.binding.setSurfaceSize(null));
        var selected = 0;
        await t.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
          builder: (context, update) {
            final selector = AppSectionTabs(alwaysPicker: true,
              tabs: [if (mlb) ('日本人', 7), ('試合情報', 0), ('チーム順位', 1), ('戦力', 3)],
              selectedIndex: selected,
              onSelected: (value) => update(() => selected = value));
            return scoped ? NavigationPickerScope(child: Column(children: [
              const NavigationPickerBar(),
              NavigationPickerLevel(level: 1, child: selector),
            ])) : selector;
          },
        ))));
        await t.pumpAndSettle();
        expect(find.byType(DropdownButton<int>), findsOneWidget);
        await t.tap(find.byType(DropdownButton<int>));
        await t.pumpAndSettle();
        await t.tap(find.text('チーム順位').last);
        await t.pumpAndSettle();
        expect(selected, 1);
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final scoped in [false, true]) {
    testWidgets('常時picker指定は広い画面でも一覧化しない scope=$scoped', (t) async {
      await t.binding.setSurfaceSize(const Size(1800, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var selected = 0;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
        builder: (context, update) {
          final selector = AdaptiveSectionSelector(
            alwaysPicker: true,
            pickerKey: const ValueKey('fixed-picker'),
            labels: const {0: '主力選手', 1: '怪我人'},
            value: selected,
            background: Colors.red,
            foreground: Colors.white,
            onChanged: (value) => update(() => selected = value),
          );
          return scoped
              ? NavigationPickerScope(child: Column(children: [
                  const NavigationPickerBar(), selector]))
              : selector;
        },
      ))));
      await t.pumpAndSettle();
      final picker = find.byKey(const ValueKey('fixed-picker'));
      expect(t.widget(picker), isA<DropdownButton<int>>());
      expect(find.byKey(const ValueKey('navigation-option-2-0')), findsNothing);
      await t.tap(picker);
      await t.pumpAndSettle();
      await t.tap(find.text('怪我人').last);
      await t.pumpAndSettle();
      expect(selected, 1);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('読み込み中の長い選択肢とフォント更新でもpickerがはみ出さない', (t) async {
    await t.binding.setSurfaceSize(const Size(375, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: NavigationPickerScope(child: Column(children: [
      const NavigationPickerBar(),
      NavigationPicker(level:0, labels: const {0:'NPB', 1:'読み込み中に更新される非常に長い選択肢のラベル'}, value:0, onChanged: (_) {}, color:Colors.red, foreground:Colors.white),
      NavigationPicker(level:1, labels: const {0:'戦力', 1:'さらに長い球団名や情報の選択肢が入った場合の表示'}, value:0, onChanged: (_) {}, color:Colors.red, foreground:Colors.white),
    ])))));
    await t.pump();
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
    final before = t.widget(find.byKey(const ValueKey('navigation-picker-0')));
    await t.binding.handleSystemMessage({'type':'fontsChange'});
    await t.pump();
    final after = t.widget(find.byKey(const ValueKey('navigation-picker-0')));
    expect(identical(before, after), isFalse);
    expect(t.takeException(), isNull);
  });
  testWidgets('右端の一覧から選択しリサイズしても選択状態を維持する', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    var selected = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, update) => NavigationPickerScope(child: Column(children: [
      const NavigationPickerBar(),
      NavigationPicker(level: 0, labels: const {0:'NPB',1:'MLB'}, value:0, onChanged: (_) {}, color: Colors.red, foreground: Colors.white),
      NavigationPicker(level: 1, labels: const {0:'戦力',1:'記録'}, value:0, onChanged: (_) {}, color: Colors.red, foreground: Colors.white),
      NavigationPicker(level: 2, labels: const {0:'ドラフト',1:'チーム'}, value:selected, onChanged: (v) => update(() => selected = v), color: Colors.red, foreground: Colors.white),
    ]))))));
    await t.pumpAndSettle();
    final option = find.byKey(const ValueKey('navigation-option-2-1'));
    await t.tap(option);
    await t.pumpAndSettle();
    expect(selected, 1);
    final selectedMaterial = t.widget<Material>(find.ancestor(of: option, matching: find.byType(Material)).first);
    final inactive = find.byKey(const ValueKey('navigation-option-2-0'));
    final inactiveMaterial = t.widget<Material>(find.ancestor(of: inactive, matching: find.byType(Material)).first);
    expect(selectedMaterial.color, Colors.red);
    expect(inactiveMaterial.color, Color.lerp(Colors.white, Colors.red, .14));
    expect(t.getSize(option).height, 34);
    expect(t.getSize(inactive).height, 34);
    final pickerContainer = find.ancestor(of:find.byKey(const ValueKey('navigation-picker-0')), matching:find.byType(Container)).first;
    expect(t.getSize(pickerContainer).height, t.getSize(option).height);

    final semantic = t.widget<Semantics>(find.ancestor(of:option, matching:find.byType(Semantics)).first);
    expect(semantic.properties.selected, isTrue);
    expect(find.byKey(const ValueKey('navigation-option-0-1')), findsNothing);
    await t.binding.setSurfaceSize(const Size(320, 700));
    await t.pumpAndSettle();
    expect(option, findsNothing);
    expect(t.widget<DropdownButton<int>>(find.byKey(const ValueKey('navigation-picker-2'))).value, 1);
    await t.binding.setSurfaceSize(const Size(1000, 700));
    await t.pumpAndSettle();
    expect(option, findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final width in [375.0, 1600.0]) {
    testWidgets('幅$widthで階層pickerを一行表示し非表示タブの項目を除く', (t) async {
      await t.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: _NavigationTest())));
      await t.pumpAndSettle();
      final row = find.byKey(const ValueKey('navigation-picker-row'));
      expect(find.byType(DropdownButton<int>), findsNWidgets(width < 500 ? 3 : 2));
      expect(find.byKey(const ValueKey('navigation-option-2-1')), width < 500 ? findsNothing : findsOneWidget);
      expect(find.text('>'), findsNWidgets(2));
      final ys = t
          .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .map((w) => t.getCenter(find.byWidget(w)).dy)
          .toSet();
      expect(ys, hasLength(1));
      expect(t.getSize(row).width, lessThanOrEqualTo(width));
      expect(find.text('▲ メニューを非表示 ▲'), findsNothing);
      await t.tap(find.byKey(const ValueKey('navigation-picker-1')));
      await t.pumpAndSettle();
      await t.tap(find.text('記録').last);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('record-picker')), findsOneWidget);
      expect(find.byKey(const ValueKey('strength-picker')), findsNothing);
      expect(find.byType(DropdownButton<int>), findsNWidgets(width < 500 ? 3 : 2));
      // Switch back: the old page survives, but only its picker returns.
      t
          .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('navigation-picker-1')))
          .onChanged!(0);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('strength-picker')), findsOneWidget);
      expect(find.byKey(const ValueKey('record-picker')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}

class _NavigationTest extends StatefulWidget {
  const _NavigationTest();
  @override
  State<_NavigationTest> createState() => _NavigationTestState();
}

class _NavigationTestState extends State<_NavigationTest> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => NavigationPickerScope(
          child: MenuScope(
              child: Column(children: [
        const NavigationPickerBar(),
        MenuBand(
            level: 0,
            child: AppSectionTabs(
                tabs: const [('NPB', 0), ('MLB', 1)],
                selectedIndex: 0,
                onSelected: (_) {})),
        MenuBand(
            level: 1,
            child: AppSectionTabs(
                tabs: const [('戦力', 0), ('記録', 1)],
                selectedIndex: tab,
                onSelected: (i) => setState(() => tab = i))),
        Expanded(
            child: RetainedTabBody(
                selected: tab,
                builder: (_) => AdaptiveSectionSelector(
                      pickerKey: ValueKey(
                          tab == 0 ? 'strength-picker' : 'record-picker'),
                      labels: tab == 0
                          ? {0: 'ドラフト', 1: 'チーム'}
                          : {0: '新人ドラフト', 1: '年表'},
                      value: 0,
                      onChanged: (_) {},
                      background: Colors.red,
                      foreground: Colors.white,
                    ))),
      ])));
}
