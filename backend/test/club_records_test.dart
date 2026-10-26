import 'package:test/test.dart';
import '../app/ClubRecords.dart';
void main() {
  test('球団別の監査値を使い全国首位の流用と未確認値を抑止する', () {
    final result=buildClubRecords([
      {'id_team':1,'short_name':'巨人'}, {'id_team':2,'short_name':'阪神'}], [],2026,
      streakRows:[{'id_team':1,'key':'wins','year':2026,'current':true,'name':'古い流用値','value':99}],
      currentStreakSnapshot:{'checked_at':'2026-10-26','clubs':{
        'G':{'records':{'wins':[{'name':'甲','value':5},{'name':'乙','value':5}]},
          'categories':{'wins':{'status':'verified','sources':['https://npb.jp/']}}},
        'T':{'records':{'wins':[{'name':'未検証','value':999}]},
          'categories':{'wins':{'status':'unavailable','note':'全試合未確認'}}},
      }});
    final metric=(result['metrics'] as List).firstWhere((m)=>m['key']=='streak_wins');
    expect(metric['cells'][0]['current'].length,2);
    expect(metric['cells'][0]['current'][0]['value'],5);
    expect(metric['cells'][0]['current_sources'],['https://npb.jp/']);
    expect(metric['cells'][1]['current'],isEmpty);
    expect(metric['cells'][1]['current_message'],contains('全試合未確認'));
  });
  test('監査ファイルがない年度の全国首位を球団首位として表示しない', () {
    final data=buildClubRecords([{'id_team':1,'short_name':'巨人'}],[],2025,
      streakRows:[{'id_team':1,'key':'wins','year':2025,'current':true,'name':'全国首位','value':10}]);
    final cell=(data['metrics'] as List).firstWhere((m)=>m['key']=='streak_wins')['cells'][0];
    expect(cell['current'],isEmpty);
    expect(cell['current_status'],'unavailable');
  });
  test('球団別に前年までと今季を分離し同率の選手を残す', () {
    final result = buildClubRecords([{'id_team': 1}, {'id_team': 2}], [
      {'id_team': 1, 'key': 'hr', 'year': 2000, 'name': '旧記録', 'value': 50},
      {'id_team': 1, 'key': 'hr', 'year': 2026, 'name': 'A', 'value': 51},
      {'id_team': 1, 'key': 'hr', 'year': 2026, 'name': 'B', 'value': 51},
      {'id_team': 2, 'key': 'hr', 'year': 2000, 'name': '他球団', 'value': 60},
    ], 2026);
    final hr = (result['metrics'] as List).firstWhere((m) => m['key'] == 'hr');
    expect(hr['cells'][0]['record'].single['value'], 50);
    expect(hr['cells'][0]['current'].length, 2);
    expect(hr['cells'][1]['current'], isEmpty);
    expect((result['metrics'] as List).length, 35);
  });
  test('通算と連続を分離し記録当時の球団だけに連続記録を割り当てる', () {
    final teams = [{'id_team':1,'name':'A'},{'id_team':2,'name':'B'}];
    final streaks = assignClubStreaks([
      {'name':'移籍選手','year':2000,'key':'wins','value':10,'current':false},
      {'name':'不明選手','year':2000,'key':'wins','value':99,'current':false},
    ], [
      {'name':'移籍選手','year':2000,'id_team':1},
      {'name':'移籍選手','year':2026,'id_team':2},
    ], teams);
    expect(streaks.single['id_team'],1);
    final data = buildClubRecords(teams,[
      {'id_team':1,'year':2025,'key':'career_hits','value':2000,'name':'歴代'},
      {'id_team':1,'year':2026,'key':'career_hits','value':1500,'name':'現役'},
    ],2026,streakRows:streaks);
    final metrics = data['metrics'] as List;
    expect(metrics.firstWhere((m)=>m['key']=='career_hits')['cells'][0]['current'].single['value'],1500);
    expect(metrics.firstWhere((m)=>m['key']=='streak_wins')['cells'][0]['record'].single['value'],10);
    expect(clubRecordValue('64 1/3'),closeTo(64.3333,.001));
  });

}
