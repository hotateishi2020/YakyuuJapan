import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/transfer_candidates.dart';
import 'package:Yakyuu_Japan/logic/contract_fa.dart';
import 'package:Yakyuu_Japan/logic/roster_contract_status.dart';
import 'package:Yakyuu_Japan/View/strength_transfers.dart';

void main() {
  final team = <String, dynamic>{
    'id_team': 7,
    'name_team': '西武',
    'name_shortest': '西',
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
  test('引退表明・引退確定はFA権があっても移籍候補から除外する', () {
    Map<String, dynamic> candidate(String key, Map<String, dynamic> extra) => {
          'player_key': key,
          'name': key,
          'fa_rights_type': 'domestic',
          'fa_rights_year': 2026,
          ...extra,
        };
    final roster = [
      candidate('npb:51755115', {'name': '栗山 巧'}),
      candidate('名前のみ', {'name': '栗山　巧'}),
      candidate('引退確定', {'retirement_confirmed': true}),
      candidate(
          '引退表明', {'retirement_announced': true, 'retirement_year': 2026}),
      candidate('当年ステータス', {'move_status': '引退表明', 'move_status_year': 2026}),
      candidate('未確定', {'move_status': '引退の可能性', 'move_status_year': 2026}),
      candidate(
          '翌年引退', {'retirement_announced': true, 'retirement_year': 2027}),
      candidate('現役', {}),
    ];
    final result = transferCandidates([
      {...team, 'roster': roster}
    ], 2026);
    expect(result.map((r) => r['player']['name']),
        unorderedEquals(['未確定', '翌年引退', '現役']));
    expect(
        transferCandidates([
          {
            ...team,
            'roster': [
              candidate(
                  'npb:51755115', {'name': '栗山 巧', 'fa_rights_year': 2025}),
            ]
          }
        ], 2025),
        hasLength(1));
  });
  testWidgets('狭い画面の移籍一覧に引退表明済み選手を表示しない', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthTransfers(
      year: 2026,
      teams: [
        {
          ...team,
          'roster': [
            ...(team['roster'] as List),
            const {
              'player_key': 'npb:51755115',
              'name': '栗山 巧',
              'fa_rights_type': 'international',
              'fa_rights_year': 2026
            },
          ]
        }
      ],
    ))));
    await t.pump();
    expect(find.text('海外FA'), findsOneWidget);
    expect(find.text('ポスティング？'), findsOneWidget);
    expect(find.text('平良 海馬'), findsOneWidget);
    expect(find.text('栗山 巧'), findsNothing);
    expect(find.byKey(const ValueKey('transfer-grid')), findsOneWidget);
    final before = t.getTopLeft(find.text('平良 海馬'));
    expect(find.text('西武'), findsNothing);
    expect(find.text('西'), findsWidgets);
    await t.drag(find.byKey(const ValueKey('transfer-horizontal-scroll')), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('平良 海馬')), before);
    expect(t.takeException(), isNull);
  });
}
