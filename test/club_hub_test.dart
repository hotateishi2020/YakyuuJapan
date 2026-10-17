import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/club_hub_board.dart';
import 'package:Yakyuu_Japan/View/team_strength_board.dart';
import 'package:Yakyuu_Japan/View/EventCalendar.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'package:Yakyuu_Japan/logic/club_analysis.dart';
import 'package:Yakyuu_Japan/logic/season_schedule.dart';

void main() {
  final game = <String, dynamic>{'date': '2026-10-16', 'id_team_home': 1, 'id_team_away': 2, 'name_home': '巨', 'name_away': '神', 'score_home': 3, 'score_away': 1, 'finished': true, 'regular': true, 'league_home': 1, 'league_away': 2};
  test('21日間は月・年境界を跨ぎ、本日を中央に含む', () {
    final days = scheduleWindow(DateTime(2026, 1, 1));
    expect(days.length, 21);
    expect(scheduleDate(days.first), '2025-12-22');
    expect(scheduleDate(days[10]), '2026-01-01');
    expect(scheduleDate(days.last), '2026-01-11');
  });
  test('相手別勝敗はホーム・ビジターを反転し未終了・PSを除外', () {
    final games = [
      game,
      {...game, 'score_home': 1, 'score_away': 3},
      {...game, 'score_home': 1, 'score_away': 1},
      {...game, 'finished': false},
      {...game, 'regular': false}
    ];
    expect(scheduleRecord(games, 1, opponent: 2), (wins: 1, losses: 1, draws: 1));
    expect(scheduleMatchup(game, teamId: 2), '●巨 1–3');
    expect(scheduleMatchup({...game, 'finished': false, 'state': '試合中止'}, teamId: 2), contains('中止'));
  });
  test('交流戦集計はリーグ内対戦を除く', () {
    final rows = interleagueStandings([
      {'id_team': 1},
      {'id_team': 2}
    ], [
      game,
      {...game, 'league_away': 1, 'score_home': 0}
    ]);
    expect(rows.first['id_team'], 1);
    expect(rows.first['wins'], 1);
    expect(rows.last['losses'], 1);
  });
  test('相対評価は低WHIPを上位とし、未計測は評価しない', () {
    expect(relativeGrade(.9, [.9, 1, 1.1], lowerBetter: true), 'S');
    expect(relativeGrade(.9, [.9, 1, 1.1]), 'G');
    expect(relativeGrade(null, [1, 2]), '—');
    expect(relativeGrade(1, [1, 1]), 'C');
    expect(clubMetrics({})['内野守備'], isNull);
  });
  test('平均年齢は複数守備の同一選手を重複集計しない', () {
    final rows = analyzeClubs([
      {
        'positions': [
          for (final slot in ['1B', 'LF'])
            {
              'slot': slot,
              'total': 10,
              'players': [
                {'player_key': 'a', 'name': 'A', 'count': 10}
              ]
            }
        ],
        'roster': [
          {'player_key': 'a', 'name': 'A', 'date_birth': '2000-01-01'}
        ]
      }
    ], 2025);
    expect(rows.single['age_count'], 1);
    expect(rows.single['regular_age'], 25);
  });
  test('自主トレは人数順、個人成績は複数ポジションでも単色', () {
    expect(
        sortedTrainingGroups([
          {
            'name': 'A',
            'members': [
              {'name': 'a'}
            ]
          },
          {
            'name': 'B',
            'members': [
              {'name': 'b'},
              {'name': 'c'}
            ]
          }
        ]).first['name'],
        'B');
    expect(
        personalStatPositionGradient({
          'txt_position': '投手',
          'positions': ['P', 'DH']
        }),
        isNull);
  });
  testWidgets('横長スタッツは打者・投手を切り替える', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: DualBandLeaguePersonalStats(batting: [
      {'title': '打率', 'stats': '.300', 'int_rank': 1, 'name_player': '打者A', 'flg_pitcher': false}
    ], pitching: [
      {'title': '防御率', 'stats': '1.00', 'int_rank': 1, 'name_player': '投手B', 'flg_pitcher': true}
    ]))));
    expect(find.text('打者A'), findsOneWidget);
    expect(find.text('投手B'), findsNothing);
    await t.tap(find.text('投手スタッツ'));
    await t.pumpAndSettle();
    expect(find.text('投手B'), findsOneWidget);
    expect(find.text('打者A'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('日程カレンダーにイベントと対戦を併記し月を移動できる', (t) async {
    DateTime? moved;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EventCalendar(
                initialMonth: DateTime(2026, 10),
                events: const [
                  {'title_event': 'ドラフト', 'date_from_temp': '2026-10-16'}
                ],
                games: [game],
                onMonthChanged: (d) => moved = d))));
    expect(find.byType(ScheduleGameTile), findsOneWidget);
    expect(find.text('ドラフト'), findsOneWidget);
    await t.tap(find.byIcon(Icons.chevron_right));
    await t.pump();
    expect(moved, DateTime(2026, 11));
    expect(find.byType(ScheduleGameTile), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('戦力の新しい4タブと球団集約は狭い画面でも開く', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    var clubRequests = 0;
    await http.runWithClient(() async {
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: TeamStrengthBoard(org: OrgConfig.npb, year: 2026, providedTeams: [
        {'id_team': 1, 'name_team': '巨人'}
      ]))));
      for (final label in ['チーム', '首脳', '自主トレ', '分析']) {
        expect(find.text(label), findsOneWidget);
      }
      await t.tap(find.text('チーム'));
      await t.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsNothing);
      final sections = t.state<ScrollableState>(find.descendant(
          of: find.byType(ClubHubBoard), matching: find.byType(Scrollable)).first);
      for (var i = 0; i < 20 && find.text('スポンサー・広告').evaluate().isEmpty; i++) {
        sections.position.jumpTo((sections.position.pixels + 600).clamp(0, sections.position.maxScrollExtent));
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('スポンサー・広告'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('strength-view-3')));
      await t.pumpAndSettle();
      await t.tap(find.text('分析'));
      await t.pumpAndSettle();
      expect(find.text('レギュラー平均年齢'), findsOneWidget);
      expect(t.takeException(), isNull);
    }, () => MockClient((r) async {
      if (r.url.path == '/club-hub') clubRequests++;
      return http.Response(jsonEncode({'clubs': []}), 200);
    }));
    expect(clubRequests, 1);
  });
  testWidgets('首脳グリッドと自主トレグループを公式出典付きで表示', (t) async {
    final data = {
      'clubs': [
        {
          'code': 'g',
          'name': '巨人',
          'staff': [
            {'name': '登録監督', 'role': '監督', 'category': '監督', 'source': 'https://npb.jp/'}
          ]
        }
      ],
      'training_groups': [
        {
          'name': '合同組',
          'members': [
            {'name': 'A', 'team': '巨人'},
            {'name': 'B', 'team': '阪神'}
          ],
          'source': 'https://npb.jp/'
        }
      ]
    };
    await http.runWithClient(() async {
      Widget board(int view) => MaterialApp(home: Scaffold(body: ClubHubBoard(org: OrgConfig.npb, year: 2026, teams: const [], view: view, teamSection: (_, __) => const SizedBox.shrink())));
      await t.pumpWidget(board(8));
      await t.pumpAndSettle();
      expect(find.text('登録監督'), findsOneWidget);
      expect(find.textContaining('スカウト'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(board(9));
      await t.pumpAndSettle();
      expect(find.text('合同組　2人'), findsOneWidget);
      expect(find.text('A (巨人)'), findsOneWidget);
      expect(t.takeException(), isNull);
    }, () => MockClient((r) async => http.Response(jsonEncode(data), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
  });
  testWidgets('順位表に全相手の列と本日前後の列を追加できる', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SeasonTableBlock(
                    standings: const [
                      {'id_team': 1, 'id_league': 1, 'name_team': '巨人', 'name_shortest': '巨', 'int_rank': 1},
                      {'id_team': 2, 'id_league': 1, 'name_team': '阪神', 'name_shortest': '神', 'int_rank': 2}
                    ],
                    stats: const [],
                    onlyLeagueId: 1,
                    pane: SeasonPane.standings,
                    portraitLayout: true,
                    showScheduleColumns: true,
                    scheduleGames: [game])))));
    expect(find.text('対神\n勝–負–分'), findsOneWidget);
    expect(find.text('1–0–0'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
