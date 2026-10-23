import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'package:Yakyuu_Japan/logic/record_awards.dart';

void main() {
  test('equivalent titles share columns but distinct awards and seasons remain separate', () {
    expect(recordAwardLabel('沢村栄治賞'), '沢村賞');
    expect(recordAwardLabel('MVP'), 'リーグMVP');
    expect(recordAwardLabel('最優秀選手'), 'リーグMVP');
    expect(recordAwardLabel('最優秀新人'), '新人王');
    expect(recordAwardLabel('ベストナイン （投手）'), recordAwardLabel('ベストナイン賞（投手）'));
    expect(recordAwardLabel('ベストDH賞（指名打者）'), recordAwardLabel('ベストDH（指名打者）'));
    expect(recordAwardLabel('勝率第一位投手'), '最高勝率');
    expect(recordAwardLabel('カムバック選手賞'), 'カムバック賞');
    expect(recordAwardLabel('最優秀投手'), isNot(recordAwardLabel('最高勝率')));
    expect(recordAwardLabel('MVP（春）'), isNot(recordAwardLabel('MVP（秋）')));
    final groups = normalizeRecordAwards([
      {'label':'最多本塁打者', 'players':[{'id_player':1,'name':'A','value':40,'unit':'本'}]},
      {'label':'本塁打王', 'players':[{'id_player':1,'name':'A','value':'受賞'},{'id_player':2,'name':'B','value':40}]},
    ]);
    expect(groups.length,1);
    expect((groups.single['players'] as List).length,2);
    expect(groups.single['players'][0]['value'],40);
  });

  testWidgets('year column stays fixed horizontally and synchronized vertically', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600,700));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final payload={'titles':[for(var year=2026;year>=1990;year--) {
      'year':year,'league':'セ・リーグ','categories':[
        {'label':year>=2017?'MVP':'最優秀選手','players':[{'name':'受賞者$year','team':'阪神タイガース'}]},
        {'label':year>=2017?'新人王':'最優秀新人','players':[{'name':'新人$year'}]},
        {'label':year>=2017?'ベストナイン賞（投手）':'ベストナイン （投手）','players':[{'name':'投手$year'}]},
        {'label':'本塁打王','players':[{'name':'打者$year','value':40}]},
      ],
    }]};
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home:Scaffold(body:RecordsBoard(org:OrgConfig.npb,year:2026))));
      await tester.pumpAndSettle();
      tester.widget<DropdownButton<int>>(find.byKey(const ValueKey('records-picker-npb'))).onChanged!(1);
      await tester.pumpAndSettle();
      expect(find.text('沢村賞'),findsOneWidget);
      expect(find.text('リーグMVP'),findsOneWidget);
      expect(tester.getTopLeft(find.text('神').first).dx, lessThan(tester.getTopLeft(find.text('受賞者2026')).dx));
      expect(find.text('阪神タイガース'), findsNothing);
      expect(find.text('MVP'),findsNothing);
      expect(find.text('最優秀選手'),findsNothing);
      expect(find.text('新人王'),findsOneWidget);
      expect(find.text('ベストナイン（投手）'),findsOneWidget);
      final yearCell=find.byKey(const ValueKey('title-fixed-year-2026'));
      final before=tester.getTopLeft(yearCell);
      final headerBefore=tester.getTopLeft(find.text('年度'));
      await tester.drag(find.byKey(const ValueKey('title-horizontal-scroll')),const Offset(-350,0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(yearCell),before);
      final right=tester.widget<ListView>(find.byKey(const ValueKey('title-body-scroll'))).controller!;
      final left=tester.widget<ListView>(find.byKey(const ValueKey('title-years-scroll'))).controller!;
      await tester.drag(find.byKey(const ValueKey('title-body-scroll')),const Offset(0,-260));
      await tester.pumpAndSettle();
      expect(right.offset,greaterThan(0));
      expect(left.offset,closeTo(right.offset,.01));
      expect(tester.getTopLeft(find.text('年度')),headerBefore);
      await tester.drag(find.byKey(const ValueKey('title-years-scroll')),const Offset(0,120));
      await tester.pumpAndSettle();
      expect(left.offset,closeTo(right.offset,.01));
      expect(tester.takeException(),isNull);
    },()=>MockClient((_)async=>http.Response(jsonEncode(payload),200,headers:{'content-type':'application/json; charset=utf-8'})));
  });
}
