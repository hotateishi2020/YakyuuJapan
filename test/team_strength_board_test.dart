import 'package:Yakyuu_Japan/View/records_board.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/team_strength_board.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';
import 'package:Yakyuu_Japan/View/strength_vertical_label.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'package:Yakyuu_Japan/pages/prediction_page.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

Map<String, dynamic> team(int id, String name) => {
      'id_team': id,
      'name_team': name,
      'color_back': 'navy',
      'color_font': 'white',
      'lineup_game_count': 100,
      'substitutions': [
        for (final role in [('PH', '代打'), ('PR', '代走'), ('DEF', '代守')])
          {
            'slot': role.$1,
            'label': role.$2,
            'total': 10,
            'players': [
              {'player_key': 'sub_$id', 'name': '途中選手$id', 'count': 10}
            ]
          },
      ],
      'pitching_workload': [
        {
          'name': '先発選手$id',
          'player_key': 'player_$id',
          'starter_outs': 60,
          'relief_outs': 0,
          'total_outs': 60
        },
        {
          'name': '兼任$id',
          'starter_outs': 30,
          'relief_outs': 60,
          'total_outs': 90
        },
        {
          'name': '中継ぎ選手$id',
          'starter_outs': 0,
          'relief_outs': 120,
          'total_outs': 120
        },
        {
          'name': '少登板$id',
          'starter_outs': 0,
          'relief_outs': 15,
          'total_outs': 15
        },
        {
          'name': '抑え選手$id',
          'starter_outs': 0,
          'relief_outs': 210,
          'total_outs': 210,
          'saves': 20
        },
      ],
      'roster': [
        {
          'name': '先発選手$id',
          'player_key': 'player_$id',
          'date_birth': '2000-01-01',
          'position_group': '投手',
          'throws': '右',
          'bats': '左',
          'registration': '支配下',
          'level_appearances': {'1': 20, '2': 2},
          'level_coverage': [1, 2]
        },
        {
          'name': '育成選手$id',
          'player_key': 'development_$id',
          'date_birth': '2005-01-01',
          'position_group': '内野手',
          'throws': '右',
          'bats': '両',
          'registration': '育成',
          'level_appearances': {'1': 0, '2': 25},
          'level_coverage': [1, 2],
          'contract_end_year': 2026,
          'fa_eligible': true,
          'departure_confirmed': true
        },
      ],
      'pitchers': {
        'starters': [
          {'name': '兼任$id', 'starts': 10, 'appearances': 30},
          {
            'name': '先発選手$id',
            'player_key': 'player_$id',
            'starts': 20,
            'appearances': 22
          },
        ],
        'relievers': [
          {'name': '少登板$id', 'appearances': 5},
          {'name': '兼任$id', 'starts': 10, 'appearances': 30},
          {'name': '中継ぎ選手$id', 'starts': 10, 'appearances': 50, 'holds': 20},
        ],
        'closers': [
          {'name': '抑え選手$id', 'appearances': 70, 'saves': 30}
        ],
      },
      'batting_order': [
        {
          'slot': 1,
          'label': '1番',
          'total': 100,
          'players': [
            {
              'name': '打者$id',
              'player_key': 'player_$id',
              'count': 65,
              'rate': 65.0
            },
            {'name': '打者B$id', 'count': 34, 'rate': 34.0},
            {'name': '狭い区分に収まらない選手名', 'count': 1, 'rate': 1.0},
          ]
        },
        {
          'slot': 2,
          'label': '2番',
          'total': 100,
          'players': [
            {'name': '五', 'count': 5},
            {'name': '四', 'count': 4},
            {'name': '六', 'count': 6},
            {'name': '大', 'count': 85},
          ],
        },
      ],
      'positions': [
        {
          'slot': 'C',
          'label': '捕手',
          'total': 100,
          'players': [
            {
              'name': '捕手$id',
              'player_key': 'player_$id',
              'count': 80,
              'rate': 80.0
            }
          ]
        },
      ],
      'notes': ['先発起用の回数を対象試合数で割った割合です。'],
      'source_label': 'スタメンデータ',
      'source_url': 'https://example.test/lineups',
      'updated_at': '2026-10-14T00:00:00Z',
    };

void main() {
  testWidgets('主力の打順別は全打順を通して同じ選手を一度だけ表示する', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StrengthRegularGrid(teams: [
      {'name_team': '球団A', 'batting_order': [
        {'slot': '1', 'total': 100, 'players': [
          {'player_key': 'a', 'name': '主力A', 'count': 60},
          {'player_key': 'b', 'name': '主力B', 'count': 42},
        ]},
        {'slot': '2', 'total': 100, 'players': [
          {'player_key': 'a', 'name': '主力A', 'count': 40},
          {'player_key': 'c', 'name': '主力C', 'count': 35},
          {'player_key': 'b', 'name': '主力B', 'count': 25},
        ]},
      ]},
    ]))));
    await tester.tap(find.text('打順別'));
    await tester.pumpAndSettle();
    expect(find.text('主力A'), findsOneWidget);
    expect(find.text('主力B'), findsOneWidget);
    expect(find.text('主力C'), findsOneWidget);
    expect(find.text('60試合'), findsOneWidget);
    expect(find.text('35試合'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('選手起用と選手一覧はそれぞれ推し球団を初期選択する', (tester) async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'teams': [team(1, '球団1'), team(2, '球団2')]
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(
                  initialView: 1, org: OrgConfig.npb, year: 2026, favoriteTeamId: 2))));
      await tester.pumpAndSettle();
      expect(find.byKey(const PageStorageKey('strength-rows-npb-2026-2-1')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('strength-team-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-view-3')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<StrengthRosterGrid>(find.byType(StrengthRosterGrid))
              .team['id_team'],
          2);
      await tester.tap(find.byKey(const ValueKey('strength-view-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const PageStorageKey('strength-rows-npb-2026-1-1')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('貢献度ヘッダーはAPIのチーム背景色と文字色をそのまま使う', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final club = team(1, '球団A')
      ..['color_back'] = '#123456'
      ..['color_font'] = '#FEDCBA';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TeamStrengthBoard(
      initialView: 0, org: OrgConfig.npb, year: 2026, providedTeams: [club],
    ))));
    await tester.pumpAndSettle();
    final heading = find.text('打撃貢献度');
    expect(tester.widget<Text>(heading).style!.color, const Color(0xFFFEDCBA));
    final container = tester.widget<Container>(find.ancestor(of: heading, matching: find.byType(Container)).first);
    expect((container.decoration as BoxDecoration).color, const Color(0xFF123456));
    expect(tester.takeException(), isNull);
  });

  testWidgets('本塁打5本以上は比率が低くても名前を表示し比較ヘッダーは球団色', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final teams = [
      team(1, '球団A')
        ..['color_back'] = '#123456'
        ..['batting_stats'] = [
          {'player_key': 'a', 'name': '本塁打最多', 'home_runs': 191},
          {'player_key': 'b', 'name': '五本打った長い選手名', 'home_runs': 5},
          {'player_key': 'c', 'name': '四本の選手', 'home_runs': 4},
        ],
      team(2, '球団B')
        ..['batting_stats'] = [
          {'player_key': 'd', 'name': '比較選手', 'home_runs': 400},
        ]
    ];
    final client = MockClient((_) async => http.Response(
        jsonEncode({'teams': teams}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(initialView: 1, org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-view-0')));
      await tester.pumpAndSettle();
      for (final comparison in [false, true]) {
        if (comparison) {
          await tester.tap(find.text('12球団比較'));
          await tester.pumpAndSettle();
        }
        expect(
            find.byKey(const ValueKey('total-bases-legend')), findsOneWidget);
        final band = find
            .byKey(const ValueKey('strength-band-contribution-home_runs'))
            .first;
        final name =
            find.descendant(of: band, matching: find.text('五本打った長い選手名'));
        expect(name, findsOneWidget);
        expect(find.descendant(of: band, matching: find.text('四本の選手')),
            findsNothing);
        expect(find.descendant(of: band, matching: find.text('5')),
            findsOneWidget);
        expect(
            find.descendant(of: band, matching: find.text('5本')), findsNothing);
        final segment = find.byTooltip('五本打った長い選手名：5本（2.5%）');
        expect(tester.getSize(name).width,
            lessThanOrEqualTo(tester.getSize(segment).width));
        if (comparison) {
          final header = find
              .ancestor(
                  of: find.text('球団A').first, matching: find.byType(Container))
              .first;
          expect(
              (tester.widget<Container>(header).decoration as BoxDecoration)
                  .color,
              const Color(0xFF123456));
        }
        expect(tester.takeException(), isNull);
      }
    }, () => client);
  });

  for (final org in [OrgConfig.npb, OrgConfig.mlb]) {
    testWidgets('${org.label}功績の全球団比較は件数より総合点を優先して並べる', (tester) async {
      final teams = [
        for (var id = 1; id <= 2; id++)
          team(id, '球団$id')
            ..['roster'] = [
              {
                'player_key': 'a$id',
                'name': '功績選手$id',
                'achievements': [
                  for (var n = 0; n < (id == 1 ? 3 : 1); n++)
                    {
                      'label': id == 1 ? '月間MVP' : 'MVP',
                      'kind': 'title',
                      'year': 2025 - n
                    },
                ]
              }
            ]
      ];
      final client = MockClient((_) async => http.Response(
          jsonEncode({'teams': teams}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(body: RecordsHonors(org: org, year: 2026))));
        await tester.pumpAndSettle();
        expect(find.text('功績選手1'), findsOneWidget);
        expect(find.text('功績選手2'), findsOneWidget);
        expect(find.text(org == OrgConfig.npb ? '12球団比較' : '30球団比較'),
            findsOneWidget);
        expect(find.byType(DropdownButton<int>), findsNothing);
        expect(find.text('球団1'), findsOneWidget);
        expect(find.text('球団2'), findsOneWidget);
        expect(tester.getTopLeft(find.text('功績選手2')).dy,
            lessThan(tester.getTopLeft(find.text('功績選手1')).dy));
        await tester.tap(find.text('各球団'));
        await tester.pumpAndSettle();
        expect(find.byType(DropdownButton<int>), findsOneWidget);
        expect(find.text('功績選手2'), findsNothing);
        final otherOrg = org == OrgConfig.npb ? OrgConfig.mlb : OrgConfig.npb;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(body: RecordsHonors(org: otherOrg, year: 2026))));
        await tester.pumpAndSettle();
        expect(find.text('功績選手1'), findsOneWidget);
        expect(find.text('功績選手2'), findsOneWidget);
        expect(find.byType(DropdownButton<int>), findsNothing);
        expect(tester.takeException(), isNull);
      }, () => client);
    });
  }
  testWidgets('成績と契約は各球団・全球団比較を切り替える', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final teams = [
      for (var id = 1; id <= 2; id++)
        team(id, '球団$id')
          ..['batting_stats'] = [
            {
              'player_key': 'b$id',
              'name': '打者$id',
              'home_runs': 10 * id,
              'rbi': 30 * id,
              'total_bases_walks': 100 * id,
              'triples': 2 * id,
              'doubles': 5 * id,
              'singles': 24 * id,
              'walks': 20 * id
            }
          ]
    ];
    final client = MockClient((_) async => http.Response(
        jsonEncode({'teams': teams}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(initialView: 1, org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-view-0')));
      await tester.pumpAndSettle();
      expect(find.text('10本'), findsWidgets);
      expect(find.text('30'), findsOneWidget);
      await tester.tap(find.text('12球団比較'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('strength-team-1')), findsNothing);
      expect(find.text('60'), findsOneWidget);
      final bands = tester.getRect(find
          .byKey(const ValueKey('strength-band-contribution-home_runs'))
          .first);
      final second = tester.getRect(find
          .byKey(const ValueKey('strength-band-contribution-home_runs'))
          .last);
      expect(second.width, closeTo(bands.width * 2, .1));
      expect(find.text('塁打数（四球含む）'), findsNothing);
      final basesLast = tester.getRect(find
          .byKey(const ValueKey('strength-band-contribution-total_bases_walks'))
          .last);
      final rbiFirst = tester.getRect(
          find.byKey(const ValueKey('strength-band-contribution-rbi')).first);
      expect(basesLast.bottom, lessThan(bands.top));
      expect(second.bottom, lessThan(rbiFirst.top));
      expect(find.text('球団1'), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('strength-view-4')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('strength-team-1')), findsNothing);
      await tester.tap(find.text('各球団'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('strength-team-1')), findsOneWidget);
      await tester.tap(find.text('12球団比較'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('strength-team-1')), findsNothing);
      expect(find.byKey(const ValueKey('contract-horizontal-scroll')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('球団セグメントは折り返す場合セとパで段を分ける', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final teams = [
      for (var i = 0; i < 12; i++)
        team(i + 1, '${i < 6 ? 'セ' : 'パ'}球団${i + 1}')
          ..['id_league'] = i < 6 ? 1 : 2
    ];
    final client = MockClient((_) async => http.Response(
        jsonEncode({'teams': teams}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(initialView: 1, org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      double y(int id) =>
          tester.getCenter(find.byKey(ValueKey('strength-team-$id'))).dy;
      for (var i = 2; i <= 6; i++) {
        expect(y(i), closeTo(y(1), 0.1));
      }
      for (var i = 8; i <= 12; i++) {
        expect(y(i), closeTo(y(7), 0.1));
      }
      expect(y(7), greaterThan(y(1)));
      await tester.binding.setSurfaceSize(const Size(1800, 900));
      await tester.pumpAndSettle();
      expect(y(12), closeTo(y(1), 0.1));
      expect(find.text('選手一覧'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('帯の詳細で省略される投手も投球回グラフに表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'teams': [team(1, '球団A')]
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(initialView: 1, org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-view-0')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const ValueKey('strength-detail-outs-relief')));
      await tester.pumpAndSettle();
      final horizontal = tester.stateList<ScrollableState>(find.byType(Scrollable))
          .where((s) => s.axisDirection == AxisDirection.right);
      expect(horizontal.every((s) => s.position.maxScrollExtent == 0), isTrue);
      expect(tester.getRect(find.byKey(const ValueKey('strength-detail-outs-relief'))).right,
          lessThanOrEqualTo(1200));
      await tester
          .tap(find.byKey(const ValueKey('strength-detail-outs-relief')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('中継負担率の詳細'), findsOneWidget);
      for (final text in [
        '抑え選手1　70回（42.4%）',
        '中継ぎ選手1　40回（24.2%）',
        '兼任1　20回（12.1%）',
        '少登板1　5回（3.0%）'
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(
          find.descendant(
              of: find.byType(Dialog),
              matching: find.byType(FractionallySizedBox)),
          findsNWidgets(4));
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('strength-view-1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const ValueKey('strength-detail-starts-C')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-detail-starts-C')));
      await tester.pumpAndSettle();
      expect(find.text('捕手1　80試合（80.0%）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('先発の選手名は負担率3%以上で表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = team(1, '球団A')
      ..['pitching_workload'] = [
        {
          'name': '三パーセント',
          'starter_outs': 15,
          'relief_outs': 0,
          'total_outs': 15
        },
        {'name': '三未満', 'starter_outs': 14, 'relief_outs': 0, 'total_outs': 14},
        {
          'name': '中継ぎ',
          'starter_outs': 0,
          'relief_outs': 471,
          'total_outs': 471
        },
      ];
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'teams': [data]
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(initialView: 1, org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-view-0')));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byTooltip('三パーセント（先発）：5回（チーム全体の3.0%）'),
              matching: find.text('三パーセント')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byTooltip('三未満（先発）：4 2/3回（チーム全体の2.8%）'),
              matching: find.text('三未満')),
          findsNothing);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('一覧の抑え選手は中継ぎ列に表示する', (tester) async {
    final data = team(1, '球団A');
    (data['roster'] as List).add({
      'name': '抑え選手1',
      'date_birth': '2000-01-01',
      'position_group': '投手',
      'throws': '右',
      'registration': '支配下',
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: StrengthRosterGrid(year: 2026, team: data),
    )));
    await tester.pumpAndSettle();
    expect(find.text('抑え'), findsNothing);
    expect(find.text('中継ぎ'), findsOneWidget);
    final header = tester.getRect(find.text('中継ぎ'));
    final player = tester.getRect(find.text('抑え選手1'));
    final nextHeader = tester.getRect(find.text('捕手'));
    expect(player.center.dx, greaterThan(header.center.dx - 72.8));
    expect(player.center.dx, lessThan(nextHeader.center.dx - 72.8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('一覧の列幅は画面が広いとき均等に広がる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: StrengthRosterGrid(year: 2026, team: team(1, '球団A')),
    )));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Table)).right, closeTo(2400, 0.1));
    expect(tester.getRect(find.byType(Table)).left, closeTo(0, 0.1));
    final table = tester.widget<Table>(find.byType(Table));
    expect((table.defaultColumnWidth as FixedColumnWidth).value,
        greaterThan(72.8));
    await tester.binding.setSurfaceSize(const Size(600, 600));
    await tester.pumpAndSettle();
    expect(
        (tester.widget<Table>(find.byType(Table)).defaultColumnWidth
                as FixedColumnWidth)
            .value,
        closeTo(72.8, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('一覧は外野3列に分け不明打席の選手を左右にまたがって表示する', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: StrengthRosterGrid(year: 2026, team: {
        'roster': [
          for (final item in [('左の選手', '右'), ('中の選手', '左'), ('右の選手', '')])
            {
              'name': item.$1,
              'date_birth': '2000-01-01',
              'bats': item.$2,
              'position_group': '外野手',
            }
        ],
        'positions': [
          for (final item in [('LF', '左の選手'), ('CF', '中の選手'), ('RF', '右の選手')])
            {
              'slot': item.$1,
              'players': [
                {'name': item.$2, 'count': 50}
              ],
            }
        ],
      }),
    )));
    await tester.pumpAndSettle();
    expect(find.text('外野手'), findsNothing);
    for (final label in ['左翼', '中堅', '右翼']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('不明打ち'), findsNothing);
    Rect card(String name) => tester.getRect(find
        .ancestor(of: find.text(name), matching: find.byType(Tooltip))
        .first);
    final right = card('左の選手');
    final left = card('中の選手');
    final unknown = card('右の選手');
    expect(unknown.left, greaterThan(left.right));
    expect(unknown.width, greaterThan(right.width * 1.8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('一覧は守備位置カラーでヘッダーを固定し注意書きを表の下に置く', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: StrengthRosterGrid(year: 2026, team: {
        'roster': [
          for (var i = 0; i < 10; i++)
            {
              'name': '選手$i',
              'date_birth': '${1980 + i}-01-01',
              'position_group': '捕手',
              'throws': '右',
              'bats': '右',
              'registration': '支配下',
              'level_appearances': {'1': 10},
            }
        ],
      }),
    )));
    await tester.pumpAndSettle();
    Color headerColor(String label) => (tester
            .widget<Container>(find
                .ancestor(
                    of: find.text(label), matching: find.byType(Container))
                .first)
            .decoration as BoxDecoration)
        .color!;
    expect(headerColor('先発'), const Color(0xFFEF5350));
    expect(headerColor('捕手'), const Color(0xFF2196F3));
    expect(headerColor('一塁'), const Color(0xFFFFD54F));
    expect(headerColor('左翼'), const Color(0xFF43A047));
    expect(find.text('指名打者'), findsNothing);
    final header = tester.getTopLeft(find.text('捕手'));
    final notes = tester.getRect(find.byKey(const ValueKey('roster-notes')));
    expect(notes.top,
        greaterThanOrEqualTo(tester.getRect(find.byType(Table)).bottom));
    final vertical = tester.state<ScrollableState>(find
        .descendant(
            of: find.byKey(const ValueKey('roster-vertical-scroll')),
            matching: find.byType(Scrollable))
        .first);
    vertical.position.jumpTo(200);
    await tester.pump();
    expect(tester.getTopLeft(find.text('捕手')), header);
    expect(tester.takeException(), isNull);
  });

  testWidgets('レギュラー野手にシーズンOPSと本塁打を表示する', (tester) async {
    final data = team(1, '球団A');
    data['positions'] = [
      {
        'slot': 'C',
        'total': 100,
        'players': [
          {'player_key': 'batter', 'name': '捕手選手', 'count': 80}
        ]
      }
    ];
    data['batting_stats'] = [
      {'player_key': 'batter', 'ops': 0.85, 'home_runs': 12}
    ];
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: StrengthRegularGrid(teams: [data]))));
    await tester.pumpAndSettle();
    expect(find.text('OPS .850  12本'), findsOneWidget);
    expect(find.text('80試合'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('レギュラー表は広い画面で列を均等に広げ右端まで表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: StrengthRegularGrid(teams: [team(1, '球団A')]),
    )));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('regular-horizontal-scroll')))
        .controller!;
    scroll.jumpTo(200);
    await tester.pump();
    await tester.binding.setSurfaceSize(const Size(3200, 600));
    await tester.pumpAndSettle();
    final table = tester.getRect(find.byType(Table));
    expect(table.left, closeTo(160, 0.1));
    expect(table.right, closeTo(3200, 0.1));
    expect(scroll.offset, 0);
    expect(scroll.position.maxScrollExtent, 0);
    expect(tester.getCenter(find.text('球団')).dx, closeTo(80, 0.1));
    expect(tester.getCenter(find.text('捕手')).dx, closeTo(1040, 0.1));
    expect(tester.getCenter(find.text('指名打者')).dx, closeTo(2320, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('レギュラー表は守備位置を上端、球団名を左端に固定する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: StrengthRegularGrid(teams: [
        for (var i = 0; i < 12; i++)
          {
            'name_team': '球団$i',
            'color_back': 'navy',
            'color_font': 'white',
            'positions': [
              {
                'slot': 'C',
                'total': 100,
                'players': [
                  {'name': '捕手選手$i', 'count': 80},
                ]
              }
            ],
          }
      ]),
    )));
    await tester.pumpAndSettle();
    final corner = tester.getTopLeft(find.text('球団'));
    final header = tester.getTopLeft(find.text('捕手'));
    final teamBefore = tester.getTopLeft(find.text('球団0'));
    final playerBefore = tester.getTopLeft(find.text('捕手選手0'));
    final horizontal = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('regular-horizontal-scroll')))
        .controller!;
    horizontal.jumpTo(180);
    await tester.pump();
    expect(tester.getTopLeft(find.text('球団')), corner);
    expect(tester.getTopLeft(find.text('球団0')), teamBefore);
    expect(tester.getTopLeft(find.text('捕手')).dy, header.dy);
    expect(
        tester.getTopLeft(find.text('捕手')).dx, closeTo(header.dx - 180, 0.1));
    expect(tester.getTopLeft(find.text('捕手選手0')).dx,
        closeTo(playerBefore.dx - 180, 0.1));
    final vertical = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('regular-vertical-scroll')))
        .controller!;
    vertical.jumpTo(150);
    await tester.pump();
    expect(tester.getTopLeft(find.text('球団')), corner);
    expect(tester.getTopLeft(find.text('捕手')).dy, header.dy);
    expect(tester.getTopLeft(find.text('球団0')).dy,
        closeTo(teamBefore.dy - 150, 0.1));
    expect(tester.getTopLeft(find.text('捕手選手0')).dy,
        closeTo(playerBefore.dy - 150, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('複数レギュラーは横並びで名前・試合数・割合を縦に収める', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      body: StrengthRegularGrid(teams: [
        {
          'name_team': '球団A',
          'color_back': 'navy',
          'color_font': 'white',
          'positions': [
            {
              'slot': 'C',
              'total': 200,
              'players': [
                {'name': '非常に長い名前の捕手選手', 'count': 80},
                {'name': '二番目の捕手', 'count': 60},
                {'name': '三番目の捕手', 'count': 56},
              ]
            }
          ],
        }
      ]),
    )));
    await tester.pumpAndSettle();
    final first = tester.getRect(find.text('非常に長い名前の捕手選手'));
    final second = tester.getRect(find.text('二番目の捕手'));
    final third = tester.getRect(find.text('三番目の捕手'));
    expect(first.center.dx, lessThan(second.center.dx));
    expect(second.center.dx, lessThan(third.center.dx));
    expect(first.center.dy, closeTo(second.center.dy, 0.1));
    expect(first.bottom, lessThan(tester.getRect(find.text('80試合')).top));
    expect(tester.getRect(find.text('80試合')).bottom,
        lessThan(tester.getRect(find.text('40.0%')).top));
    expect(first.width, lessThanOrEqualTo(128 / 3 - 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('選手起用では投手のスタメン割合を捕手より上に表示する', (tester) async {
    final data = team(1, '球団A');
    (data['positions'] as List).add({
      'slot': 'P', 'label': '投手', 'total': 100,
      'players': [{'name': '先発投手', 'count': 25}],
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: TeamStrengthBoard(initialView: 1, org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      final pitcher = find.byKey(const ValueKey('strength-band-starts-P'));
      final catcher = find.byKey(const ValueKey('strength-band-starts-C'));
      expect(pitcher, findsOneWidget);
      expect(catcher, findsOneWidget);
      expect(tester.getTopLeft(pitcher).dy, lessThan(tester.getTopLeft(catcher).dy));
      expect(find.text('25.0%'), findsWidgets);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response(jsonEncode({'teams': [data]}), 200,
      headers: {'content-type': 'application/json; charset=utf-8'})));
  });
  testWidgets('スクロール位置の保存値を投手詳細の開閉状態として読み込まない', (tester) async {
    final bucket = PageStorageBucket();
    const listKey = PageStorageKey('strength-rows-npb-2026-1-0');
    await tester.pumpWidget(MaterialApp(
        home: PageStorage(
      bucket: bucket,
      child: Builder(
          key: listKey,
          builder: (context) {
            bucket.writeState(context, 321.0);
            return const SizedBox.shrink();
          }),
    )));
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'teams': [team(1, '球団A')]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PageStorage(
        bucket: bucket,
        child: const TeamStrengthBoard(initialView: 1, org: OrgConfig.npb, year: 2026),
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-view-0')));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(find
          .descendant(
              of: find.byKey(listKey), matching: find.byType(Scrollable))
          .first);
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('各投手の投球回・負担率'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('各投手の投球回・負担率'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          bucket.readState(tester.element(find.byKey(listKey))), isA<double>());
      await tester.tap(find.byKey(const ValueKey('strength-view-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-view-1')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('戦力で年度を変更して当年度の試合へ戻ると定期取得を再開する', (tester) async {
    final requests = <Uri>[];
    final pollHeaders = <Map<String, String>>[];
    final currentYear = DateTime.now().year;
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.queryParameters['fresh'] == '1') {
        pollHeaders.add(request.headers);
      }
      if (request.url.path == '/predictions/ready') {
        return http.Response('', 204);
      }
      if (request.url.path == '/predictions/part') {
        return http.Response('{}', 200);
      }
      if (request.url.path == '/team-strength') {
        return http.Response('{"teams":[]}', 200);
      }
      return http.Response('{}', 401);
    });
    int polls() => requests
        .where((uri) =>
            uri.queryParameters['part'] == 'games' &&
            uri.queryParameters['fresh'] == '1')
        .length;
    await http.runWithClient(() async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: PredictionPage())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('戦力'));
      await tester.pumpAndSettle();
      for (final year in [currentYear - 1, currentYear]) {
        await tester.tap(find.byTooltip('年度を選択'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('$year').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('$year').last);
        await tester.pumpAndSettle();
      }
      AuthSession.instance.token = 'browser-session-test';
      addTearDown(() => AuthSession.instance.token = null);
      final before = polls();
      await tester.pump(const Duration(seconds: 61));
      expect(polls(), before);
      final gameSwitchIndex = requests.length;
      await tester.tap(find.text('試合情報'));
      await tester.pumpAndSettle();
      expect(
        requests
            .skip(gameSwitchIndex)
            .where((uri) => uri.path == '/predictions/part')
            .map((uri) => uri.queryParameters['part']),
        containsAll(['games', 'standings', 'players']),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();
      expect(polls(), before + 1);
      expect(
          pollHeaders.last['Authorization'] ??
              pollHeaders.last['authorization'],
          'Bearer browser-session-test');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 21));
    }, () => client);
  });

  testWidgets('戦力はタブを開くまで取得せず、他の初期応答を待たずに開ける', (tester) async {
    final pending = Completer<http.Response>();
    final strengthRequests = <Uri>[];
    final client = MockClient((request) async {
      if (request.url.path == '/team-strength') {
        strengthRequests.add(request.url);
        return http.Response(
            jsonEncode({
              'teams': [team(1, '球団A')]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (request.url.path == '/predictions/part') return pending.future;
      return http.Response('{}', 401);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: PredictionPage())));
      await tester.pump();
      expect(strengthRequests, isEmpty);
      expect(find.text('戦力'), findsOneWidget);
      expect(tester.getTopLeft(find.text('戦力')).dx,
          greaterThan(tester.getTopLeft(find.text('個人成績')).dx));
      await tester.tap(find.text('戦力'));
      await tester.pump();
      await tester.pump();
      expect(strengthRequests, hasLength(1));
      expect(strengthRequests.single.queryParameters['org'], 'npb');
      await tester.tap(find.byKey(const ValueKey('strength-view-1')));
      await tester.pump();
      expect(find.text('投手のスタメン割合'), findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data)
              .join(' | '));
      expect(pending.isCompleted, isFalse);
      pending.complete(http.Response('{}', 200));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 21));
    }, () => client);
  });

  testWidgets('記録は戦力の右で初期通信を待たずに開く', (tester) async {
    final pending = Completer<http.Response>();
    var records = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: PredictionPage())));
      await tester.pump();
      expect(records, 0);
      expect(tester.getTopLeft(find.text('記録')).dx,
          greaterThan(tester.getTopLeft(find.text('戦力')).dx));
      await tester.tap(find.text('記録'));
      await tester.pump();
      await tester.pump();
      expect(records, 1);
      expect(find.text('連続記録'), findsOneWidget);
      expect(find.text('功績'), findsOneWidget);
      expect(pending.isCompleted, isFalse);
      pending.complete(http.Response('{}', 200));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 31));
    },
        () => MockClient((r) async {
              if (r.url.path == '/records') {
                records++;
                return http.Response('{}', 200);
              }
              if (r.url.path == '/predictions/part') return pending.future;
              return http.Response('{}', 401);
            }));
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('幅$widthで投手とスタメン比率を表示し、球団変更で通信しない', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response(
            jsonEncode({
              'teams': [team(1, '球団A'), team(2, '球団B')]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
            home: Scaffold(
                body: TeamStrengthBoard(initialView: 1, org: OrgConfig.npb, year: 2026))));
        await tester.pumpAndSettle();
        for (final label in ['選手起用', '主力選手', '選手一覧', '経歴']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.byType(DropdownButton<int>), findsNothing);
        expect(find.text('投手のスタメン割合'), findsOneWidget);
        expect(find.text('投手の投球回負担率'), findsNothing);
        double bandTop(String key) =>
            tester.getTopLeft(find.byKey(ValueKey(key))).dy;
        expect(bandTop('strength-band-starts-pitcher_starts'),
            lessThan(bandTop('strength-band-outs-pitching_hand')));
        expect(bandTop('strength-band-pa-batting_hand'),
            lessThan(bandTop('strength-band-starts-1')));
        expect(find.text('途中出場の起用割合'), findsOneWidget);
        expect(tester.getTopLeft(find.text('途中出場の起用割合')).dy,
            greaterThan(tester.getTopLeft(find.text('打順のスタメン比率')).dy));
        for (final role in ['PH', 'PR', 'DEF']) {
          expect(find.byKey(ValueKey('strength-band-starts-$role')),
              findsOneWidget);
          expect(find.byKey(ValueKey('strength-detail-starts-$role')),
              findsOneWidget);
        }
        await tester.tap(find.byKey(const ValueKey('strength-view-0')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
            find.byKey(const ValueKey('strength-band-outs-starter')));
        await tester.pumpAndSettle();
        expect(find.text('30回（18.2%）'), findsOneWidget);
        expect(find.text('135回（81.8%）'), findsOneWidget);
        final header = find
            .ancestor(
              of: find.text('先発負担率'),
              matching: find.byType(Container),
            )
            .first;
        expect(
            (tester.widget<Container>(header).decoration as BoxDecoration)
                .color,
            const Color(0xFFEF5350));
        expect(tester.getSize(header).width, closeTo(105.6, 0.01));
        final starter = find.byTooltip('先発選手1（先発）：20回（チーム全体の12.1%）');
        expect(starter, findsOneWidget);
        final starterRect = tester.getRect(starter);
        final secondStarter =
            tester.getRect(find.byTooltip('兼任1（先発）：10回（チーム全体の6.1%）'));
        final band = tester
            .getRect(find.byKey(const ValueKey('strength-band-outs-starter')));
        final headerRect = tester.getRect(header);
        expect(headerRect.height, closeTo(band.height, 0.01));
        expect(headerRect.top, closeTo(band.top, 0.01));
        expect(headerRect.bottom, closeTo(band.bottom, 0.01));
        expect(starterRect.width + secondStarter.width,
            closeTo(band.width, 0.01));
        expect(secondStarter.right, closeTo(band.right, 0.01));
        expect(
            find.descendant(
                of: find.byTooltip('少登板1（中継ぎ・抑え）：5回（チーム全体の3.0%）'),
                matching: find.text('少登板1')),
            findsOneWidget);

        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('strength-view-2')));
        await tester.pumpAndSettle();
        expect(find.text('球団A'), findsOneWidget);
        expect(find.text('球団B'), findsOneWidget);
        expect(find.byType(Table), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('strength-view-3')));
        await tester.pumpAndSettle();
        expect(find.text('起用'), findsOneWidget);
        expect(find.text('育成選手1 【契・FA・退】'), findsOneWidget);
        expect(find.text('内野手'), findsNothing);
        expect(find.text('（起用不明）'), findsWidgets);
        expect(find.text('両打ち'), findsOneWidget);
        expect(find.text('先発'), findsOneWidget);
        expect(find.textContaining('（確認範囲）'), findsNothing);
        expect(find.textContaining('契約・FA・退団未確認'), findsNothing);
        expect(tester.getTopLeft(find.text('2軍中心')).dy,
            lessThan(tester.getTopLeft(find.text('育成')).dy));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('strength-team-2')));
        await tester.pumpAndSettle();
        expect(find.text('育成選手2 【契・FA・退】'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('strength-view-1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const PageStorageKey('strength-rows-npb-2026-1-1')),
            findsOneWidget);
        expect(requests, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    });
  }

  testWidgets('縦横どちらの画面でも横向きの帯を横スクロールできる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var requests = 0;
    final payload = team(1, '球団A');
    final firstOrder = (payload['batting_order'] as List).first as Map;
    payload['batting_order'] = [
      for (var slot = 1; slot <= 9; slot++)
        {...firstOrder, 'slot': slot, 'label': '$slot番'},
    ];
    final client = MockClient((request) async {
      requests++;
      return http.Response(
          jsonEncode({
            'teams': [payload]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(initialView: 1, org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-view-0')));
      await tester.pumpAndSettle();
      final starter = find.byTooltip('先発選手1（先発）：20回（チーム全体の12.1%）');
      final before = tester.getRect(starter);
      expect(before.width, greaterThan(before.height));
      final horizontalScroll = find.byWidgetPredicate((widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal);
      expect(horizontalScroll, findsOneWidget);
      await tester.dragFrom(
          tester.getTopLeft(horizontalScroll) + const Offset(200, 200),
          const Offset(-180, 0));
      await tester.pumpAndSettle();
      final after = tester.getRect(starter);
      expect(after.left, lessThan(before.left));
      expect(after.top, closeTo(before.top, 0.01));
      expect(requests, 1);

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pumpAndSettle();
      final wide = tester.getRect(starter);
      expect(wide.width, greaterThan(wide.height));
      expect(find.byType(StrengthVerticalLabel), findsNothing);
      expect(find.text('先発選手1'), findsOneWidget);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });

  testWidgets('ClientExceptionはサーバー未起動の案内を表示する', (tester) async {
    final client =
        MockClient((_) async => throw http.ClientException('Failed to fetch'));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(initialView: 1, org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      expect(find.text('サーバーが起動されていません'), findsOneWidget);
      expect(find.textContaining('ClientException'), findsNothing);
      expect(find.text('再読み込み'), findsOneWidget);
    }, () => client);
  });

  testWidgets('未登録年は空表示、API失敗は再読み込みできる', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return calls == 1
          ? http.Response('{}', 503)
          : http.Response('{"teams":[]}', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(initialView: 1, org: OrgConfig.mlb, year: 2025))));
      await tester.pumpAndSettle();
      expect(find.text('再読み込み'), findsOneWidget);
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('2025年のMLBの戦力情報はまだ登録されていません。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });
}
