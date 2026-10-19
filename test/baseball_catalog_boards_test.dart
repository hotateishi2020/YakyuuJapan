import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/baseball_catalog_boards.dart';
import 'package:Yakyuu_Japan/View/other_baseball_board.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/View/team_strength_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  test('stadium sort uses league, numeric units and keeps missing values last', () {
    expect(compareStadiumRows({'id_league':1}, {'id_league':2}, null, true), lessThan(0));
    expect(compareStadiumRows({'id_league':1}, {'id_league':2}, 'team', true), lessThan(0));
    expect(compareStadiumRows({'id_league':1}, {'id_league':2}, 'team', false), greaterThan(0));
    expect(compareStadiumRows({'id_league':1, 'id_team':1}, {'id_league':1, 'id_team':2}, 'team', true), lessThan(0));
    expect(compareStadiumRows({'construction':'約90億円'}, {'construction':'約123.1億円'}, 'construction', true), lessThan(0));
    expect(compareStadiumRows({'capacity':null}, {'capacity':'35,000人'}, 'capacity', false), greaterThan(0));
    expect(stadiumSortValue('52億2,800万円（総工費）', 'construction')!.$1, 5228000000);
    expect(stadiumSortValue('駅：徒歩約15分', 'station_distance')!.$1, 15);
  });
  test('現役で当年未着用なら別色、永久欠番の色は優先', () {
    const current={'status':'active','worn_in_selected_year':true};
    const past={'status':'active','worn_in_selected_year':false};
    expect(uniformStatus(past),'現役（当年未着用）');
    expect(uniformColor(past),isNot(uniformColor(current)));
    expect(uniformColor(past),isNot(uniformColor({'status':'retired'})));
    expect(uniformColor({...past,'status':'permanent'}),uniformColor({'status':'permanent'}));
  });
  testWidgets('record picker switches to uniforms and hall', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: RecordsBoard(org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('records-picker-npb'));
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('背番号').last);
      await tester.tap(find.text('背番号').last);
      await tester.pumpAndSettle();
      expect(find.byType(UniformHistoryBoard), findsOneWidget);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('殿堂入り・名球会').last);
      await tester.tap(find.text('殿堂入り・名球会').last);
      await tester.pumpAndSettle();
      expect(find.byType(HallOfFameBoard), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });
  testWidgets('strength picker opens stadiums without strength data',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(
                  org: OrgConfig.npb, year: 2026, providedTeams: []))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-picker')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('球場').last);
      await tester.tap(find.text('球場').last);
      await tester.pumpAndSettle();
      expect(find.byType(StadiumsBoard), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });
  testWidgets(
      'jersey 0 and 00 stay separate and +N opens history at mobile width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: UniformHistoryBoard(org: 'npb', year: 2026))));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      expect(find.text('00'), findsOneWidget);
      expect(find.text('現姓'), findsOneWidget);
      expect(find.text('新背番号'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('uniform-more-1-0')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('旧姓 選手'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'teams': [
                {'id_team': 1, 'name_team': '球団'}
              ],
              'uniforms': [
                {
                  'id_team': 1,
                  'number': '0',
                  'name': '現姓 選手',
                  'surname': '現姓',
                  'new_uniform_number': true,
                  'status': 'active'
                },
                {
                  'id_team': 1,
                  'number': '0',
                  'name': '旧姓 選手',
                  'surname': '旧姓',
                  'status': 'retired'
                },
                {
                  'id_team': 1,
                  'number': '00',
                  'name': '別人',
                  'surname': '別人',
                  'status': 'retired'
                },
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
  });
  testWidgets('stadium columns scroll as one grid at mobile width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: StadiumsBoard(org: 'npb'))));
      await tester.pumpAndSettle();
      expect(find.text('球場名'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stadium-sort-team')));
      await tester.pumpAndSettle();
      expect(find.text('ホームチーム ▲'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stadium-sort-team')));
      await tester.pumpAndSettle();
      expect(find.text('ホームチーム ▼'), findsOneWidget);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(-1500, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stadium-sort-station_distance')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stadium-sort-station_distance')));
      await tester.pumpAndSettle();
      expect(find.text('最寄り駅・距離／徒歩目安 ▲'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stadium-sort-station_distance')));
      await tester.pumpAndSettle();
      expect(find.text('最寄り駅・距離／徒歩目安 ▼'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'stadiums': [
                {'name': '球場', 'team': '球団'}
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
  });
  testWidgets('other tab renders official bracket and international section',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: OtherBaseballBoard(year: 2026))));
    await tester.pumpAndSettle();
    expect(find.textContaining('祐誠'), findsOneWidget);
    expect(find.text('決勝'), findsOneWidget);
    await tester.tap(find.text('国際シリーズ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('まだ登録されていません'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
