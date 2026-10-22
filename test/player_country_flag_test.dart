import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/View/player_country_flag.dart';

void main() {
  test(
      'representative country takes precedence; old payloads retain birthplace',
      () {
    expect(
        playerCountryEmoji(
            {'emoji_display_country': '🇯🇵', 'emoji_country': '🇺🇸'}),
        '🇯🇵');
    expect(playerCountryEmoji({'emoji_country': '🇩🇴'}), '🇩🇴');
    expect(playerCountryEmoji({'flg_japan': true}), '🇯🇵');
    expect(playerCountryEmoji({}), '');
  });
  testWidgets(
      'MLB flag appears once to the left of the club, including on a narrow cell',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: PlayerStatCell(
      width: 240,
      showJapanFlag: true,
      row: {
        'int_rank': 2,
        'name_team': 'STL',
        'name_player': 'ヌートバー',
        'stats': 20,
        'emoji_country': '🇺🇸',
        'emoji_display_country': '🇯🇵',
        'country_flag_basis': 'WBC 2023'
      },
    ))));
    expect(find.text('🇯🇵'), findsOneWidget);
    expect(find.text('🇺🇸'), findsNothing);
    expect(tester.getCenter(find.text('🇯🇵')).dx,
        lessThan(tester.getCenter(find.text('STL')).dx));
    expect(tester.takeException(), isNull);
  });
  testWidgets('NPB cell does not add a country column', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: PlayerStatCell(
      width: 240,
      row: {'name_player': '選手', 'emoji_country': '🇯🇵'},
    ))));
    expect(find.byType(PlayerCountryFlag), findsNothing);
  });
}
