import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/logic/game_visibility.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';

void main() {
  final session = AuthSession.instance;
  tearDown(() { session.user = null; session.token = null; });
  final live = <String, dynamic>{
    'id_game': 1, 'state': '8回裏 1アウト', 'date_game': '2026-10-26',
    'name_team_home': 'ホーム', 'name_team_away': 'ビジター',
    'id_team_home': 1, 'id_team_away': 2,
    'score_home': 7, 'score_away': 3,
    'txt_scores_home': '0,0,0,0,0,0,0,7',
    'name_current_pitcher_home': '速報投手',
    'lineup': [{'players': [{'name': '速報打者', 'plays': '左飛|out'}]}],
  };
  test('nested API data keeps completed scores, strips live data and all plate results without mutating cache', () {
    final payload = {'games': [live, {...live, 'state': '試合終了'}],
      'recent_games': [{'plays': [{'result': '左飛'}]}]};
    final result = publicGameData(payload) as Map;
    expect(result['games'][0]['score_home'], -1);
    expect(result['games'][0]['name_current_pitcher_home'], isNull);
    expect(result['games'][0]['lineup'], isNull);
    expect(result['games'][1]['score_home'], 7);
    expect(result['games'][1]['lineup'][0]['players'][0]['plays'], isNull);
    expect(result['recent_games'][0]['plays'], isNull);
    expect(live['score_home'], 7);
    expect(publicGameData(result), result);
  });
  testWidgets('cached live card and plate blocks disappear on account switch and logout', (tester) async {
    session.token = 'test';
    session.user = AuthUser.fromJson({'id': 1});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      const GameBattingResult(play: {'result': '左飛'}),
      Expanded(child: GamesBoardYahooStyle(games: [live], horizontal: true)),
    ]))));
    for (final id in [1, 2, 3, 99, 1]) {
      session.user = AuthUser.fromJson({'id': id, 'flg_special': true, 'flg_admin': true});
      await tester.pump(const Duration(milliseconds: 100));
      final allowed = id == 1 || id == 2;
      expect(find.text('左飛'), allowed ? findsOneWidget : findsNothing);
      expect(find.textContaining('8回裏'), allowed ? findsWidgets : findsNothing);
      expect(find.text('7 - 3'), allowed ? findsWidgets : findsNothing);
      expect(tester.takeException(), isNull);
    }
    session.token = null;
    await tester.pump();
    expect(find.text('左飛'), findsNothing);
    expect(find.textContaining('8回裏'), findsNothing);
    expect(find.text('7 - 3'), findsNothing);
  });
}
