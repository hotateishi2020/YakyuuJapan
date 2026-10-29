import 'dart:convert';
import 'dart:async';
import 'package:Yakyuu_Japan/tools/player_detail_cache.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/player_detail_dialog.dart';
import 'package:Yakyuu_Japan/View/player_stats_grid.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart' show GameBattingResult, GamePlayerAppearance;
import 'package:Yakyuu_Japan/View/BlinkBg.dart';

void main() {
  setUp(() {
    PlayerDetailCache.clear();
    AuthSession.instance.user = AuthUser.fromJson({'id': 1});
    AuthSession.instance.token = 'test';
  });
  tearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
  testWidgets('最新成績の取得を待たずにプロフィールを表示する', (t) async {
    final season = Completer<http.Response>();
    await http.runWithClient(() async {
      await t.pumpWidget(const MaterialApp(home: PlayerDetailDialog(player: {'id_player': 999}, org: 'npb', year: 2026)));
      await t.pumpAndSettle();
      expect(find.text('先に表示する選手'), findsWidgets);
      expect(find.text('生年月日'), findsWidgets);
      season.complete(http.Response('{}', 503));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(find.text('選手情報を取得できませんでした。'), findsNothing);
      expect(find.text('先に表示する選手'), findsWidgets);
      await t.pumpWidget(const SizedBox());
    }, () => MockClient((request) async {
      if (request.url.queryParameters['section'] == 'season') return season.future;
      return http.Response(jsonEncode({'found': true, 'profile': {'id': 999, 'name_full': '先に表示する選手'}}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  testWidgets('一時的な503は自動再試行し、再表示はプロフィールを再取得しない', (t) async {
    var requests = 0;
    await http.runWithClient(() async {
      Widget dialog() => const MaterialApp(home: PlayerDetailDialog(player: {'id_player': 999}, org: 'npb', year: 2026));
      await t.pumpWidget(dialog());
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(find.text('復旧した選手'), findsWidgets);
      expect(requests, 2);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(dialog());
      await t.pumpAndSettle();
      expect(find.text('復旧した選手'), findsWidgets);
      expect(requests, 2);
      await t.pumpWidget(const SizedBox());
    }, () => MockClient((request) async {
      if (request.url.queryParameters['section'] == 'season') return http.Response('{"season_stats":[]}', 200);
      requests++;
      if (requests == 1) return http.Response('{}', 503);
      return http.Response('{"found":true,"profile":{"id":999,"name_full":"復旧した選手"}}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
  for (final special in [false, true]) {
    testWidgets('選手生成画像は許可ユーザーだけ表示しログアウトで消える $special', (t) async {
      AuthSession.instance.user = AuthUser.fromJson({'id': special ? 1 : 3, 'flg_special': special});
      AuthSession.instance.token = 'test';
      addTearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(home: PlayerDetailDialog(player: {'id_player': 1}, org: 'npb', year: 2026)));
        await t.pumpAndSettle();
        final frame = find.byKey(const ValueKey('player-character-frame'));
        expect(frame, special ? findsOneWidget : findsNothing);
        AuthSession.instance.user = null;
        await t.pumpAndSettle();
        expect(frame, findsNothing);
      }, () => MockClient((_) async => http.Response(jsonEncode({
        'found': true, 'profile': {'name_full': '甲'},
        'character_image': {'url': '/test-character.png'},
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
    });
  }
  for (final matched in [false, true]) {
    testWidgets('ホームラン動画は特定できた直接動画だけ再生可能 $matched', (t) async {
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(
            home: Scaffold(
                body: PlayerDetailDialog(
          player: {'name': '佐藤太郎'},
          org: 'npb',
          year: 2026,
        ))));
        await t.pumpAndSettle();
        final button = find.byKey(const ValueKey('home-run-video-2026-10-20'));
        await t.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
        expect(t.widget<InkWell>(button).onTap, matched ? isNotNull : isNull);
        expect(find.descendant(of: button, matching: find.byType(CircularProgressIndicator)), findsNothing);
        expect(find.descendant(of: button, matching: find.byIcon(matched ? Icons.play_arrow : Icons.videocam_off_outlined)), findsOneWidget);
      },
          () => MockClient((request) async {
                final Object payload;
                if (request.url.path.endsWith('/videos') || request.url.path.endsWith('/home-run-video')) {
                  payload = {
                    'channels': [
                      {
                        'id': 'official',
                        'videos': matched
                            ? [
                                {'id': 'abcdefghijk', 'title': '佐藤太郎 ホームラン 2026/10/20'},
                              ]
                            : []
                      }
                    ]
                  };
                } else {
                  payload = {
                    'found': true,
                    'profile': {'name_full': '佐藤太郎', 'id_league': 1},
                    'recent_games': [
                      {
                        'datetime_start': '2026-10-20',
                        'plays': [
                          {'result': '左本', 'bases': 4}
                        ]
                      }
                    ]
                  };
                }
                return http.Response(jsonEncode(payload), 200, headers: {'content-type': 'application/json; charset=utf-8'});
              }));
    });
  }

  for (final portrait in [false, true]) {
    testWidgets('本塁打がある試合だけ出場成績の横に再生ボタンを表示する', (t) async {
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(home: Scaffold(body: PlayerDetailDialog(player: {'name': '甲'}, org: 'npb', year: 2026))));
        await t.pumpAndSettle();
        final button = find.byKey(const ValueKey('home-run-video-2026-10-20'));
        await t.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
        expect(button, findsOneWidget);
        expect(find.byKey(const ValueKey('home-run-video-2026-10-19')), findsNothing);
        expect(t.takeException(), isNull);
      },
          () => MockClient((_) async => http.Response(
              jsonEncode({
                'found': true,
                'profile': {'name_full': '甲', 'id_league': 2},
                'recent_games': [
                  {
                    'datetime_start': '2026-10-20',
                    'opponent': '西武',
                    'plays': [
                      {'result': '左本', 'bases': 4}
                    ]
                  },
                  {
                    'datetime_start': '2026-10-19',
                    'opponent': '西武',
                    'plays': [
                      {'result': '左安', 'bases': 1}
                    ]
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'})));
    });

    testWidgets('代打の今季スタッツは投手では非表示にし野手では表示する', (t) async {
      for (final pitcher in [true, false]) {
        PlayerDetailCache.clear();
        await http.runWithClient(() async {
          await t.pumpWidget(MaterialApp(home: Scaffold(body: PlayerDetailDialog(key: ValueKey(pitcher), player: const {'name': '甲'}, org: 'npb', year: 2026))));
          await t.pumpAndSettle();
          for (final title in ['代打起用数', '代打打率']) {
            expect(find.text(title), pitcher ? findsNothing : findsOneWidget);
          }
          expect(find.text('防御率'), findsOneWidget);
          expect(t.takeException(), isNull);
        },
            () => MockClient((_) async => http.Response(
                jsonEncode({
                  'found': true,
                  'profile': {'name_full': '甲', 'txt_position': pitcher ? '投手' : '内野手'},
                  'season_stats': [
                    {'title': '代打起用数', 'stats': '3'},
                    {'title': '代打打率', 'stats': '.250'},
                    {'title': '防御率', 'stats': '2.30', 'int_rank': 4},
                  ],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'})));
      }
    });

    testWidgets('成績ブロックの半角全角空白を除去する', (t) async {
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: GamePlayerAppearance(
        lines: [],
        plays: [
          {'result': '空 三 振'},
          {'result': '故意四球'},
          {'result': r'中\u3000飛'},
          {'result': '左 前 安', 'bases': 1},
          {'result': '右中間二塁打', 'bases': 2},
          {'result': '遊ゴロ併殺打'},
          {'result': '捕犠打'},
          {'result': '右犠飛'},
        ],
      ))));
      for (final label in ['三振', '四球', '中飛', '左安', '右２', '遊併', '犠打', '犠飛']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('出場記録は勝敗HSを投球ブロック左に置きHQSと球速を表示', (t) async {
      for (final mark in ['勝', '負', 'H', 'S']) {
        await t.pumpWidget(MaterialApp(
            home: Scaffold(
                body: GamePlayerAppearance(
          lines: [
            {'code_result_pitcher': mark, 'double_inning_pitch': 7, 'starter': true, 'int_runs': 2, 'int_runs_earned': 2, 'int_velo_max': 160, 'int_hit': 4, 'int_four': 0, 'int_dead_pitching': 0, 'int_strike_out': 10, 'txt_achieve': 'QS|qs HQS|hqs'}
          ],
          plays: const [],
        ))));
        await t.pump();
        expect(find.text(mark), findsOneWidget);
        expect(find.text('HQS'), findsOneWidget);
        expect(find.ancestor(of: find.text('HQS'), matching: find.byType(BlinkBg)), findsOneWidget);
        expect(find.text('QS'), findsNothing);
        expect(find.text('160km'), findsOneWidget);
        expect(t.getTopLeft(find.text(mark)).dx, lessThan(t.getTopLeft(find.text('7回2失点')).dx));
        expect(t.takeException(), isNull);
      }
    });

    testWidgets('出場記録は猛打賞と5タコを表示し四球なら5タコにしない', (t) async {
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: GamePlayerAppearance(
        lines: [
          {'int_batting': 4, 'int_hit1': 3}
        ],
        plays: [],
      ))));
      expect(find.text('猛打賞'), findsOneWidget);
      expect(find.ancestor(of: find.text('猛打賞'), matching: find.byType(BlinkBg)), findsOneWidget);
      for (final walk in [false, true]) {
        await t.pumpWidget(MaterialApp(
            home: Scaffold(
                body: GamePlayerAppearance(
          lines: [
            {'int_batting': walk ? 4 : 5, 'int_hit1': 0}
          ],
          plays: [
            for (var i = 0; i < 5; i++) {'result': walk && i == 0 ? '四球' : '空三振'}
          ],
        ))));
        expect(find.text('5タコ'), walk ? findsNothing : findsOneWidget);
      }
    });

    testWidgets('今季スタッツとリーグ順位を${portrait ? '功績の下' : 'プロフィール右側'}に表示', (t) async {
      AuthSession.instance.user = AuthUser.fromJson({'id': 1, 'flg_special': true});
      AuthSession.instance.token = 'test';
      addTearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
      t.view.physicalSize = portrait ? const Size(390, 900) : const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(home: PlayerDetailDialog(player: {'name': '甲'}, org: 'npb', year: 2026)));
        await t.pumpAndSettle();
        expect(find.text('.320'), findsOneWidget);
        expect(find.text('リーグ2位'), findsOneWidget);
        expect(find.text('今季成績'), findsNothing);
        if (!portrait) {
          final profileGrid = find.byKey(const ValueKey('player-profile-grid'));
          final statsGrid = find.byKey(const ValueKey('player-season-stats-grid'));
          expect(t.getSize(profileGrid).width, t.getSize(statsGrid).width);
          final profileHeader = find.descendant(of: profileGrid, matching: find.byType(Container)).evaluate().map((e) => e.widget as Container).where((c) => c.constraints?.hasTightWidth == true).first;
          final statsHeader = find.descendant(of: statsGrid, matching: find.byType(Container)).evaluate().map((e) => e.widget as Container).where((c) => c.constraints?.hasTightWidth == true).first;
          expect(profileHeader.constraints!.maxWidth, statsHeader.constraints!.maxWidth);
        }
        expect(find.text('リーグ1位'), findsOneWidget);
        expect(find.text('リーグ3位'), findsOneWidget);
        expect(find.text('12（リーグ4位）'), findsOneWidget);
        final gold = t.widget<Container>(find.byKey(const ValueKey('player-stat-medal-安打')));
        expect(((gold.decoration as BoxDecoration).image!.image as AssetImage).assetName, 'backend/assets/images/analysis_grade_gold.jpg');
        expect(find.text('7（順位なし）'), findsOneWidget);
        final grid = find.byKey(const ValueKey('player-profile-grid'));
        if (portrait) {
          final table = t.widget<Table>(grid);
          final labels = table.children.map((row) => (find.descendant(of: find.byWidget(row.children.first), matching: find.byType(Text)).evaluate().single.widget as Text).data).toList();
          expect(labels.indexOf('打率'), greaterThan(labels.indexOf('功績')));
          expect(find.byKey(const ValueKey('player-season-stats-grid')), findsNothing);
        } else {
          final stats = find.byKey(const ValueKey('player-season-stats-grid'));
          expect(t.getTopLeft(stats).dx, greaterThanOrEqualTo(t.getTopRight(grid).dx));
          expect(t.getTopLeft(stats).dy, t.getTopLeft(grid).dy);
          final lower = find.byKey(const ValueKey('player-profile-links-honors'));
          final image = find.byKey(const ValueKey('player-character-frame'));
          expect(t.getSize(stats).height, closeTo(t.getSize(grid).height, .01));
          expect(t.getSize(image).height, closeTo(t.getSize(grid).height, .01));
          expect(t.getTopLeft(lower).dy, closeTo(t.getBottomLeft(stats).dy, .01));
          expect(t.getTopLeft(lower).dx, t.getTopLeft(image).dx);
          expect(t.getTopRight(lower).dx, closeTo(t.getTopRight(stats).dx, .01));
        }
        expect(t.takeException(), isNull);
      },
          () => MockClient((_) async => http.Response(
              jsonEncode({
                'found': true,
                'profile': {'name_full': '甲', 'name_team': '阪神'},
                'character_image': {'url': '/test-character.png'},
                'season_stats': [
                  {'title': '打率', 'stats': '.320', 'int_rank': 2},
                  {'title': '本塁打', 'stats': '7', 'int_rank': 1000},
                  {'title': '安打', 'stats': '150', 'int_rank': 1},
                  {'title': '打点', 'stats': '80', 'int_rank': 3},
                  {'title': '盗塁', 'stats': '12', 'int_rank': 4},
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'})));
    });
  }

  testWidgets('投手の無失点と端数の投球回を先頭のブロックに表示する', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: GamePlayerAppearance(
      lines: [
        {'double_inning_pitch': 1.2, 'int_runs': 0, 'int_hit': 1, 'int_four': 0, 'int_dead_pitching': 0, 'int_strike_out': 2, 'int_pitch': 24}
      ],
      plays: [],
    ))));
    expect(find.text('1.2回無失点'), findsOneWidget);
    expect(t.getTopLeft(find.text('1.2回無失点')).dx, lessThan(t.getTopLeft(find.text('被安打1')).dx));
  });
  testWidgets('狭い出場成績セルでも打席ブロックを同じ幅で横一列に並べる', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
      width: 100,
      child: GamePlayerAppearance(lines: [], plays: [
        {'result': '中安', 'bases': 1},
        {'result': '三振'},
        {'result': '左本', 'bases': 4, 'rbi': 2},
        {'result': '四球'},
        {'result': '二ゴ'},
      ]),
    )))));
    final chips = find.byType(GameBattingResult);
    final first = t.getRect(chips.first);
    for (var i = 1; i < 5; i++) {
      final rect = t.getRect(chips.at(i));
      expect(rect.top, closeTo(first.top, .01));
      expect(rect.width, closeTo(first.width, .01));
      expect(rect.left, greaterThan(t.getRect(chips.at(i - 1)).left));
    }
    expect(find.byKey(const ValueKey('rbi-badge-2')), findsOneWidget);
    final scroll = find.byType(Scrollable);
    await t.drag(scroll, const Offset(-200, 0));
    await t.pumpAndSettle();
    expect(t.state<ScrollableState>(scroll).position.pixels, greaterThan(0));
    expect(t.takeException(), isNull);
  });

  testWidgets('出場成績は試合情報と共通の投打ブロックを表示', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: GamePlayerAppearance(
      lines: [
        {'double_inning_pitch': 4, 'int_runs': 3, 'int_hit': 5, 'int_four': 0, 'int_dead_pitching': 0, 'int_strike_out': 3, 'int_pitch': 57, 'starter': true}
      ],
      plays: [
        {'result': '中安', 'bases': 1}
      ],
    ))));
    for (final text in ['4回3失点', '被安打5', '0四死', '3K', '57球', '中安']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.byType(GameBattingResult), findsOneWidget);
    final sizes = ['4回3失点', '被安打5', '0四死', '3K', '57球', '中安'].map((label) => t.widget<Text>(find.text(label)).style!.fontSize).toSet();
    expect(sizes, {12.0});
    expect(find.descendant(of: find.byType(GamePlayerAppearance), matching: find.byType(FittedBox)), findsNothing);
    final row = t.widget<Row>(find.descendant(of: find.byType(GamePlayerAppearance), matching: find.byType(Row)).first);
    final divider = find.byKey(const ValueKey('appearance-pitching-batting-divider'));
    expect(divider, findsOneWidget);
    expect(t.getSize(divider).width, 1);
    expect(t.getTopLeft(divider).dx, greaterThan(t.getTopRight(find.text('57球')).dx));
    expect(t.getTopRight(divider).dx, lessThan(t.getTopLeft(find.text('中安')).dx));
    final heights = row.children.where((child) => !(child is Padding && child.child?.key == const ValueKey('appearance-pitching-batting-divider'))).map((child) => t.getSize(find.byWidget(child)).height).toList();
    expect(heights, hasLength(6));
    expect(heights.every((height) => height == heights.first), isTrue, reason: '投球回、被安打、四死球、奪三振、球数、打撃結果の高さを統一する');
    expect(t.takeException(), isNull);
  });

  testWidgets('画像とプロフィールの高さを揃え直近25試合を過去シーズンの前に表示する', (t) async {
      AuthSession.instance.user = AuthUser.fromJson({'id': 1, 'flg_special': true});
      AuthSession.instance.token = 'test';
      addTearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
    await t.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: PlayerDetailDialog(player: {'name': '甲'}, org: 'npb', year: 2026))));
      await t.pumpAndSettle();
      final image = find.byKey(const ValueKey('player-character-frame'));
      final grid = find.byKey(const ValueKey('player-profile-grid'));
      expect(t.getSize(image).height, t.getSize(grid).height);
      expect(t.getSize(image).width, greaterThan(300));
      final lower = find.byKey(const ValueKey('player-profile-links-honors'));
      expect(t.getTopLeft(lower).dx, t.getTopLeft(image).dx);
      expect(t.getTopRight(lower).dx, closeTo(t.getTopRight(grid).dx, .01));
      expect(t.getTopLeft(lower).dy, closeTo(t.getBottomLeft(image).dy, .01));
      expect(t.getTopLeft(grid).dx, greaterThan(t.getTopLeft(image).dx));
      final profile = t.widget<Table>(grid);
      final headerWidth = (profile.columnWidths![0] as FixedColumnWidth).value;
      expect(headerWidth, greaterThan(110));
      final usage = find.text('今シーズンの起用');
      await t.scrollUntilVisible(usage, 200, scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
      await t.pumpAndSettle();
      final left = find.byKey(const ValueKey('player-usage-三塁'));
      final right = find.byKey(const ValueKey('player-usage-右翼'));
      expect(t.getSize(left).width / t.getSize(right).width, closeTo(3, .01));
      expect(t.getTopLeft(left).dy, t.getTopLeft(right).dy);
      expect(find.text('三塁 30回（75.0%）'), findsOneWidget);
      final more = find.byTooltip('直近25試合を表示');
      await t.scrollUntilVisible(more, 200, scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
      await t.pumpAndSettle();
      expect(find.text('直近の試合の出場成績'), findsOneWidget);
      expect(find.byType(GameBattingResult), findsNWidgets(10));
      expect(find.text('vs巨人'), findsNWidgets(10));
      final recentGrid = t.widget<Table>(find.byKey(const ValueKey('recent-appearances-rows')));
      expect(recentGrid.children, hasLength(10));
      final viewport = find.byKey(const ValueKey('recent-appearances-viewport'));
      expect(t.getSize(viewport).height, 480);
      expect(find.byKey(const ValueKey('recent-appearances-scroll')), findsNothing);
      expect(recentGrid.children.every((row) => row.children.length == 3), isTrue);
      await t.tap(more);
      await t.pumpAndSettle();
      final popup = find.byType(Dialog).last;
      expect(find.descendant(of: popup, matching: find.byType(GameBattingResult)), findsNWidgets(25));
      expect(t.takeException(), isNull);
    },
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'found': true,
              'profile': {'name_full': '甲', 'txt_position': '内野手'},
              'character_image': {'url': '/test-character.png'},
              'usage': {
                'positions': [
                  {'slot': '三塁', 'count': 30},
                  {'slot': '右翼', 'count': 10}
                ]
              },
              'careers': [
                {'int_year': 2025, 'double_average_onbase': .4, 'double_average_slugging': .5}
              ],
              'recent_games': [
                for (var i = 0; i < 25; i++)
                  {
                    'datetime_start': '2026-10-20',
                    'away': '阪神',
                    'home': '巨人',
                    'opponent': '読売ジャイアンツ',
                    'plays': [
                      {'result': '中安', 'bases': 1, 'rbi': 1}
                    ],
                  }
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
  });

  testWidgets('画像取得失敗でも表示領域を保ちスクロール後に戻れる', (t) async {
      AuthSession.instance.user = AuthUser.fromJson({'id': 1, 'flg_special': true});
      AuthSession.instance.token = 'test';
      addTearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: PlayerDetailDialog(player: {'name': '甲'}, org: 'npb', year: 2026))));
      await t.pumpAndSettle();
      final frame = find.byKey(const ValueKey('player-character-frame'));
      final before = t.getSize(frame);
      final grid = find.byKey(const ValueKey('player-profile-grid'));
      expect(before.width, t.getSize(grid).width);
      expect(t.getTopLeft(grid).dx, t.getTopLeft(frame).dx);
      expect(t.getTopLeft(grid).dy, closeTo(t.getBottomLeft(frame).dy, .01));
      expect(find.text('AI生成キャラクター'), findsNothing);
      expect(find.byKey(const ValueKey('player-profile-links-honors')), findsNothing);
      final list = find.byType(ListView).first;
      await t.drag(list, const Offset(0, -600));
      await t.pumpAndSettle();
      await t.drag(list, const Offset(0, 1200));
      await t.pumpAndSettle();
      expect(t.getSize(frame), before);
      expect(t.takeException(), isNull);
    },
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'found': true,
              'profile': {'name_full': '甲', 'txt_position': '内野手'},
              'character_image': {'url': '/test-character.png'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
  });

  for (final pitcher in [false, true]) {
    testWidgets('選手詳細の役割別項目と今季年俸のみの表示 $pitcher', (t) async {
      t.view.physicalSize = const Size(1200, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(home: PlayerDetailDialog(player: {'id_player': 1}, org: 'npb', year: 2026)));
        await t.pumpAndSettle();
        expect(find.text('過去シーズン'), findsOneWidget);
        expect(find.text('経歴'), findsOneWidget);
        expect(find.text('甲高校→乙大学→ソフトバンク→日本ハム→ソフトバンク'), findsOneWidget);
        expect(find.text('出典の注釈'), findsNothing);
        expect(t.getTopLeft(find.text('経歴')).dy, lessThan(t.getTopLeft(find.text('過去シーズン')).dy));
        expect(find.text('2026年 シーズン成績'), findsOneWidget);
        expect(find.text('リーグ順位'), findsOneWidget);
        expect(find.text('2位'), findsNWidgets(2));
        expect(find.text('1000位'), findsNothing);
        expect(find.text('0位'), findsNothing);
        expect(find.text('投球速度'), pitcher ? findsOneWidget : findsNothing);
        expect(find.text('打球速度'), pitcher ? findsNothing : findsOneWidget);
        expect(find.text('防御率'), pitcher ? findsOneWidget : findsNothing);
        expect(find.text('本塁打'), pitcher ? findsNothing : findsOneWidget);
        expect(find.text('2026年 年俸'), findsOneWidget);
        expect(find.text('1998-05-12'), findsOneWidget);
        expect(find.textContaining('00:00:00'), findsNothing);
        expect(t.getTopLeft(find.text('2026年 年俸')).dy, lessThan(t.getTopLeft(find.text('過去シーズン')).dy));
        expect(find.textContaining('過去契約'), findsNothing);
        final gauge = t.widget<LinearProgressIndicator>(find.byKey(ValueKey(pitcher ? 'player-usage-先発' : 'player-usage-中堅')));
        expect(gauge.value, pitcher ? 0.25 : 0.6);
        expect(find.text('https://ja.wikipedia.org/wiki/Test_player'), findsOneWidget);
        expect(t.getTopLeft(find.text('過去シーズン')).dy, lessThan(t.getTopLeft(find.text(pitcher ? '直近25試合の投球成績' : '直近25試合の打撃成績')).dy));
        if (!pitcher) {
          expect(find.byType(GameBattingResult), findsNothing);
          await t.tap(find.text('直近25試合の打撃成績'));
          await t.pumpAndSettle();
          expect(find.text('甲：直近25試合の打撃成績'), findsOneWidget);
          expect(find.byType(GameBattingResult), findsNWidgets(3));
          expect(find.byKey(const ValueKey('rbi-badge-1')), findsOneWidget);
          expect(find.byKey(const ValueKey('rbi-badge-2')), findsOneWidget);
          final chips = find.byType(GameBattingResult);
          expect(t.getSize(chips.at(0)).width, t.getSize(chips.at(1)).width);
          expect(t.getSize(chips.at(1)).width, t.getSize(chips.at(2)).width);
          await t.tap(find.byTooltip('閉じる').last);
          await t.pumpAndSettle();
          expect(find.byType(PlayerDetailDialog), findsOneWidget);
          expect(find.byType(GameBattingResult), findsNothing);
        }
        expect(t.takeException(), isNull);
      },
          () => MockClient((_) async => http.Response(
              jsonEncode({
                'found': true,
                'wikipedia_url': 'https://ja.wikipedia.org/wiki/Test_player',
                'usage': {
                  'positions': pitcher
                      ? []
                      : [
                          {'slot': '中堅', 'count': 60, 'total': 100}
                        ],
                  'pitching_workload': pitcher
                      ? [
                          {'starts': 5, 'appearances': 20}
                        ]
                      : [],
                },
                'profile': {'name_full': '甲', 'name_team': 'ソフトバンク', 'id_team': 10, 'date_birth': '1998-05-12 00:00:00', 'txt_position': pitcher ? '投手' : '外野手'},
                'careers': [
                  {'int_year': 2025, 'id_team': 10, 'name_team': 'ソフトバンク'},
                  {'int_year': 2024, 'id_team': 8, 'name_team': '日本ハム'},
                  {'int_year': 2023, 'id_team': 10, 'name_team': 'ソフトバンク'},
                  {'int_year': 2022, 'id_team': 10, 'name_team': 'ソフトバンク'}
                ],
                'season_stats': [
                  {'title': 'ボール見極め率', 'stats': '80', 'int_rank': 2},
                  {'title': '得点圏打率', 'stats': '.320', 'int_rank': '2'},
                  {'title': '代打打率', 'stats': '.250', 'int_rank': 1000},
                  {'title': '代打起用数', 'stats': '—', 'int_rank': 0}
                ],
                'roster': {
                  'career_history': [
                    {'team': '甲高校', 'category': '高校', 'detail': '出典の注釈'},
                    {'team': '乙大学', 'category': '大学'}
                  ],
                  'contract_data': {
                    'salary_history': [
                      {'year': 2025, 'detail': '過去契約'}
                    ],
                    'periods': [
                      {'start_year': 2024, 'end_year': 2028, 'detail': '過去契約'}
                    ]
                  }
                },
                'recent_games': [
                  {
                    'datetime_start': '2026-10-10',
                    'plays': [
                      {'result': '左安', 'bases': 1, 'rbi': 1},
                      {'result': '三振', 'bases': 0, 'rbi': 0},
                      {'result': '中安②', 'bases': 1},
                    ],
                    'lines': []
                  }
                ]
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'})));
    });
  }

  testWidgets('実データの経歴・起用・契約・功績まで表示してもスマホで崩れない', (t) async {
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final data = File('test/fixtures/player_detail_verified.json').readAsStringSync();
    await http.runWithClient(() async {
      await t.pumpWidget(const MaterialApp(home: PlayerDetailDialog(player: {'id_player': 654}, org: 'npb', year: 2026)));
      await t.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        expect(find.text('出典'), findsNothing);
        await t.drag(find.byType(ListView).first, const Offset(0, -650));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    }, () => MockClient((_) async => http.Response(data, 200, headers: {'content-type': 'application/json; charset=utf-8'})));
  });

  testWidgets('グリッドは数値で並び替え、欠損を末尾に置き選手を重複させない', (t) async {
    final rows = [
      for (final r in [
        {'id': 1, 'name': '甲', 'value': '2'},
        {'id': 2, 'name': '乙', 'value': '10'},
        {'id': 3, 'name': '丙', 'value': '—'}
      ])
        {'id_player': r['id'], 'name_player': r['name'], 'title': '本塁打', 'stats': r['value']},
      {'id_player': 1, 'name_player': '甲', 'title': '打席数', 'stats': '100'}
    ];
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PlayerStatsGrid(rows: rows, batting: true))));
    expect(find.text('甲'), findsOneWidget);
    await t.tap(find.text('本塁打'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('乙')).dy, lessThan(t.getTopLeft(find.text('甲')).dy));
    expect(t.getTopLeft(find.text('丙')).dy, greaterThan(t.getTopLeft(find.text('甲')).dy));
    await t.tap(find.text('本塁打'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('甲')).dy, lessThan(t.getTopLeft(find.text('乙')).dy));
    expect(t.getTopLeft(find.text('丙')).dy, greaterThan(t.getTopLeft(find.text('乙')).dy));
    expect(t.takeException(), isNull);
  });
  testWidgets('横長画面にグリッド表切替ボタンを表示しない', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: DualBandLeaguePersonalStats(batting: [
      {'id_player': 1, 'name_player': '甲', 'title': '打率', 'stats': '.300'}
    ], pitching: []))));
    expect(find.text('グリッド表'), findsNothing);
    expect(find.text('従来の表'), findsNothing);
    expect(find.text('打者スタッツ'), findsOneWidget);
    expect(find.text('投手スタッツ'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final width in [390.0, 1400.0]) {
    testWidgets('選手名から詳細を開き、幅$widthで情報を表示', (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(home: PlayerDetailScope(org: 'npb', year: 2026, child: Scaffold(body: PlayerNameLink(player: {'id_player': 1, 'name': '甲'}, child: Text('甲'))))));
        await t.tap(find.text('甲'));
        await t.pumpAndSettle();
        expect(find.byType(PlayerDetailDialog), findsOneWidget);
        expect(find.text('AI生成イメージ（共通）'), findsNothing);
        expect(find.text('今季所属'), findsNWidgets(2)); // 所属と経歴の両セル
        expect(t.takeException(), isNull);
        await t.drag(find.byType(ListView).first, const Offset(0, -650));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
          () => MockClient((r) async {
                expect(r.url.queryParameters['id_player'], '1');
                return http.Response(
                    jsonEncode({
                      'found': true,
                      'profile': {'name_full': '甲', 'name_team': '今季所属', 'txt_position': '投手'},
                      'season_stats': [
                        {'title': 'BB/9', 'stats': '2.30'}
                      ],
                      'recent_games': [
                        {
                          'datetime_start': '2026-10-10',
                          'home': '甲球団',
                          'away': '乙球団',
                          'lines': [
                            {'int_batting': 4, 'int_hit1': 2, 'int_homerun': 1}
                          ],
                          'plays': []
                        }
                      ],
                      'roster': {},
                      'verified': {},
                      'careers': []
                    }),
                    200,
                    headers: {'content-type': 'application/json; charset=utf-8'});
              }));
    });
  }
}
