import 'package:flutter/material.dart';
import 'package:Yakyuu_Japan/widgets/replay_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/game_replay.dart';
import 'package:Yakyuu_Japan/widgets/game_replay_dialog.dart';

Map<String, dynamic> play(int id,
        {String code = 'SINGLE',
        int bases = 0,
        int home = 0,
        int away = 0,
        bool bottom = false,
        int order = 1}) =>
    {
      'id': id,
      'int_inning': 1,
      'flg_bottom': bottom,
      'int_batting_order': order,
      'cnt_out': 0,
      'flg_runner_first': bases & 1 != 0,
      'flg_runner_second': bases & 2 != 0,
      'flg_runner_third': bases & 4 != 0,
      'int_score_home': home,
      'int_score_away': away,
      'code_result': code,
      'name_full': '打者$order',
      'label': code,
    };
const game = <String, dynamic>{
  'id_team_home': 1,
  'state': '試合終了',
  'score_home': 0,
  'score_away': 1,
  'name_team_home': 'ホーム',
  'name_team_away': 'ビジター',
  'name_pitcher_home': '先発投手',
  'lineup': [
    {
      'id_team': 1,
      'players': [
        {'name': '近藤', 'pos': '右'}
      ]
    }
  ]
};

void main() {
  test('batting hands survive before/after frames and choose matching boxes', () {
    for (final hand in [0, 1, 2]) {
      final frames = buildGameReplay(game, [{...play(1), 'batting_hand': hand, 'pitching_hand': 0}]);
      for (final frame in frames) {
        expect(frame.battingHand, ['右', '左', '両'][hand]);
        expect(replayBatterBox(frame).dx, hand == 0 ? .45 : .55);
      }
    }
    final unknown = buildGameReplay(game, [play(1)]).first;
    expect(replayBattingSide(unknown), isEmpty);
    expect(replayBatterBox(unknown).dx, .5);
  });
  test(
      'chronology, steal, scoring and inning transitions use recorded snapshots',
      () {
    final frames = buildGameReplay(game, [
      play(4, bottom: true, away: 1),
      play(3, code: 'HOME_RUN', bases: 2, order: 2),
      play(1),
      play(2, code: 'STEAL_BASE_SAFE', bases: 1, order: 2),
    ]);
    expect(frames.length, 8);
    expect(frames[0].batter, '打者1');
    expect(frames[0].nextBatter, '打者2');
    expect(frames[1].bases, 1);
    expect(frames[3].bases, 2);
    expect(frames[5].awayScore, 1);
    expect(frames[5].outs, 3);
    expect(frames[5].bases, 0);
    expect(frames.last.awayScore, 1);
    expect(frames.last.bases, -1);
  });

  test('defensive changes preserve earlier frames for rewind', () {
    final change = play(1, code: 'CHANGE_POSITION')
      ..addAll({
        'name_enter': '近藤',
        'code_position_from': 'RIGHT',
        'code_position_to': 'LEFT'
      });
    final pitcher = play(2, code: 'CHANGE_PITCHER')..['name_enter'] = '救援投手';
    final frames = buildGameReplay(game, [change, pitcher]);
    expect(frames[0].defense['右'], '近藤');
    expect(frames[1].defense['左'], '近藤');
    expect(frames[1].defense.containsKey('右'), false);
    expect(frames[2].defense['投'], '先発投手');
    expect(frames[3].defense['投'], '救援投手');
    expect(frames[0].defense['投'], '先発投手');
  });

  test('live final event does not invent a resulting score or bases', () {
    final frames = buildGameReplay({...game, 'state': '試合中'}, [play(1)]);
    expect(frames.last.homeScore, isNull);
    expect(frames.last.bases, -1);
    expect(buildGameReplay(game, []), isEmpty);
  });

  testWidgets('phone popup supports auto, pause, manual next and rewind',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final frames =
        buildGameReplay(game, [play(1), play(2, bases: 1, order: 2)]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameReplayDialog(game: game, frames: frames))));
    expect(find.text('1 / 4'), findsOneWidget);
    await tester.tap(find.byTooltip('自動再生'));
    await tester.pump(const Duration(milliseconds: 4200));
    expect(find.text('2 / 4'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.byTooltip('自動再生'), findsNothing);
    await tester.tap(find.byTooltip('一つ進む'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 4'), findsOneWidget);
    await tester.tap(find.byTooltip('一つ戻る'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
