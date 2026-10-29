import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/logic/game_replay.dart';
import 'package:Yakyuu_Japan/logic/replay_motion.dart';
import 'package:Yakyuu_Japan/widgets/game_replay_dialog.dart';
import 'package:Yakyuu_Japan/widgets/replay_field.dart';

ReplayFrame makeFrame(
        {bool after = true, bool bottom = false, String batter = '打者'}) =>
    ReplayFrame(
        inning: 1,
        bottom: bottom,
        after: after,
        outs: 0,
        bases: after ? 1 : 0,
        beforeBases: 0,
        homeScore: 0,
        awayScore: 0,
        batter: batter,
        nextBatter: '次打者',
        label: '四球',
        defense: const {'投': '投手'},
        result: 'WALK');

void main() {
  testWidgets('offensive and defensive labels swap team colors by half inning',
      (tester) async {
    for (final bottom in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox(
                  width: 600,
                  height: 420,
                  child: ReplayField(
                      frame: makeFrame(bottom: bottom, after: false),
                      homeBackground: Colors.yellow,
                      homeForeground: Colors.black,
                      awayBackground: Colors.blue,
                      awayForeground: Colors.white)))));
      final name =
          tester.widget<Container>(find.byKey(const Key('replay-batter')));
      expect((name.decoration as BoxDecoration).color,
          bottom ? Colors.yellow : Colors.blue);
      expect((name.child as Text).style!.color,
          bottom ? Colors.black : Colors.white);
      final pitcher = tester.widget<Container>(find
          .ancestor(of: find.text('投 投手'), matching: find.byType(Container))
          .first);
      expect((pitcher.decoration as BoxDecoration).color,
          bottom ? Colors.blue : Colors.yellow);
      expect((pitcher.child as Text).style!.color,
          bottom ? Colors.white : Colors.black);
    }
  });
  testWidgets(
      'walk result and running finish before the next batter starts',
      (tester) async {
    AuthSession.instance.user = AuthUser.fromJson({'id': 1});
    AuthSession.instance.token = 'test';
    await tester.pumpWidget(MaterialApp(
        home: GameReplayDialog(game: const {}, frames: [
      makeFrame(after: false),
      makeFrame(),
      makeFrame(after: false, batter: '次の打者'),
      makeFrame(batter: '次の打者'),
    ])));
    await tester.tap(find.byTooltip('自動再生'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2700));
    expect(find.byKey(const Key('replay-result')), findsNothing);
    await tester.pump(const Duration(milliseconds: 48));
    expect(find.text('四球'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(find.text('打 打者'), findsOneWidget);
    expect(replayMotionProgress(makeFrame(), 4.747), 1);
    // The old wall-clock schedule advanced here, while the field could still
    // be drawing. Hold the completed play for two seconds instead.
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('打 打者'), findsOneWidget);
    final remaining = replayPresentationDuration(makeFrame()) - const Duration(milliseconds: 4748);
    await tester.pump(remaining - const Duration(milliseconds: 1));
    expect(find.text('打 打者'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 17));
    await tester.pump();
    expect(find.text('打 次の打者'), findsOneWidget);
    expect(find.byKey(const Key('replay-result')), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    final opacity = tester.widget<Opacity>(find
        .ancestor(
            of: find.byKey(const Key('replay-batter')),
            matching: find.byType(Opacity))
        .first);
    expect(opacity.opacity, .15);
    await tester.pumpWidget(const SizedBox());
    AuthSession.instance.user = null;
    AuthSession.instance.token = null;
  });
  testWidgets('描画が止まっている間は時間が経っても次の打者を開始しない', (tester) async {
    AuthSession.instance.user = AuthUser.fromJson({'id': 1});
    AuthSession.instance.token = 'test';
    addTearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
    final frames = [makeFrame(after: false), makeFrame(),
      makeFrame(after: false, batter: '次の打者'), makeFrame(batter: '次の打者')];
    Widget page(bool enabled) => MaterialApp(home: TickerMode(enabled: enabled,
      child: GameReplayDialog(game: const {}, frames: frames)));
    await tester.pumpWidget(page(false));
    await tester.tap(find.byTooltip('自動再生'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.text('打 打者'), findsOneWidget);
    expect(find.byKey(const Key('replay-result')), findsNothing);
    await tester.pumpWidget(page(true));
    await tester.pump();
    await tester.pump(replayPresentationDuration(makeFrame()));
    await tester.pump();
    expect(find.text('打 次の打者'), findsOneWidget);
    await tester.tap(find.byTooltip('一時停止'));
    await tester.pumpAndSettle();
    expect(find.text('4 / 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
