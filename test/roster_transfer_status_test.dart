import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/roster_transfer_status.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';
import 'package:Yakyuu_Japan/View/team_section_layout.dart';

void main() {
  test('入団選手は支配下・育成の区分内で数値の指名順', () {
    final players = <Map<String, dynamic>>[
      {'name': '移籍', 'move_method': 'トレード'},
      {'name': 'FA加入', 'move_method': 'FA移籍'},
      {'name': '現役加入', 'move_method': '現役ドラフト', 'arrival_draft_type':'現役','arrival_draft_rank':1},
      {'name': '育成1', 'move_method': '育成ドラフト1位'},
      {'name': '10位', 'move_method': '新人ドラフト10位'},
      {'name': '2位', 'arrival_draft_rank': 2, 'arrival_draft_type': '支配下'},
      {'name': '1位', 'move_method': '新人ドラフト1位'},
    ]..sort((a, b) => compareRosterArrivalDraft(a, b, {}));
    expect(players.take(3).map((p) => p['name']).toSet(), {'移籍','FA加入','現役加入'});
    expect(players.skip(3).map((p) => p['name']), ['1位', '2位', '10位', '育成1']);
  });
  const team = {'opening_date': '2026-03-27'};
  test('開幕時の所属と噂は在籍、開幕後加入と確定退団を分ける', () {
    for (final date in ['2025-12-01', '2026-02-10', '2026-03-27']) {
      expect(
          rosterTransferBlock({
            'new_arrival': true,
            'arrival_year': 2026,
            'arrival_as_of': date
          }, team, 2026),
          1);
    }
    expect(
        rosterTransferBlock({
          'new_arrival': true,
          'arrival_year': 2026,
          'arrival_as_of': '2026-06-01'
        }, team, 2026),
        0);
    expect(
        rosterTransferBlock(
            {'new_arrival': true, 'arrival_year': 2027}, team, 2026),
        0);
    expect(
        rosterTransferBlock(
            {'new_arrival': true, 'arrival_year': 2025}, team, 2026),
        1);
    expect(
        rosterTransferBlock({
          'new_arrival': true,
          'arrival_year': 2026,
          'arrival_as_of': '2026-06-01'
        }, {
          'id_league': 1,
          'opening_date': '2026-10-02'
        }, 2026),
        0);
    expect(
        rosterTransferBlock(
            {'move_status': 'FA移籍の可能性', 'fa_eligible': true}, team, 2026),
        1);
    expect(
        rosterTransferBlock({
          'new_arrival': true,
          'arrival_year': 2026,
          'departure_confirmed': true
        }, team, 2026),
        2);
    expect(rosterTransferBlock({'retirement_confirmed': true}, team, 2026), 2);
  });
  test('新人・現役ドラフトを追加し重複と入団拒否を除外する', () {
    final result = rosterWithDraftArrivals([
      {'name': '登録 済'}
    ], [
      {'team': '巨人', 'name': '登録済'},
      {'team': '巨人', 'name': '新人', 'rank': 1, 'status': '交渉権獲得'},
      {'team': '巨人', 'name': '移籍', 'type': '現役', 'rank': 1},
      {'team': '巨人', 'name': '拒否', 'status': '入団拒否'},
      {'team': '阪神', 'name': '他球団'},
    ], {
      'name_team': '巨人'
    }, 2026);
    expect(result.map((p) => p['name']), ['登録 済', '新人', '移籍']);
    expect(result[1]['draft_status'], '交渉権獲得');
    expect(result[2]['move_method'], '現役ドラフト');
  });
  for (final embedded in [false, true]) {
    testWidgets('移籍状況の3列・起用順と狭い画面（embedded=$embedded）', (tester) async {
      tester.view.physicalSize = const Size(375, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const roster = [
        {
          'name': '少起用',
          'player_key': 'low',
          'position_group': '捕手',
          'level_appearances': {'1': 10},
          'level_usage_metrics': {
            '1': {'pa': 30}
          }
        },
        {
          'name': '多起用',
          'player_key': 'high',
          'position_group': '捕手',
          'level_appearances': {'1': 40},
          'level_usage_metrics': {
            '1': {'pa': 150}
          }
        },
        {
          'name': '新加入',
          'position_group': '外野手',
          'player_key': 'new',
          'new_arrival': true,
          'arrival_year': 2027
        },
        {'name': '退団', 'player_key': 'out', 'position_group': '投手', 'departure_confirmed': true},
        {'name': '新投手', 'player_key': 'new-p', 'position_group': '投手', 'new_arrival': true, 'arrival_year': 2027},
        {'name': '新捕手', 'player_key': 'new-c', 'position_group': '捕手', 'new_arrival': true, 'arrival_year': 2027},
        {'name': '新内野', 'player_key': 'new-i', 'position_group': '内野手', 'new_arrival': true, 'arrival_year': 2027},
        {'name':'新人投手','player_key':'draft-p','position_group':'投手','new_arrival':true,'arrival_year':2027,'move_method':'新人ドラフト1位'},
        {'name':'FA移籍','player_key':'FA移籍','position_group':'外野手','new_arrival':true,'arrival_year':2027,'move_method':'FA移籍'},
        {'name':'トレード','player_key':'トレード','position_group':'外野手','new_arrival':true,'arrival_year':2027,'move_method':'トレード'},
        {'name':'現役ドラフト','player_key':'現役ドラフト','position_group':'外野手','new_arrival':true,'arrival_year':2027,'move_method':'現役ドラフト'},
        {'name':'育成投手','player_key':'development-p','position_group':'投手','new_arrival':true,'arrival_year':2027,'arrival_draft_type':'育成','arrival_draft_rank':1},
        {'name':'新人外野','player_key':'draft-o','position_group':'外野手','new_arrival':true,'arrival_year':2027,'move_method':'新人ドラフト6位'},
        {'name': '噂', 'player_key': 'rumor', 'move_status': '移籍未定'},
      ];
      const grid = StrengthRosterGrid(
          year: 2026, team: {'name_team': 'テスト', 'roster': roster});
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: embedded
                  ? const SingleChildScrollView(
                      child: TeamSectionLayout(child: grid))
                  : grid)));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.tap(find.text('移籍状況'));
      await tester.pump();
      Finder block(int index) =>
          find.byKey(ValueKey('roster-transfer-block-$index'));
      Finder card(String key) => find.byKey(ValueKey('roster-card-$key'));
      expect(
          find.descendant(of: block(0), matching: card('new')), findsOneWidget);
      expect(find.descendant(of: block(1), matching: card('rumor')),
          findsOneWidget);
      expect(
          find.descendant(of: block(2), matching: card('out')), findsOneWidget);
      expect(tester.getTopLeft(card('high')).dy,
          lessThan(tester.getTopLeft(card('low')).dy));
      expect(tester.getTopLeft(block(0)).dx,
          lessThan(tester.getTopLeft(block(1)).dx));
      expect(tester.getTopLeft(block(1)).dx,
          lessThan(tester.getTopLeft(block(2)).dx));
      for (final pos in ['投手', '捕手', '一塁', '二塁', '三塁', '遊撃', '左翼', '中堅', '右翼']) {
        expect(find.byKey(ValueKey('transfer-resident-$pos')), findsOneWidget);
      }
      expect(find.descendant(of: find.byKey(const ValueKey('transfer-resident-捕手')), matching: card('high')), findsOneWidget);
      for (final pair in [('new-p', 'new-c'), ('new-c', 'new-i'), ('new-i', 'new')]) {
        expect(tester.getTopLeft(card(pair.$1)).dy, lessThan(tester.getTopLeft(card(pair.$2)).dy));
      }
      for(final method in ['FA移籍','トレード','現役ドラフト']) {
        expect(tester.getTopLeft(card(method)).dy,lessThan(tester.getTopLeft(card('draft-p')).dy));
      }
      expect(tester.getTopLeft(card('draft-o')).dy,lessThan(tester.getTopLeft(card('development-p')).dy));
      final decoration = tester.widget<Container>(card('out')).decoration as BoxDecoration;
      expect(decoration.color, isNot(Colors.white));
      expect(find.text('右'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('年齢順'));
      await tester.pump();
      expect(block(0), findsNothing);
      expect(card('high'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
