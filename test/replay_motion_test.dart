import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/game_replay.dart';
import 'package:Yakyuu_Japan/logic/replay_motion.dart';
import 'package:Yakyuu_Japan/widgets/replay_field.dart';

ReplayFrame frame(String result,{int before=1,int bases=2,int runs=0})=>ReplayFrame(
  inning:1,bottom:false,after:true,outs:0,bases:bases,beforeBases:before,
  homeScore:0,awayScore:runs,runsScored:runs,batter:'現在の打者',nextBatter:'次の打者',
  label:result,result:result,direction:'LEFT',defense:const {'投':'投手名'});
void main(){
  test('runner paths cover stealing, forced advance, scoring and home runs',(){
    expect(replayRunnerTravel(frame('STEAL_BASE_SAFE')).map((r)=>(r.from,r.to)),[(1,2)]);
    expect(replayRunnerTravel(frame('WALK',bases:3)).map((r)=>(r.from,r.to)),[(0,1),(1,2)]);
    expect(replayRunnerTravel(frame('HIT2',before:4,bases:2,runs:1)).map((r)=>(r.from,r.to)),[(0,2),(3,4)]);
    expect(replayRunnerTravel(frame('HOMERUN',before:7,bases:0,runs:4)).map((r)=>(r.from,r.to)),[(1,4),(2,4),(3,4),(0,4)]);
    expect(replayRunnerTravel(frame('OUT_GROUND',before:3,bases:1)),isEmpty);
  });
  test('result types remain distinct',(){
    expect(['OUT_GROUND','OUT_FLY','OUT_LINE_DRIVE','HOMERUN','ERROR','ERROR_RUNNING','ERROR_FIELDING']
      .map((code)=>replayResultTitle(frame(code))),['ゴロ','フライ','ライナー','ホームラン','エラー','送球エラー','捕球エラー']);
  });
  testWidgets('field positions, foreground result and moving paint on a phone', (tester) async {
    final boundary=GlobalKey();
    await tester.pumpWidget(MaterialApp(home:Center(child:SizedBox(width:340,
      child:RepaintBoundary(key:boundary,child:ReplayField(frame:frame('OUT_FLY')))))));
    final field=tester.getRect(find.byType(ReplayField));
    final pitcher=tester.getCenter(find.text('投 投手名'));
    expect(pitcher.dx,closeTo(field.center.dx,1));
    expect(pitcher.dy,closeTo(field.top+field.height*.645,3));
    expect(tester.getCenter(find.byKey(const Key('replay-batter'))).dx,greaterThan(field.center.dx));
    expect(tester.getCenter(find.byKey(const Key('replay-next'))).dx,lessThan(field.center.dx));
    expect(find.text('フライ'),findsOneWidget);
    await tester.pump(const Duration(milliseconds:900));
    final render=boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final firstBytes=await tester.runAsync(() async {final image=await render.toImage();final bytes=await image.toByteData();image.dispose();return bytes;});
    await tester.pump(const Duration(milliseconds:900));
    final secondBytes=await tester.runAsync(() async {final image=await render.toImage();final bytes=await image.toByteData();image.dispose();return bytes;});
    expect(firstBytes!.buffer.asUint8List(),isNot(orderedEquals(secondBytes!.buffer.asUint8List())));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
  });
}
