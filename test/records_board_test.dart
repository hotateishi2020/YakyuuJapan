import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

final fixture = {
  'standings': [
    {
      'year': 2025,
      'champion': '優勝球団',
      'leagues': [
        {
          'name': 'セ・リーグ',
          'teams': [
            {
              'rank': 1,
              'name': '優勝球団',
              'short_name': '優勝略称',
              'color_back': '#ff0000',
              'color_font': '#ffffff',
              'wins': 90,
              'losses': 50,
              'draws': 3,
              'champion': true,
              'postseason': true
            },
            for (var rank = 2; rank <= 6; rank++)
              {'rank': rank, 'name': '球団$rank', 'short_name': '略称$rank', 'postseason': rank <= 3}
          ]
        }
      ]
    }
  ],
  'titles': [
    {
      'year': 2025,
      'league': 'セ・リーグ',
      'categories': [
        {
          'label': '本塁打王',
          'players': [
            {'name': 'タイトル 選手', 'team': '所属球団', 'color_back': '#003300', 'color_font': '#ffffff', 'value': 40, 'status': 'unknown', 'year': 2025},
            {'name': '同率　選手', 'value': 40, 'status': 'unknown', 'year': 2025}
          ]
        },
        {
          'label': 'MVP',
          'players': [
            {'name': 'MVP選手', 'value': '受賞', 'status': 'active'}
          ]
        }
      ]
    }
  ],
  'season': [
    {
      'label': '本塁打',
      'unit': '本',
      'leaders': [
        {'name': '歴代選手', 'value': 60, 'status': 'retired'}
      ],
      'current': [
        {'name': '今季選手', 'value': 40, 'status': 'active'}
      ]
    }
  ],
  'career': [
    {
      'label': '安打',
      'unit': '安打',
      'leaders': [
        {'name': '引退選手', 'value': 3000, 'status': 'retired', 'combined': true},
        {'name': '現役選手', 'value': 2000, 'status': 'active'}
      ]
    }
  ],
  'streaks': [
    {
      'label': '連続安打（打席）',
      'unit': '打席',
      'leaders': [
        {'name': '歴代選手', 'value': 11, 'status': 'retired'}
      ],
      'current': [
        {'name': '今季選手', 'value': 5, 'status': 'active'}
      ],
      'current_note': '取得済み試合の確認範囲'
    }
  ],
};
void main() {
  test('championship intervals follow franchise IDs and selected year', () {
    Map<String,dynamic> season(int year,String name,{bool champion=false,int rank=2}) => {
      'year':year,'leagues':[{'teams':[{'id_team':1,'name':name,'rank':rank,'champion':champion}, {'id_team':2,'name':'未優勝','rank':3}]}]
    };
    final result=championshipIntervals([season(2026,'現球団'),season(2020,'前身球団',champion:true,rank:1),season(2028,'未来',champion:true,rank:1)],2026);
    expect(result.first['name'],'現球団');
    expect(result.first['league_years'],6);
    expect(result.first['champion_years'],6);
    expect(result.last['league_years'],isNull);
    expect(championshipIntervals([season(2026,'現球団',champion:true,rank:1)],2026).first['champion_years'],0);
    expect(championshipIntervals([season(2026,'現球団',rank:1)],2026,mlb:true).first['league_years'],isNull);
  });

  testWidgets('春季と秋季の順位・優勝球団を別行で表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payload = {'standings': [for (final phase in ['spring', 'fall']) {
      'year': 1937, 'phase': phase, 'phase_label': phase == 'spring' ? '春季' : '秋季',
      'leagues': [{'id_league': 1, 'name': '日本野球連盟', 'teams': [
        {'id_team': 1, 'name': phase == 'spring' ? '春優勝' : '秋優勝', 'rank': 1, 'champion': true},
        {'id_team': 2, 'name': '二位球団', 'rank': 2},
      ]}]
    }]};
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecordsBoard(org: OrgConfig.npb, year: 1937))));
      await tester.pumpAndSettle();
      for (final phase in ['spring', 'fall']) {
        final row = find.byKey(ValueKey('standings-year-1937-$phase'));
        expect(row, findsOneWidget);
        expect(find.descendant(of: row, matching: find.text(phase == 'spring' ? '春季' : '秋季')), findsOneWidget);
        expect(find.descendant(of: row, matching: find.text(phase == 'spring' ? '春優勝' : '秋優勝')), findsNWidgets(2));
      }
      await tester.tap(find.byKey(const ValueKey('standings-league-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('standings-year-1937-spring')), findsNothing);
      expect(find.byKey(const ValueKey('standings-year-1937-fall')), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response(jsonEncode(payload), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
  });
  for (final org in [OrgConfig.npb, OrgConfig.mlb]) {
    testWidgets('${org.label}優勝表はリーグを切り替えても日本一・WS優勝を維持する', (tester) async {
      final payload = {'standings': [
        {'year': 2025, 'leagues': [for (var i = 0; i < 2; i++) {
          'id_league': org.leagues[i].id, 'name': org.leagues[i].name,
          'teams': [{'name': '球団$i', 'short_name': '略称$i', 'champion': i == 1,
            'color_back': '#003366', 'color_font': '#ffffff'}],
        }]},
        if (org.kind == OrgKind.npb) {'year': 1949, 'leagues': [
          {'id_league': 1, 'name': '日本野球連盟', 'teams': [{'name': '昔の球団'}]},
        ]},
      ]};
      var requests = 0;
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecordsBoard(org: org, year: 2026))));
        await tester.pumpAndSettle();
        expect(find.text('略称0'), findsOneWidget);
        expect(find.text('略称1'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('standings-league-${org.leagues.first.id}')));
        await tester.pumpAndSettle();
        expect(find.text('リーグ'), findsNothing);
        expect(find.text('1位'), findsOneWidget);
        expect(find.text('リーグ優勝'), findsNothing);
        expect(find.text('略称0'), findsOneWidget);
        expect(tester.widget<Text>(find.text('略称0')).style!.color, Colors.black87);
        expect(tester.widgetList<Container>(find.ancestor(of: find.text('略称0'), matching: find.byType(Container)))
            .any((c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).color == Color.lerp(org.leagues.first.color, Colors.white, .88)), isTrue);
        expect(find.text('略称1'), findsNothing);
        expect(find.text('球団1'), findsOneWidget);
        expect(find.text('1949'), findsNothing);
        await tester.tap(find.byKey(ValueKey('standings-league-${org.leagues.last.id}')));
        await tester.pumpAndSettle();
        expect(find.text('略称0'), findsNothing);
        expect(find.text('球団1'), findsOneWidget);
        expect(find.text('略称1'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('standings-league-0')));
        await tester.pumpAndSettle();
        expect(find.text('略称0'), findsOneWidget);
        if (org.kind == OrgKind.npb) expect(find.text('1949'), findsOneWidget);
        expect(requests, 1);
        expect(tester.takeException(), isNull);
      }, () => MockClient((_) async {
        requests++;
        return http.Response(jsonEncode(payload), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }));
    });
  }
  testWidgets('優勝表は全年度を一括描画せず末尾まで往復スクロールできる', (tester) async {
    final history = {'standings': [for (var year = 2026; year >= 1936; year--) {
      'year': year, 'leagues': [{'name': 'パ・リーグ', 'teams': [
        {'name': '西武ライオンズ', 'champion': true,
          'logo_url': 'asset:backend/assets/images/history_seibu.jpg'},
      ]}],
    }]};
    var requests = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: RecordsBoard(org: OrgConfig.npb, year: 2026))));
      await tester.pumpAndSettle();
      final scroll = tester.stateList<ScrollableState>(find.byType(Scrollable))
          .singleWhere((s) => s.axisDirection == AxisDirection.down);
      expect(find.byType(Image).evaluate().length, lessThan(100));
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        final provider = image.image as ResizeImage;
        expect((provider.imageProvider as AssetImage).assetName,
            'backend/assets/images/thumb_history_seibu.jpg');
      }
      for (var n = 0; n < 3; n++) {
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('standings-year-1936')), findsOneWidget);
        scroll.position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('standings-year-2026')), findsOneWidget);
      }
      expect(requests, 1);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async {
      requests++;
      return http.Response(jsonEncode(history), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets('記録の全タブ・比較表示は幅$widthで収まる', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var requests = 0;
      final client = MockClient((r) async {
        requests++;
        return http.Response(jsonEncode(fixture), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
            home:
                Scaffold(body: RecordsBoard(org: OrgConfig.npb, year: 2026))));
        await tester.pumpAndSettle();
        expect(recordTabs, ['優勝チーム', '個人タイトル', 'シーズン記録', '通算記録', '連続記録', '功績']);
        expect(find.text('日本一'), findsOneWidget);
        expect(find.text('1位'), findsOneWidget);
        expect(find.text('優勝略称'), findsOneWidget);
        expect(find.text('優勝球団'), findsNWidgets(2));
        expect(find.text('最後のリーグ優勝から'), findsOneWidget);
        expect(find.text('最後の日本一から'), findsOneWidget);
        expect(find.text('1年'), findsNWidgets(2));
        final horizontal = tester.stateList<ScrollableState>(find.byType(Scrollable))
            .where((state) => state.axisDirection == AxisDirection.right).first;
        expect(horizontal.position.maxScrollExtent, width < 600 ? greaterThan(0) : 0);
        final championCell = tester.widgetList<Container>(find.byType(Container)).where((c) =>
          c.decoration is BoxDecoration && (c.decoration as BoxDecoration).color == const Color(0xFFFF0000));
        expect(championCell.length, 1);
        final leagueBackground = Color.lerp(OrgConfig.npb.leagues.first.color, Colors.white, .88);
        final rankCells = tester.widgetList<Container>(find.byType(Container)).where((c) =>
          c.decoration is BoxDecoration && (c.decoration as BoxDecoration).color == leagueBackground);
        expect(rankCells.length, 6);
        expect(championCell.single.constraints!.minWidth, greaterThanOrEqualTo(240));
        expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('standings-year-2025')), matching: find.text('優勝球団'))).maxLines, 1);
        expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('standings-year-2025')), matching: find.text('優勝球団'))).style!.color, Colors.white);
        expect(find.textContaining('90勝'), findsNothing);
        expect(find.textContaining('PS進出'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('records-tab-1')));
        await tester.pumpAndSettle();
        expect(find.text('タイトル選手'), findsOneWidget);
        expect(find.text('同率選手'), findsOneWidget);
        expect(find.textContaining('区分未確認'), findsNothing);
        expect(find.textContaining('現在の首位'), findsNothing);
        expect(find.text('2025年'), findsOneWidget);
        expect(tester.widget<Text>(find.text('2025年')).style!.color, Colors.white);
        expect(tester.widget<Text>(find.text('タイトル選手')).style!.color, Colors.black);
        expect(tester.widget<Text>(find.text('所属球団')).style!.color, Colors.white);
        expect(find.text('受賞'), findsNothing);
        expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').contains('受賞')), findsNothing);
        expect(tester.widgetList<Container>(find.byType(Container)).where((c) => c.color == const Color(0xFF003300)), hasLength(1));
        expect(tester.getCenter(find.text('タイトル選手')).dy,
            tester.getCenter(find.text('同率選手')).dy);
        final tied = tester.getSize(find.byKey(const ValueKey('title-cell-0-本塁打王')));
        final single = tester.getSize(find.byKey(const ValueKey('title-cell-0-MVP')));
        expect(tied, single);
        expect(tied.height, 60);
        await tester.tap(find.byKey(const ValueKey('records-tab-2')));
        await tester.pumpAndSettle();
        expect(find.text('歴代選手'), findsOneWidget);
        expect(find.text('今季選手'), findsOneWidget);
        expect(tester.getCenter(find.text('歴代選手')).dy,
            lessThan(tester.getCenter(find.text('今季選手')).dy));
        final historicalBar = tester.getSize(find.byKey(const ValueKey('season-bar-本塁打-historical-0'))).width;
        final currentBar = tester.getSize(find.byKey(const ValueKey('season-bar-本塁打-current-0'))).width;
        expect(currentBar / historicalBar, closeTo(40 / 60, .001));
        expect(tester.getTopLeft(find.byKey(const ValueKey('season-bar-本塁打-historical-0'))).dx,
            tester.getTopLeft(find.byKey(const ValueKey('season-bar-本塁打-current-0'))).dx);
        await tester.tap(find.byKey(const ValueKey('records-tab-3')));
        await tester.pumpAndSettle();
        expect(find.text('日米通算'), findsOneWidget);
        expect(find.text('現役'), findsNothing);
        expect(find.text('引退'), findsNothing);
        final active = find
            .ancestor(of: find.text('現役選手'), matching: find.byType(Container))
            .first;
        final retired = find
            .ancestor(of: find.text('引退選手'), matching: find.byType(Container))
            .first;
        expect(tester.widget<Container>(active).color, const Color(0xFFFFF9C4));
        expect(tester.widget<Container>(retired).color, Colors.white);
        for (final label in ['順位', '安打']) {
          final header = find.text(label);
          expect(tester.widget<Text>(header).style!.color, Colors.white);
          final container = tester.widget<Container>(find.ancestor(of: header, matching: find.byType(Container)).first);
          expect((container.decoration as BoxDecoration).color, Colors.black);
        }
        await tester.tap(find.byKey(const ValueKey('records-tab-4')));
        await tester.pumpAndSettle();
        expect(find.text('歴代記録'), findsOneWidget);
        expect(find.text('今シーズン記録（2026年）'), findsOneWidget);
        expect(tester.getCenter(find.text('歴代選手')).dy,
            lessThan(tester.getCenter(find.text('今季選手')).dy));
        final streakHistorical = find.byKey(const ValueKey('streaks-bar-連続安打（打席）-historical-0'));
        final streakCurrent = find.byKey(const ValueKey('streaks-bar-連続安打（打席）-current-0'));
        expect(tester.getSize(streakCurrent).width / tester.getSize(streakHistorical).width,
            closeTo(5 / 11, .001));
        expect(tester.getTopLeft(streakCurrent).dx, tester.getTopLeft(streakHistorical).dx);
        expect(requests, 1);
        expect(tester.takeException(), isNull);
      }, () => client);
    });
  }
  testWidgets('NPB順位列は1958年6列・1957年9列、旧球団ロゴは同梱画像', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final history = {'standings': [for (final year in [1958,1957]) {
      'year': year, 'leagues': [{'name':'パ・リーグ', 'teams': [
        {'name':'南海ホークス','short_name':'南海','champion':true,
         'historical_identity':true,'logo_url':'asset:backend/assets/images/history_nankai.jpg'},
        for (var n=2;n<=9;n++) {'name':'球団$n','short_name':'球団$n'}
      ]}]
    }]};
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecordsBoard(org: OrgConfig.npb,year:2026))));
      await tester.pumpAndSettle();
      expect(find.text('6位'), findsNWidgets(2));
      expect(find.text('9位'), findsOneWidget);
      final modern = find.byKey(const ValueKey('standings-year-1958'));
      final older = find.byKey(const ValueKey('standings-year-1957'));
      expect(find.descendant(of:modern,matching:find.text('球団7')), findsNothing);
      expect(find.descendant(of:older,matching:find.text('球団9')), findsOneWidget);
      expect(tester.getSize(modern).width, 1200);
      expect(tester.getSize(older).width, 1200);
      expect(find.byType(Image), findsNWidgets(5));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.binding.setSurfaceSize(const Size(390, 800));
      await tester.pumpAndSettle();
      final horizontal = tester.stateList<ScrollableState>(find.byType(Scrollable))
          .where((state) => state.axisDirection == AxisDirection.right).toList();
      expect(horizontal, hasLength(1));
      expect(horizontal.single.position.maxScrollExtent, 0);
      expect(tester.getSize(modern).width, 390);
      expect(tester.getSize(older).width, 390);
      expect(tester.takeException(),isNull);
    }, () => MockClient((_) async => http.Response(jsonEncode(history),200,headers:{'content-type':'application/json; charset=utf-8'})));
  });
  for (final org in [OrgConfig.npb, OrgConfig.mlb]) {
    testWidgets('${org.label}タイトルは同年の両リーグを各タイトルの下に表示', (tester) async {
      final payload = {'titles': [for (var i=0;i<2;i++) {
        'year':2025,'league':org.leagues[i].name,
        'categories':[{'label':'本塁打王','players':[{'name':'選手$i','value':40}]}]
      }]};
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecordsBoard(org:org,year:2026))));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('records-tab-1')));
        await tester.pumpAndSettle();
        expect(find.text('2025年'), findsOneWidget);
        expect(tester.widget<Text>(find.text('2025年')).style!.color, Colors.white);

        expect(find.text(org.kind == OrgKind.npb ? 'セ' : 'ア'), findsOneWidget);
        expect(find.text(org.kind == OrgKind.npb ? 'パ' : 'ナ'), findsOneWidget);
        expect(tester.getCenter(find.text('選手0')).dy, tester.getCenter(find.text('選手1')).dy);
        expect(tester.getCenter(find.text('選手0')).dx, lessThan(tester.getCenter(find.text('選手1')).dx));
        final bothWidth = tester.getSize(find.byKey(const ValueKey('title-cell-0-本塁打王'))).width;
        await tester.tap(find.byKey(ValueKey('titles-league-${org.leagues.first.id}')));
        await tester.pumpAndSettle();
        expect(find.text('選手0'), findsOneWidget);
        expect(find.text('選手1'), findsNothing);
        expect(tester.getSize(find.byKey(const ValueKey('title-cell-0-本塁打王'))).width, bothWidth / 2);
        await tester.tap(find.byKey(ValueKey('titles-league-${org.leagues.last.id}')));
        await tester.pumpAndSettle();
        expect(find.text('選手0'), findsNothing);
        expect(find.text('選手1'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('titles-league-0')));
        await tester.pumpAndSettle();
        expect(find.text('選手0'), findsOneWidget);
        expect(find.text('選手1'), findsOneWidget);
        expect(tester.takeException(),isNull);
      }, () => MockClient((_) async => http.Response(jsonEncode(payload),200,headers:{'content-type':'application/json; charset=utf-8'})));
    });
  }
  for (final org in [OrgConfig.npb, OrgConfig.mlb]) {
    testWidgets('${org.label}通算記録は50位まで表示し同率順位の行を縦結合', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final payload = {'career': [
        {'label':'安打','unit':'安打','leaders':[
          {'name':'安打首位','rank':1,'value':3000,'status':'retired'},
          {'name':'同率A','rank':2,'value':2500,'status':'active'},
          {'name':'同率B','rank':2,'value':2500,'status':'retired'}]},
        {'label':'本塁打','unit':'本','leaders':[
          {'name':'本塁打首位','rank':1,'value':600,'status':'retired'}]},
        {'label':'勝利','unit':'勝','leaders':[]},
      ]};
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecordsBoard(org:org,year:2026))));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('records-tab-3')));
        await tester.pumpAndSettle();
        expect(tester.getCenter(find.text('安打首位')).dy, tester.getCenter(find.text('本塁打首位')).dy);
        expect(tester.getCenter(find.text('安打')).dx, lessThan(tester.getCenter(find.text('本塁打')).dx));
        expect(tester.getCenter(find.text('同率A')).dy, lessThan(tester.getCenter(find.text('同率B')).dy));
        expect(tester.getSize(find.byKey(const ValueKey('career-cell-0-2'))).height,
            tester.getSize(find.byKey(const ValueKey('career-cell-1-2'))).height * 2);
        expect(find.byKey(const ValueKey('career-cell-0-3')), findsNothing);
        expect(find.text('50位'), findsOneWidget);
        final scroll = tester.stateList<ScrollableState>(find.byType(Scrollable))
          .firstWhere((s) => s.axisDirection == AxisDirection.right);
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        expect(tester.takeException(),isNull);
      }, () => MockClient((_) async => http.Response(jsonEncode(payload),200,headers:{'content-type':'application/json; charset=utf-8'})));
    });
  }
  testWidgets('順位セルはホバーでは強調せずクリックだけで同一球団を強調する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200,800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payload = {'standings': [for (final year in [2005,2004]) {
      'year':year,'leagues':[{'id_league':2,'name':'パ・リーグ','teams':[
        {'id_team':7,'name':year==2005?'ソフトバンク':'ダイエー','historical_identity':true,'color_back':'#123456','color_font':'#FEDCBA'},
        {'id_team':8,'name':'他球団','historical_identity':true}
      ]}]
    }]};
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecordsBoard(org:OrgConfig.npb,year:2026))));
      await tester.pumpAndSettle();
      final current = find.byKey(const ValueKey('rank-team-2005-id:7'));
      final old = find.byKey(const ValueKey('rank-team-2004-id:7'));
      bool highlighted(Finder f) => tester.widgetList<Container>(find.descendant(of:f,matching:find.byType(Container)))
        .any((c) => c.decoration is BoxDecoration &&
          (c.decoration as BoxDecoration).color == const Color(0xFF123456));
      Color? background(Finder f) => tester.widgetList<Container>(find.descendant(of:f,matching:find.byType(Container)))
        .where((c) => c.decoration is BoxDecoration).map((c) => (c.decoration as BoxDecoration).color).first;
      final originalBackground = background(old);
      final mouse = await tester.createGesture(kind:PointerDeviceKind.mouse);
      await mouse.addPointer(location:Offset.zero);
      await mouse.moveTo(tester.getCenter(current));
      await tester.pump();
      expect(highlighted(current),isFalse);
      expect(highlighted(old),isFalse);
      expect(highlighted(find.byKey(const ValueKey('rank-team-2004-id:8'))),isFalse);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(highlighted(old),isFalse);
      await tester.tap(current);
      await tester.pump();
      expect(highlighted(old),isTrue);
      expect(highlighted(current),isTrue);
      expect(background(old), const Color(0xFF123456));
      expect(tester.widget<Text>(find.text('ダイエー')).style!.color, const Color(0xFFFEDCBA));
      expect(tester.widgetList<Container>(find.descendant(of: old, matching: find.byType(Container)))
        .every((c) => c.foregroundDecoration == null), isTrue);
      expect(highlighted(find.byKey(const ValueKey('rank-team-2004-id:8'))),isFalse);
      await tester.tap(current);
      await tester.pump();
      expect(highlighted(old),isFalse);
      expect(background(old), originalBackground);
      await mouse.removePointer();
      expect(tester.takeException(),isNull);
    }, () => MockClient((_) async => http.Response(jsonEncode(payload),200,headers:{'content-type':'application/json; charset=utf-8'})));
  });
  testWidgets('記録の取得失敗は再読み込みできる', (tester) async {
    var count = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: RecordsBoard(org: OrgConfig.mlb, year: 2026))));
      await tester.pumpAndSettle();
      expect(find.text('再読み込み'), findsOneWidget);
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('WS優勝'), findsOneWidget);
    },
        () => MockClient((_) async => ++count == 1
            ? http.Response('error', 500)
            : http.Response(jsonEncode(fixture), 200,
                headers: {'content-type': 'application/json; charset=utf-8'})));
  });
  testWidgets('団体変更前の遅延応答が新しい表示を上書きしない', (tester) async {
    final first = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: RecordsBoard(org: OrgConfig.npb, year: 2026))));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: RecordsBoard(org: OrgConfig.mlb, year: 2025))));
      await tester.pumpAndSettle();
      first.complete(http.Response(jsonEncode({'standings': []}), 200));
      await tester.pumpAndSettle();
      expect(find.text('WS優勝'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((r) async => r.url.queryParameters['org'] == 'npb'
            ? first.future
            : http.Response(jsonEncode(fixture), 200,
                headers: {'content-type': 'application/json; charset=utf-8'})));
  });
}
