import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/logic/game_visibility.dart';
import 'package:Yakyuu_Japan/View/EventCalendar.dart';

void main() {
  tearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
  testWidgets('future calendar keeps team identity and restricts logos by user', (tester) async {
    final raw = <String,dynamic>{'id':1,'date':'2026-10-27','time':'2026-10-27 18:00',
      'state':'試合前','score_home':-1,'score_away':-1,
      'name_home':'ソ','name_away':'De','name_home_logo':'ソフトバンク','name_away_logo':'DeNA',
      'league_home':2,'league_away':1,'code_game':'JS',
      'lineup':[{'name':'非公開打者'}]};
    final game = publicGameData(raw) as Map<String,dynamic>;
    expect(game['name_home_logo'],'ソフトバンク');
    expect(game['name_away_logo'],'DeNA');
    expect(game['time'],'2026-10-27 18:00');
    expect(game['lineup'],isNull);
    for (final id in [1,2,3,null]) {
      AuthSession.instance.user = id == null ? null : AuthUser.fromJson({'id':id});
      AuthSession.instance.token = id == null ? null : 'test';
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:ScheduleGameTile(game:game))));
      await tester.pump();
      expect(find.byType(Image), id == 1 || id == 2 ? findsNWidgets(2) : findsNothing);
      expect(tester.takeException(),isNull);
    }
  });
}
