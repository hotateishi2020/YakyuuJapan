import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/widgets/navigation_picker.dart';

void main() {
  for (final bothLeagues in [false, true]) {
    testWidgets('再描画・データ更新・項目追加削除でセグメントを打率に戻さない both=$bothLeagues', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = <Map<String, dynamic>>[
        for (final title in ['打率', '本塁打', '打点'])
          {
            'id_league': 1,
            'id_player': 1,
            'name_player': '$title選手',
            'title': title,
            'stats': '10',
            'flg_pitcher': false,
            'rank': 1,
          }
      ];
      var rows = original;
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return bothLeagues ? BothLeaguePersonalStats(stats: rows, segmentOnly: true) : SegmentedLeaguePersonalStats(batting: rows, pitching: const []);
        },
      ))));
      final segment = find.byType(StatsSegmentControl);
      await tester.tap(find.descendant(of: segment, matching: find.byType(InkWell)).last);
      await tester.pump();
      expect(find.textContaining('打点選手'), findsWidgets);
      for (final next in [
        original.map((r) => Map<String, dynamic>.from(r)).toList(),
        original.where((r) => r['title'] != '本塁打').toList(),
        original.map((r) => {...r, 'stats': '11'}).toList(),
      ]) {
        update(() => rows = next);
        await tester.pump();
        final control = tester.widget<StatsSegmentControl>(segment);
        expect(control.labels[control.selectedIndex!], '打点');
        expect(find.textContaining('打点選手'), findsWidgets);
        expect(find.textContaining('打率選手'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final org in [OrgConfig.npb, OrgConfig.mlb]) {
    for (final wide in [false, true]) {
      testWidgets('${org.label}は縦でリーグpickerと投打セグメント、横で4タブを表示する wide=$wide', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(wide ? 1400 : 375, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final rows = [
          for (var i = 0; i < 4; i++)
            for (final extra in [false, true])
              {
                'id_league': org.leagues[i ~/ 2].id,
                'id_player': i + 1,
                'name_player': '選手$i${extra ? '別項目' : ''}',
                'name_team': '球団',
                'title': extra ? (i.isEven ? '本塁打' : '最多勝') : (i.isEven ? '打率' : '防御率'),
                'stats': i.isEven ? '.300' : '2.50',
                'flg_pitcher': i.isOdd,
                'rank': 1,
              }
        ];
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: NavigationPickerScope(
                    child: Column(children: [
          const NavigationPickerBar(),
          NavigationPicker(level: 1, alwaysPicker: true, labels: const {2: '個人成績'}, value: 2, onChanged: (_) {}, color: Colors.black, foreground: Colors.white),
          Expanded(child: LeagueRolePersonalStats(stats: rows, org: org, wideLayout: wide)),
        ])))));
        await tester.pumpAndSettle();
        if (wide)
          for (var i = 0; i < 4; i++) {
            expect(find.text('${org.leagues[i ~/ 2].name}${i.isEven ? '打者' : '投手'}'), findsOneWidget);
            final tab = find.byKey(ValueKey('navigation-option-2-$i'));
            expect(tab, findsOneWidget);
            final material = find.ancestor(of: tab, matching: find.byType(Material)).first;
            expect(tester.widget<Material>(material).color, i == 0 ? org.leagues[0].color : Color.lerp(Colors.white, org.leagues[i ~/ 2].color, .14));
          }
        expect(find.text('打者スタッツ'), findsNothing);
        expect(find.text('投手スタッツ'), findsNothing);
        for (var i = 0; i < 4; i++) {
          final tab = find.byKey(ValueKey('navigation-option-2-$i'));
          if (wide) {
            await tester.ensureVisible(tab);
            await tester.pumpAndSettle();
            await tester.tap(tab);
          } else {
            expect(tab, findsNothing);
            final picker = find.byKey(const ValueKey('navigation-picker-2'));
            expect(tester.widget(picker), isA<DropdownButton<int>>());
            await tester.tap(picker);
            await tester.pumpAndSettle();
            expect(tester.widget<DropdownButton<int>>(picker).items, hasLength(2));
            await tester.tap(find.text(org.leagues[i ~/ 2].name).last);
            await tester.pumpAndSettle();
            final segments = find.byType(StatsSegmentControl);
            expect(segments, findsNWidgets(2));
            await tester.tap(find.descendant(of: segments.at(i.isEven ? 0 : 1), matching: find.byType(InkWell)).first);
          }
          await tester.pumpAndSettle();
          expect(find.textContaining('選手$i'), findsWidgets);
          for (var other = 0; other < 4; other++) {
            if (other != i) expect(find.textContaining('選手$other'), findsNothing);
          }
          if (wide) {
            final material = find.ancestor(of: tab, matching: find.byType(Material)).first;
            expect(tester.widget<Material>(material).color, org.leagues[i ~/ 2].color);
          } else {
            final segment = find.byType(StatsSegmentControl).at(i.isEven ? 0 : 1);
            expect(segment, findsOneWidget);
            expect(tester.widget<StatsSegmentControl>(segment).labels, hasLength(2));
            await tester.tap(find.descendant(of: segment, matching: find.byType(InkWell)).last);
            await tester.pumpAndSettle();
            expect(find.textContaining('選手$i別項目'), findsWidgets);
            expect(tester.widget<StatsSegmentControl>(segment).selectedIndex, 1);
            expect(find.byKey(const ValueKey('navigation-picker-3')), findsNothing);
          }
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
