import 'package:test/test.dart';
import '../app/ClubRecords.dart';
void main() {
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
