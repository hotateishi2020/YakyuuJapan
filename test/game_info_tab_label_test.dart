import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/View/BlinkBg.dart';
import 'package:Yakyuu_Japan/widgets/game_info_tab_label.dart';
// Compile the integration as well as the label.
import 'package:Yakyuu_Japan/pages/prediction_page.dart';

void main() {
  test('当日の対象団体の進行中カードだけを検出する', () {
    expect(const PredictionPage(), isA<Widget>());
    Map<String, dynamic> game(String state, {String date = '2026-10-21', int league = 1}) => {
      'state': state, 'date_game': date, 'id_league_home': league, 'id_league_away': league,
    };
    for (final state in ['3回表', '９回裏', '試合中']) {
      expect(orgGamesInProgress([game(state)], '2026-10-21', {1, 2}), isTrue);
    }
    for (final state in ['18:00', '試合前', '試合終了（延長12回）', '5回コールド', '試合中止', '延期']) {
      expect(orgGamesInProgress([game(state)], '2026-10-21', {1, 2}), isFalse);
    }
    expect(orgGamesInProgress([game('3回表', date: '2026-10-20')], '2026-10-21', {1, 2}), isFalse);
    expect(orgGamesInProgress([game('3回表', league: 3)], '2026-10-21', {1, 2}), isFalse);
    expect(orgGamesInProgress([game('3回表', league: 3)], '2026-10-21', {3, 4}), isTrue);
  });
  testWidgets('試合情報の文字に点滅背景を表示する', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: GameInfoTabLabel()))));
    expect(find.text('試合情報'), findsOneWidget);
    expect(find.byType(BlinkBg), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(find.byType(BlinkBg), findsNothing);
  });
}
