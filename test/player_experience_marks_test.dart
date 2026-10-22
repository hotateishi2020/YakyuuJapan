import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/View/player_experience_marks.dart';

void main() {
  for (final flags in [
    <String, dynamic>{},
    {'flg_npb_experience': true},
    {'flg_wbc': true},
    {'flg_npb_experience': true, 'flg_wbc': true}
  ]) {
    testWidgets('MLB name marks $flags', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PlayerStatCell(
        width: 240,
        showJapanFlag: true,
        row: {'name_player': '選手', 'name_team': 'LAD', 'int_rank': 2, ...flags},
      ))));
      for (final label in ['NPB', 'WBC']) {
        final expected = playerExperienceLabels(flags).contains(label);
        expect(find.text(label), expected ? findsOneWidget : findsNothing);
        if (expected) {
          expect(tester.getCenter(find.text(label)).dx, greaterThan(tester.getCenter(find.text('選手', findRichText: true).last).dx));
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('NPB stats do not display MLB experience marks', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: PlayerStatCell(
      width: 240,
      row: {'name_player': '選手', 'flg_npb_experience': true, 'flg_wbc': true},
    ))));
    expect(find.byType(PlayerExperienceMarks), findsNothing);
  });
}
