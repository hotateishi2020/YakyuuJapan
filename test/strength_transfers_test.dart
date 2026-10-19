import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/transfer_candidates.dart';
import 'package:Yakyuu_Japan/logic/contract_fa.dart';
import 'package:Yakyuu_Japan/logic/roster_contract_status.dart';
import 'package:Yakyuu_Japan/View/team_strength_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  final team = <String, dynamic>{
    'id_team': 7,
    'name_team': '西武',
    'id_league': 2,
    'roster': [
      {
        'player_key': 'npb:71075130',
        'name': '髙橋 光成',
        'contract_end_year': 2027
      },
      {'player_key': 'npb:31035136', 'name': '平良 海馬'},
      {
        'player_key': 'eligible',
        'name': 'FA候補',
        'contract_end_year': 2026,
        'fa_rights_type': 'domestic',
        'fa_rights_year': 2026
      },
      {
        'player_key': 'extended',
        'name': '契約継続',
        'contract_end_year': 2028,
        'fa_rights_type': 'domestic',
        'fa_rights_year': 2026
      },
      {
        'player_key': 'departed',
        'name': '移籍済み',
        'departure_confirmed': true,
        'contract_end_year': 2026,
        'fa_rights_type': 'domestic',
        'fa_rights_year': 2026
      },
    ]
  };
  test('高橋の海外FA取得と今オフ報道を掲載し確定・前年の候補を混ぜない', () {
    final rows = transferCandidates([team], 2026);
    expect(rows.map((r) => r['player']['name']),
        containsAll(['髙橋 光成', '平良 海馬', 'FA候補']));
    expect(rows.length, 3);
    expect(rows.firstWhere((r) => r['player']['name'] == '髙橋 光成')['labels'],
        ['海外FA']);
    expect(rows.firstWhere((r) => r['player']['name'] == '平良 海馬')['labels'],
        ['ポスティング？']);
    expect(transferCandidates([team], 2027), isEmpty);
    expect(
        transferCandidates([
          {...team, 'org': 'mlb'}
        ], 2026),
        isEmpty);
    final events =
        contractFaEvents({'player_key': 'npb:71075130'}, null, isNpb: true);
    expect(
        events.any((e) =>
            e['year'] == 2026 &&
            e['type'] == 'international' &&
            e['projected'] == false),
        isTrue);
    expect(rosterContractLabels({'player_key': 'npb:31035136'}, team, 2026),
        ['ポスティング？']);
  });
  testWidgets('狭い画面でドラフトの右に移籍がありFA・ポスティングで絞れる', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TeamStrengthBoard(
                org: OrgConfig.npb,
                year: 2026,
                providedTeams: [team],
                initialView: 12))));
    await t.pump();
    expect(t.getTopLeft(find.text('移籍')).dx,
        greaterThan(t.getTopLeft(find.text('ドラフト')).dx));
    expect(find.text('海外FA'), findsOneWidget);
    expect(find.text('ポスティング？'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, 'ポスティング'));
    await t.pump();
    expect(find.text('海外FA'), findsNothing);
    expect(find.text('平良 海馬'), findsOneWidget);
    expect(find.byKey(const ValueKey('transfer-grid')), findsOneWidget);
    expect(find.text('出典'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
