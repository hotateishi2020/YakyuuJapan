import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/transfer_candidates.dart';
import 'package:Yakyuu_Japan/logic/contract_fa.dart';
import 'package:Yakyuu_Japan/logic/roster_contract_status.dart';
import 'package:Yakyuu_Japan/View/strength_transfers.dart';

void main() {
  test('入団決定はFA権がなくても掲載し、新人ドラフトを除外して現役ドラフトを残す', () {
    Map<String,dynamic> arrival(String name, {String method = '', String type = ''}) => {
      'player_key': name,'name': name,'new_arrival': true,'arrival_year': 2026,
      'arrival_as_of': '2026-09-23','move_method': method,
      if (type.isNotEmpty) 'arrival_draft_type': type,
      'status_source': 'https://example.com/announcement',
      'previous_team': {'name': 'ドジャース'},
    };
    final rows = transferCandidates([{
      'id_team': 3,'id_league': 1,'name_team': '中日','roster': [
        arrival('ライアン・ウォード'),
        arrival('FA加入',method: 'FA移籍'),
        arrival('新人',method: '新人ドラフト1位'),
        arrival('育成',type: '育成'),
        arrival('現役移籍',method: '現役ドラフト',type: '現役'),
        {...arrival('前年の新加入'), 'arrival_as_of': '2025-12-01'},
        {...arrival('翌年加入決定'), 'arrival_year': 2027},
        {...arrival('退団済み'), 'departure_confirmed': true},
      ],
    }], 2026);
    expect(rows.map((r) => r['player']['name']).toSet(),
        {'ライアン・ウォード','FA加入','現役移籍','翌年加入決定'});
    final ward = rows.singleWhere((r) => r['player']['name'] == 'ライアン・ウォード');
    expect(ward['status'], '入団決定');
    expect(ward['labels'], ['新加入']);
    expect(ward['detail'], contains('ドジャース → 中日'));
    expect(ward['sources'], ['https://example.com/announcement']);
  });
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
  final sortedTeams = [
    {...team, 'id_team': 1, 'name_team': '球団A', 'roster': [
      {'player_key': 'attention-low', 'name': '権利保有選手', 'fa_rights_type': 'domestic', 'fa_rights_year': 2026},
    ]},
    {...team, 'id_team': 2, 'name_team': '球団B', 'roster': [
      {'player_key': 'attention-high', 'name': '宣言選手', 'fa_rights_type': 'domestic', 'fa_rights_year': 2026,
        'move_status': 'FA宣言（移籍先未定）', 'move_status_year': 2026},
      {'player_key': 'attention-medium', 'name': '報道選手', 'fa_rights_type': 'domestic', 'fa_rights_year': 2026,
        'transfer_reports': [{'year': 2026, 'status': 'rumored', 'source_url': 'https://example.com/report'}]},
    ]},
  ];
  test('初期表示は注目度順で、チーム別では球団内を注目度順にする', () {
    final rows = transferCandidates(sortedTeams, 2026);
    expect(rows.map((r) => r['attention']), [3, 2, 1]);
    expect(rows.map((r) => r['player']['name']), ['宣言選手', '報道選手', '権利保有選手']);
    expect(transferCandidates(sortedTeams, 2026, sort: TransferSort.team).map((r) => r['player']['name']),
      ['権利保有選手', '宣言選手', '報道選手']);
  });
  testWidgets('注目度列と並び順切替を表示する', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StrengthTransfers(teams: sortedTeams, year: 2026))));
    expect(find.text('注目度'), findsOneWidget);
    expect(find.text('★★★'), findsOneWidget);
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '注目度順')).selected, isTrue);
    expect(t.getTopLeft(find.text('宣言選手')).dy, lessThan(t.getTopLeft(find.text('権利保有選手')).dy));
    await t.tap(find.text('チーム別'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('権利保有選手')).dy, lessThan(t.getTopLeft(find.text('宣言選手')).dy));
    await t.tap(find.text('注目度順'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('宣言選手')).dy, lessThan(t.getTopLeft(find.text('権利保有選手')).dy));
    expect(t.takeException(), isNull);
  });
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
