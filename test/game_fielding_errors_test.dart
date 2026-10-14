import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';

void main() {
  testWidgets('交代済みの先発投手の2失策を守備図から消さない', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox(
      width: 900,
      height: 520,
      child: GamesBoardYahooStyle(
          initialStatsExpanded: true,
          horizontal: true,
          games: [
            {
              'date_game': '2026-10-13',
              'time_game': '06:00',
              'name_team_home': 'ブリュワーズ',
              'name_team_away': 'ドジャース',
              'name_stadium': 'アメリカンファミリー・フィールド',
              'path_image_inside':
                  'backend/assets/images/stadiums/inside/npb-03-belluna.jpg',
              'state': '試合終了',
              'score_home': 7,
              'score_away': 4,
              'id_team_home': 35,
              'id_team_away': 40,
              'id_league_home': 3,
              'id_league_away': 3,
              'name_pitcher_home': 'ローガン・ヘンダーソン',
              'name_pitcher_away': '山本由伸',
              'summaries': [
                {
                  'id_game_summary': 1,
                  'id_team_summary': 35,
                  'name_full_summary': 'ローガン・ヘンダーソン',
                  'flg_pitcher': true,
                  'txt_pitching': '4回4失点'
                },
                {
                  'id_game_summary': 2,
                  'id_team_summary': 35,
                  'name_full_summary': 'アーロン・アシュビー',
                  'flg_pitcher': true,
                  'txt_pitching': '1.2回無失点'
                },
              ],
              'fielding_errors': [
                {'id_team': 35, 'name': 'ローガン・ヘンダーソン', 'count': 2},
              ],
              'lineup': [
                {
                  'id_team': 35,
                  'order': 3,
                  'players': [
                    {'name': 'ウィリアム・コントレラス', 'pos': '捕'}
                  ]
                },
              ],
            },
          ]),
    ))));
    await tester.pump();
    await tester.tap(find.text('詳細表示'));
    await tester.pump();
    expect(find.byKey(const ValueKey('field-mark-E2')), findsOneWidget);
    expect(find.byKey(const ValueKey('defense-pinch-ローガン・ヘンダーソン')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('defense-name-アーロン・アシュビー')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
