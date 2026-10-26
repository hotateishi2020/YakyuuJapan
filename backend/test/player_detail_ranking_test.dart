import 'package:test/test.dart';
import '../app/PlayerDisplay.dart';

void main() {
  test('詳細は個人成績の値・順位をそのまま使用し選手内で再順位付けしない', () {
    final rows=<Map<String,dynamic>>[
      {'id_player':1,'title':'BB/9','stats':'0.96','int_rank':1},
      {'id_player':2,'title':'BB/9','stats':'1.56','int_rank':2},
      {'id_player':2,'title':'四死球/9','stats':'1.79','int_rank':2},
      {'id_player':2,'title':'平均投球回','stats':'6.45','int_rank':6},
      {'id_player':2,'title':'登板回数','stats':'25','int_rank':49},
      {'id_player':2,'title':'QS率','stats':'88.0','int_rank':1},
      {'id_player':2,'title':'GG受賞回数','stats':'1','int_rank':3},
    ];
    final result=playerDetailSeasonStats(rows,2);
    expect(result.map((r)=>r['int_rank']),[2,2,6,49,1,3]);
    expect(result.map((r)=>r['stats']),['1.56','1.79','6.45','25','88.0','1']);
    result.first['int_rank']=99;
    expect(rows[1]['int_rank'],2);
  });
  test('規定未到達・同順位を保持し、現行ランキングにない項目を復活させない', () {
    final result=playerDetailSeasonStats([
      {'id_player':'2','title':'打率','int_rank':1000},
      {'id_player':2,'title':'本塁打','int_rank':3},
      {'id_player':3,'title':'本塁打','int_rank':3},
    ],2);
    expect(result.map((r)=>r['int_rank']),[1000,3]);
    expect(playerDetailSeasonStats([],2),isEmpty);
  });
}
