import 'dart:convert';
import 'dart:async';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:Yakyuu_Japan/View/videos_board.dart';
import 'package:Yakyuu_Japan/pages/prediction_page.dart';

class _Launcher extends UrlLauncherPlatform {
  final urls = <String>[];
  @override
  Null get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return true;
  }
}

String channelId(int i) => 'UC${i.toString().padLeft(22, '0')}';
String videoId(int i) => 'v${i.toString().padLeft(10, '0')}';
List<Map<String, dynamic>> videos(int start, int count, String title) => [
      for (var i = 0; i < count; i++)
        {
          'id': videoId(start + i),
          'title': '$title$i',
          'thumbnail_url':
              'https://i.ytimg.com/vi/${videoId(start + i)}/hqdefault.jpg',
          'published_at': '2026-10-18T00:00:00Z',
          'source_name': i.isEven ? '球団公式' : '関連チャンネル'
        },
    ];
Map<String, dynamic> data() => {
      'channels': [
        {
          'id': channelId(1),
          'name': 'パ・リーグTV',
          'lookback_days': 2,
          'minimum_videos': 10,
          'category': 'league',
          'status': 'ok',
          'display_mode': 'recent',
          'videos': videos(0, 7, 'パ動画')
        },
        {
          'id': channelId(2),
          'name': '上原浩治の雑談魂',
          'tab_label': '上原浩治',
          'category': 'ob',
          'status': 'ok',
          'videos': videos(100, 8, '上原動画')
        },
        {
          'id': channelId(3),
          'name': 'Satozaki Channel',
          'tab_label': '里崎智也',
          'category': 'ob',
          'status': 'stale',
          'display_mode': 'recent',
          'fetched_at': '2026-10-17T00:00:00Z',
          'videos': videos(200, 7, '里崎動画')
        },
        for (var i = 0; i < 12; i++)
          {
            'id': channelId(10 + i),
            'name': '球団$i公式チャンネル',
            'tab_label': '球団$i',
            'league': i < 6 ? 'central' : 'pacific',
            'color': '#005BAC',
            'category': 'teams',
            'status': 'ok',
            'videos': videos(300 + i * 100, 32, '球団$i動画')
          },
        {
          'id': channelId(30),
          'name': 'Baseball inc.',
          'category': 'media',
          'status': 'ok',
          'fetched_at': '2026-10-18T03:00:00Z',
          'videos': videos(1600, 10, 'Baseball動画')
              .map((v) =>
                  {...v, 'published_at': null, 'published_label': '4 週間前'})
              .toList()
        },
        {
          'id': channelId(31),
          'name': 'MNsports',
          'category': 'media',
          'status': 'ok',
          'fetched_at': '2026-10-18T03:00:00Z',
          'videos': videos(1700, 10, 'MN動画')
              .map((v) =>
                  {...v, 'published_at': null, 'published_label': '23 時間前'})
              .toList()
        },
        {
          'id': channelId(32),
          'name': '追加解説チャンネル',
          'category': 'media',
          'status': 'ok',
          'videos': videos(1800, 10, '追加解説動画'),
        },
      ]
    };
http.Response jsonResponse(Object value) =>
    http.Response(jsonEncode(value), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 400,
      scrollable: find.byType(Scrollable).first, maxScrolls: 50);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('MLBの球団関連動画は有識者とは別の球団タブで切り替える', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payload = {'channels': [
      {'id': channelId(50), 'name': '武田一浩', 'category': 'ob', 'status': 'ok', 'videos': []},
      for (final entry in [('dodgers', 'ドジャース', 9000), ('yankees', 'ヤンキース', 9100)]) {
        'id': 'mlb-team-${entry.$1}', 'name': '${entry.$2}の関連動画',
        'tab_label': entry.$2, 'category': 'mlb_teams', 'display_mode': 'all',
        'status': 'ok', 'videos': videos(entry.$3, 6, '${entry.$2}解説'),
      },
    ]};
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VideosBoard(org: OrgKind.mlb))));
      await tester.pumpAndSettle();
      expect(find.text('球団関連動画'), findsOneWidget);
      expect(find.text('ドジャース解説0'), findsOneWidget);
      expect(find.byKey(ValueKey('video-${videoId(9005)}')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('videos-tab-mlb-team-yankees')));
      await tester.pumpAndSettle();
      expect(find.text('ヤンキース解説0'), findsOneWidget);
      expect(find.text('ドジャース解説0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((_) async => jsonResponse(payload)));
  });

  testWidgets('MLBにも有識者ALLと武田一浩のコンパクトなタブを表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final names = ['武田一浩', '五十嵐亮太', '上原浩治', '里崎智也', '古田敦也'];
    final payload = {'channels': [for (var i=0;i<names.length;i++) {
      'id': channelId(i+50), 'name': names[i], 'tab_label': names[i],
      'category': 'ob', 'status': 'ok', 'videos': videos(8000+i, 1, names[i]),
    }]};
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VideosBoard(org: OrgKind.mlb))));
      await tester.pumpAndSettle();
      expect(find.text('有識者'), findsOneWidget);
      final all = find.byKey(const ValueKey('videos-tab-ob-all'));
      final takeda = find.byKey(ValueKey('videos-tab-${channelId(50)}'));
      final furuta = find.byKey(ValueKey('videos-tab-${channelId(54)}'));
      expect(tester.getSize(all).width, lessThan(50));
      expect(tester.getSize(takeda).width, lessThan(80));
      expect(tester.getTopLeft(all).dy, tester.getTopLeft(furuta).dy);
      expect(tester.getBottomRight(furuta).dx, lessThanOrEqualTo(390));
      await tester.tap(takeda);
      await tester.pumpAndSettle();
      expect(find.text('武田一浩0'), findsOneWidget);
      expect(find.text('上原浩治0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((_) async => jsonResponse(payload)));
  });

  testWidgets('MLB側でも分類済みMNsportsを野球系解説欄に表示する', (tester) async {
    final payload = {'channels': [{
      'id': 'UCgxdkQmUjKLWjh058Pl4dAQ', 'name': 'MNsports',
      'category': 'media', 'status': 'ok',
      'videos': videos(9900, 2, 'ドジャース解説'),
    }]};
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: VideosBoard(org: OrgKind.mlb))));
      await tester.pumpAndSettle();
      expect(find.text('野球系解説チャンネル'), findsOneWidget);
      expect(find.text('ドジャース解説0'), findsOneWidget);
      expect(find.text('12球団の動画'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((_) async => jsonResponse(payload)));
  });

  testWidgets('server progress is shown while polling cached data then disappears', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return jsonResponse({...data(), 'progress': {
        'active': calls == 1, 'percent': calls == 1 ? 50 : 100,
      }});
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VideosBoard())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('50%'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsNothing);
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox());
    }, () => client);
  });

  late _Launcher launcher;
  setUp(() {
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
  });
  for (final size in [
    const Size(320, 900),
    const Size(390, 900),
    const Size(1200, 900)
  ]) {
    testWidgets('画面$sizeで件数と横1行・有識者と球団タブを切り替える', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var calls = 0;
      await http.runWithClient(() async {
        await tester
            .pumpWidget(const MaterialApp(home: Scaffold(body: VideosBoard())));
        await tester.pumpAndSettle();
        expect(find.textContaining('パ動画'), findsNWidgets(7));
        expect(find.text('当日〜2日前の動画（10件未満の場合は最新10件）'), findsOneWidget);
        expect(find.text('球団公式'), findsWidgets);
        expect(find.text('関連チャンネル'), findsWidgets);
        final first =
            tester.getRect(find.byKey(ValueKey('video-${videoId(0)}')));
        final second =
            tester.getRect(find.byKey(ValueKey('video-${videoId(1)}')));
        final third =
            tester.getRect(find.byKey(ValueKey('video-${videoId(2)}')));
        expect(second.top, first.top);
        expect(third.top, first.top);
        expect(third.left, greaterThan(second.left));
        final row = find.byKey(PageStorageKey('video-row-${channelId(1)}'));
        final last = find.byKey(ValueKey('video-${videoId(6)}'));
        final before = tester.getTopLeft(last).dx;
        await tester.drag(row, const Offset(-400, 0));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(last).dx, lessThan(before));
        final scroll = tester.state<ScrollableState>(
            find.descendant(of: row, matching: find.byType(Scrollable)));
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.getRect(last).right, lessThanOrEqualTo(size.width));
        scroll.position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('video-${videoId(0)}')));
        await tester.pumpAndSettle();
        expect(launcher.urls.single,
            'https://www.youtube.com/watch?v=${videoId(0)}');
        final list = tester.widget<ListView>(
            find.byKey(const PageStorageKey('video-channel-list')));
        final children =
            (list.childrenDelegate as SliverChildListDelegate).children;
        expect(children[1].key, const ValueKey('videos-section-ob'));
        expect(children[2].key, const ValueKey('videos-section-teams'));

        final expert = find.byKey(ValueKey('videos-tab-${channelId(3)}'));
        await show(tester, expert);
        expect(find.textContaining('上原動画'), findsNWidgets(4));
        expect(find.textContaining('里崎動画'), findsNWidgets(7));
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('videos-section-ob')),
                matching: find.text('ALL')),
            findsOneWidget);
        expect(find.text('各有識者の動画をすべて表示（新しい順・11件）'), findsOneWidget);
        expect(find.byTooltip('有識者の動画一覧をYouTubeで開く'), findsNothing);

        expect(find.descendant(of: expert, matching: find.text('里崎智也')),
            findsOneWidget);
        expect(
            find.descendant(
                of: expert, matching: find.text('Satozaki Channel')),
            findsNothing);
        await tester.tap(expert);
        await tester.pumpAndSettle();
        expect(find.textContaining('里崎動画'), findsNWidgets(7));
        expect(find.textContaining('上原動画'), findsNothing);
        expect(find.textContaining('前回取得分'), findsOneWidget);
        await tester.tap(find.byTooltip('Satozaki ChannelをYouTubeで開く'));
        await tester.pumpAndSettle();
        expect(launcher.urls.last,
            'https://www.youtube.com/channel/${channelId(3)}');

        final allExperts = find.byKey(const ValueKey('videos-tab-ob-all'));
        await show(tester, allExperts);
        await tester.tap(allExperts);
        await tester.pumpAndSettle();
        expect(find.textContaining('上原動画'), findsNWidgets(4));
        expect(find.textContaining('里崎動画'), findsNWidgets(7));
        final allRow = find.byKey(const PageStorageKey('video-row-ob-all'));
        expect(find.descendant(of: allRow, matching: find.text('上原浩治の雑談魂')),
            findsNWidgets(4));
        expect(
            find.descendant(
                of: allRow, matching: find.text('Satozaki Channel')),
            findsNWidgets(7));
        expect(calls, 1);

        final team = find.byKey(ValueKey('videos-tab-${channelId(11)}'));
        await show(tester, team);
        for (var i = 0; i < 12; i++) {
          expect(find.byKey(ValueKey('videos-tab-${channelId(10 + i)}')),
              findsOneWidget);
        }
        final firstTab = find.byKey(ValueKey('videos-tab-${channelId(10)}'));
        final lastCentral = find.byKey(ValueKey('videos-tab-${channelId(15)}'));
        final firstPacific =
            find.byKey(ValueKey('videos-tab-${channelId(16)}'));
        final lastPacific = find.byKey(ValueKey('videos-tab-${channelId(21)}'));
        expect(tester.getCenter(firstTab).dy, tester.getCenter(lastCentral).dy);
        expect(tester.getCenter(firstPacific).dy,
            tester.getCenter(lastPacific).dy);
        expect(tester.getCenter(firstPacific).dy,
            greaterThan(tester.getCenter(firstTab).dy));
        Color? tabColor(Finder tab) => tester
            .widget<Material>(
                find.ancestor(of: tab, matching: find.byType(Material)).first)
            .color;
        expect(tabColor(firstTab), const Color(0xFF005BAC));
        expect(tabColor(team),
            Color.lerp(const Color(0xFF005BAC), Colors.white, .88));
        expect(find.textContaining('球団0動画'), findsNWidgets(30));
        await tester.tap(team);
        await tester.pumpAndSettle();
        expect(tabColor(team), const Color(0xFF005BAC));
        expect(tabColor(firstTab),
            Color.lerp(const Color(0xFF005BAC), Colors.white, .88));
        expect(find.textContaining('球団1動画'), findsNWidgets(30));
        expect(find.textContaining('球団0動画'), findsNothing);
        await show(tester, find.text('野球系解説チャンネル'));
        expect(find.text('野球系解説チャンネル'), findsOneWidget);
        expect(find.textContaining('Baseball動画'), findsNWidgets(10));
        expect(find.textContaining('MN動画'), findsNWidgets(10));
        expect(find.textContaining('追加解説動画'), findsNWidgets(10));
        expect(find.text('各チャンネルの最新動画（新しい順・30件）'), findsOneWidget);
        expect(
            find.byKey(ValueKey('videos-tab-${channelId(30)}')), findsNothing);
        expect(
            find.byKey(ValueKey('videos-tab-${channelId(31)}')), findsNothing);
        expect(
            find.byKey(const ValueKey('videos-tab-media-all')), findsNothing);
        final mediaRow =
            find.byKey(const PageStorageKey('video-row-media-all'));
        final mnFirst = find.descendant(
            of: mediaRow,
            matching: find.byKey(ValueKey('video-${videoId(1700)}')));
        final baseballFirst = find.descendant(
            of: mediaRow,
            matching: find.byKey(ValueKey('video-${videoId(1600)}')));
        expect(tester.getTopLeft(mnFirst).dx,
            lessThan(tester.getTopLeft(baseballFirst).dx));

        expect(calls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
          () => MockClient((_) async {
                calls++;
                return jsonResponse(data());
              }));
    });
  }
  testWidgets('有識者が多くても一行で末尾まで横スクロールして選択できる', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final fixture = {
      'channels': [
        for (var i = 0; i < 15; i++)
          {
            'id': channelId(100 + i),
            'name': '有識者$i',
            'tab_label': '氏名$i',
            'category': 'ob',
            'status': 'ok',
            'videos': videos(2000 + i * 10, 1, '解説$i動画'),
          }
      ]
    };
    await http.runWithClient(() async {
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: VideosBoard())));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('videos-tab-ob-all'));
      final last = find.byKey(ValueKey('videos-tab-${channelId(114)}'));
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(last).dy);
      final row = find.byKey(const PageStorageKey('expert-segment-row'));
      final scroll = tester.state<ScrollableState>(
          find.descendant(of: row, matching: find.byType(Scrollable)));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(find.text('解説14動画0'), findsOneWidget);
      expect(find.text('解説0動画0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => jsonResponse(fixture)));
  });
  testWidgets('MLBは専用2チャンネルを一覧表示し遅れて届くNPB応答を破棄する', (tester) async {
    final npb = Completer<http.Response>();
    final requests = <Uri>[];
    final mlb = {
      'channels': [
        for (final entry in [(40, 'SPOTV NOW'), (41, 'MLB公式')])
          {
            'id': channelId(entry.$1),
            'name': entry.$2,
            'category': 'league',
            'status': 'ok',
            'display_mode': 'recent',
            'videos': videos(entry.$1 * 100, 2, entry.$2),
          }
      ]
    };
    await http.runWithClient(() async {
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: VideosBoard())));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: VideosBoard(org: OrgKind.mlb))));
      await tester.pumpAndSettle();
      expect(find.text('SPOTV NOW0'), findsOneWidget);
      expect(find.text('MLB公式0'), findsOneWidget);
      expect(find.text('12球団の動画'), findsNothing);
      expect(find.text('有識者'), findsNothing);
      npb.complete(jsonResponse(data()));
      await tester.pumpAndSettle();
      expect(find.text('パ動画0'), findsNothing);
      expect(find.text('SPOTV NOW0'), findsOneWidget);
      await tester.tap(find.byTooltip('動画を再読み込み'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters, {'org': 'mlb', 'refresh': '1', 'background': '1'});
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: VideosBoard())));
      await tester.pumpAndSettle();
      expect(find.text('パ動画0'), findsOneWidget);
      expect(find.text('SPOTV NOW0'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((r) {
              requests.add(r.url);
              return r.url.queryParameters['org'] == 'mlb'
                  ? Future.value(jsonResponse(mlb))
                  : npb.future;
            }));
  });
  testWidgets('取得失敗から再読み込みでき、10分後に更新する', (tester) async {
    var calls = 0;
    await http.runWithClient(() async {
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: VideosBoard())));
      await tester.pumpAndSettle();
      expect(find.textContaining('時間をおいて'), findsOneWidget);
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('パ動画0'), findsOneWidget);
      await tester.pump(const Duration(minutes: 10));
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) async {
              calls++;
              expect(request.url.queryParameters['refresh'],
                  calls == 2 ? '1' : isNull);
              return calls == 1 ? http.Response('', 503) : jsonResponse(data());
            }));
  });
  testWidgets('動画タブは記録の右にあり開いたときだけ取得する', (tester) async {
    var videoCalls = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: PredictionPage())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(videoCalls, 0);
      expect(tester.getCenter(find.text('動画')).dx,
          greaterThan(tester.getCenter(find.text('記録')).dx));
      await tester.tap(find.text('動画'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(videoCalls, 1);
      expect(find.byType(VideosBoard), findsOneWidget);
      expect(find.text('パ動画0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 21));
    },
        () => MockClient((r) async {
              if (r.url.path == '/videos') {
                videoCalls++;
                return jsonResponse(data());
              }
              return jsonResponse({});
            }));
  });
}
