import 'game_replay.dart';

class RunnerTravel {
  const RunnerTravel(this.from, this.to);
  // 0 = batter's box, 1–3 = bases, 4 = home plate.
  final int from, to;
}

/// Schematic paths inferred from successive base snapshots, never runner IDs.
List<RunnerTravel> replayRunnerTravel(ReplayFrame frame) {
  if (!frame.after || frame.beforeBases < 0) return [];
  final occupied = [
    for (var b = 1; b <= 3; b++)
      if (frame.beforeBases & (1 << (b - 1)) != 0) b
  ];
  if (frame.result == 'HOMERUN' || frame.result == 'HOME_RUN') {
    return [
      for (final b in occupied) RunnerTravel(b, 4),
      const RunnerTravel(0, 4)
    ];
  }
  if (frame.bases < 0) return [];
  final destinations = [
    for (var b = 1; b <= 3; b++)
      if (frame.bases & (1 << (b - 1)) != 0) b
  ];
  final batterBase = switch (frame.result) {
    'HIT1' || 'SINGLE' => 1,
    'HIT2' => 2,
    'HIT3' => 3,
    'WALK' || 'WALK_DEAD' || 'HIT_BY_PITCH' => 1,
    _ => 0
  };
  final moves = <RunnerTravel>[];
  if (batterBase > 0 && destinations.remove(batterBase)) {
    moves.add(RunnerTravel(0, batterBase));
  }
  final targets = [
    ...destinations,
    for (var n = 0; n < frame.runsScored; n++) 4
  ];
  // When outs or unrecorded advances leave identity ambiguous, don't animate
  // a guessed runner. The final occupancy is still shown.
  if (targets.length == occupied.length) {
    for (var i = 0; i < occupied.length; i++) {
      if (targets[i] > occupied[i]) {
        moves.add(RunnerTravel(occupied[i], targets[i]));
      }
    }
  }
  return moves;
}

String replayResultTitle(ReplayFrame f) => switch (f.result) {
      'OUT_GROUND' => 'ゴロ',
      'OUT_DOUBLE_PLAY' => '併殺',
      'OUT_FLY' => 'フライ',
      'OUT_POP_UP' => 'フライ',
      'OUT_LINE_DRIVE' => 'ライナー',
      'HOMERUN' || 'HOME_RUN' => 'ホームラン',
      'ERROR' => 'エラー',
      'ERROR_RUNNING' => '送球エラー',
      'ERROR_FIELDING' => '捕球エラー',
      _ => f.label,
    };
