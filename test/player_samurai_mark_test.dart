import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/View/player_samurai_mark.dart';
import 'package:Yakyuu_Japan/logic/display_settings.dart';

void main() {
  setUp(() => DisplaySettings.instance.value = {});
  tearDown(() => DisplaySettings.instance.value = {});
  for (final category in samuraiCategories.entries) {
    testWidgets(
        '${category.key}: mark right of NPB player name and correct color',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PlayerStatCell(
        width: 240,
        row: {'name_player': '代表選手', 'samurai_category': category.key},
      ))));
      expect(find.text('侍'), findsOneWidget);
      expect(
          tester.getCenter(find.text('侍')).dx,
          greaterThan(
              tester.getCenter(find.text('代表選手', findRichText: true).last).dx));
      final containers = tester.widgetList<Container>(find.descendant(
          of: find.byType(PlayerSamuraiMark),
          matching: find.byType(Container)));
      expect((containers.single.decoration as BoxDecoration).color,
          category.value.$2);
      DisplaySettings.instance.value = {'flg_samurai'};
      await tester.pump();
      expect(find.text('侍'), findsNothing);
      DisplaySettings.instance.value = {};
      await tester.pump();
      expect(find.text('侍'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('no mark without selection or in MLB', (tester) async {
    for (final mlb in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PlayerStatCell(
        width: 240,
        showJapanFlag: mlb,
        row: {'name_player': '選手', if (mlb) 'samurai_category': 'wbc'},
      ))));
      expect(find.text('侍'), findsNothing);
    }
  });
}
