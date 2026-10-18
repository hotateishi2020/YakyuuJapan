import 'package:test/test.dart';
import '../app/CombinedCareerRecords.dart';
void main() {
  Map<String,dynamic> player({int ab=3000}) => {
    'name':'選手甲','mlb_id':42,'active':true,
    'npb':{'hitting':{'試合':1000,'安打':1000,'打数':ab,'打席':ab+100},'pitching':{'登板':100,'勝利':100,'投球回':'1000.2','自責点':200}},
    'mlb':{'hitting':{'gamesPlayed':500,'hits':500,'atBats':1500,'plateAppearances':1600},'pitching':{'gamesPlayed':100,'wins':50,'inningsPitched':'1000.1','earnedRuns':200}},
  };
  test('combined counts replace league-only entries and preserve ties', () {
    final rows=[{'key':'hits','leaders':[{'name':'選手 甲','value':1000},{'name':'選手乙','value':1500}]}];
    final merged=mergeCombinedCareer(rows,[player()],npb:true).single['leaders'] as List;
    expect(merged,hasLength(2)); expect(merged.map((p)=>p['rank']),[1,1]);
    expect(merged.where((p)=>p['combined']==true).single['value'],1500);
  });
  test('MLB dedup uses ID and rates use combined denominators', () {
    final merged=mergeCombinedCareer([{'key':'avg','leaders':[{'name':'English Name','player_id':42,'value':'.200'}]}],[player(ab:4000)],npb:false);
    final row=(merged.single['leaders'] as List).single;
    expect(row['value'],'0.273'); expect(row['combined'],true);
  });
  test('foreign-player short names deduplicate only with matching NPB totals', () {
    final p=player()..['name']='Ａ．選手甲';
    final r=mergeCombinedCareer([{'key':'hits','leaders':[{'name':'選手甲','value':1000}]}],[p],npb:true);
    expect(r.single['leaders'],hasLength(1));
    expect((r.single['leaders'] as List).single['value'],1500);
  });
  test('innings are outs and low-volume rates excluded', () {
    expect(careerOuts('10.2'),32);
    final merged=mergeCombinedCareer([{'key':'era','leaders':[]},{'key':'avg','leaders':[]}],[player(ab:1000)],npb:true);
    expect((merged[0]['leaders'] as List).single['value'],'1.80'); expect(merged[1]['leaders'],isEmpty);
  });
}
