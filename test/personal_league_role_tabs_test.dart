import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/widgets/navigation_picker.dart';

void main() {
  for (final org in [OrgConfig.npb, OrgConfig.mlb]) {
    for (final wide in [false, true]) {
      testWidgets('${org.label}は4つのリーグ別打者投手タブで切り替える wide=$wide', (tester) async {
        await tester.binding.setSurfaceSize(Size(wide ? 1400 : 375, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final rows = [for (var i = 0; i < 4; i++) {
          'id_league': org.leagues[i ~/ 2].id, 'id_player': i + 1,
          'name_player': '選手$i', 'name_team': '球団', 'title': i.isEven ? '打率' : '防御率',
          'stats': i.isEven ? '.300' : '2.50', 'flg_pitcher': i.isOdd, 'rank': 1,
        }];
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: NavigationPickerScope(child: Column(children: [
          const NavigationPickerBar(),
          NavigationPicker(level: 1, alwaysPicker: true, labels: const {2: '個人成績'}, value: 2,
              onChanged: (_) {}, color: Colors.black, foreground: Colors.white),
          Expanded(child: LeagueRolePersonalStats(stats: rows, org: org, wideLayout: wide)),
        ])))));
        await tester.pumpAndSettle();
        for (var i = 0; i < 4; i++) {
          expect(find.text('${org.leagues[i ~/ 2].name}${i.isEven ? '打者' : '投手'}'), findsOneWidget);
          final tab = find.byKey(ValueKey('navigation-option-2-$i'));
          expect(tab, findsOneWidget);
          final material = find.ancestor(of: tab, matching: find.byType(Material)).first;
          expect(tester.widget<Material>(material).color,
              i == 0 ? org.leagues[0].color : Color.lerp(Colors.white, org.leagues[i ~/ 2].color, .14));
        }
        expect(find.text('打者スタッツ'), findsNothing);
        expect(find.text('投手スタッツ'), findsNothing);
        for (var i = 0; i < 4; i++) {
          final tab = find.byKey(ValueKey('navigation-option-2-$i'));
          await tester.ensureVisible(tab);
          await tester.pumpAndSettle();
          await tester.tap(tab);
          await tester.pumpAndSettle();
          expect(find.textContaining('選手$i'), findsWidgets);
          for (var other = 0; other < 4; other++) {
            if (other != i) expect(find.textContaining('選手$other'), findsNothing);
          }
          final material = find.ancestor(of: tab, matching: find.byType(Material)).first;
          expect(tester.widget<Material>(material).color, org.leagues[i ~/ 2].color);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
