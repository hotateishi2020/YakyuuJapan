import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
void main() {
 testWidgets('MLB記録の個人タイトルは日本語名と英字球団略称を表示', (tester) async {
  await tester.binding.setSurfaceSize(const Size(3200, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final data={'titles':[{'year':2022,'league':'ア・リーグ','categories':[
   {'label':'本塁打王','players':[{'name':'アーロン・ジャッジ','team':'Yankees','name_shortest':'Yankees','value':62,'unit':'本'}]},
   {'label':'首位打者','players':[{'name':'ユリエスキ・グリエル','team':'Astros','name_shortest':'Astros','value':'.319'}]},
   {'label':'最優秀防御率','players':[{'name':'コーリー・クルーバー','team':'Indians','name_shortest':'Indians','value':'2.25'}]},
  ]},{'year':2022,'league':'ナ・リーグ','categories':[
   {'label':'本塁打王','players':[{'name':'大谷翔平','team':'Dodgers','name_shortest':'Dodgers','value':54,'unit':'本'}]},
  ]}]};
  await http.runWithClient(() async {
   await tester.pumpWidget(const MaterialApp(home:Scaffold(body:RecordsBoard(org:OrgConfig.mlb,year:2026))));
   await tester.pumpAndSettle();
   await tester.tap(find.byKey(const ValueKey('records-tab-1')));
   await tester.pumpAndSettle();
   for(final code in ['NYY','HOU','CLE','LAD']) {expect(find.text(code),findsOneWidget);}
   expect(find.text('アーロン・ジャッジ'),findsOneWidget);
   expect(find.text('62本'),findsOneWidget);
   expect(find.text('Yankees'),findsNothing);
   expect(tester.takeException(),isNull);
  },()=>MockClient((_)async=>http.Response(jsonEncode(data),200,headers:{'content-type':'application/json; charset=utf-8'})));
 });
}
