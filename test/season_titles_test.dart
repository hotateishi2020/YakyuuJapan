import 'package:Yakyuu_Japan/View/mlb_season_titles_table.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/season_titles.dart';
import 'package:Yakyuu_Japan/View/season_titles_board.dart';
import 'package:Yakyuu_Japan/View/season_titles_table.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _HighlightLauncher extends UrlLauncherPlatform {
  @override
  Null get linkDelegate => null;
  String? opened;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened = url;
    return true;
  }
}

void main() {
  testWidgets('HOMEのMLB個人タイトルは年度の球団最短名を空欄ラベルにも補完する', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: SeasonTitlesGrid(year: 2026, org: OrgConfig.mlb, individualOnly: true, data: {
        'season_awards': {'pages': {'mlb': [
          {'key': 'major', 'name': '選手A', 'team': 'Los Angeles Dodgers', 'id_team': 40,
            'id_league': 4, 'detail': '本塁打王', 'name_shortest': '', 'confirmed': true},
        ]}},
        'standings': [{'year': 2026, 'leagues': [{'teams': [
          {'id_team': 40, 'name': 'ドジャース', 'name_shortest': 'LAD'},
        ]}]}],
      }),
    ))));
    expect(find.text('LAD'), findsOneWidget);
    expect(find.text('Los Angeles Dodgers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final home in [false, true]) {
    testWidgets('MLBのチームラベルは古い最短名より英字略称を優先する home=$home', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: MlbSeasonTitlesTable(year: 2026, individualOnly: home, groups: const {
          'major': [
            {'name': '選手A', 'team': 'ドジャース', 'id_league': 4, 'detail': '本塁打王', 'name_shortest': 'LA'},
            {'name': '選手B', 'team': 'ヤンキース', 'id_league': 3, 'detail': '本塁打王', 'name_shortest': 'ヤンキース'},
          ],
        }),
      ))));
      await tester.pumpAndSettle();
      expect(find.text('LAD'), findsOneWidget);
      expect(find.text('LA'), findsNothing);
      expect(find.text('NYY'), findsOneWidget);
      expect(find.text('ドジャース'), findsNothing);
      expect(find.text('ヤンキース'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('MLB titles use league grids at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: SeasonTitlesGrid(
        org: OrgConfig.mlb,
        year: 2026,
        data: {
          'season_awards': {
            'pages': {
              'test': [
                {'key': 'league_mvp', 'name': 'AL選手', 'detail': 'アメリカン・リーグ', 'confirmed': true},
                {'key': 'league_mvp', 'name': 'NL選手', 'detail': 'ナ・リーグ', 'confirmed': true},
                {'key': 'major', 'name': 'タイトル選手', 'detail': 'ナショナル・リーグ 本塁打王', 'confirmed': true},
                {'key': 'monthly', 'name': '月間選手', 'detail': 'AL 5月 野手', 'confirmed': true},
                {'key': 'glove', 'name': '未分類選手', 'detail': '外野手', 'confirmed': true},
              ]
            }
          }
        },
      ))));
      expect(find.byKey(const ValueKey('mlb-titles-grid-league')), findsOneWidget);
      for (final name in ['AL選手', 'NL選手', 'タイトル選手', '月間選手', '未分類選手']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('セ'), findsNothing);
      expect(find.text('沢村栄治賞'), findsNothing);
      expect(find.text('ワールドシリーズ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('サヨナラ賞の再生ボタンで登録済みの該当動画を開く', (tester) async {
    final previous = UrlLauncherPlatform.instance;
    final launcher = _HighlightLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SeasonTitlesGrid(data: {
      'season_awards': {
        'pages': {
          'test': [
            {'key': 'sayonara', 'name': '受賞選手', 'team': '阪神', 'detail': 'セントラル・リーグ 5月度', 'confirmed': true, 'highlight_video_id': 'abcdefghijk'},
          ]
        }
      }
    }, year: 2026, org: OrgConfig.npb))));
    final button = find.byTooltip('サヨナラシーンをYouTubeで見る');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final control = tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'サヨナラシーンをYouTubeで見る'));
    final circle = control.icon as Container;
    expect((circle.decoration as BoxDecoration).shape, BoxShape.circle);
    expect((circle.decoration as BoxDecoration).color, const Color(0xffd71920));
    expect((circle.child as Icon).color, Colors.white);
    expect(tester.getCenter(button).dx, greaterThan(tester.getCenter(find.text('受賞選手')).dx));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(launcher.opened, 'https://www.youtube.com/watch?v=abcdefghijk');
    expect(tester.takeException(), isNull);
  });
  testWidgets('サヨナラ賞を月間と週間の間、2軍12部門を週間の下に配置する', (tester) async {
    final data = jsonDecode(File('backend/data/season_awards/2026.json').readAsStringSync());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SeasonTitlesGrid(data: {'season_awards': data}, year: 2026, org: OrgConfig.npb))));
    final monthly = find.byKey(const ValueKey('titles-grid-monthly'));
    final sayonara = find.byKey(const ValueKey('titles-grid-sayonara'));
    final weekly = find.byKey(const ValueKey('titles-grid-weekly'));
    final farm = find.byKey(const ValueKey('titles-grid-farm'));
    expect(tester.getTopLeft(sayonara).dy, greaterThan(tester.getBottomLeft(monthly).dy));
    expect(tester.getTopLeft(weekly).dy, greaterThan(tester.getBottomLeft(sayonara).dy));
    expect(tester.getTopLeft(farm).dy, greaterThan(tester.getBottomLeft(weekly).dy));
    expect(find.descendant(of: sayonara, matching: find.text('大山 悠輔')), findsOneWidget);
    for (final label in ['東地区', '中地区', '西地区', '最多勝', '奪三振王', '最多安打', '最高出塁率']) {
      expect(find.descendant(of: farm, matching: find.text(label)), findsOneWidget);
    }
    expect(find.descendant(of: farm, matching: find.text('小西 慶治')), findsWidgets);
    final special = find.byKey(const ValueKey('titles-grid-special-awards'));
    final top = ['最優秀監督賞', '沢村栄治賞', '長嶋茂雄賞', '正力松太郎賞', '正力松太郎賞 特別賞'];
    final bottom = ['連盟特別表彰（功労賞）', '連盟特別表彰（特別賞）', 'コミッショナー特別表彰', 'スピードアップ賞', 'HIKESHI賞'];
    for (var i = 0; i < 5; i++) {
      final upper = find.descendant(of: special, matching: find.text(top[i]));
      final lower = find.descendant(of: special, matching: find.text(bottom[i]));
      expect(tester.getCenter(upper).dx, tester.getCenter(lower).dx);
      expect(tester.getCenter(lower).dy, greaterThan(tester.getCenter(upper).dy));
    }
    expect(tester.takeException(), isNull);
  });
  test('2026年の指定結果を既存の受賞データより優先する', () {
    final supplement = (jsonDecode(File('backend/data/season_award_supplement.json').readAsStringSync()) as List).where((r) => r['org'] == 'npb' && r['year'] == 2026).toList();
    final groups = buildSeasonTitles({
      'season_awards': {
        'pages': {
          'old': [
            {'key': 'allstar_champion', 'name': '旧結果'},
            {'key': 'interleague_outstanding', 'name': '旧選手'},
          ]
        }
      },
      'season_award_supplement': supplement,
    }, 2026);
    expect(groups['fresh_champion']!.single['name'], 'パ・リーグ');
    expect(groups['allstar_champion']!.single['name'], '引き分け');
    expect(groups['interleague_outstanding']!.map((r) => r['name']), ['栗原 陵矢', '高橋 遥人']);
  });
  testWidgets('選手名の左に最短球団ラベルを表示し、空の5週目を省く', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      body: SeasonTitlesGrid(data: {
        'standings': [
          {
            'year': 2026,
            'leagues': [
              {
                'teams': [
                  {'name': 'ソフトバンク', 'name_shortest': 'ソ', 'color_back': '#ffcc00', 'color_font': '#000000'},
                ]
              },
            ]
          },
        ],
        'season_awards': {
          'pages': {
            'test': [
              {'key': 'league_mvp', 'name': 'とても長い名前のタイトル受賞選手A', 'team': '福岡ソフトバンク', 'detail': 'パ・リーグ', 'confirmed': true},
              {'key': 'weekly', 'name': '週投手', 'team': '阪神', 'detail': '2026/04/01発表 セ・リーグ 投手', 'confirmed': true},
            ]
          }
        },
      }, year: 2026, org: OrgConfig.npb),
    )));
    expect(find.text('ソ'), findsOneWidget);
    final badge = tester.widget<Container>(find.ancestor(of: find.text('ソ'), matching: find.byType(Container)).first);
    expect((badge.decoration as BoxDecoration).color, const Color(0xffffcc00));
    expect(tester.widget<Text>(find.text('ソ')).style!.color, Colors.black);
    final playerName = find.text('とても長い名前のタイトル受賞選手A');
    expect(tester.widget<Text>(playerName).maxLines, 1);
    expect(tester.widget<Text>(playerName).softWrap, false);
    expect(tester.widget<FittedBox>(find.ancestor(of: playerName, matching: find.byType(FittedBox)).first).fit, BoxFit.scaleDown);
    expect(tester.getCenter(find.text('ソ')).dx, lessThan(tester.getCenter(playerName).dx));
    expect(find.text('4週目'), findsOneWidget);
    expect(find.text('5週目'), findsNothing);
    for (final key in ['interleague_outstanding', 'rookie']) {
      final header = find.byKey(ValueKey('titles-split-header-$key'));
      expect(tester.getSize(header).height, 84);
      expect(find.descendant(of: header, matching: find.text('セ')), findsOneWidget);
      expect(find.descendant(of: header, matching: find.text('パ')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  test('all screenshot sections exist and no current first place is declared champion', () {
    final groups = buildSeasonTitles({
      'standings': [
        {
          'year': 2026,
          'leagues': [
            {
              'name': 'セ・リーグ',
              'teams': [
                {'name': '阪神', 'league_champion': true}
              ]
            }
          ]
        }
      ]
    }, 2026);
    expect(groups.length, seasonTitleSections.length);
    expect(groups, contains('series_fighting'));
    expect(groups, contains('series_outstanding'));
    expect(groups['league_champion'], isEmpty);
  });
  test('selected year and all title categories survive fallback', () {
    final groups = buildSeasonTitles({
      'titles': [
        {
          'year': 2025,
          'league': 'セ・リーグ',
          'categories': [
            {
              'label': 'MVP',
              'players': [
                {'name': '旧年度'}
              ]
            }
          ]
        },
        {
          'year': 2026,
          'league': 'セ・リーグ',
          'provisional': true,
          'categories': [
            {
              'label': '首位打者',
              'players': [
                {'name': 'A'}
              ]
            },
            {
              'label': '本塁打王',
              'players': [
                {'name': 'B'}
              ]
            },
          ]
        },
      ]
    }, 2026);
    expect(groups['major']!.map((p) => p['name']), ['A', 'B']);
    expect(groups['major']!.every((p) => p['confirmed'] == false), isTrue);
    expect(groups['league_mvp'], isEmpty);
  });
  test('official winners replace provisional leaders only for that league', () {
    final groups = buildSeasonTitles({
      'season_awards': {
        'pages': {
          'cl': [
            {'key': 'major', 'name': '確定', 'detail': 'セ・リーグ 首位打者賞', 'confirmed': true}
          ]
        }
      },
      'titles': [
        {
          'year': 2026,
          'league': 'セ・リーグ',
          'categories': [
            {
              'label': '首位打者',
              'players': [
                {'name': '暫定'}
              ]
            }
          ]
        },
        {
          'year': 2026,
          'league': 'パ・リーグ',
          'categories': [
            {
              'label': '首位打者',
              'players': [
                {'name': 'パ首位'}
              ]
            }
          ]
        },
      ]
    }, 2026);
    expect(groups['major']!.map((p) => p['name']), ['確定', 'パ首位']);
  });
  testWidgets('table places league, position and monthly winners without losing ties', (tester) async {
    final awards = [
      {'key': 'glove', 'name': '外野手A', 'team': '阪神', 'detail': '外野手'},
      {'key': 'glove', 'name': '外野手B', 'team': '中日', 'detail': '外野手'},
      {'key': 'series_entrants', 'name': '横浜DeNA'},
      {'key': 'league_champion', 'name': '阪神'},
      {'key': 'monthly', 'name': '同月打者', 'detail': 'セントラル・リーグ 打者 3、4月度'},
      {'key': 'monthly', 'name': '同月パ投手', 'detail': 'パシフィック・リーグ 投手 3、4月度'},
      {'key': 'monthly', 'name': '月間投手', 'detail': 'セントラル・リーグ 投手 3、4月度'},
      {'key': 'monthly', 'name': '月間打者', 'detail': 'パシフィック・リーグ 打者 9、10月度'},
      {'key': 'major', 'name': '勝利投手', 'detail': 'セ・リーグ 最多勝利投手賞'},
      {'key': 'major', 'name': '同率勝利投手', 'detail': 'セ・リーグ 最多勝利投手賞'},
    ];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SeasonTitlesGrid(data: {
      'season_awards': {
        'pages': {'test': awards}
      }
    }, year: 2026, org: OrgConfig.npb))));
    for (final row in awards) {
      expect(find.text(row['name']!), findsOneWidget);
    }
    expect(find.text('ベストナイン'), findsOneWidget);
    expect(find.text('ゴールデングラブ賞'), findsOneWidget);
    expect(find.text('3・4月月間MVP'), findsOneWidget);
    expect(find.text('リーグ優勝'), findsOneWidget);
    expect(find.text('CS優勝'), findsOneWidget);
    expect(tester.getCenter(find.text('最多勝').first).dy, tester.getCenter(find.text('首位打者').first).dy);
    expect(tester.getCenter(find.text('月間投手')).dy, tester.getCenter(find.text('同月打者')).dy);
    expect(tester.getCenter(find.text('同月打者')).dx, greaterThan(tester.getCenter(find.text('月間投手')).dx));
    expect(tester.getCenter(find.text('同月パ投手')).dy, greaterThan(tester.getCenter(find.text('月間投手')).dy));
    expect(tester.getCenter(find.text('新人王')).dy, tester.getCenter(find.text('交流戦優秀選手')).dy);

    expect(tester.takeException(), isNull);
    await tester.dragFrom(const Offset(600, 200), const Offset(-500, 0));
    await tester.pumpAndSettle();
    final horizontal = tester.state<ScrollableState>(find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.right));
    expect(horizontal.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets('weekly MVP sits below monthly and groups month, week, league and role', (tester) async {
    final awards = [
      for (var week = 0; week < 6; week++) {'key': 'weekly', 'name': '週投手$week', 'detail': '2026/04/${(week * 5 + 1).toString().padLeft(2, '0')}発表 セ・リーグ 投手', 'confirmed': true},
      {'key': 'weekly', 'name': '週野手', 'detail': '2026/04/01発表 セ・リーグ 野手', 'confirmed': true},
      {'key': 'weekly', 'name': 'パ週投手', 'detail': '2026/04/01発表 パ・リーグ 投手', 'confirmed': true},
      {'key': 'weekly', 'name': '区分不明選手', 'detail': '', 'confirmed': true},
    ];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SeasonTitlesGrid(data: {
      'season_awards': {
        'pages': {'test': awards}
      }
    }, year: 2026, org: OrgConfig.npb))));
    for (final row in awards) {
      expect(find.text(row['name'] as String), findsOneWidget);
    }
    expect(find.text('6週目'), findsOneWidget);
    expect(tester.getCenter(find.text('週間MVP（3・4月）')).dy, greaterThan(tester.getCenter(find.text('3・4月月間MVP')).dy));
    expect(tester.getCenter(find.text('週間MVP（5月）')).dx, closeTo(tester.getCenter(find.text('5月月間MVP')).dx, .01));
    expect(tester.getCenter(find.text('週投手0')).dy, tester.getCenter(find.text('週野手')).dy);
    expect(tester.getCenter(find.text('週野手')).dx, greaterThan(tester.getCenter(find.text('週投手0')).dx));
    expect(tester.getCenter(find.text('パ週投手')).dy, greaterThan(tester.getCenter(find.text('週投手0')).dy));
    expect(tester.getCenter(find.text('週投手1')).dy, greaterThan(tester.getCenter(find.text('パ週投手')).dy));
    expect(tester.takeException(), isNull);
  });
  testWidgets('wide screens expand title grids to the available width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(2100, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SeasonTitlesGrid(data: {}, year: 2026, org: OrgConfig.npb))));
    for (final key in ['series', 'league', 'best9', 'glove', 'statistical', 'events', 'monthly', 'weekly']) {
      expect(tester.getSize(find.byKey(ValueKey('titles-grid-$key'))).width, 2066);
    }
    final horizontal = tester.state<ScrollableState>(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right));
    expect(horizontal.position.maxScrollExtent, 0);
    await tester.binding.setSurfaceSize(const Size(1700, 1100));
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('titles-grid-best9'))).width, 1666);
    expect(tester.getSize(find.byKey(const ValueKey('titles-grid-statistical'))).width, 1666);
    for (final width in [1200.0, 1440.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      await tester.pump();
      for (final key in ['series', 'league', 'statistical', 'events', 'monthly', 'weekly']) {
        expect(tester.getSize(find.byKey(ValueKey('titles-grid-$key'))).width, width - 34);
      }
      expect(horizontal.position.maxScrollExtent, 0);
      expect(tester.takeException(), isNull);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('縦画面は項目を行、リーグを列に転置し横スクロールしない', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final launcher = _HighlightLauncher();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    final groups = <String, List<Map<String, dynamic>>>{
      'best9': [
        {'name': 'セ投手', 'team': '阪神', 'detail': 'セントラル・リーグ 投手', 'confirmed': true},
        {'name': 'パ投手', 'team': '西武', 'detail': 'パシフィック・リーグ 投手', 'confirmed': true},
        {'name': 'セ捕手', 'team': '阪神', 'detail': 'セントラル・リーグ 捕手', 'confirmed': true},
      ],
      'monthly': [
        {'name': '月間選手', 'team': '阪神', 'detail': 'セントラル・リーグ 5月 投手', 'confirmed': true}
      ],
      'weekly': [
        {'name': '週間選手', 'team': '西武', 'detail': '2026/08/17発表 パ・リーグ 野手', 'confirmed': true}
      ],
      'sayonara': [
        {'name': '動画選手', 'team': '阪神', 'detail': 'セントラル・リーグ 5月度', 'confirmed': true, 'highlight_video_id': 'abcdefghijk'}
      ],
    };
    for (final width in [320.0, 390.0, 768.0]) {
      tester.view.physicalSize = Size(width, 1024);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SeasonTitlesTable(groups: groups, year: 2026))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('titles-portrait-board')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right), findsNothing);
      for (final key in ['series', 'league', 'special-awards', 'best9', 'glove', 'statistical', 'events', 'monthly', 'sayonara', 'weekly', 'farm']) {
        final rect = tester.getRect(find.byKey(ValueKey('titles-grid-$key')));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
      }
      expect(tester.getCenter(find.text('セ投手')).dy, tester.getCenter(find.text('パ投手')).dy);
      expect(tester.getCenter(find.text('セ投手')).dx, lessThan(tester.getCenter(find.text('パ投手')).dx));
      expect(tester.getCenter(find.text('セ捕手')).dy, greaterThan(tester.getCenter(find.text('セ投手')).dy));
      expect(find.text('月間選手'), findsOneWidget);
      expect(find.text('週間選手'), findsOneWidget);
      expect(find.textContaining('5週目'), findsNothing);
      expect(find.textContaining('表は左右にスクロールできます'), findsNothing);
      final button = find.byTooltip('サヨナラシーンをYouTubeで見る');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(launcher.opened, 'https://www.youtube.com/watch?v=abcdefghijk');
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(1024, 768);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('titles-portrait-board')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow title screen scrolls without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SeasonTitlesGrid(data: {
      'season_awards': {
        'pages': {
          'x': [
            {'key': 'series_mvp', 'name': '受賞者', 'team': '所属球団', 'confirmed': true}
          ]
        }
      }
    }, year: 2026, org: OrgConfig.npb))));
    expect(find.text('受賞者'), findsOneWidget);
    expect(find.text('日本シリーズMVP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
