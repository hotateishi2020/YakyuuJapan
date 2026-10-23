import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/View/player_stats_grid.dart';

void main() {
  test('投手専任と二刀流を成績種別フラグとは別に判定する', () {
    expect(isPitcherOnlyStatPlayer({'txt_position':'投手','flg_pitcher':false}),true);
    expect(isPitcherOnlyStatPlayer({'txt_position':'投手','season_position_groups':['指名打者']}),false);
    expect(isPitcherOnlyStatPlayer({'txt_position':'投手','flg_two_way':true}),false);
    expect(isPitcherOnlyStatPlayer({'id_league':4,'txt_position':'投手','name_player':'大谷 翔平','season_position_groups':[]}),false);
    expect(isPitcherOnlyStatPlayer({'txt_position':'外野手'}),false);
  });
  for(final grid in [false,true]) {
    testWidgets('打者全項目から日本人投手を除外し大谷と野手は残す grid=$grid', (tester) async {
      final rows=<Map<String,dynamic>>[
        for(final title in ['打率','本塁打','打点','盗塁','最多安打','出塁率','長打率','OPS','打席数','ボール球見極め率','代打起用数'])
          for(final name in ['今井達也','菊池雄星','大谷翔平','吉田正尚']) {
            'id_player':name,'name_player':name,'name_team':'球団','id_league':3,'title':title,
            'txt_position':name=='吉田正尚'?'外野手':'投手',
            'season_position_groups':name=='大谷翔平'?['投手','指名打者']:[],
            'flg_japan':true,'flg_pitcher':false,'stats':'.300','int_rank':1000,
          }
      ];
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:grid
        ? PlayerStatsGrid(rows:rows,batting:true)
        : ScrollLeaguePersonalStats(rows:rows,batting:true,showJapanFlag:true))));
      await tester.pump();
      expect(find.textContaining('今井達也'),findsNothing);
      expect(find.textContaining('菊池雄星'),findsNothing);
      expect(find.textContaining('大谷翔平'),findsWidgets);
      expect(find.textContaining('吉田正尚'),findsWidgets);
      expect(tester.takeException(),isNull);
    });
  }
}
