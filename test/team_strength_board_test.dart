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
              body: TeamStrengthBoard(org: OrgConfig.npb, year: 2026))));
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
              body: TeamStrengthBoard(org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
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
              body: TeamStrengthBoard(org: OrgConfig.npb, year: 2026))));
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

  testWidgets('一覧は外野を統合し不明打席の選手を左右にまたがって表示する', (tester) async {
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
    expect(find.text('外野手'), findsOneWidget);
    for (final label in ['左翼', '中堅', '右翼', '不明打ち']) {
      expect(find.text(label), findsNothing);
    }
    Rect card(String name) => tester.getRect(find
        .ancestor(of: find.text(name), matching: find.byType(Tooltip))
        .first);
    final right = card('左の選手');
    final left = card('中の選手');
    final unknown = card('右の選手');
    expect(unknown.left, closeTo(right.left, 0.1));
    expect(unknown.right, closeTo(left.right, 0.1));
    expect(unknown.top, greaterThan(right.bottom));
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
    expect(headerColor('外野手'), const Color(0xFF43A047));
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
    await tester.binding.setSurfaceSize(const Size(1600, 600));
    await tester.pumpAndSettle();
    final table = tester.getRect(find.byType(Table));
    expect(table.left, closeTo(160, 0.1));
    expect(table.right, closeTo(1600, 0.1));
    expect(scroll.offset, 0);
    expect(scroll.position.maxScrollExtent, 0);
    expect(tester.getCenter(find.text('球団')).dx, closeTo(80, 0.1));
    expect(tester.getCenter(find.text('捕手')).dx, closeTo(240, 0.1));
    expect(tester.getCenter(find.text('指名打者')).dx, closeTo(1520, 0.1));
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

  testWidgets('スクロール位置の保存値を投手詳細の開閉状態として読み込まない', (tester) async {
    final bucket = PageStorageBucket();
    const listKey = PageStorageKey('strength-lineup-npb-2026-1');
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
        child: const TeamStrengthBoard(org: OrgConfig.npb, year: 2026),
      ))));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('各投手の投球回・負担率'), 300,
          scrollable: find
              .descendant(
                  of: find.byKey(listKey), matching: find.byType(Scrollable))
              .first);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('各投手の投球回・負担率'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          bucket.readState(tester.element(find.byKey(listKey))), isA<double>());
      await tester.tap(find.byKey(const ValueKey('strength-view-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('strength-view-0')));
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
      expect(find.text('先発選手1'), findsOneWidget,
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

  for (final width in [390.0, 1200.0]) {
    testWidgets('幅$widthで投手とスタメン比率を表示し、球団変更で通信しない', (tester) async {
      final vertical = width < 600;
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
                body: TeamStrengthBoard(org: OrgConfig.npb, year: 2026))));
        await tester.pumpAndSettle();
        for (final label in ['選手起用', 'レギュラー', '選手一覧']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.byType(DropdownButton<int>), findsNothing);
        expect(find.text('投手の投球回負担率'), findsOneWidget);
        expect(find.text('先発負担率'), findsOneWidget);
        expect(find.text('中継負担率'), findsOneWidget);
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
        if (!vertical) {
          expect(tester.getSize(header).width, closeTo(105.6, 0.01));
        }
        final starter = find.byTooltip('先発選手1（先発）：20回（チーム全体の12.1%）');
        expect(starter, findsOneWidget);
        final starterRect = tester.getRect(starter);
        final secondStarter =
            tester.getRect(find.byTooltip('兼任1（先発）：10回（チーム全体の6.1%）'));
        final band = tester
            .getRect(find.byKey(const ValueKey('strength-band-outs-starter')));
        if (vertical) {
          final detail = tester.getRect(
              find.byKey(const ValueKey('strength-detail-outs-starter')));
          expect(detail.top, greaterThanOrEqualTo(band.bottom));
          expect(detail.center.dx, closeTo(band.center.dx, 0.01));
          expect(starterRect.height + secondStarter.height,
              closeTo(band.height, 0.01));
        } else {
          expect(starterRect.width + secondStarter.width,
              closeTo(band.width, 0.01));
          expect(secondStarter.right, closeTo(band.right, 0.01));
          expect(
              find.descendant(
                  of: find.byTooltip('少登板1（中継ぎ・抑え）：5回（チーム全体の3.0%）'),
                  matching: find.text('少登板1')),
              findsOneWidget);
        }

        if (vertical) {
          expect(tester.getTopLeft(find.text('打順のスタメン比率')).dy,
              greaterThan(starterRect.bottom));
          expect(starterRect.height, closeTo(780 * 60 / 90, 0.01));
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('strength-view-1')));
        await tester.pumpAndSettle();
        expect(find.text('球団A'), findsOneWidget);
        expect(find.text('球団B'), findsOneWidget);
        expect(find.byType(Table), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('strength-view-2')));
        await tester.pumpAndSettle();
        expect(find.text('年齢'), findsOneWidget);
        expect(find.text('育成選手1 【契・FA・退】'), findsOneWidget);
        expect(find.text('内野手'), findsOneWidget);
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
        await tester.tap(find.byKey(const ValueKey('strength-view-0')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('先発選手2（先発）：20回（チーム全体の12.1%）'), findsOneWidget);
        expect(requests, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    });
  }

  testWidgets('狭い画面は帯を横スクロールでき、画面を広げると通信せず横向きの帯に戻る', (tester) async {
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
              body: TeamStrengthBoard(org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      final starter = find.byTooltip('先発選手1（先発）：20回（チーム全体の12.1%）');
      final before = tester.getRect(starter);
      expect(before.height, greaterThan(before.width));
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
              body: TeamStrengthBoard(org: OrgConfig.mlb, year: 2025))));
      await tester.pumpAndSettle();
      expect(find.text('再読み込み'), findsOneWidget);
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('2025年のMLBの戦力情報はまだ登録されていません。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });
}
