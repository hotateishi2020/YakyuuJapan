import 'package:Yakyuu_Japan/tools/home_data_cache.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/View/home_games_behind_board.dart';
import 'package:Yakyuu_Japan/View/season_schedule_board.dart';
import 'package:Yakyuu_Japan/View/EventCalendar.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/home_board.dart';

void main() {
  setUp(HomeDataCache.clear);
  setUp(HomeCalendarCache.clear);
  tearDown(HomeCalendarCache.clear);
  testWidgets('HOME取得前にニュースとカレンダーを表示し、再訪で読み直さない', (tester) async {
    final response = Completer<http.Response>();
    var homeReads = 0;
    await http.runWithClient(() async {
      Widget page() => const MaterialApp(home: Scaffold(body: HomeBoard(
        year: 2026, news: Text('先に表示するニュース'),
      )));
      await tester.pumpWidget(page());
      await tester.pump();
      expect(find.text('先に表示するニュース'), findsOneWidget);
      expect(find.byType(HomeSeasonCalendar), findsOneWidget);
      final calendar = tester.state(find.byType(HomeSeasonCalendar));
      response.complete(http.Response(jsonEncode({
        'today': '2026-10-28','games': [],'heroes': [],
        'birthdays': [{'name_player': '誕生日選手','name_team': '阪神','age': 25,'org': 'npb'}],
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'}));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(HomeSeasonCalendar)), same(calendar));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(homeReads, 1);
      await tester.tap(find.byTooltip('再読み込み').first);
      await tester.pumpAndSettle();
      expect(homeReads, 2);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((request) async {
      if (request.url.path == '/home') { homeReads++; return response.future; }
      return http.Response('{"games":[],"events":[]}',200,
        headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  testWidgets('活躍選手は画像の取得を待たずに表示する', (tester) async {
    AuthSession.instance.user = AuthUser.fromJson({'id': 1, 'flg_special': true});
    AuthSession.instance.token = 'test';
    addTearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
    final images = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeBoard())));
      await tester.pumpAndSettle();
      expect(find.textContaining('画像を待たない選手'), findsOneWidget);
      expect(find.text('4打数3安打'), findsOneWidget);
      images.complete(http.Response('{"images":{}}', 200));
      await tester.pumpAndSettle();
      expect(find.text('4打数3安打'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((request) async {
      if (request.url.path == '/home') {
        if (request.url.queryParameters['section'] == 'images') return images.future;
        return http.Response(jsonEncode({
          'today': '2026-10-28','birthdays': [],
          'games': [{'id_game': 1,'org': 'NPB','date_game': '2026-10-28','state': '試合終了','name_team_home': '阪神','name_team_away': '巨人','score_home': 2,'score_away': 0}],
          'heroes': [{'id_game': 1,'org': 'NPB','id_player': 10,'name_player': '画像を待たない選手','name_team': '阪神','appearance_stats': ['4打数3安打']}],
        }),200,headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{"games":[],"events":[]}',200);
    }));
  });
  testWidgets('HOME表示で前回既読日時を保持し、認証ユーザーの日時を一度だけ更新する', (tester) async {
    final session = AuthSession.instance;
    session.user = AuthUser.fromJson({'id': 1, 'date_read_news': '2026-10-25T00:00:00Z'});
    session.token = 'test-session';
    addTearDown(() { session.user = null; session.token = null; });
    var writes = 0;
    DateTime? baseline;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeBoard(onNewsViewed: (id, previous) {
        expect(id, 1); baseline = previous;
      }))));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(baseline, DateTime.utc(2026,10,25));
      expect(session.user!.dateReadNews, DateTime.utc(2026,10,27));
      await tester.pump();
      expect(writes, 1);
    }, () => MockClient((request) async {
      if (request.url.path == '/auth/mark-read') {
        writes++;
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer test-session');
        expect(jsonDecode(request.body), {'target': 'news'});
        return http.Response(jsonEncode({'ok': true, 'user': {'id': 1, 'date_read_news': '2026-10-27T00:00:00Z'}}), 200);
      }
      return http.Response(jsonEncode({'today': '2026-10-27', 'games': [], 'heroes': [], 'events': [], 'stats_team': []}), 200);
    }));
  });

  testWidgets('終了試合の生成画像と成績を表示し未終了の試合を含めない', (tester) async {
    final session = AuthSession.instance;
    session.user = AuthUser.fromJson({'id': 1});
    session.token = 'test-session';
    addTearDown(() { session.user = null; session.token = null; });
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeBoard())));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-hero-game-NPB-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-hero-game-NPB-2')), findsNothing);
      expect(find.text('7回 0失点（自責点0） 10奪三振'), findsOneWidget);
      expect(find.text('勝利投手'), findsOneWidget);
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images.any((image) => image.semanticLabel == '投手の生成画像' &&
        image.image is NetworkImage && (image.image as NetworkImage).url.endsWith('/player-art/test.png')), isTrue);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async {
      if (request.url.path == '/auth/mark-read') return http.Response('{}', 401);
      return http.Response(jsonEncode({
        'today': '2026-10-27', 'events': [], 'stats_team': [],
        'games': [
          {'id_game': 1, 'org': 'NPB', 'date_game': '2026-10-27', 'state': '試合終了'},
          {'id_game': 2, 'org': 'NPB', 'date_game': '2026-10-27', 'state': '5回表'},
        ],
        'heroes': [{'id_game': 1, 'org': 'NPB', 'id_player': 1, 'name_player': '投手',
          'name_team': '球団', 'character_image': {'url': '/player-art/test.png'},
          'appearance_stats': ['7回 0失点（自責点0） 10奪三振'], 'highlights': ['勝利投手']}],
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });

  testWidgets('誕生日の選手はゲストにも表示し、狭い画面でも折り返す', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeBoard())));
      await tester.pumpAndSettle();
      expect(find.text('今日誕生日の選手'), findsOneWidget);
      expect(find.text('対象選手（阪神）  25歳'), findsOneWidget);
      expect(find.text('MLB選手（LAD）  30歳'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async => http.Response(jsonEncode({
      'today': '2026-10-27', 'games': [], 'heroes': [], 'events': [], 'stats_team': [],
      'birthdays': [
        {'id_player': 10, 'name_player': '対象選手', 'name_team': '阪神', 'org': 'npb', 'age': 25},
        {'id_player': 20, 'name_player': 'MLB選手', 'name_team': 'LAD', 'org': 'mlb', 'age': 30},
      ],
    }), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
  });

  testWidgets('HOME順位はセ・パ横並び、MLBはア3地区・ナ3地区の2段', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      for (final size in [const Size(1400, 800), const Size(900, 1200), const Size(375, 750), const Size(320, 640), const Size(1400, 800)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
          SingleChildScrollView(child: Column(children: [HomeStandingsBoard(year: 2026), HomeStandingsBoard(year: 2026, org: OrgConfig.mlb)])))));
        await tester.pumpAndSettle();
        final panels = find.byType(SeasonTableBlock);
        expect(panels, findsNWidgets(8));
        expect(find.byType(GamesBehindChart), findsNWidgets(8));
        expect(find.text('ワイルドカード順位'), findsNothing);
        final portrait = size.height > size.width;
        expect(find.byKey(const Key('standings-gb-beside')),
            portrait ? findsNothing : findsNWidgets(8));
        for (final panel in panels.evaluate()) {
          final scope = find.byWidget(panel.widget);
          expect((panel.widget as SeasonTableBlock).useFullStandingsTeamNames, isTrue);
          if ((panel.widget as SeasonTableBlock).org.kind == OrgKind.npb &&
              (panel.widget as SeasonTableBlock).onlyLeagueId == 1) {
            expect(find.descendant(of: scope, matching: find.text('巨人')), findsNWidgets(6));
          }
          if ((panel.widget as SeasonTableBlock).org.kind == OrgKind.mlb) {
            expect(find.descendant(of: scope,
                matching: find.text('ロサンゼルス・ドジャース')), findsNWidgets(5));
          }
          final chart = tester.getRect(find.descendant(of: scope, matching: find.byType(GamesBehindChart)));
          expect(chart.height, closeTo(200, .01));
          final header = tester.getRect(find.descendant(of: scope,
              matching: find.byKey(const ValueKey('standings-team-name-header'))));
          if (portrait) {
            expect(chart.top, greaterThanOrEqualTo(header.bottom + 40));
            final rank = tester.getRect(find.ancestor(of: find.descendant(of: scope, matching: find.text('順位')), matching: find.byType(SizedBox)).first);
            expect(chart.left, closeTo(rank.left, .01));
            expect(chart.right, closeTo(header.right, .01));
          } else {
            expect(chart.left, greaterThanOrEqualTo(header.right));
            final row = tester.widget<Row>(find.descendant(of: scope,
              matching: find.byKey(const Key('standings-gb-beside'))));
            final table = tester.getRect(find.byWidget(row.children.first));
            expect(table.top, closeTo(chart.top, .01));
            expect(table.bottom, closeTo(chart.bottom, .01));
          }
        }
        final nameHeaders = find.byKey(const ValueKey('standings-team-name-header'));
        expect(nameHeaders, findsNWidgets(8));
        final nameWidths = [for (final element in nameHeaders.evaluate())
          tester.getSize(find.byWidget(element.widget)).width];
        for (var i = 0; i < nameWidths.length; i++) {
          expect(nameWidths[i], closeTo(nameWidths[portrait && i >= 2 ? 2 : 0], .01));
        }

        final rects = [for (final panel in panels.evaluate()) tester.getRect(find.byWidget(panel.widget))];
        for (final indices in [[0,1],[2,3,4],[5,6,7]]) {
          for (final i in indices.skip(1)) {
            expect(rects[i].top,closeTo(rects[indices.first].top,.01));
            expect(rects[i].left,greaterThanOrEqualTo(rects[i-1].right));
          }
        }
        for (final rect in rects) {
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width + .01));
        }
        for (final board in find.byType(HomeStandingsBoard).evaluate()) {
          expect(find.descendant(of: find.byWidget(board.widget), matching:
            find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right)), findsNothing);
        }
        expect(rects[5].top,greaterThanOrEqualTo(rects[2].bottom));
        expect(rects[5].left,closeTo(rects[2].left,.01));
        expect(tester.takeException(), isNull);
      }
    }, () => MockClient((request) async {
      final mlb = request.url.queryParameters['org'] == 'mlb';
      return http.Response(jsonEncode({'stats_team': [
        for (final league in mlb ? [3, 4] : [1, 2])
          for (final area in mlb ? ['EAST', 'CENTER', 'WEST'] : [''])
            for (var rank = 1; rank <= (mlb ? 5 : 6); rank++)
              {'id_league':league,'code_area':area,'int_rank':rank,'name_team':league==1?'巨人':'ロサンゼルス・ドジャース','name_shortest':league==1?'巨':'LAD','game_behind':rank==1?'-':'${rank * (area == 'EAST' ? .5 : 3.5)}'},
      ]}), 200, headers: {'content-type':'application/json; charset=utf-8'});
    }));
  });

  testWidgets('週間カレンダーは前後に移動でき年をまたぐ週も両年を取得する', (tester) async {
    final requests = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        HomeSeasonCalendar(year: 2026, weekStart: DateTime(2026, 12, 20), weekCount: 2))));
      await tester.pumpAndSettle();
      DateTime? week() => tester.widget<EventCalendar>(find.byType(EventCalendar)).weekStart;
      expect(tester.widget<EventCalendar>(find.byType(EventCalendar)).weekCount, 2);
      expect(requests, containsAll(['npb:2027', 'mlb:2027']));
      await tester.tap(find.byTooltip('次の週'));
      await tester.pumpAndSettle();
      expect(week(), DateTime(2026, 12, 27));
      expect(requests, containsAll(['npb:2026', 'mlb:2026', 'npb:2027', 'mlb:2027']));
      final calendar = tester.widget<EventCalendar>(find.byType(EventCalendar));
      expect(calendar.events.map((e) => e['title_event']), containsAll(['2026イベント', '2027イベント']));
      await tester.tap(find.byTooltip('次の週'));
      await tester.pumpAndSettle();
      expect(week(), DateTime(2027, 1, 3));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('前の週'));
        await tester.pumpAndSettle();
      }
      expect(week(), DateTime(2026, 12, 13));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      final year = request.url.queryParameters['year'];
      requests.add('${request.url.queryParameters['org']}:$year');
      return http.Response(jsonEncode({'games': [], 'events': [
        {'title_event': '$yearイベント', 'date_from_temp': '$year-12-31', 'date_to': '$year-12-31'}
      ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });

  testWidgets("終了した今日の試合がなければTODAY'S HEROを表示しない", (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeBoard())));
      await tester.pump();
      expect(find.textContaining('（日本時間）'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text("TODAY'S HERO — 今日の試合"), findsNothing);
      expect(find.text('今日誕生日の選手はいません。'), findsOneWidget);
      expect(find.text('勝利チームの活躍選手'), findsNothing);
      expect(find.text('今日の試合は登録されていません。'), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async => http.Response(jsonEncode({
      'today': '2026-10-23',
      'games': [
        {'date_game': '2026-10-24', 'id_game': 2, 'org': 'NPB', 'state': '試合終了'},
        {'date_game': '2026-10-23', 'id_game': 3, 'org': 'NPB', 'state': '5回表'},
        {'date_game': '2026-10-23', 'id_game': 4, 'org': 'NPB', 'state': '試合前'},
        {'date_game': '2026-10-23', 'id_game': 5, 'org': 'NPB', 'state': '中止'},
      ],
      'heroes': [], 'events': [], 'stats_team': [],
    }), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
  });

  testWidgets('HOMEカレンダーは両団体の日程をまとめ年送りで両方更新する', (tester) async {
    final requests = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home:Scaffold(body: HomeSeasonCalendar(year:2026))));
      await tester.pumpAndSettle();
      var calendar = tester.widget<EventCalendar>(find.byType(EventCalendar));
      expect(calendar.games.map((g) => g['org']), containsAll(['npb','mlb']));
      expect(calendar.events, hasLength(1));
      calendar.onMonthChanged!(DateTime(2027,1));
      await tester.pumpAndSettle();
      calendar = tester.widget<EventCalendar>(find.byType(EventCalendar));
      expect(requests, containsAll(['npb:2026','mlb:2026','npb:2027','mlb:2027']));
      expect(calendar.games.every((g) => g['date_game'] == '2027-04-01'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      final org = request.url.queryParameters['org'];
      final year = request.url.queryParameters['year'];
      requests.add('$org:$year');
      return http.Response(jsonEncode({
        'games':[{'org':org, 'date_game':'$year-04-01', 'name_team_home':'ホーム', 'name_team_away':'ビジター'}],
        'events':[{'title_event':'共通イベント','date_from_temp':'$year-04-01','date_to':'$year-04-01'}],
      }),200,headers:{'content-type':'application/json; charset=utf-8'});
    }));
  });

  testWidgets('HOMEを狭い画面で表示し、日程と対戦と活躍選手と首位を表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 750));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeBoard())));
      await tester.pump();
      expect(find.textContaining('（日本時間）'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('NPB 公式サイト'), findsNothing);
      expect(find.text('MLB 公式サイト'), findsNothing);
      expect(find.text('高校野球 公式サイト'), findsNothing);
      expect(find.text('テストの野球記事タイトル'), findsNothing);
      expect(find.text('野球ニュース'), findsNothing);
      expect(find.text("TODAY'S HERO — 今日の試合"), findsOneWidget);
      expect(find.text('勝利チームの活躍選手'), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('home-hero-game-NPB-1')),
          matching: find.text('NPB  阪神  活躍選手')), findsOneWidget);
      expect(find.text('NPB  阪神  活躍選手'), findsOneWidget);
      expect(find.text('4打数3安打 2打点'), findsOneWidget);
      expect(find.text('猛打賞'), findsOneWidget);
      expect(find.text('1本塁打'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('今週・翌週のカレンダー（NPB・MLB）'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('今週・翌週のカレンダー（NPB・MLB）'), findsOneWidget);
      expect(tester.widget<EventCalendar>(find.byType(EventCalendar)).weekStart, DateTime(2026,10,18));
      expect(tester.widget<EventCalendar>(find.byType(EventCalendar)).weekCount, 2);
      expect(find.text('31'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('1ヶ月分の日程を見る'), 150, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('1ヶ月分の日程を見る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1ヶ月分の日程を見る'));
      await tester.pumpAndSettle();
      final dialogCalendar = find.descendant(of: find.byType(Dialog), matching:find.byType(EventCalendar));
      expect(tester.widget<EventCalendar>(dialogCalendar).weekStart, isNull);
      expect(find.text('1ヶ月分の日程'), findsOneWidget);
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.scrollUntilVisible(find.text('順位・ゲーム差'), 250, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(HomeStandingsBoard).first, matching: find.byType(GamesBehindChart)), findsNWidgets(2));
      expect(find.text('立'), findsNothing);
      expect(find.text('江'), findsNothing);
      expect(find.text('得点率'), findsNothing);
      expect(find.text('順位'), findsWidgets);
      for (final board in find.byType(HomeGamesBehindBoard).evaluate()) {
        final scope = find.byWidget(board.widget);
        expect(find.descendant(of: scope, matching: find.text('チーム')), findsWidgets);
        for (final title in ['試合', '勝率', '打率', '救援', '得点率']) {
          expect(find.descendant(of: scope, matching: find.text(title)), findsNothing);
        }
      }

      for (final row in tester.widgetList<Row>(find.byKey(const Key('standings-gb-beside')))) {
        final table = find.byWidget(row.children.first);
        final chart = find.descendant(of: find.byWidget(row), matching: find.byType(GamesBehindChart));
        expect(tester.getTopRight(table).dx, lessThanOrEqualTo(tester.getTopLeft(chart).dx));
      }

      for (final board in tester.widgetList<HomeGamesBehindBoard>(find.byType(HomeGamesBehindBoard))) {
        final charts = find.descendant(of: find.byWidget(board), matching: find.byType(GamesBehindChart));
        expect(charts, findsNWidgets(board.org.kind.name == 'npb' ? 2 : 6));
        for (final chart in tester.widgetList<GamesBehindChart>(charts)) {
          expect(chart.rows, hasLength(2));
          expect(chart.rows.map((r) => r['id_league']).toSet(), hasLength(1));
          expect(chart.rows.map((r) => r['code_area']).toSet(), hasLength(1));
        }

      }
      await tester.scrollUntilVisible(find.text('個人タイトル').first, 250, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('titles-grid-statistical')), findsOneWidget);
      expect(find.byKey(const ValueKey('mlb-titles-grid-major')), findsOneWidget);
      final mlbStandings = find.byWidgetPredicate((w) => w is HomeStandingsBoard && w.org.kind == OrgKind.mlb);
      expect(mlbStandings,findsOneWidget);
      expect(tester.getBottomLeft(mlbStandings).dy,lessThanOrEqualTo(tester.getTopLeft(find.byKey(const ValueKey('mlb-titles-grid-major'))).dy));
      List<double> columnWidths(String key) {
        final row = tester.widget<Row>(find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.byType(Row)).first);
        return row.children.map((cell) => tester.getSize(find.byWidget(cell)).width).toList();
      }
      final npbWidths = columnWidths('titles-grid-statistical');
      final mlbWidths = columnWidths('mlb-titles-grid-major');
      expect(npbWidths, hasLength(3));
      expect(mlbWidths, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(mlbWidths[i], closeTo(npbWidths[i], .01));
      }

      expect(find.byKey(const ValueKey('titles-grid-series')), findsNothing);
      expect(find.textContaining('首位打者'), findsWidgets);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async {
      if (request.url.path == '/predictions/part') {
        expect(request.url.queryParameters['part'], 'standings');
        expect(request.url.queryParameters['year'], '2026');
        final mlb = request.url.queryParameters['org'] == 'mlb';
        return http.Response(jsonEncode({'stats_team': [
          for (final league in mlb ? [3, 4] : [1, 2])
            for (final area in mlb ? ['EAST', 'CENTER', 'WEST'] : [''])
              for (var rank = 1; rank <= 2; rank++)
                {'id_league': league, 'code_area': area, 'int_rank': rank,
                 'name_team': '球団$league-$area-$rank', 'game_behind': rank == 1 ? '-' : '2.5'},
        ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (request.url.path == '/season-schedule') return http.Response(jsonEncode({'games':[], 'events':[]}), 200);
      if (request.url.path == '/records') return http.Response(jsonEncode({'season_awards':{'pages':{}}}), 200);
      expect(request.url.path, '/home');
      return http.Response(jsonEncode({
        'today':'2026-10-23', 'notification':[], 'events':[],
        'articles':[{'title':'テストの野球記事タイトル', 'url':'https://news.yahoo.co.jp/articles/test', 'category':'NPB', 'source':'Yahoo!ニュース'}],
        'games':[{'id_game':1,'date_game':'2026-10-23','org':'NPB','name_team_home':'阪神','name_team_away':'巨人','score_home':3,'score_away':1,'state':'試合終了'}],
        'heroes':[{'id_game':1,'id_player':1,'name_player':'活躍選手','name_team':'阪神','org':'NPB','appearance_stats':['4打数3安打 2打点'],'highlights':['1本塁打','猛打賞'],'character_image':{'url':'/player-art/test.png'}}],
        'leaders':[{'id_league':1,'title':'打率','name_player':'首位打者','name_team':'阪神','stats':'.330'}],
      }),200,headers:{'content-type':'application/json; charset=utf-8'});
    }));
  });
}
