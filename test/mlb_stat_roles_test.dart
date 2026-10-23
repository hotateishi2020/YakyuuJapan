import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/View/player_stats_grid.dart';
void main() {
  for(final grid in [false,true]) for(final batting in [false,true]) {
    testWidgets('古い保存データの誤った投手分類を補正する grid=$grid batting=$batting',(tester) async {
      final rows=<Map<String,dynamic>>[
        for(final name in ['吉田正尚','西田陸浮','岡本和真','村上宗隆','鈴木誠也','ラーズ・ヌートバー','今井達也','菊池雄星','大谷翔平'])
          {'id_player':name,'name_player':'$name(50.0%)','name_team':'球団','id_league':3,
           'title':batting?'打率':'防御率','stats':batting?'.274':'2.50','int_rank':1000,
           'txt_position':'投手','season_position_groups':[],'flg_japan':true},
      ];
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:grid
        ? PlayerStatsGrid(rows:rows,batting:batting)
        : ScrollLeaguePersonalStats(rows:rows,batting:batting,showJapanFlag:true))));
      for(final name in ['吉田正尚','西田陸浮','岡本和真','村上宗隆','鈴木誠也','ラーズ・ヌートバー']) {
        expect(find.textContaining(name),batting?findsOneWidget:findsNothing);
      }
      for(final name in ['今井達也','菊池雄星']) {
        expect(find.textContaining(name),batting?findsNothing:findsOneWidget);
      }
      expect(find.textContaining('大谷翔平'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }
}
