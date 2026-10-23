import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/japanese_mlb_board.dart';
void main() {
  testWidgets('グリッドの役割を限定し球団色を28pxのセル全体に表示する', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: JapaneseMlbStatsGrid(
      pitching: true,
      players: [
        {'id_player': 1, 'name_player': '対象投手（25.5%）', 'id_league': 4, 'name_league': 'ナ・リーグ', 'name_area': '西地区', 'name_team': 'LAD', 'color_back': '#123456', 'pitching': true, 'salary_label': '1800万ドル', 'contract_label': '5年 9000万ドル（2030年まで）'},
        {'id_player': 2, 'name_player': '対象野手', 'name_team': 'SEA', 'pitching': false},
      ],
    ))));
    expect(find.text('対象投手'), findsOneWidget);
    expect(find.text('対象野手'), findsNothing);
    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.dataRowMinHeight, 28);
    expect(table.dataRowMaxHeight, 28);
    expect(table.columnSpacing, 0);
    expect((table.columns.last.label as Padding).child, isA<Text>().having((t) => t.data, 'title', '契約内容'));
    expect(find.text('年俸 1800万ドル【5年 9000万ドル（2030年まで）】'), findsOneWidget);
    expect(find.text('規定到達率'), findsOneWidget);
    expect((table.columns[4].label as Padding).child, isA<Text>().having((t) => t.data, 'title', '規定到達率'));
    expect(find.text('ー'), findsWidgets);
    final team = table.rows.single.cells[2].child as Container;
    final teamRect = tester.getRect(find.byWidget(team));
    final playerRect = tester.getRect(find.byWidget(table.rows.single.cells[3].child));
    // Compare laid-out edges: a fixed Table column may expand to fill the table.
    expect(teamRect.left, greaterThan(tester.getRect(find.byType(DataTable)).left));
    expect(find.text('リーグ'), findsOneWidget);
    expect(find.text('地区'), findsOneWidget);
    expect(find.text('リーグ・地区・球団順'), findsOneWidget);
    expect(teamRect.right, closeTo(playerRect.left, .01));
    for (final index in [0,1]) {
      final cell=table.rows.single.cells[index].child as Container;
      expect(cell.color,const Color(0xff002d72));
      expect(tester.getSize(find.byWidget(cell)).height,28);
    }
    expect(team.constraints!.maxHeight, 28);
    expect((team.decoration as BoxDecoration).color, const Color(0xff123456));
    expect((team.decoration as BoxDecoration).borderRadius, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日本人選手を投手・野手に分け、選択年度を取得する', (tester) async {
    tester.view.physicalSize = const Size(390,800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: JapaneseMlbBoard(year:2025))));
      await tester.pumpAndSettle();
      expect(find.text('投手'),findsOneWidget);
      expect(find.text('野手'),findsOneWidget);
      expect(find.text('ダルビッシュ有'),findsOneWidget);
      expect(find.text('ラーズ・ヌートバー'),findsOneWidget);
      expect(find.byType(DataTable),findsNWidgets(2));
      final tables = find.byType(DataTable);
      expect(tester.getSize(tables.first).width, tester.getSize(tables.last).width);
      final grids = tester.widgetList<DataTable>(tables).toList();
      for (var i = 0; i < 4; i++) {
        expect((grids[0].columns[i].columnWidth as FixedColumnWidth).value,
            (grids[1].columns[i].columnWidth as FixedColumnWidth).value);
      }
      await tester.ensureVisible(find.text('規定到達率').first);
      await tester.tap(find.text('規定到達率').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(),isNull);
    },()=>MockClient((request) async {
      expect(request.url.path,endsWith('/mlb-japanese-stats'));
      expect(request.url.queryParameters['year'],'2025');
      return http.Response(jsonEncode({'players':[
        for(final pitching in [true,false]) {'id_player':1,'name_player':pitching?'ダルビッシュ有':'ラーズ・ヌートバー','name_team':pitching?'パドレス':'ダイヤモンドバックス','id_league':4,'name_league':'ナ・リーグ','name_area':'西地区','pitching':pitching,'salary_label':'2202.5万ドル','contract_label':'1年 2202.5万ドル（2026年まで）','stats':{'本塁打':50,'防御率':'2.50','規定到達率':'100.0','投球回':'185.1','打率':'.239','盗塁':32}}
      ]}),200,headers:{'content-type':'application/json; charset=utf-8'});
    }));
  });
}
