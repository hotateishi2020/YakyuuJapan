import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

void main() {
  testWidgets('MLBの左側スタメン名は略記を省略せず表示する', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    final session = AuthSession.instance;
    session.user = AuthUser.fromJson({'id': 1});
    session.token = 'test';
    addTearDown(() {
      session.user = null;
      session.token = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GamesBoardYahooStyle(
      horizontal: true,
      playerStats: const [{'name_full': 'ジェーコブ ミジオロウスキー', 'name_last': 'ジェーコブ'}],
      initialStatsExpanded: true,
      games: [
        {
          'id_game': 1,
          'date_game': '2026-10-28',
          'state': '8回表',
          'id_team_home': 1,
          'id_team_away': 2,
          'id_league_home': 3,
          'id_league_away': 4,
          'name_team_home': 'ホーム',
          'name_team_away': 'ビジター',
          'player_hands': const [
            {'id_player': 501, 'id_team': 1, 'name_full_summary': 'マイケル・ディアス'}
          ],
          'season_player_stats': const [
            {'id_player': 501, 'name_player': '別の表記', 'title': '打率', 'stats': .301},
            {'id_player': 501, 'name_player': '別の表記', 'title': '本塁打', 'stats': 14},
          ],
          'lineup': [
            {
              'id_team': 1,
              'order': 1,
              'players': [
                {'name': 'M.ディアス', 'pos': '左', 'plays': ['三振|out/event${Uri.encodeComponent('先発投手:ジェーコブ・ミジオロウスキー')}', ...List.filled(11, '三振|out')].join(' ')},
                const {'name': 'エリー・デラクルーズ', 'role': '代打', 'plays': '左ホームラン|hr/pinch'},
              ],
            }
          ],
        }
      ],
    ))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.descendant(of: find.byKey(const ValueKey('batting-name-home-1')), matching: find.text('M.ディアス')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('plate-event-label-先発投手')), matching: find.text('ミジオ')), findsOneWidget);
    expect(find.text('ジェー'), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('game-season-stats-M.ディアス'))).data, '.301 14本');
    expect(tester.widget<Text>(find.byKey(const ValueKey('substitution-title-エリー・デラクルーズ'))).data, 'デラク');
    final season = find.byKey(const ValueKey('game-season-stats-M.ディアス'));
    final horizontalScroll = find
        .ancestor(
            of: season,
            matching: find.byWidgetPredicate(
              (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal,
            ))
        .first;
    final fixedNameX = tester.getTopLeft(find.descendant(of: find.byKey(const ValueKey('batting-name-home-1')), matching: find.text('M.ディアス'))).dx;
    final seasonX = tester.getTopLeft(season).dx;
    await tester.drag(horizontalScroll, const Offset(-100, 0));
    await tester.pump();
    expect(tester.getTopLeft(season).dx, lessThan(seasonX - 20));
    expect(tester.getTopLeft(find.descendant(of: find.byKey(const ValueKey('batting-name-home-1')), matching: find.text('M.ディアス'))).dx, fixedNameX);
    expect(tester.takeException(), isNull);
  });
  for (final runnerPlays in ['', '中ホームラン|hr']) {
    testWidgets('代走選手は自身の打撃がある場合だけ枠・選手名・走バッジを表示する plays=$runnerPlays', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      final session = AuthSession.instance;
      session.user = AuthUser.fromJson({'id': 1});
      session.token = 'test';
      addTearDown(() {
        session.user = null;
        session.token = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: GamesBoardYahooStyle(
        horizontal: true,
        games: [
          {
            'id_game': 1,
            'date_game': '2026-10-25',
            'state': '8回表',
            'id_team_home': 1,
            'id_team_away': 2,
            'name_team_home': 'ソフトバンク',
            'name_team_away': 'DeNA',
            'score_home': 3,
            'score_away': 0,
            'lineup': [
              const {
                'id_team': 1,
                'order': 1,
                'players': [
                  {'name': '先発一', 'plays': '三振|out'},
                  {'name': '山川　穂高', 'role': '代打', 'plays': '左ホームラン|hr/pinch'},
                ]
              },
              {
                'id_team': 1,
                'order': 2,
                'players': [
                  const {'name': '先発二', 'plays': '二ゴ|out 左安|single'},
                  {'name': '川村　友斗', 'role': '代走', 'plays': runnerPlays},
                ]
              },
              const {
                'id_team': 1,
                'order': 3,
                'players': [
                  {'name': '先発三', 'plays': '右飛|out'},
                  {'name': '守備　選手', 'role': '代守', 'plays': '右安|single/pinch1'},
                ]
              },
              const {
                'id_team': 1,
                'order': 4,
                'players': [
                  {'name': '先発四', 'plays': '遊ゴ|out'},
                  {'name': '代打　選手名', 'role': '代打', 'plays': '四球|walk 中安|single'},
                  {'name': '代走　選手名', 'role': '代走', 'plays': '二飛|out'},
                  {'name': '最後　選手名', 'role': '代守', 'plays': '捕邪|out'},
                ]
              },
            ],
          }
        ],
      ))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(find.byKey(const ValueKey('substitution-title-代打選手名'))).data, '代打選');
      expect(find.byKey(const ValueKey('batting-runner-代走選手名')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('substitution-title-最後選手名'))).data, '最後選手名');
      for (final pair in [('山川穂高', '左本'), ('守備選手', '右安')]) {
        expect(find.text(pair.$1), findsOneWidget);
        expect(tester.getTopLeft(find.text(pair.$1)).dy, greaterThanOrEqualTo(tester.getBottomLeft(find.text(pair.$2)).dy));
      }
      final titleTop = tester.getTopLeft(find.byKey(const ValueKey('substitution-title-山川穂高'))).dy;
      final homerChip = tester.getRect(find.ancestor(of: find.text('左本'), matching: find.byType(Container)).first);
      expect(titleTop - homerChip.bottom, greaterThanOrEqualTo(2));
      final homerFrame = find.ancestor(of: find.byKey(const ValueKey('substitution-title-山川穂高')), matching: find.byType(Stack)).first;
      final rbiBadge = find.descendant(of: homerFrame, matching: find.byKey(const ValueKey('rbi-badge-1')));
      expect(tester.getBottomLeft(rbiBadge).dy, lessThan(titleTop));
      for (final pair in [('三振', '左本'), ('右飛', '右安'), ('二ゴ', '左安')]) {
        expect(tester.getCenter(find.text(pair.$1)).dy, closeTo(tester.getCenter(find.text(pair.$2)).dy, 0.1));
      }
      for (final pair in [('先発一', '三振'), ('先発二', '二ゴ'), ('先発三', '右飛')]) {
        expect(tester.getCenter(find.text(pair.$1)).dy, closeTo(tester.getCenter(find.text(pair.$2)).dy, 0.5));
      }
      expect(tester.getCenter(find.text('先発二')).dy - tester.getCenter(find.text('先発一')).dy, lessThanOrEqualTo(56));
      final compactFrame = tester.getRect(find.byKey(const ValueKey('substitution-frame-代打選手名')));
      final walkChip = tester.getRect(find.ancestor(of: find.text('四球'), matching: find.byType(Container)).first);
      expect(walkChip.left - compactFrame.left, closeTo(4, 0.1));
      // 全打順で1打席目と2打席目の列を揃える（途中出場の枠も列幅の整数倍）。
      for (final labels in [
        ['三振', '二ゴ', '右飛', '遊ゴ'],
        ['左本', '左安', '右安', '四球']
      ]) {
        final x = tester.getCenter(find.text(labels.first)).dx;
        for (final label in labels.skip(1)) {
          expect(tester.getCenter(find.text(label)).dx, closeTo(x, 0.1));
        }
      }
      final pitch = tester.getCenter(find.text('左安')).dx - tester.getCenter(find.text('二ゴ')).dx;
      final origin = tester.getCenter(find.text('二ゴ')).dx;
      for (final label in ['中安', '二飛', '捕邪']) {
        final column = (tester.getCenter(find.text(label)).dx - origin) / pitch;
        expect(column, closeTo(column.roundToDouble(), 0.01));
      }
      for (final pair in [('山川穂高', '左本'), ('守備選手', '右安')]) {
        final border = tester.getRect(find.byKey(ValueKey('substitution-frame-${pair.$1}')));
        final title = tester.getRect(find.byKey(ValueKey('substitution-title-${pair.$1}')));
        final chip = tester.getRect(find.ancestor(of: find.text(pair.$2), matching: find.byType(Container)).first);
        final contentRight = title.right > chip.right ? title.right : chip.right;
        expect(border.right - contentRight, closeTo(4, 0.1));
      }
      expect(find.byKey(const ValueKey('batting-runner-川村友斗')), findsNothing);
      expect(find.byKey(const ValueKey('substitution-frame-川村友斗')), runnerPlays.isEmpty ? findsNothing : findsOneWidget);
      expect(find.byKey(const ValueKey('substitution-title-川村友斗')), runnerPlays.isEmpty ? findsNothing : findsOneWidget);
      for (final pair in [('山川穂高', '打'), ('守備選手', '守')]) {
        expect(find.descendant(of: find.byKey(ValueKey('substitution-badge-${pair.$1}')), matching: find.text(pair.$2)), findsOneWidget);
      }
      expect(find.text('代'), findsNothing);
      expect(find.byKey(const ValueKey('pinch-badge')), findsNothing);
      expect(find.byKey(const ValueKey('pinch-badge-1')), findsNothing);
      expect(find.byKey(const ValueKey('rbi-badge-1')), findsWidgets);
      expect(find.textContaining('代打：'), findsNothing);
      expect(find.textContaining('代走：'), findsNothing);
      expect(find.textContaining('代守：'), findsNothing);
      if (runnerPlays.isNotEmpty) {
        expect(find.text('中本'), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('substitution-badge-川村友斗')), matching: find.text('走')), findsOneWidget);
        expect(tester.widget<Text>(find.byKey(const ValueKey('substitution-title-川村友斗'))).data, '川村友斗');
        expect(tester.getCenter(find.text('左安')).dy, closeTo(tester.getCenter(find.text('中本')).dy, 0.1));
      }
      expect(find.text('先発一 '), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
