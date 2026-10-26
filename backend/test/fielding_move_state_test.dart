import 'package:test/test.dart';
import '../app/LiveText.dart';

void main() {
  test('代走は交代元のレフトを引き継ぎ、翌回のfromとして保存できる', () {
    final runner = ParsedLiveEvent()..result='PINCH_RUNNER'..exitName='柳田'..enterName='川村';
    final kondo = ParsedLiveEvent()..result='CHANGE_POSITION'..enterName='近藤'..exitName='近藤'..positionTo='LEFT';
    final kawamura = ParsedLiveEvent()..result='CHANGE_POSITION'..enterName='川村'..exitName='川村'..positionTo='RIGHT';
    ParsedPlate plate(List<ParsedLiveEvent> events) => ParsedPlate(battingOrder:1,batterName:'打者',outs:0,runnerFirst:false,runnerSecond:false,runnerThird:false,events:events);
    final parsed = ParsedLiveText(finished:true, positions:{false:{'柳田':'左','近藤':'右'}}, halves:[
      ParsedHalf(inning:7,bottom:false,plates:[plate([runner])]),
      ParsedHalf(inning:8,bottom:true,plates:[plate([kondo,kawamura])]),
    ]);
    LiveText.completeFieldingMoves(parsed);
    expect(kondo.positionFrom,'RIGHT');
    expect(kondo.positionTo,'LEFT');
    expect(kawamura.positionFrom,'LEFT');
    expect(kawamura.positionTo,'RIGHT');
    expect(kawamura.result,'CHANGE_POSITION');
  });
}
