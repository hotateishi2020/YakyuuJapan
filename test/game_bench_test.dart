import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/game_bench.dart';
import 'package:Yakyuu_Japan/widgets/game_bench_row.dart';
void main() {
  final game = <String,dynamic>{'id_team_home':1,'id_team_away':2,
    'name_team_home':'ホーム','name_team_away':'ビジター',
    'name_pitcher_home':'先発投手',
    'lineup':[{'id_team':1,'players':[{'name':'出場 選手'}]}],
    'summaries':[{'id_team_summary':1,'name_full_summary':'登板投手'}],
    'bench_players':[
      for (final name in ['先発投手','登板投手','控え投手']) {'id_team':1,'name':name,'pitcher':true},
      {'id_team':1,'name':'出場選手','pitcher':false},
      {'id_team':1,'name':'控え野手','pitcher':false},
      {'id_team':2,'name':'相手野手','pitcher':false},
    ]};
  test('excludes starters and appeared players, preserves opposing bench', () {
    expect(unusedGameBench(game,1).map((r)=>r['name']),['控え投手','控え野手']);
    expect(unusedGameBench(game,2).map((r)=>r['name']),['相手野手']);
  });
  for (final stacked in [true,false]) {
    testWidgets('bench layout stacked=$stacked', (tester) async {
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:stacked?320:900,
        child:GameBenchRow(game:game,stacked:stacked)))));
      expect(find.text('控え投手'),findsOneWidget);
      expect(find.text('出場選手'),findsNothing);
      expect(tester.takeException(),isNull);
    });
  }
}
