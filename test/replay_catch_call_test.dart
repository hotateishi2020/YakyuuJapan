import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/game_replay.dart';
import 'package:Yakyuu_Japan/logic/replay_motion.dart';
import 'package:Yakyuu_Japan/widgets/replay_field.dart';

ReplayFrame play(String code,{int bases=0,int before=0,String direction='LEFT'})=>ReplayFrame(
  inning:1,bottom:false,after:true,outs:1,bases:bases,beforeBases:before,
  homeScore:0,awayScore:0,batter:'打者',nextBatter:'次打者',label:code,
  result:code,direction:direction,defense:const {'左':'左翼手'});
void main(){
  test('catch location and verdict follow the recorded result',(){
    final fly=replayCatchCall(play('OUT_FLY'))!;
    expect(fly.position,'左');expect(fly.safe,false);expect(fly.at,.65);
    expect(replayCatchCall(play('OUT_GROUND'))!.base,1);
    for(var b=1;b<=3;b++) {
      final hit=replayCatchCall(play('HIT$b',bases:1<<(b-1)))!;
      expect(hit.base,b);expect(hit.safe,true);
    }
    expect(replayCatchCall(play('STEAL_BASE_OUT',before:2))!.base,3);
    expect(replayCatchCall(play('STEAL_BASE_SAFE',before:1,bases:2))!.base,2);
    for(final code in ['ERROR','FIELDERS_CHOICE','OUT_DOUBLE_PLAY','HOMERUN']) {
      expect(replayCatchCall(play(code)),isNull);
    }
    expect(replayCatchCall(play('OUT_FLY',direction:'')),isNull);
    expect(replayCatchCall(play('STEAL_BASE_OUT',before:3)),isNull);
  });
  testWidgets('fly verdict appears at the left fielder only after the catch',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Center(child:SizedBox(width:340,child:ReplayField(frame:play('OUT_FLY'))))));
    await tester.pump(const Duration(milliseconds:4200));
    expect(find.byKey(const Key('replay-catch-call')),findsNothing);
    await tester.pump(const Duration(milliseconds:200));
    expect(find.text('アウト'),findsOneWidget);
    final field=tester.getRect(find.byType(ReplayField));
    final call=tester.getCenter(find.byKey(const Key('replay-catch-call')));
    expect(call.dx,closeTo(field.left+field.width*.17,1));
    expect(call.dy,lessThan(field.top+field.height*.15));
    await tester.pumpAndSettle();expect(tester.takeException(),isNull);
  });
  testWidgets('double shows safe at second base when the throw arrives',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Center(child:SizedBox(width:340,child:ReplayField(frame:play('HIT2',bases:2))))));
    await tester.pump(const Duration(milliseconds:5399));
    expect(find.text('セーフ'),findsNothing);
    await tester.pump(const Duration(milliseconds:2));
    expect(find.text('セーフ'),findsOneWidget);
    final field=tester.getRect(find.byType(ReplayField));
    final call=tester.getCenter(find.byKey(const Key('replay-catch-call')));
    expect(call.dx,closeTo(field.center.dx,1));
    expect(call.dy,lessThan(field.top+field.height*.43));
    await tester.pumpAndSettle();expect(tester.takeException(),isNull);
  });
}
