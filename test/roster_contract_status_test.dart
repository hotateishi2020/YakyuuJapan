import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/roster_contract_status.dart';
import 'package:Yakyuu_Japan/View/strength_contracts.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';

void main() {
  final player = <String, dynamic>{
    'player_key': 'test',
    'name': '確認選手',
    'position_group': '外野手',
    'bats': '左',
    'contract_end_year': 2026,
    'fa_rights_year': 2026,
    'fa_rights_type': 'domestic'
  };
  test('契約満了かつ保有中の権利のみ、海外を優先', () {
    expect(rosterContractLabels(player, {}, 2026), ['国内FA']);
    expect(
        rosterContractLabels(
            {...player, 'fa_rights_type': 'international'}, {}, 2026),
        ['海外FA']);
    expect(
        rosterContractLabels({...player, 'contract_end_year': 2027}, {}, 2026),
        isEmpty);
    expect(
        rosterContractLabels({...player, 'contract_end_year': null}, {}, 2026),
        isEmpty);
    expect(
        rosterContractLabels({...player, 'fa_exercised_year': 2026}, {}, 2026),
        isEmpty);
    expect(
        rosterContractLabels(
            {...player, 'departure_confirmed': true}, {}, 2026),
        isEmpty);
    expect(rosterContractLabels(player, {'org': 'mlb'}, 2026), isEmpty);
    expect(rosterContractLabels(player, {}, 2027), isEmpty);
  });
  test('契約延長を優先し噂は当年の出典があり契約が継続する場合だけ', () {
    final team = {
      'contracts': [
        {
          'player_key': 'test',
          'periods': [
            {'start_year': 2027, 'end_year': 2029}
          ]
        }
      ]
    };
    final rumor = {
      'year': 2026,
      'status': 'rumored',
      'source_url': 'https://example.com/report'
    };
    expect(rosterContractLabels(player, team, 2026), isEmpty);
    expect(
        rosterContractLabels({
          ...player,
          'posting_reports': [rumor]
        }, team, 2026),
        ['ポスティング？']);
    expect(
        rosterContractLabels({
          ...player,
          'posting_reports': [rumor]
        }, {}, 2026),
        ['国内FA']);
    expect(
        rosterContractLabels({
          ...player,
          'posting_reports': [
            {...rumor, 'source_url': ''}
          ]
        }, team, 2026),
        isEmpty);
    expect(
        rosterContractLabels({
          ...player,
          'posting_reports': [
            {...rumor, 'year': 2025}
          ]
        }, team, 2026),
        isEmpty);
  });
  test('外国人適用除外は開始年以降のみ。見込みは確定扱いしない', () {
    final p = {'player_key': 'npb:63965134'};
    expect(rosterContractLabels(p, {}, 2025), isEmpty);
    expect(rosterContractLabels(p, {}, 2026), ['外国人適用除外']);
    expect(rosterContractLabels(p, {'org': 'mlb'}, 2026), isEmpty);
    expect(
        rosterContractLabels({
          'foreign_exemption_events': [
            {
              'year': 2026,
              'projected': true,
              'source_url': 'https://example.com'
            }
          ]
        }, {}, 2026),
        isEmpty);
  });
  testWidgets('選手カードにFA、契約表の開始年に適用除外を表示', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthRosterGrid(team: {
      'roster': [player]
    }, year: 2026))));
    expect(find.text('今オフ 国内FA'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: StrengthContracts(year: 2026, team: {
      'name_team': '球団',
      'id_team': 1,
      'roster': [
        {'player_key': 'npb:63965134', 'name': 'モイネロ'}
      ],
    }))));
    expect(find.text('外国人適用除外'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
