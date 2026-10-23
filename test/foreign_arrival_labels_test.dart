import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/foreign_arrival_labels.dart';
import 'package:Yakyuu_Japan/logic/strength_usage.dart';
import 'package:Yakyuu_Japan/logic/roster_transfer_status.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';

void main() {
  test('12球団の保存済み名簿を補完し、残留選手と別年度は対象にしない', () {
    final teams = [for (final name in foreignArrivals2026.map((e) => e.team).toSet()) <String,dynamic>{
      'name_team':name,
      'roster': [for (final e in foreignArrivals2026.where((e) => e.team == name))
        {'name':e.name,'player_key':e.key}, {'name':'残留選手','birth_country':'アメリカ'}],
    }];
    expect(teams, hasLength(12));
    final filled = withForeignArrivalLabels(teams, 2026, npb:true);
    for(final team in filled) {
      final players = team['roster'] as List;
      for(final p in players.take(players.length-1)) {
        expect(rosterMoveLabels(Map<String,dynamic>.from(p),2026), contains(p['move_method']));
        expect(rosterTimedMoveLabel(p['move_method'],Map<String,dynamic>.from(p),2026),
          '${p['move_method_period']} ${p['move_method']}');
        expect(rosterTransferBlock(Map<String,dynamic>.from(p),team,2026),p['arrival_period']=='昨オフ'?1:0);
      }
      expect(players.last['move_method'],isNull);
    }
    expect((teams.first['roster'] as List).first['move_method'],isNull);
    expect(withForeignArrivalLabels(teams,2025,npb:true).first['roster'],teams.first['roster']);
    expect(withForeignArrivalLabels(teams,2026,npb:false),same(teams));
    expect(withForeignArrivalLabels(filled,2026,npb:true),filled);
  });
  test('新外国人表記をFA移籍にし、その後の退団・トレードは保持する', () {
    final team = {'name_team':'西武','roster':[
      {'name':'カナリオ','move_method':'新外国人','move_method_year':2026,'move_method_as_of':'2025-12-22','departure_confirmed':true},
      {'name':'ワイナンス','move_method':'トレード','move_method_year':2026,'move_method_as_of':'2026-07-10'},
    ]};
    final players=withForeignArrivalLabels([team],2026,npb:true).single['roster'] as List;
    expect(players.first['departure_confirmed'],true);
    expect(rosterTimedMoveLabel('FA移籍',Map<String,dynamic>.from(players.first),2026),'昨オフ FA移籍');
    expect(players.last['move_method'],'トレード');
    expect(players.last['move_method_as_of'],'2026-07-10');
  });
  testWidgets('カナリオとマッカスカーのカードに昨オフFA移籍を表示する', (tester) async {
    final teams=withForeignArrivalLabels([
      {'name_team':'西武','id_team':8,'roster':[{'name':'カナリオ','player_key':'npb:23325152','position_group':'外野手'}]},
      {'name_team':'楽天','id_team':11,'roster':[{'name':'マッカスカー','player_key':'npb:73775152','position_group':'外野手'}]},
    ],2026,npb:true);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:Column(children:[
      for(final team in teams) SizedBox(height:500, child:StrengthRosterGrid(team:team,year:2026)),
    ])))));
    expect(find.text('昨オフ FA移籍'),findsNWidgets(2));
    expect(find.text('昨オフ 新戦力'),findsNWidgets(2));
    expect(tester.takeException(),isNull);
  });
}
