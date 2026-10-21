import 'package:test/test.dart';
import '../app/TimelineCs.dart';
void main() {
  Map<String,dynamic> season(int year) => {'year':year,'leagues':[{'id_league':1,'teams':[for(var id=1;id<=3;id++) {'id_team':id,'rank':id,'wins':80-id,'losses':60+id}]}]};
  Map<String,dynamic> game(int year, String code, int home, int away, int h, int a) => {'year':year,'code_game':code,'id_team_home':home,'id_team_away':away,'score_home':h,'score_away':a,'state':'試合終了'};
  test('2004年パのプレーオフを最終順位に左右されず集計', () {
    final s=season(2004);
    final l=s['leagues'][0]; l['id_league']=2;
    l['teams'][0]['rank']=2; l['teams'][1]['rank']=1;
    addTimelineCs([s],[for(var i=0;i<2;i++) game(2004,'CS1',2,3,2,0),for(var i=0;i<3;i++) game(2004,'CSF',1,2,0,2)]);
    expect(l['cs_first_winner'],2); expect(l['cs_first_loser'],3); expect(l['cs_final_winner'],2); expect(l['cs_final_loser'],1);
    expect(l['postseason_format'],'プレーオフ');
  });
  test('確定した突破・敗退を分類', () {
    final s=season(2025);
    addTimelineCs([s],[for(var i=0;i<2;i++) game(2025,'CS1',2,3,0,2),for(var i=0;i<4;i++) game(2025,'CSF',1,3,0,2)]);
    final l=s['leagues'][0];
    expect(l['cs_first_winner'],3); expect(l['cs_first_loser'],2); expect(l['cs_final_winner'],3); expect(l['cs_final_loser'],1);
  });
  test('未確定は空欄・引き分け時の上位進出', () {
    final s=season(2025), games=[game(2025,'CS1',2,3,2,0)];
    addTimelineCs([s],games); expect(s['leagues'][0]['cs_first_winner'],isNull);
    games.add(game(2025,'CS1',2,3,0,0));
    addTimelineCs([s],games); expect(s['leagues'][0]['cs_first_winner'],2);
  });
  test('FINAL STAGEの途中では敗退チームを表示しない', () {
    final s = season(2025);
    s['leagues'][0]['cs_final_loser'] = 3;
    addTimelineCs([s], [game(2025, 'CSF', 1, 3, 0, 2)]);
    expect(s['leagues'][0]['cs_final_winner'], isNull);
    expect(s['leagues'][0]['cs_final_loser'], isNull);
  });
  test('CS未開催で日本シリーズ記録もない場合は結果を付与しない', () {
    for (final year in [2004, 2005, 2006, 2020]) {
      final s = season(year);
      s['leagues'][0]['cs_final_winner'] = 1;
      s['leagues'][0]['cs_final_loser'] = 2;
      addTimelineCs([s], [game(year, 'CSF', 1, 2, 2, 0)]);
      expect(s['leagues'][0]['cs_final_winner'], isNull);
      expect(s['leagues'][0]['cs_final_loser'], isNull);
    }
  });
  test('2020年のセは日本シリーズ出場球団を表示しCS敗退欄は空欄', () {
    final s = season(2020);
    addTimelineCs([s], [game(2020, 'JS', 1, 7, 1, 5)]);
    final league = s['leagues'][0];
    expect(league['cs_final_winner'], 1);
    expect(league['cs_final_loser'], isNull);
    expect(league['cs_first_loser'], isNull);
    expect(league['cs_first_winner'], isNull);
  });
  test('日本シリーズの未開催カードから進出球団を推測しない', () {
    final s = season(2020);
    final scheduled = game(2020, 'JS', 1, 7, 0, 0)..['state'] = '試合前';
    addTimelineCs([s], [scheduled]);
    expect(s['leagues'][0]['cs_final_winner'], isNull);
  });
  test('2007年と2020年の方式', () {
    for(final year in [2007,2020]) {
      final s=season(year);
      if (year == 2020) s['leagues'][0]['id_league'] = 2;
      addTimelineCs([s],[for(var i=0;i<(year==2007?3:2);i++) game(year,'CSF',1,2,2,0)]);
      expect(s['leagues'][0]['cs_final_winner'],1);
      expect(s['leagues'][0]['cs_final_loser'],2);
      expect(s['leagues'][0]['cs_first_winner'],isNull);
    }
  });
}
