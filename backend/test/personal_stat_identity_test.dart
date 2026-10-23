import 'package:test/test.dart';
import '../app/PersonalStatIdentity.dart';
void main() {
  test('短縮名を統合しランク内の成績とフルネームIDを残す（入力順によらない）', () {
    final rows=<Map<String,dynamic>>[
      {'id_player':1,'id_team':40,'id_league':4,'title':'本塁打','name_player':'大谷(3.0%)','stats':'0','int_rank':1000,'cnt_play':14,'id_users':'1'},
      {'id_player':2,'id_team':40,'id_league':4,'title':'本塁打','name_player':'大谷翔平','stats':'30','int_rank':9,'cnt_play':618,'id_users':'2'},
      {'id_player':3,'id_team':40,'id_league':4,'title':'防御率','name_player':'山本','stats':'9.99','int_rank':1000},
      {'id_player':4,'id_team':40,'id_league':4,'title':'防御率','name_player':'山本由伸','stats':'0.00','int_rank':1},
    ];
    for(final input in [rows,rows.reversed.toList()]) {
      final result=canonicalMlbPersonalStats(input);
      expect(result,hasLength(2));
      final hr=result.firstWhere((r)=>r['title']=='本塁打');
      expect(hr['stats'],'30');expect(hr['id_player'],2);expect(hr['name_player'],'大谷翔平');
      expect('${hr['id_users']}'.split('/').toSet(),{'1','2'});
      final era=result.firstWhere((r)=>r['title']=='防御率');
      expect(era['name_player'],'山本由伸');expect(era['stats'],'0.00');
    }
  });
  test('球団・リーグ・スタッツをまたいで統合せずNPB同姓選手にも触れない', () {
    final rows=<Map<String,dynamic>>[
      for(final team in [40,41]) for(final title in ['打率','本塁打'])
        {'id_team':team,'id_league':4,'title':title,'name_player':'大谷翔平','stats':1},
      {'id_team':1,'id_league':1,'title':'打率','name_player':'山本'},
      {'id_team':1,'id_league':1,'title':'打率','name_player':'山本由伸'},
    ];
    expect(canonicalMlbPersonalStats(rows),hasLength(6));
    expect(rows.last['name_player'],'山本由伸');
  });
}
