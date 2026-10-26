import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/compact_game_batting.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';

void main() {
  tearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
  test('打数・合計安打・HR・盗塁だけ表示しHRを安打数に再加算しない', () {
    expect(compactGameBatting({'int_batting':4,'int_hit1':3,'int_homerun':2,'int_steal_base':1,'int_rbi':5}), '4打数3安打2HR1盗塁');
    expect(compactGameBatting({'txt_batting':'4打数無安打(1四球)'}), '4打数0安打');
    expect(compactGameBatting({'txt_batting':'4打数3安打(2HR5打点1四球1盗塁)'}), '4打数3安打2HR1盗塁');
    expect(compactGameBatting({}), '');
  });
  for (final lineup in [false, true]) {
    testWidgets('詳細の打席は2文字で表示し打数安打の集計は表示しない lineup=$lineup', (tester) async {
      final session = AuthSession.instance;
      final game = <String,dynamic>{
        'id_game':1,'date_game':'2026-10-23','state':lineup ? '7回表' : '試合終了',
        'id_team_home':1,'id_team_away':2,'name_team_home':'阪神','name_team_away':'広島',
        'score_home':4,'score_away':0,
        'name_full_summary':'打者テスト','id_team_summary':1,'flg_pitcher':false,
        'txt_batting':'4打数3安打(2HR5打点1盗塁)','txt_plays':'右安|single 遊ゴ|out 1回表先制19号ソロ左ホームラン|hr 2回表20号ソロホームラン^中|hr 3回表21号ソロホームラン^右|hr',
        'batting_summary':[{'id_team':1,'name_full':'打者テスト','int_batting':4,'int_hit1':3,'int_homerun':2,'int_steal_base':1}],
        if (lineup) 'lineup':[{'id_team':1,'order':1,'players':[{'name':'打者テスト','pos':'右','role':'','plays':'右安|single 遊ゴ|out 1回表先制19号ソロ左ホームラン|hr 2回表20号ソロホームラン^中|hr 3回表21号ソロホームラン^右|hr'}]}],
      };
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: GamesBoardYahooStyle(games:[game],horizontal:true))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('4打数'), findsNothing);
      session.token = 'test';
      session.user = AuthUser.fromJson({'id':3,'flg_special':true});
      await tester.pump();
      expect(find.textContaining('4打数'), findsNothing);
      session.user = AuthUser.fromJson({'id':1,'flg_special':false});
      await tester.pump();
      expect(find.textContaining('4打数'), findsNothing);
      expect(find.textContaining('5打点'), findsNothing);
      expect(find.textContaining('左ホームラン'), findsNothing);
      expect(find.textContaining('中ホームラン'), findsNothing);
      expect(find.textContaining('右ホームラン'), findsNothing);
      expect(find.textContaining('猛打賞'), findsWidgets);
      expect(find.textContaining('19号'), lineup ? findsNothing : findsWidgets);
      expect(find.textContaining('先制'), lineup ? findsNothing : findsWidgets);
      if (lineup) {
        expect(find.textContaining('右安'), findsWidgets);
        expect(find.textContaining('遊ゴ'), findsWidgets);
        expect(find.text('左本'), findsWidgets);
        expect(find.text('中本'), findsWidgets);
        expect(find.text('右本'), findsWidgets);
      }
      session.user = AuthUser.fromJson({'id':2,'flg_special':false});
      await tester.pump();
      expect(find.textContaining('4打数'), findsNothing);
      if (lineup) {
        expect(find.text('左本'), findsWidgets);
        expect(find.text('中本'), findsWidgets);
        expect(find.text('右本'), findsWidgets);
      }
      expect(find.textContaining('19号'), lineup ? findsNothing : findsWidgets);
      session.token = null;
      await tester.pump();
      expect(find.textContaining('4打数'), findsNothing);
      expect(find.textContaining('19号'), lineup ? findsNothing : findsWidgets);
      expect(find.textContaining('猛打賞'), lineup ? findsNothing : findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
