import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

void main() {
  setUp(() {
    AuthSession.instance.user = AuthUser.fromJson({'id': 1});
    AuthSession.instance.token = 'test';
  });
  tearDown(() {
    AuthSession.instance.user = null;
    AuthSession.instance.token = null;
  });

  for (final summary in ['佐野1号', '佐野1号、牧2号']) {
    testWidgets('活躍表示で本塁打要約を選手として追加しない: $summary', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
        width: 1100, height: 800,
        child: GamesBoardYahooStyle(
          horizontal: true,
          initialStatsExpanded: true,
          games: [{
            'id_game': 1, 'date_game': '2026-10-28', 'state': '4回裏',
            'id_team_home': 1, 'id_team_away': 2,
            'id_league_home': 1, 'id_league_away': 2,
            'name_team_home': 'ソフトバンク', 'name_team_away': 'DeNA',
            'score_home': 0, 'score_away': 2,
            'name_pitcher_home': '前田悠伍',
            'name_homerun_away': summary,
            'summaries': const [{
              'id_game_summary': 1, 'id_team_summary': 1,
              'name_full_summary': '前田悠伍', 'flg_pitcher': true,
              'txt_pitching': '4回2失点',
            }, {
              'id_game_summary': 1, 'id_team_summary': 2,
              'name_full_summary': '佐野恵太', 'flg_pitcher': false,
              'int_homerun': 1, 'txt_batting': '1安打 1HR 2打点',
              'txt_plays': '先制2ランホームラン|hr',
            }],
          }],
        ),
      ))));
      await tester.pump();
      expect(find.text('佐野恵太'), findsOneWidget);
      expect(find.text(summary), findsNothing);
      expect(find.text('先制2ランホームラン'), findsOneWidget);
      for (final name in ['佐野恵太', '前田悠伍']) {
        final season = find.byKey(ValueKey('game-season-stats-$name'));
        expect(find.ancestor(of: season, matching: find.byWidgetPredicate(
          (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal,
        )), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
