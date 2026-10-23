import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/View/player_stats_grid.dart';

void main() {
  test('欠損記号と空欄を除外しゼロ・負数・複合成績を維持する', () {
    for(final value in [null,'',' ','ー','—','－','-','–','―','−','ー（ー）','— (.250)']) {
      expect(hasPersonalStatValue({'stats':value,'numeric_value':0}),false,reason:'$value');
    }
    for(final value in [0,'0','.000','0.00','0（ー）','-1','30 - 10']) {
      expect(hasPersonalStatValue({'stats':value}),true,reason:'$value');
    }
  });
  test('日本人・予想・長押し補完と詳細ランキングも欠損選手を除外する', () {
    final rows=<Map<String,dynamic>>[
      for(var i=0;i<60;i++) {'id_player':i,'int_rank':i+1,'stats':i==59?'ー':'$i','id_league':3,'flg_japan':i==59,'id_users':i==59?'1':''},
    ];
    expect(personalStatPreview(rows,includeJapanese:true,isHighlighted:(r)=>r['id_player']==59).any((r)=>r['id_player']==59),false);
    expect(personalStatRankingDetail(rows,includeJapanese:true).any((r)=>r['id_player']==59),false);
  });
  for(final batting in [true,false]) {
    testWidgets('項目ごとに欠損選手を非表示、ゼロは表示 batting=$batting',(tester) async {
      final rows=<Map<String,dynamic>>[
        {'id_player':1,'name_player':'欠損選手','stats':'ー','title':batting?'打席数':'WHIP','id_league':3,'flg_japan':true},
        {'id_player':2,'name_player':'ゼロ選手','stats':'0','title':batting?'打席数':'WHIP','id_league':3,'flg_japan':true},
      ];
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:ScrollLeaguePersonalStats(rows:rows,batting:batting,showJapanFlag:true))));
      expect(find.textContaining('欠損選手'),findsNothing);
      expect(find.textContaining('ゼロ選手'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }
}
