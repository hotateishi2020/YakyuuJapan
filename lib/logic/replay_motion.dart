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
      'STRIKE_OUT' => '三振',
      'DROPPED_THIRD' => '振逃',
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

class ReplayCatchCall {
  const ReplayCatchCall(
      {required this.safe, this.base, this.position, required this.at});
  final bool safe;
  final int? base;
  final String? position;

  /// Progress through the ball animation, excluding the batter introduction.
  final double at;
}

ReplayCatchCall? replayCatchCall(ReplayFrame frame) {
  if (!frame.after) return null;
  if (const {'OUT_FLY', 'OUT_POP_UP', 'OUT_LINE_DRIVE', 'SACRIFICE_FLY'}
      .contains(frame.result)) {
    final position = replayPosition(frame.direction);
    if (!const {'投', '捕', '一', '二', '三', '遊', '左', '中', '右'}
        .contains(position)) {
      return null;
    }
    return ReplayCatchCall(safe: false, position: position, at: .65);
  }
  if (frame.result == 'OUT_GROUND' || frame.result == 'SACRIFICE_BUNT') {
    return const ReplayCatchCall(safe: false, base: 1, at: .95);
  }
  final hitBase = switch (frame.result) {
    'HIT1' || 'SINGLE' => 1,
    'HIT2' => 2,
    'HIT3' => 3,
    _ => 0
  };
  if (hitBase > 0 &&
      frame.bases >= 0 &&
      frame.bases & (1 << (hitBase - 1)) != 0) {
    return ReplayCatchCall(safe: true, base: hitBase, at: 1);
  }
  if (frame.result == 'STEAL_BASE_SAFE') {
    final paths = replayRunnerTravel(frame);
    if (paths.length == 1) {
      return ReplayCatchCall(safe: true, base: paths.single.to, at: 1);
    }
  }
  if (frame.result == 'STEAL_BASE_OUT' && frame.beforeBases > 0) {
    final occupied = [
      for (var b = 1; b <= 3; b++)
        if (frame.beforeBases & (1 << (b - 1)) != 0) b
    ];
    if (occupied.length == 1) {
      return ReplayCatchCall(safe: false, base: occupied.single + 1, at: 1);
    }
  }
  // A fielder's choice, double play or generic error alone doesn't identify
  // the base where the catch/tag happened.
  return null;
}

const replayBatterRunStart = .30;

bool replayBatterSwings(ReplayFrame f) => const {
      'HIT1',
      'HIT2',
      'HIT3',
      'SINGLE',
      'HOMERUN',
      'HOME_RUN',
      'OUT_GROUND',
      'OUT_DOUBLE_PLAY',
      'OUT_FLY',
      'OUT_POP_UP',
      'OUT_LINE_DRIVE',
      'SACRIFICE_FLY',
      'ERROR',
      'ERROR_FIELDING',
      'FIELDERS_CHOICE',
    }.contains(f.result);

/// Finish the follow-through before switching the same figure to a runner.
double replaySwingProgress(double t) => ((t - .16) / .14).clamp(0.0, 1.0);

int? replayBatterDestination(ReplayFrame f) {
  if (!f.after) return null;
  for (final move in replayRunnerTravel(f)) {
    if (move.from == 0) return move.to;
  }
  if (const {'OUT_GROUND', 'OUT_DOUBLE_PLAY', 'SACRIFICE_BUNT'}
      .contains(f.result)) {
    return 1;
  }
  return null;
}

// Normalized ball-animation time at which the pitch reaches home/catcher.
const replayPitchArrival = .22;

String replayResultKind(ReplayFrame frame) {
  if (frame.result.startsWith('HIT') &&
      (frame.label.contains('適時') || frame.label.contains('タイムリー'))) {
    return 'timely';
  }
  return switch (frame.result) {
    'HOMERUN' || 'HOME_RUN' => 'hr',
    'HIT1' || 'SINGLE' => 'single',
    'HIT2' => 'double',
    'HIT3' => 'triple',
    'WALK' => 'walk',
    'WALK_DEAD' || 'INTERFERENCE_BATTING' => 'dead',
    'ERROR' || 'ERROR_FIELDING' || 'ERROR_RUNNING' => 'error',
    'FIELDERS_CHOICE' => 'fc',
    'SACRIFICE_FLY' => 'sacfly',
    'SACRIFICE_BUNT' => 'sacbunt',
    'SQUEEZE' => 'squeeze',
    'STEAL_BASE_SAFE' => 'steal',
    'STEAL_BASE_OUT' => 'stealout',
    _ => 'out',
  };
}

bool replayResultAtCatch(ReplayFrame f) =>
    const {'STRIKE_OUT', 'WALK', 'WALK_DEAD'}.contains(f.result);
double replayLeadSeconds(ReplayFrame f) => f.after &&
        !replayChanges.contains(f.result) &&
        !replayRunning.contains(f.result)
    ? 2
    : 0;
double replayResultSeconds(ReplayFrame f) =>
    replayLeadSeconds(f) +
    (replayResultAtCatch(f) ? 3.4 * replayPitchArrival : 1.8);
double replayMotionSeconds(ReplayFrame f) =>
    replayResultAtCatch(f) ? 3.4 * replayPitchArrival + 1.6 : 3.4;
double replayMotionProgress(ReplayFrame f, double elapsed) {
  final time = elapsed - replayLeadSeconds(f);
  const arrival = 3.4 * replayPitchArrival;
  if (replayResultAtCatch(f) && time >= arrival) {
    return (replayPitchArrival +
            (time - arrival) / 1.6 * (1 - replayPitchArrival))
        .clamp(0.0, 1.0);
  }
  return (time / 3.4).clamp(0.0, 1.0);
}
