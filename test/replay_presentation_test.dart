import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/logic/game_replay.dart';
import 'package:Yakyuu_Japan/widgets/game_replay_dialog.dart';
import 'package:Yakyuu_Japan/widgets/replay_field.dart';

ReplayFrame frame({bool after = false, int runs = 0}) => ReplayFrame(
      inning: 1,
      bottom: false,
      after: after,
      outs: 2,
      bases: 0,
      homeScore: 0,
      awayScore: runs,
      batter: '打者',
      nextBatter: '次打者',
      label: '本塁打',
      defense: const {'中': '中堅手', '左': '左翼手', '右': '右翼手', '投': '投手'},
      result: 'HOMERUN',
      runsScored: runs,
    );

void main() {
  tearDown(() {
    AuthSession.instance.user = null;
    AuthSession.instance.token = null;
  });
  for (final size in [
    const Size(1400, 900),
    const Size(390, 844),
    const Size(844, 390)
  ]) {
    testWidgets('field and next batter fit without vertical scrolling at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AuthSession.instance.user = AuthUser.fromJson({'id': 1});
      AuthSession.instance.token = 'test';
      await tester.pumpWidget(MaterialApp(
          home: GameReplayDialog(game: const {}, frames: [frame()])));
      await tester.pump();
      final dialog =
          tester.getRect(find.byKey(const Key('replay-dialog-body')));
      expect(dialog.height, greaterThan(size.height * .9));
      for (final finder in [
        find.byKey(const Key('replay-next')),
        find.text('中 中堅手'),
        find.byKey(const Key('replay-outs'))
      ]) {
        final rect = tester.getRect(finder);
        expect(dialog.contains(rect.topLeft), isTrue);
        expect(dialog.contains(rect.bottomRight), isTrue);
      }
      expect(
          tester
              .widgetList<SingleChildScrollView>(
                  find.byType(SingleChildScrollView))
              .any((w) => w.scrollDirection == Axis.vertical),
          isFalse);
      final field = tester.getRect(find.byType(ReplayField));
      final scoreboard =
          tester.getRect(find.byKey(const Key('replay-field-scoreboard')));
      expect(scoreboard.left, greaterThan(field.center.dx));
      expect(scoreboard.top, greaterThan(field.center.dy));
      expect(field.contains(scoreboard.bottomRight), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('score effect follows scoring animation and clears on rewind',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
                width: 600,
                height: 420,
                child: ReplayField(frame: frame(after: true, runs: 2))))));
    expect(find.byKey(const Key('replay-score-effect')), findsNothing);
    await tester.pump(const Duration(milliseconds: 6500));
    expect(find.byKey(const Key('replay-score-effect')), findsOneWidget);
    expect(find.text('2 - 0'), findsOneWidget);
    final outs = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('replay-outs')), matching: find.byType(Text)));
    expect(outs.style!.fontSize, greaterThanOrEqualTo(22));
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
                width: 600, height: 420, child: ReplayField(frame: frame())))));
    await tester.pump();
    expect(find.byKey(const Key('replay-score-effect')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
