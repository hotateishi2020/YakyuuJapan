import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

void main() {
  setUp(() {
    AuthSession.instance.user = AuthUser.fromJson({'id': 1});
    AuthSession.instance.token = 'test';
  });
  tearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });

  Map<String,dynamic> game({bool innings = false, bool pinch = false}) => {
    'id_game': 1,'date_game': '2026-10-28','state': '5回裏',
    'id_team_home': 1,'id_team_away': 2,'id_league_home': 1,'id_league_away': 1,
    'name_team_home': '巨人','name_team_away': '阪神','score_home': 1,'score_away': 0,
    'name_batter': pinch ? '代打選手' : '山田二郎','id_team_batter': 1,'int_batter_order': 2,'int_outs': 1,
    'lineup': [
      {'id_team': 1,'order': 1,'players': [{'name': '山田太郎','pos': '左','plays': innings ? '三振|out/inning1' : '三振|out'}]},
      {'id_team': 1,'order': 2,'players': [
        {'name': '山田二郎','pos': '右','plays': innings ? '右安|single/inning1 二ゴ|out/inning3' : '右安|single'},
        if (pinch) {'name': '代打選手','role': '代打','plays': ''},
      ]},
      {'id_team': 2,'order': 1,'players': [{'name': '相手打者','pos': '遊','plays': innings ? '中安|single/inning1' : '中安|single'}]},
    ],
  };
  Widget board(Map<String,dynamic> g) => MaterialApp(home: Scaffold(body: SizedBox(
    width: 1100, height: 800,
    child: GamesBoardYahooStyle(games: [g], horizontal: true, initialStatsExpanded: true),
  )));

  for (final innings in [false,true]) {
    for (final pinch in [false,true]) {
      testWidgets('打撃ブロックにNowを一つ表示し終了後は消す innings=$innings pinch=$pinch', (tester) async {
        tester.view.physicalSize = const Size(1200,1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final g = game(innings: innings,pinch: pinch);
        await tester.pumpWidget(board(g));
        await tester.pump(const Duration(milliseconds:300));
        expect(find.text('Now'), findsOneWidget);
        final now = tester.getRect(find.byKey(const ValueKey('now-play-chip')));
        final dueRow = tester.getRect(find.byKey(const ValueKey('batting-name-home-2')));
        expect(now.center.dy, inInclusiveRange(dueRow.top, dueRow.bottom));
        expect(now.left, greaterThan(tester.getRect(find.text('右安')).right));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(board({...g,'state': '試合終了'}));
        await tester.pump();
        expect(find.text('Now'), findsNothing);
      });
    }
  }
  testWidgets('3アウトでは次の攻撃チームにNowを移す', (tester) async {
    tester.view.physicalSize = const Size(1200,1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(board({...game(innings: true),
      'int_outs': 3,'id_team_batter': 2,'name_batter': '相手打者','int_batter_order': 1,
    }));
    await tester.pump(const Duration(milliseconds:300));
    expect(find.text('Now'), findsOneWidget);
    final row = tester.getRect(find.byKey(const ValueKey('batting-name-away-1')));
    final now = tester.getRect(find.byKey(const ValueKey('now-play-chip')));
    expect(now.center.dy, inInclusiveRange(row.top,row.bottom));
    expect(tester.takeException(), isNull);
  });
}
