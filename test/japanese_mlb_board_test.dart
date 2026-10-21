import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/japanese_mlb_board.dart';
void main() {
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
      expect(find.text('二刀流'),findsNWidgets(2));
      expect(find.byType(DataTable),findsNWidgets(2));
      final tables = find.byType(DataTable);
      expect(tester.getSize(tables.first).width, tester.getSize(tables.last).width);
      expect(tester.takeException(),isNull);
    },()=>MockClient((request) async {
      expect(request.url.path,endsWith('/mlb-japanese-stats'));
      expect(request.url.queryParameters['year'],'2025');
      return http.Response(jsonEncode({'players':[
        for(final pitching in [true,false]) {'id_player':1,'name_player':'二刀流','name_team':'LAD','pitching':pitching,'stats':{'本塁打':50,'防御率':'2.50'}}
      ]}),200,headers:{'content-type':'application/json; charset=utf-8'});
    }));
  });
}
