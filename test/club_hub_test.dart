import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/club_hub_board.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';
import 'package:Yakyuu_Japan/View/strength_contracts.dart';
import 'package:Yakyuu_Japan/View/team_strength_board.dart';
import 'package:Yakyuu_Japan/View/EventCalendar.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart' show teamLogoAsset;
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'package:Yakyuu_Japan/logic/club_analysis.dart';
import 'package:Yakyuu_Japan/logic/season_schedule.dart';

void main() {
  testWidgets('契約タブは常に比較し球団別契約はチームのセグメントで開く', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final teams = <Map<String,dynamic>>[for (var i=1; i<=12; i++) {
      'id_team':i, 'name_team':'球団$i',
      'roster':[{'player_key':'npb:$i','name':'選手$i','position':'投手'}],
      'contracts':[{'player_key':'npb:$i','salary_history':[{'year':2026,'amount':10000000,'currency':'JPY'}]}],
    }];
    await http.runWithClient(() async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: TeamStrengthBoard(
        org: OrgConfig.npb, year: 2026, initialView:4, favoriteTeamId:2, providedTeams:teams,
      ))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('strength-comparison-false')), findsNothing);
      expect(find.byKey(const ValueKey('strength-team-2')), findsNothing);
      expect(t.widget<StrengthContracts>(find.byType(StrengthContracts)).comparisonTeams, hasLength(12));
      await t.tap(find.byKey(const ValueKey('strength-view-8')));
      await t.pumpAndSettle();
      final hub = find.byType(ClubHubBoard);
      await t.tap(find.byKey(const ValueKey('team-section-segment-6')));
      await t.pumpAndSettle();
      final contracts = find.descendant(of:hub, matching:find.byType(StrengthContracts));
      expect(contracts, findsOneWidget);
      expect(t.widget<StrengthContracts>(contracts).comparisonTeams, isNull);
      expect(find.text('この年度の公式スポンサー情報は未収録です。'), findsNothing);
      await t.tap(find.byKey(const ValueKey('team-tab-segment-2')));
      await t.pumpAndSettle();
      expect(t.widget<StrengthContracts>(contracts).team['id_team'], 2);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('strength-view-4')));
      await t.pumpAndSettle();
      // Comparison stays configured even after browsing a single team.
      expect(find.byWidgetPredicate((w) => w is StrengthContracts && w.comparisonTeams?.length == 12), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    }, () => MockClient((_) async => http.Response('{"clubs":[]}',200)));
  });

  testWidgets('旧選手一覧はチームへ移り独立したタブを表示しない', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: TeamStrengthBoard(
        org: OrgConfig.npb, year: 2026, initialView: 3,
        providedTeams: [{'id_team':1, 'name_team':'球団A', 'roster':[]}],
      ))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('strength-view-3')), findsNothing);
      expect(find.byKey(const ValueKey('strength-view-8')), findsOneWidget);
      expect(t.widget<ClubHubBoard>(find.byType(ClubHubBoard)).view, 7);
      expect(find.text('選手一覧'), findsOneWidget); // チーム内の見出し
      expect(find.byType(StrengthRosterGrid), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    }, () => MockClient((_) async => http.Response('{"clubs":[]}',200)));
  });

  test('戦前のイーグルスに楽天のロゴを割り当てない', () {
    expect(teamLogoAsset('イーグルス'), isNull);
    expect(teamLogoAsset('大和軍'), isNull);
    for (final name in ['楽天', '東北楽天ゴールデンイーグルス', 'ゴールデンイーグルス']) {
      expect(teamLogoAsset(name), 'backend/assets/images/team_e.png');
    }
  });
  testWidgets('分析の評価色とクリック時のOAA根拠を表示する', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 800));
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1200, 800);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: ClubHubBoard(
        org: OrgConfig.mlb, year: 2026, view: 10, teamSection: (_, __) => const SizedBox.shrink(),
        teams: [for (var i=1; i<=2; i++) {
          'id_team': i, 'name_team': '球団$i', 'color_back': '#003366', 'color_font': '#ffffff',
          'defense_analysis': {'infield': {'metric': 'OAA', 'year': 2026, 'value': i == 1 ? 20 : -20,
            'source_url': 'https://baseballsavant.mlb.com/', 'checked_at': '2026-10-17'}},
        }],
      ))));
      await t.pumpAndSettle();
      final badge = find.byKey(const ValueKey('analysis-grade-1-内野守備'));
      expect((t.widget<Container>(badge).decoration as BoxDecoration).color, clubAnalysisGradeColors['S']);
      await t.tap(badge);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('OAA：20.0'), findsWidgets);
      expect(find.text('指標の出典'), findsNothing);
      await t.tap(find.text('閉じる'));
      await t.pumpAndSettle();
      final tableFinder = find.byKey(const ValueKey('analysis-table'));
      expect(find.byKey(const ValueKey('analysis-fixed-header')), findsOneWidget);
      final teamCell = find.byKey(const ValueKey('analysis-team-1'));
      expect(t.widget<Container>(teamCell).color, const Color(0xFF003366));
      await t.binding.setSurfaceSize(const Size(1600, 800));
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1600, 800);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpAndSettle();
      expect(t.getSize(tableFinder).width, closeTo(1600, 1));
      await t.binding.setSurfaceSize(const Size(600, 800));
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(600, 800);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpAndSettle();
      expect(t.getSize(tableFinder).width, closeTo(600, .01));
      expect(t.getSize(teamCell).width, closeTo(46, 1));
      expect(find.descendant(of: teamCell, matching: find.byType(Text)), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('analysis-vertical-scroll')), matching: find.textContaining('取得済み成績による団体内')), findsOneWidget);
      expect(find.byKey(const ValueKey('analysis-grade-legend')), findsNothing);
      final horizontal = find.descendant(
        of: find.byKey(const ValueKey('analysis-horizontal-scroll')),
        matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right),
      );
      expect(t.state<ScrollableState>(horizontal).position.maxScrollExtent, greaterThan(600));
      final teamLeft = t.getTopLeft(teamCell).dx;
      await t.drag(horizontal, const Offset(-300, 0));
      await t.pumpAndSettle();
      expect(t.state<ScrollableState>(horizontal).position.pixels, greaterThan(0));
      expect(t.getTopLeft(teamCell).dx, teamLeft);
      expect(t.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });
  testWidgets('分析表のヘッダーは縦スクロールしても同じ位置に残る', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: ClubHubBoard(
        org: OrgConfig.npb, year: 2026, view: 10,
        teamSection: (_, __) => const SizedBox.shrink(),
        teams: [for(var i=1;i<=12;i++) {'id_team':i,'name_team':'球団$i'}],
      ))));
      await t.pumpAndSettle();
      final header = find.byKey(const ValueKey('analysis-fixed-header'));
      final before = t.getTopLeft(header);
      final row = find.byKey(const ValueKey('analysis-team-1'));
      final rowBefore = t.getTopLeft(row);
      await t.drag(find.byKey(const ValueKey('analysis-vertical-scroll')), const Offset(0,-300));
      await t.pumpAndSettle();
      expect(t.getTopLeft(header), before);
      expect(t.getTopLeft(row).dy, lessThan(rowBefore.dy));
      expect(t.takeException(),isNull);
    }, () => MockClient((_) async => http.Response('{}',200)));
  });
  test('守備OAAは比較球団すべてが同年度で揃った場合だけ使用する', () {
    Map<String, dynamic> team(int id, int value, int year) => {
      'id_team': id,
      'defense_analysis': {'infield': {'metric': 'OAA', 'year': year, 'value': value}},
      'fielding_stats': [{'position': 'SS', 'putouts': 99, 'assists': 0, 'errors': 1}],
    };
    final complete = analyzeClubs([team(1, 10, 2026), team(2, -10, 2026)], 2026);
    expect(complete.first['grades']['内野守備'], 'S');
    expect(complete.last['grades']['内野守備'], 'G');
    expect(complete.first['defense_methods']['内野守備'], 'OAA');
    final incomplete = analyzeClubs([team(1, 10, 2026), team(2, -10, 2025)], 2026);
    expect(incomplete.first['defense_methods']['内野守備'], '失策参考');
    expect(incomplete.first['metrics']['内野守備'], .99);
  });
  test('分析の8段階は指定された色を使用する', () {
    expect(clubAnalysisGradeColors.values, [
      const Color(0xFFFFD700), const Color(0xFFFF80AB), const Color(0xFFEF5350),
      const Color(0xFFFF9800), const Color(0xFFFFEB3B), const Color(0xFFB2DB59),
      const Color(0xFF81D4FA), const Color(0xFFBDBDBD),
    ]);
  });
  final game = <String, dynamic>{'date': '2026-10-16', 'id_team_home': 1, 'id_team_away': 2, 'name_home': '巨', 'name_away': '神', 'score_home': 3, 'score_away': 1, 'finished': true, 'regular': true, 'league_home': 1, 'league_away': 2};
  testWidgets('CSの横浜の略称デでも球団ロゴを表示する', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: ScheduleGameTile(game: {
      'name_away': 'デ', 'name_home': '神', 'finished': false,
    }))));
    expect(find.byWidgetPredicate((w) => w is Image && w.image is AssetImage &&
      (w.image as AssetImage).assetName == 'backend/assets/images/team_db.png'), findsOneWidget);
    expect(find.byIcon(Icons.sports_baseball), findsNothing);
  });
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
  test('走力はチーム盗塁と盗塁死を試合数で補正する', () {
    final team = <String, dynamic>{'game_count': 100, 'batting_stats': [
      {'stolen_bases': 30, 'caught_stealing': 5},
      {'stolen_bases': 20, 'caught_stealing': 2},
    ]};
    expect(clubMetrics(team)['走力'], closeTo(.36, .00001));
    expect(clubMetrics({...team, 'game_count': 50})['走力'], closeTo(.72, .00001));
    expect(clubMetrics({'game_count': 100, 'batting_stats': [{'stolen_bases': 10}]})['走力'], isNull);
  });
  test('守備は位置別失策率で評価し、外野合計と個別位置を重複しない', () {
    Map<String, dynamic> row(String pos, int po, int assists, int errors) =>
      {'position': pos, 'putouts': po, 'assists': assists, 'errors': errors};
    final metrics = clubMetrics({'fielding_stats': [
      row('1B', 80, 10, 10), row('SS', 40, 60, 0),
      row('LF', 90, 5, 5), row('OF', 90, 5, 5),
      row('P', 0, 0, 99), row('C', 0, 0, 99),
    ]});
    expect(metrics['内野守備'], closeTo(.95, .00001));
    expect(metrics['外野守備'], closeTo(.95, .00001));
    expect(clubMetrics({'fielding_stats': [row('OF', 100, 0, 0)]})['外野守備'], 1);
    expect(clubMetrics({'fielding_stats': [row('OF', 0, 0, 0)]})['外野守備'], isNull);
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
      for (final label in ['チーム', '自主トレ', '分析']) {
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
  testWidgets('首脳と自主トレは出典リンクなしで内容を表示', (t) async {
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
          'source': 'https://npb.jp/',
          'sources': ['https://npb.jp/', 'https://www.nikkansports.com/baseball/']
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
      expect(find.text('合同組  2人'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('出典：npb.jp'), findsNothing);
      expect(find.text('出典：www.nikkansports.com'), findsNothing);
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
    expect(find.text('神\n勝–負–分'), findsOneWidget);
    expect(find.text('1–0–0'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
