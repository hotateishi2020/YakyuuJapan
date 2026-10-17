import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/player_condition.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/View/player_stats_grid.dart';
import 'package:Yakyuu_Japan/View/strength_careers.dart';
import 'package:Yakyuu_Japan/View/EventCalendar.dart';

void main() {
  testWidgets('NPBとMLBの試合情報に受け取った調子の顔を表示する', (t) async {
    for (final league in [1, 3]) {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: GamesBoardYahooStyle(
                  initialStatsExpanded: true,
                  horizontal: true,
                  games: [
            {
              'id_game': league,
              'id_league_home': league,
              'id_league_away': league,
              'date_game': '2026-10-16',
              'time_game': '🌙 18:00',
              'code_game': league == 1 ? 'CSF' : 'NLCS',
              'name_team_home': 'ホーム',
              'name_team_away': 'ビジター',
              'id_team_home': 1,
              'id_team_away': 2,
              'state': '試合終了',
              'score_home': 1,
              'score_away': 0,
              'id_team_summary': 1,
              'name_full_summary': '好調選手',
              'flg_pitcher': false,
              'txt_plays': '中安|hit',
              'lineup': [
                {
                  'id_team': 1,
                  'order': 1,
                  'players': [
                    {'name': '好調選手', 'pos': '中', 'plays': '中安|hit'}
                  ]
                }
              ],
              'player_hands': [
                {
                  'name_full_summary': '好調選手',
                  'batting_hand': 1,
                  'pitching_hand': 0
                }
              ],
              'postseason_form': [
                {
                  'id_player': 1,
                  'name': '好調選手',
                  'pitcher': false,
                  'level': 2,
                  'label': '絶好調',
                  'season': .25,
                  'postseason': .5,
                  'note': '比較結果'
                }
              ],
            }
          ]))));
      await t.pump();
      await t.tap(find.text('詳細表示'));
      await t.pump();
      expect(
          find.byWidgetPredicate(
              (w) => w is PlayerConditionFace && w.level == 2),
          findsWidgets,
          reason: t
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .join(' | '));
      expect(
          find.byWidgetPredicate((w) => w is PlayerHandBadge && w.hand == '左'),
          findsWidgets);
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('判定データ不足は黄色の普通顔で仮表示する', (t) async {
    await t.pumpWidget(
        const MaterialApp(home: PlayerConditionFace(level: null, size: 20)));
    expect(PlayerConditionFace.colorFor(null), PlayerConditionFace.colorFor(0));
    expect(find.byIcon(Icons.sentiment_neutral), findsOneWidget);
    expect(find.byIcon(Icons.question_mark), findsNothing);
  });

  test('追加指標は値の良い順で欠損を最後にする', () {
    for (final title in [
      ...extraBattingTitles,
      ...extraPitchingTitles,
      '四球/9'
    ]) {
      final rows = <Map<String, dynamic>>[
        {'title': title, 'stats': '—'},
        {'title': title, 'stats': '2'},
        {'title': title, 'stats': '10'}
      ];
      sortPersonalStatRows(rows);
      expect(rows.first['stats'],
          ['BB/9', '四球/9', '四死球/9'].contains(title) ? '2' : '10');
      expect(rows.last['stats'], '—');
    }
  });
  test('出身地は都道府県と国・州でグループ化する', () {
    final groups = careerGroups([
      {
        'id_team': 1,
        'roster': [
          {'name': '甲', 'birth_place': '神奈川県横浜市'},
          {'name': '乙', 'birth_country': 'USA', 'birth_state': 'California'},
        ]
      }
    ], '出身地');
    expect(groups.map((g) => g['name']),
        containsAll(['日本 / 神奈川県', 'USA / California']));
  });
  testWidgets('左右の配色と5段階の顔色', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Row(children: [
      PlayerHandBadge(hand: '右', size: 20),
      PlayerHandBadge(hand: '左', size: 20)
    ])));
    expect(t.widget<Text>(find.text('右')).style!.color, Colors.white);
    expect(t.widget<Text>(find.text('左')).style!.color, Colors.black);
    expect([
      for (final n in [2, 1, 0, -1, -2]) PlayerConditionFace.colorFor(n)
    ], [
      const Color(0xFFFF80AB),
      const Color(0xFFEF5350),
      const Color(0xFFFFEB3B),
      const Color(0xFF81D4FA),
      const Color(0xFF7E57C2)
    ]);
  });
  testWidgets('狭い画面でも月末まで表示し対戦はロゴになる', (t) async {
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EventCalendar(
                initialMonth: DateTime(2026, 10),
                events: const [],
                games: const [
          {'date': '2026-10-31', 'name_home': '巨', 'name_away': '神'}
        ]))));
    expect(t.getBottomRight(find.text('31')).dx, lessThanOrEqualTo(390));
    expect(
        find.descendant(
            of: find.byType(ScheduleGameTile), matching: find.byType(Image)),
        findsNWidgets(2));
    expect(t.takeException(), isNull);
  });
}
