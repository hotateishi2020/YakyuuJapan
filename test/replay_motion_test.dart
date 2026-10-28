import 'package:flutter/material.dart';
import 'package:Yakyuu_Japan/logic/batting_result_colors.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/game_replay.dart';
import 'package:Yakyuu_Japan/logic/replay_motion.dart';
import 'package:Yakyuu_Japan/widgets/replay_field.dart';

ReplayFrame frame(String result, {int before = 1, int bases = 2, int runs = 0}) => ReplayFrame(inning: 1, bottom: false, after: true, outs: 0, bases: bases, beforeBases: before, homeScore: 0, awayScore: runs, runsScored: runs, batter: '現在の打者', nextBatter: '次の打者', label: result, result: result, direction: 'LEFT', defense: const {'投': '投手名'});
void main() {
  testWidgets('strikeout appears immediately when the pitch reaches catcher', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 600, child: ReplayField(frame: frame('STRIKE_OUT'))))));
    await tester.pump(const Duration(milliseconds: 2700));
    expect(find.byKey(const Key('replay-result')), findsNothing);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('三振'), findsOneWidget);
    final block = tester.widget<Container>(find.byKey(const Key('replay-result')));
    expect((block.decoration as BoxDecoration).color, battingResultColor('out', '三振'));
    await tester.pumpAndSettle();
  });
  test('replay uses detailed batting block colors and readable ink', () {
    for (final pair in [('HOMERUN', 'hr'), ('HIT1', 'single'), ('HIT2', 'double'), ('WALK', 'walk'), ('ERROR_FIELDING', 'error'), ('SACRIFICE_BUNT', 'sacbunt')]) {
      final f = frame(pair.$1);
      expect(battingResultColor(replayResultKind(f), replayResultTitle(f)), battingResultColor(pair.$2, replayResultTitle(f)));
    }
    expect(battingResultInk('single', '安'), Colors.black87);
    expect(battingResultInk('out', '併殺'), const Color(0xFFE53935));
  });

  test('runner paths cover stealing, forced advance, scoring and home runs', () {
    expect(replayRunnerTravel(frame('STEAL_BASE_SAFE')).map((r) => (r.from, r.to)), [(1, 2)]);
    expect(replayRunnerTravel(frame('WALK', bases: 3)).map((r) => (r.from, r.to)), [(0, 1), (1, 2)]);
    expect(replayRunnerTravel(frame('HIT2', before: 4, bases: 2, runs: 1)).map((r) => (r.from, r.to)), [(0, 2), (3, 4)]);
    expect(replayRunnerTravel(frame('HOMERUN', before: 7, bases: 0, runs: 4)).map((r) => (r.from, r.to)), [(1, 4), (2, 4), (3, 4), (0, 4)]);
    expect(replayRunnerTravel(frame('OUT_GROUND', before: 3, bases: 1)), isEmpty);
  });
  test('result types remain distinct', () {
    expect(['OUT_GROUND', 'OUT_FLY', 'OUT_LINE_DRIVE', 'HOMERUN', 'ERROR', 'ERROR_RUNNING', 'ERROR_FIELDING'].map((code) => replayResultTitle(frame(code))), ['ゴロ', 'フライ', 'ライナー', 'ホームラン', 'エラー', '送球エラー', '捕球エラー']);
  });
  test('swing finishes before the batter starts running through first base', () {
    expect(replayBatterSwings(frame('HIT1', before: 0, bases: 1)), isTrue);
    expect(replaySwingProgress(.15), 0);
    expect(replaySwingProgress(.22), closeTo(.42857, .001));
    expect(replaySwingProgress(replayBatterRunStart), closeTo(1, .001));
    expect(replayBatterDestination(frame('HIT1', before: 0, bases: 1)), 1);
    expect(replayBatterDestination(frame('HIT2', before: 0, bases: 2)), 2);
    expect(replayBatterDestination(frame('HOMERUN', before: 0, bases: 0)), 4);
    expect(replayBatterDestination(frame('OUT_GROUND', before: 0, bases: 0)), 1);
    expect(replayBatterDestination(frame('OUT_FLY', before: 0, bases: 0)), isNull);
    expect(replayBatterSwings(frame('WALK', before: 0, bases: 1)), isFalse);
    expect(replayBatterSwings(frame('PINCH_RUNNER')), isFalse);
  });
  testWidgets('batter flashes for two seconds and change follows the result', (tester) async {
    const f = ReplayFrame(inning: 1, bottom: false, after: true, outs: 3, bases: 0, beforeBases: 1, homeScore: 0, awayScore: 0, batter: '打者', nextBatter: '次打者', label: '左飛', result: 'OUT_FLY', direction: 'LEFT', defense: const {});
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 340, child: ReplayField(frame: f)))));
    double opacity() => tester.widget<Opacity>(find.ancestor(of: find.byKey(const Key('replay-batter')), matching: find.byType(Opacity)).first).opacity;
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacity(), .15);
    expect(find.byKey(const Key('replay-result')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1800));
    expect(opacity(), 1);
    expect(find.byKey(const Key('replay-result')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('フライ'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('チェンジ！'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('field positions, foreground result and moving paint on a phone', (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 340, child: RepaintBoundary(key: boundary, child: ReplayField(frame: frame('OUT_FLY')))))));
    final field = tester.getRect(find.byType(ReplayField));
    final pitcher = tester.getCenter(find.text('投 投手名'));
    expect(pitcher.dx, closeTo(field.center.dx, 1));
    expect(pitcher.dy, closeTo(field.top + field.height * .645, 3));
    expect(tester.getCenter(find.byKey(const Key('replay-batter'))).dx, lessThan(field.center.dx));
    expect(tester.getRect(find.byKey(const Key('replay-batter'))).bottom, lessThan(tester.getRect(find.byKey(const Key('replay-next'))).top));
    expect(tester.getCenter(find.byKey(const Key('replay-next'))).dx, lessThan(field.center.dx));
    expect(find.text('フライ'), findsNothing);
    await tester.pump(const Duration(milliseconds: 3900));
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final firstBytes = await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = await image.toByteData();
      image.dispose();
      return bytes;
    });
    await tester.pump(const Duration(milliseconds: 900));
    final secondBytes = await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = await image.toByteData();
      image.dispose();
      return bytes;
    });
    expect(firstBytes!.buffer.asUint8List(), isNot(orderedEquals(secondBytes!.buffer.asUint8List())));
    await tester.pumpAndSettle();
    expect(find.text('フライ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
