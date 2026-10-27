import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/game_replay.dart';
import 'package:Yakyuu_Japan/widgets/replay_scoreboard.dart';
import 'package:Yakyuu_Japan/widgets/replay_field.dart';
ReplayFrame frame(int inning,bool bottom,int home,int away,{int outs=0})=>ReplayFrame(
  inning:inning,bottom:bottom,after:false,outs:outs,bases:0,homeScore:home,awayScore:away,
  batter:'打者',nextBatter:'次打者',label:'',defense:const {});
void main(){
  final frames=[frame(1,false,0,0),frame(1,false,0,2),frame(1,true,0,2),frame(1,true,1,2),frame(2,false,1,2),frame(2,false,1,3,outs:2)];
  test('inning totals follow progress and rewind without revealing future runs',(){
    expect(replayInningScores(frames,5),{'1:false':2,'1:true':1,'2:false':1});
    expect(replayInningScores(frames,0),{'1:false':0});
    expect(replayInningScores(frames,2),{'1:false':2,'1:true':0});
  });
  testWidgets('phone scoreboard and red outs render without overflow',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Center(child:SizedBox(width:320,child:Column(mainAxisSize:MainAxisSize.min,children:[
      ReplayScoreboard(frames:frames,index:5,home:'ソフトバンク',away:'DeNA'),ReplayField(frame:frames.last),
    ]))))));
    expect(find.text('3 - 1'),findsOneWidget);
    expect(find.text('OUT 🔴🔴'),findsOneWidget);
    expect(find.text('表 DeNA'),findsOneWidget);
    expect(find.text('裏 ソフトバンク'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
