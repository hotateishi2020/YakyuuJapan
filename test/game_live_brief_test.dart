import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AuthSession.instance.user = AuthUser.fromJson({'id': 1, 'flg_special': true});
    AuthSession.instance.token = 'test';
  });
  tearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
  for (final announced in [false, true]) {
  testWidgets('成績なしでも投手とホームランを表示する（スタメン=$announced）', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GamesBoardYahooStyle(
      games: [{
        'id_game': 1, 'id_team_home': 1, 'id_team_away': 2,
        'name_team_home': '阪神', 'name_team_away': '広島',
        'name_pitcher_home': '先発投手', 'name_pitcher_away': '相手先発',
        'name_current_pitcher_home': '救援投手',
        'name_current_pitcher_away': '相手救援',
        'name_homerun_home': '主砲 12号(6回裏ソロ)',
        'state': '7回表', 'score_home': 1, 'score_away': 0,
        'date_game': '2026-10-23',
        if (announced) 'lineup': [
          {'id_team': 1, 'order': 1, 'players': [{'name': '主砲', 'pos': '右', 'role': '', 'plays': ''}]},
          {'id_team': 2, 'order': 1, 'players': [{'name': '相手打者', 'pos': '中', 'role': '', 'plays': ''}]},
        ],
      }], horizontal: true,
    ))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('救援投手'), findsWidgets);
    expect(find.textContaining('12号'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  }
}
