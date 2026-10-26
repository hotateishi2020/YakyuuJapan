import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/season_titles.dart';
import 'package:Yakyuu_Japan/View/season_titles_table.dart';

void main() {
  test('HR-盗塁の歴代上位入りをシーズン記録更新と扱わない', () {
    final data=<String,dynamic>{'season':[{
      'key':'hr_sb','label':'HR - 盗塁','unit':'',
      'leaders':[
        {'name':'大谷翔平','year':2024,'value':'54 - 59','numeric_value':54,'rank':1},
        {'name':'PCA','year':2026,'value':'45 - 41','numeric_value':41,'rank':3},
      ],
      'current':[{'name':'PCA','year':2026,'value':'45 - 41','numeric_value':41}],
    }]};
    expect(buildSeasonTitles(data,2026)['records'],isEmpty);
    final holder=buildSeasonTitles(data,2024)['records']!;
    expect(holder.single['name'],'大谷翔平');
    expect(holder.single['value'],'54 - 59');
  });
  test('単独更新と同記録の最高値だけを選ぶ', () {
    final rows=buildSeasonTitles({'season':[
      {'key':'hr','label':'本塁打','unit':'本','leaders':[
        {'name':'歴代','year':2013,'value':60},
        {'name':'当年上位','year':2026,'value':40}],
        'current':[{'name':'更新者','year':2026,'value':61}]},
      {'key':'sb','label':'盗塁','unit':'個','leaders':[
        {'name':'同記録','year':2026,'value':100},{'name':'過去','year':2000,'value':100}]},
    ]},2026)['records']!;
    expect(rows.map((r)=>r['name']),['更新者','同記録']);
    expect(rows.first['unit'],'本');
  });
  testWidgets('記録更新者の名前とスタッツ値を表示する', (tester) async {
    final groups=buildSeasonTitles({'season':[{
      'key':'hr','label':'本塁打','unit':'本',
      'leaders':[{'name':'更新者','year':2026,'value':61}],
    }]},2026);
    final table=SeasonTitlesTable(groups:groups,year:2026);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:table.winners(groups['records']!))));
    expect(find.text('更新者'),findsOneWidget);
    expect(find.text('本塁打：61本'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
