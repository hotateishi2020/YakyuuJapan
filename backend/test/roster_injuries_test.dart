import 'package:test/test.dart';
import '../app/RosterInjuries.dart';
void main() {
  test('IDまたは同球団の一意な氏名で負傷フラグを重ね、復帰済み・別球団・曖昧な選手は表示しない', () {
    final teams = <Map<String,dynamic>>[{'id_team':1,'roster':[
      {'name':'別表記','id_player':10}, {'name':'山田　太郎'},
      {'name':'復帰選手','flg_injury':true}, {'name':'別球団'}, {'name':'同姓同名'}, {'name':'重複登録'},
    ]}];
    final result = withRosterInjuries(teams, [
      {'id_player':10,'id_team':1,'name_player':'登録名','flg_injury':true},
      {'id_player':11,'id_team':1,'name_player':'山田 太郎','flg_injury':true},
      {'id_player':12,'id_team':1,'name_player':'復帰選手','flg_injury':false},
      {'id_player':13,'id_team':2,'name_player':'別球団','flg_injury':true},
      for (final id in [14,15]) {'id_player':id,'id_team':1,'name_player':'同姓同名','flg_injury':id == 14},
      for (final id in [16,17]) {'id_player':id,'id_team':1,'name_player':'重複登録','flg_injury':true},
    ]);
    expect((result.single['roster'] as List).map((r)=>r['flg_injury']), [true,true,false,false,false,true]);
    expect((teams.single['roster'] as List)[2]['flg_injury'], true);
  });
}
