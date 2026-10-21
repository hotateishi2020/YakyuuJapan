import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/widgets/collapsible_menu.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';

void main() {
  testWidgets('フェード中は本文を毎フレーム再レイアウトしない', (t) async {
    var layouts = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: MenuScope(child: Column(children: [
      const MenuBand(child: SizedBox(height: 80, child: Text('メニュー'))),
      Expanded(child: LayoutBuilder(builder: (_, constraints) {
        layouts++;
        return const SizedBox.expand();
      })),
    ])))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('menu-visibility-toggle')));
    await t.pump();
    final afterTap = layouts;
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(layouts, afterTap);
    await t.pumpAndSettle();
    expect(layouts, lessThanOrEqualTo(afterTap + 1));
    expect(find.text('メニュー').hitTestable(), findsNothing);
    await t.tap(find.byKey(const ValueKey('menu-visibility-toggle')));
    await t.pumpAndSettle();
    expect(find.text('メニュー').hitTestable(), findsOneWidget);
  });

  testWidgets('左右の余白も表示非表示バーとして押せる', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: MenuScope(
      child: Padding(padding: EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [MenuBand(child: SizedBox(height: 30))])),
    ))));
    await t.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('menu-visibility-toggle'));
    await t.tapAt(Offset(1, t.getCenter(toggle).dy));
    await t.pumpAndSettle();
    expect(find.text('▼ メニュー表示 ▼'), findsOneWidget);
    await t.tapAt(Offset(799, t.getCenter(toggle).dy));
    await t.pumpAndSettle();
    expect(find.text('▲ メニューを非表示 ▲'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('toggle follows selected tab colors and leaves a five pixel gap', (t) async {
    Widget page(Color color) => MaterialApp(home: Scaffold(body: MenuScope(color: color, foreground: Colors.white,
      child: const Column(children: [MenuBand(child: SizedBox(key: ValueKey('test-tabs'), height: 30))]))));
    await t.pumpWidget(page(Colors.red));
    await t.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('menu-visibility-toggle'));
    Material material() => t.widget<Material>(find.ancestor(of: toggle, matching: find.byType(Material)).first);
    expect(material().color, Colors.red);
    expect(t.getTopLeft(toggle).dy - t.getBottomLeft(find.byKey(const ValueKey('test-tabs'))).dy, 5);
    await t.pumpWidget(page(Colors.blue));
    await t.pumpAndSettle();
    expect(material().color, Colors.blue);
    expect(t.widget<Text>(find.text('▲ メニューを非表示 ▲')).style!.color,Colors.white);
    expect(t.takeException(),isNull);
  });

  testWidgets(
      'personal stats puts one toggle below all tabs and hides the segment hint',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MenuScope(
                child: BothLeaguePersonalStats(
      segmentOnly: true,
      stats: [
        for (final league in [1, 2])
          {
            'id_league': league,
            'title': '打率',
            'name_player': '選手$league',
            'stats': '.300',
            'int_rank': 1
          },
      ],
    )))));
    await t.pumpAndSettle();
    expect(find.text('気になる選手を長押ししてみてね！'), findsNothing);
    expect(find.text('▲ メニューを非表示 ▲'), findsOneWidget);
    await t.tap(find.text('▲ メニューを非表示 ▲'));
    await t.pumpAndSettle();
    expect(find.text('▼ メニュー表示 ▼'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });

  testWidgets('only the deepest band toggles all menus and preserves content',
      (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MenuScope(
                child: Column(children: [
      MenuBand(child: SizedBox(height: 50, child: Text('header'))),
      MenuGap(height: 12),
      MenuBand(level: 1, child: SizedBox(height: 30, child: Text('tabs'))),
      MenuBand(level: 3, child: SizedBox(height: 30, child: Text('leaf tabs'))),
      Expanded(child: Text('content', key: ValueKey('content'))),
    ])))));
    await t.pumpAndSettle();
    expect(find.text('▲ メニューを非表示 ▲'), findsOneWidget);
    final before = t.getTopLeft(find.byKey(const ValueKey('content'))).dy;
    await t.tap(find.text('▲ メニューを非表示 ▲'));
    await t.pumpAndSettle();
    expect(find.text('▼ メニュー表示 ▼'), findsOneWidget);
    expect(t.getTopLeft(find.byKey(const ValueKey('content'))).dy,
        lessThan(before - 100));
    await t.tap(find.text('▼ メニュー表示 ▼'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byKey(const ValueKey('content'))).dy, before);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
