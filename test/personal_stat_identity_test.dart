import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/View/player_stats_grid.dart';
void main() {
  for(final grid in [false,true]) {
    testWidgets('保存済みの短縮名とフルネームを個人成績で1人にまとめる grid=$grid',(tester) async {
      final rows=<Map<String,dynamic>>[
        for(final (id,name,rank,value) in [(1,'山本',1000,'9.99'),(2,'山本由伸',1,'2.53'),(3,'大谷',1000,'9.99'),(4,'大谷翔平',2,'1.79')])
          {'id_player':id,'id_team':40,'id_league':4,'title':'防御率','name_player':name,'stats':value,'int_rank':rank,'flg_pitcher':true},
      ];
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:grid
        ? PlayerStatsGrid(rows:rows,batting:false)
        : ScrollLeaguePersonalStats(rows:rows,batting:false,showJapanFlag:true))));
      expect(find.text('山本'),findsNothing);expect(find.text('大谷'),findsNothing);
      expect(find.textContaining('山本由伸'),findsOneWidget);
      expect(find.textContaining('大谷翔平'),findsOneWidget);
      expect(find.text('9.99'),findsNothing);
      expect(tester.takeException(),isNull);
    });
  }
}
