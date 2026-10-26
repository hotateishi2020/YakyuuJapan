import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/widgets/golden_glove_badge.dart';

void main() {
  testWidgets('交代済みの先発投手の2失策を守備図から消さない', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox(
      width: 900,
      height: 1400,
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
              // Synthetic award counts exercise both starters and substitutes.
              'season_player_stats': [
                {'name_player': 'テスト捕手', 'title': 'GG受賞回数', 'stats': '1'},
                {'name_player': 'ローガン・ヘンダーソン', 'title': 'GG受賞回数', 'stats': '2'},
                {'name_player': 'ウィリアム・コントレラス', 'title': 'GG受賞回数', 'stats': '10'},
              ],
              'bench_players': [
                {'id_team': 35, 'name': '控え投手', 'pitcher': true},
                {'id_team': 35, 'name': 'アーロン・アシュビー', 'pitcher': true},
              ],
              'highlight_videos': [
                {'id': 'abcdefghijk', 'title': '試合ハイライト', 'thumbnail_url': 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg'},
              ],
              'fielding_errors': [
                {'id_team': 35, 'name': 'ローガン・ヘンダーソン', 'count': 2},
              ],
              'lineup': [
                {
                  'id_team': 35,
                  'order': 3,
                  'players': [
                    {'name': 'ウィリアム・コントレラス', 'pos': '捕'},
                    {'name': 'テスト捕手', 'pos': '捕', 'role': '代守'}
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
    expect(find.byKey(const ValueKey('defense-name-ローガン・ヘンダーソン')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('defense-pinch-テスト捕手')), findsOneWidget);
    expect(tester.widget<GoldenGloveBadge>(find.byKey(
        const ValueKey('defense-glove-ローガン・ヘンダーソン'))).count, 2);
    expect(tester.widget<GoldenGloveBadge>(find.byKey(
        const ValueKey('defense-glove-ウィリアム・コントレラス'))).count, 10);
    expect(find.byKey(const ValueKey('defense-glove-アーロン・アシュビー')), findsNothing);
    expect(find.text('控え投手'), findsOneWidget);
    expect(find.text('動画'), findsOneWidget);
    expect(find.text('試合ハイライト'), findsOneWidget);
    final story = tester.widget<Text>(find.byKey(const ValueKey('game-story')));
    expect(story.maxLines, 1);
    expect(story.data, isNot(contains('見どころ')));
    expect(story.data, isNot(contains('\n')));
    expect(tester.takeException(), isNull);
  });
}
