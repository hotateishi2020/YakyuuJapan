import '../logic/batting_result_colors.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../logic/game_replay.dart';
import '../logic/replay_motion.dart';

const _bases = [
  Offset(.5, .86),
  Offset(.70, .66),
  Offset(.5, .43),
  Offset(.3, .66),
  Offset(.5, .86)
];
Offset replayBatterBox(ReplayFrame frame) => switch (replayBattingSide(frame)) {
      '右' => const Offset(.45, .86),
      '左' => const Offset(.55, .86),
      _ => const Offset(.5, .89),
    };
const _mound = Offset(.5, .645);
const _positions = {
  '投': _mound,
  '捕': Offset(.5, .96),
  '一': Offset(.79, .56),
  '二': Offset(.65, .36),
  '三': Offset(.21, .56),
  '遊': Offset(.35, .36),
  '左': Offset(.17, .15),
  '中': Offset(.5, .09),
  '右': Offset(.83, .15)
};

class ReplayField extends StatefulWidget {
  const ReplayField(
      {super.key,
      required this.frame,
      this.homeBackground = Colors.blue,
      this.awayBackground = Colors.red,
      this.homeForeground,
      this.awayForeground,
      this.scoreboard});
  final Color homeBackground, awayBackground;
  final Color? homeForeground, awayForeground;
  final ReplayFrame frame;
  final Widget? scoreboard;
  @override
  State<ReplayField> createState() => _ReplayFieldState();
}

class _ReplayFieldState extends State<ReplayField>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 6400));
  @override
  void initState() {
    super.initState();
    if (widget.frame.after) motion.forward();
  }

  @override
  void didUpdateWidget(ReplayField old) {
    super.didUpdateWidget(old);
    if (old.frame != widget.frame) {
      motion.reset();
      if (widget.frame.after) motion.forward();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  Widget tag(String text, Color bg, {Key? key, Color fg = Colors.black}) =>
      Container(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: fg)));
  @override
  Widget build(BuildContext context) => AspectRatio(
      aspectRatio: 1.45,
      child: LayoutBuilder(
          builder: (context, c) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AnimatedBuilder(
                  animation: motion,
                  builder: (context, _) {
                    final f = widget.frame;
                    final elapsed = motion.value * 6.4;
                    final lead = replayLeadSeconds(f);
                    final t = replayMotionProgress(f, elapsed);
                    final blinking = f.after && elapsed < lead;
                    final motionEnd = lead + replayMotionSeconds(f);
                    final change =
                        f.after && f.outs == 3 && elapsed >= motionEnd;
                    final showResult =
                        f.after && elapsed >= replayResultSeconds(f);
                    final offense = f.bottom
                        ? widget.homeBackground
                        : widget.awayBackground;
                    final defense = f.bottom
                        ? widget.awayBackground
                        : widget.homeBackground;
                    Color ink(Color bg, Color? configured) =>
                        configured ??
                        (bg.computeLuminance() > .45
                            ? Colors.black
                            : Colors.white);
                    final offenseInk = ink(
                        offense,
                        f.bottom
                            ? widget.homeForeground
                            : widget.awayForeground);
                    final defenseInk = ink(
                        defense,
                        f.bottom
                            ? widget.awayForeground
                            : widget.homeForeground);
                    final title = replayResultTitle(f);
                    final kind = replayResultKind(f);
                    final resultColor = change
                        ? Colors.blueGrey
                        : battingResultColor(kind, title);
                    final resultInk =
                        change ? Colors.white : battingResultInk(kind, title);
                    final travels = replayRunnerTravel(f);
                    final call = replayCatchCall(f);
                    final callPoint = call == null
                        ? null
                        : call.base != null
                            ? _bases[call.base!]
                            : _positions[call.position];
                    final occupancy =
                        f.after && t < 1 ? f.beforeBases : f.bases;
                    return Stack(children: [
                      Positioned.fill(
                          child: CustomPaint(
                              painter: _FieldPainter(f, t, travels))),
                      for (final e in f.defense.entries.where((e) =>
                          _positions.containsKey(e.key) && e.value.isNotEmpty))
                        AnimatedPositioned(
                            key: ValueKey('fielder-${e.value}'),
                            duration: const Duration(milliseconds: 600),
                            left: (_positions[e.key]!.dx * c.maxWidth - 44)
                                .clamp(0, c.maxWidth - 88),
                            top: _positions[e.key]!.dy * c.maxHeight - 10,
                            width: 88,
                            height: 22,
                            child: Center(
                                child: tag('${e.key} ${e.value}', defense,
                                    fg: defenseInk))),
                      for (var b = 1; b <= 3; b++)
                        Positioned(
                            left: _bases[b].dx * c.maxWidth - 18,
                            top: _bases[b].dy * c.maxHeight + 5,
                            child: tag(
                                occupancy < 0
                                    ? '—'
                                    : occupancy & (1 << (b - 1)) != 0 &&
                                            !(f.after &&
                                                t < 1 &&
                                                travels.any((r) => r.from == b))
                                        ? '$b塁'
                                        : '$b塁',
                                occupancy >= 0 &&
                                        occupancy & (1 << (b - 1)) != 0
                                    ? Colors.red.shade200
                                    : Colors.white70)),
                      Positioned(
                          left: c.maxWidth * .04,
                          bottom: 4,
                          width: c.maxWidth * .32,
                          child: tag(
                              '次 ${f.nextBatter.isEmpty ? '—' : f.nextBatter}',
                              offense,
                              fg: offenseInk,
                              key: const Key('replay-next'))),
                      Positioned(
                          left: c.maxWidth * .04,
                          bottom: 28,
                          width: c.maxWidth * .32,
                          child: Opacity(
                              opacity: blinking && (elapsed * 4).floor().isOdd
                                  ? .15
                                  : 1,
                              child: tag(
                                  '打 ${f.batter.isEmpty ? '—' : f.batter}',
                                  offense,
                                  fg: offenseInk,
                                  key: const Key('replay-batter')))),
                      Positioned(
                          left: c.maxWidth * .04,
                          bottom: 52,
                          child: Semantics(
                              label: f.outs < 0 ? 'アウト数未記録' : '${f.outs}アウト',
                              child: Container(
                                  key: const Key('replay-outs'),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Text(
                                      f.outs < 0
                                          ? 'OUT —'
                                          : 'OUT ${List.filled(f.outs.clamp(0, 3), '🔴').join()}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold))))),
                      // Ball and runners are painted over all field labels.
                      Positioned.fill(
                          child: IgnorePointer(
                              child: CustomPaint(
                                  painter: _MotionPainter(f, t, travels,
                                      teamColor: offense,
                                      pitching: !blinking,
                                      batterOpacity: blinking &&
                                              (elapsed * 4).floor().isOdd
                                          ? .15
                                          : 1)))),
                      if (widget.scoreboard != null)
                        Positioned(
                            right: 4,
                            bottom: 4,
                            width: math.min(400, c.maxWidth * .38),
                            height: math.min(160, c.maxHeight * .27),
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.bottomRight,
                                child: SizedBox(
                                    key: const Key('replay-field-scoreboard'),
                                    width: 400,
                                    child: widget.scoreboard))),
                      if (showResult)
                        Positioned(
                            left: 8,
                            right: 8,
                            top: c.maxHeight * .22,
                            child: IgnorePointer(
                                child: Opacity(
                                    opacity: 1,
                                    child: Center(
                                        child: Container(
                                            key: const Key('replay-result'),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 5),
                                            decoration: BoxDecoration(
                                                color: resultColor,
                                                border: Border.all(
                                                    color: Colors.white,
                                                    width: 3),
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: Text(
                                                change
                                                    ? 'チェンジ！'
                                                    : replayResultTitle(f),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color: resultInk,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: c.maxWidth < 450
                                                        ? 36
                                                        : 56,
                                                    shadows: const [
                                                      Shadow(
                                                          color: Colors.black26,
                                                          blurRadius: 5)
                                                    ]))))))),
                      if (call != null &&
                          callPoint != null &&
                          t >= call.at &&
                          !blinking)
                        Positioned(
                            left: (callPoint.dx * c.maxWidth - 42)
                                .clamp(0, c.maxWidth - 84),
                            top: (callPoint.dy * c.maxHeight - 40)
                                .clamp(0, c.maxHeight - 30),
                            width: 84,
                            child: IgnorePointer(
                                child: Container(
                                    key: const Key('replay-catch-call'),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    decoration: BoxDecoration(
                                        color: call.safe
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                        border: Border.all(color: Colors.white, width: 2),
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: const [
                                          BoxShadow(
                                              color: Colors.black54,
                                              blurRadius: 4)
                                        ]),
                                    child: Text(call.safe ? 'セーフ' : 'アウト',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900))))),
                      if (f.after && f.runsScored > 0 && elapsed >= motionEnd)
                        Positioned.fill(
                            child: IgnorePointer(
                                child: Container(
                          key: const Key('replay-score-effect'),
                          color: Colors.black.withValues(alpha: .55),
                          alignment: Alignment.center,
                          child: Transform.scale(
                            scale: 1 +
                                .12 *
                                    (1 -
                                        ((elapsed - motionEnd) / .35)
                                            .clamp(0.0, 1.0)),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('${f.runsScored}点！',
                                          style: const TextStyle(
                                              fontSize: 42,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.amber)),
                                      Text(
                                          '${f.awayScore ?? '—'} - ${f.homeScore ?? '—'}',
                                          style: const TextStyle(
                                              fontSize: 96,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              shadows: [
                                                Shadow(
                                                    color: Colors.amber,
                                                    blurRadius: 20)
                                              ])),
                                      Text(
                                          '${f.inning}回${f.bottom ? '裏' : '表'}',
                                          style: const TextStyle(
                                              fontSize: 24,
                                              color: Colors.white)),
                                    ],
                                  )),
                            ),
                          ),
                        ))),
                    ]);
                  }))));
}

Offset _pixel(Offset p, Size s) => Offset(p.dx * s.width, p.dy * s.height);

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.frame, this.t, this.travels);
  final ReplayFrame frame;
  final double t;
  final List<RunnerTravel> travels;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF25733D));
    final fence = Path()
      ..moveTo(size.width * .05, size.height * .18)
      ..quadraticBezierTo(size.width * .5, -size.height * .05, size.width * .95,
          size.height * .18);
    canvas.drawPath(
        fence,
        Paint()
          ..color = Colors.lightBlue.shade100
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    // Extend the exact home-to-base vectors so the infield and outfield
    // portions remain collinear at every viewport aspect ratio.
    final home = _pixel(_bases[0], size);
    for (final base in [_bases[1], _bases[3]]) {
      final throughBase = _pixel(base, size);
      canvas.drawLine(
          home,
          home + (throughBase - home) * 4,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 2);
    }
    final path = Path()..moveTo(size.width * .5, size.height * .86);
    for (final p in _bases.skip(1)) {
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFFB88B59));
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    for (final x in [.45, .55]) {
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(size.width * x, size.height * .84),
              width: size.width * .06,
              height: size.height * .10),
          Paint()
            ..color = Colors.white70
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_FieldPainter old) => false;
}

class _MotionPainter extends CustomPainter {
  _MotionPainter(this.f, this.t, this.travels,
      {this.pitching = true,
      this.batterOpacity = 1,
      this.teamColor = Colors.amber});
  final double batterOpacity;
  final Color teamColor;
  final bool pitching;
  final ReplayFrame f;
  final double t;
  final List<RunnerTravel> travels;
  Offset target() =>
      _positions[replayPosition(f.direction)] ?? const Offset(.5, .24);
  @override
  void paint(Canvas canvas, Size size) {
    final occupancy = f.after && t < 1 ? f.beforeBases : f.bases;
    for (var b = 1; b <= 3; b++) {
      if (occupancy >= 0 &&
          occupancy & (1 << (b - 1)) != 0 &&
          !(f.after && t < 1 && travels.any((r) => r.from == b))) {
        _person(canvas, _pixel(_bases[b], size), 0, false, teamColor);
      }
    }
    final batterDestination = replayBatterDestination(f);
    final battingEvent =
        !replayChanges.contains(f.result) && !replayRunning.contains(f.result);
    final runningBatter =
        f.after && batterDestination != null && t >= replayBatterRunStart;
    if (battingEvent && !runningBatter) {
      _person(canvas, _pixel(replayBatterBox(f), size), 0, false,
          teamColor.withValues(alpha: batterOpacity),
          mirror: replayBattingSide(f) == '左',
          batSwing:
              f.after && replayBatterSwings(f) ? replaySwingProgress(t) : 0);
    }
    if (!f.after) return;
    final code = f.result;
    final change = replayChanges.contains(code);
    final running = replayRunning.contains(code);
    final homer = code == 'HOMERUN' || code == 'HOME_RUN';
    final ground = code == 'OUT_GROUND' ||
        code == 'OUT_DOUBLE_PLAY' ||
        code == 'SACRIFICE_BUNT';
    final fly = code == 'OUT_FLY' ||
        code == 'OUT_POP_UP' ||
        code == 'SACRIFICE_FLY' ||
        homer;
    final contact = ground ||
        fly ||
        code == 'OUT_LINE_DRIVE' ||
        code.startsWith('HIT') ||
        code == 'SINGLE' ||
        code == 'ERROR' ||
        code == 'ERROR_FIELDING';
    Offset ball = _mound;
    String phase = '投球';
    if (!change && pitching) {
      if (running) {
        phase = code == 'ERROR_RUNNING'
            ? '送球エラー'
            : code == 'PASS_BALL'
                ? '捕逸'
                : code == 'WILD_PITCH'
                    ? '暴投'
                    : '送球';
        final end = code == 'STEAL_BASE_SAFE' || code == 'STEAL_BASE_OUT'
            ? _bases[replayCatchCall(f)?.base ?? 2]
            : const Offset(.8, .9);
        ball = Offset.lerp(_bases[0], end, t)!;
      } else if (t < replayPitchArrival) {
        ball = Offset.lerp(
            _mound,
            replayResultAtCatch(f) ? _positions['捕']! : _bases[0],
            t / replayPitchArrival)!;
      } else if (code == 'HIT2' || code == 'HIT3') {
        final left = replayPosition(f.direction) != '右';
        final fence = Offset(left ? .10 : .90, .156);
        final pickup = Offset(left ? .17 : .83, .20);
        final corner = Offset(left ? .02 : .98, .14);
        if (code == 'HIT2') {
          if (t < .55) {
            final q = ((t - .22) / .33).clamp(0.0, 1.0);
            ball = Offset.lerp(_bases[0], fence, q)! -
                Offset(0, math.sin(q * math.pi) * .08);
            phase = '打球';
          } else if (t < .72) {
            final q = (t - .55) / .17;
            ball = Offset.lerp(fence, pickup, q)! -
                Offset(0, math.sin(q * math.pi) * .06);
            phase = '打球';
          } else {
            ball =
                Offset.lerp(pickup, _bases[2], ((t - .72) / .28).clamp(0, 1))!;
            phase = '捕球 → 送球';
          }
        } else {
          final fair = Offset(left ? .21 : .79, .31);
          if (t < .50) {
            final q = ((t - .22) / .28).clamp(0.0, 1.0);
            ball = Offset.lerp(_bases[0], fair, q)! -
                Offset(0, math.sin(q * math.pi) * .12);
            phase = '打球';
          } else if (t < .78) {
            final q = (t - .50) / .28;
            ball = Offset.lerp(fair, corner, q)! -
                Offset(0, math.sin(q * math.pi * 4).abs() * .04 * (1 - q));
            phase = '打球';
          } else {
            ball =
                Offset.lerp(corner, _bases[3], ((t - .78) / .22).clamp(0, 1))!;
            phase = '捕球 → 送球';
          }
        }
        if (t > .5 && t < .92) {
          final destination = code == 'HIT2' ? pickup : corner;
          final fielder =
              Offset.lerp(target(), destination, ((t - .5) / .22).clamp(0, 1))!;
          _person(canvas, _pixel(fielder, size), t * 35, true,
              Colors.lightBlueAccent);
        }
      } else if (contact) {
        var end = target();
        if (homer) end = Offset(end.dx, .02);
        final progress = ((t - .22) / .43).clamp(0.0, 1.0);
        ball = Offset.lerp(_bases[0], end, progress)!;
        if (fly) ball -= Offset(0, math.sin(progress * math.pi) * .24);
        if (ground) {
          ball -= Offset(
              0,
              math.sin(progress * math.pi * 5).abs() *
                  .065 *
                  (1 - progress * .55));
        }
        phase = '打球';
        if (t > .65 && !fly && code != 'OUT_LINE_DRIVE') {
          phase = code == 'ERROR_FIELDING' ? '捕球エラー' : '送球';
          final endThrow = code == 'ERROR_FIELDING' || code == 'ERROR'
              ? end + const Offset(.08, .07)
              : _bases[1];
          ball = Offset.lerp(end, endThrow, ((t - .65) / .30).clamp(0, 1))!;
        }
      } else {
        ball = replayResultAtCatch(f) ? _positions['捕']! : _bases[0];
      }
      if (t < 1) {
        final p = _pixel(ball, size);
        canvas.drawOval(
            Rect.fromCenter(
                center: p + const Offset(0, 8), width: 13, height: 4),
            Paint()..color = Colors.black38);
        canvas.drawCircle(p, 5, Paint()..color = Colors.white);
        canvas.drawCircle(
            p,
            5,
            Paint()
              ..color = Colors.red
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
        final text = TextPainter(
            text: TextSpan(
                text: phase,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    backgroundColor: Colors.black54)),
            textDirection: TextDirection.ltr)
          ..layout();
        text.paint(canvas, p + const Offset(7, -10));
      }
    }
    if (t < 1) {
      final runnerPaths = [
        ...travels.where((r) => r.from != 0),
        if (batterDestination != null && runningBatter)
          RunnerTravel(0, batterDestination)
      ];
      for (final r in runnerPaths) {
        final start = r.from == 0 ? replayBatterRunStart : .22;
        final progress =
            ((t - start) / (1 - start)).clamp(0.0, 1.0) * (r.to - r.from);
        final base = (r.from + progress.floor()).clamp(0, 3);
        final p = Offset.lerp(base == 0 ? replayBatterBox(f) : _bases[base],
            _bases[base + 1], progress - progress.floor())!;
        _person(canvas, _pixel(p, size), t * 45, t > .22, teamColor);
      }
    }
  }

  void _person(
      Canvas canvas, Offset foot, double phase, bool running, Color color,
      {double? batSwing, bool mirror = false}) {
    canvas.save();
    canvas.translate(foot.dx, foot.dy);
    if (mirror) canvas.scale(-1, 1);
    final swing = running ? math.sin(phase) * 6 : 0.0;
    final limb = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(
        const Rect.fromLTWH(-7, -1, 14, 4), Paint()..color = Colors.black26);
    canvas.drawLine(const Offset(0, -13), Offset(-4 + swing, 0), limb);
    canvas.drawLine(const Offset(0, -13), Offset(4 - swing, 0), limb);
    canvas.drawLine(
        const Offset(0, -23), const Offset(0, -12), limb..strokeWidth = 6);
    if (batSwing != null) {
      final angle = 1.5 - batSwing * 3.7;
      final hands = Offset(5 + math.sin(batSwing * math.pi) * 4, -22);
      canvas.drawLine(const Offset(0, -22), hands, limb..strokeWidth = 3);
      canvas.drawLine(const Offset(0, -18), hands, limb);
      final tip = hands + Offset(math.cos(angle) * 27, math.sin(angle) * 27);
      canvas.drawLine(
          hands,
          tip,
          Paint()
            ..color = const Color(0xFFE9BD7C).withValues(alpha: color.a)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round);
      if (batSwing > 0 && batSwing < 1) {
        canvas.drawArc(
            Rect.fromCircle(center: hands, radius: 24),
            angle + .5,
            -.5,
            false,
            Paint()
              ..color = Colors.white38
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke);
      }
    } else {
      canvas.drawLine(
          const Offset(0, -21), Offset(-6 - swing, -13), limb..strokeWidth = 3);
      canvas.drawLine(const Offset(0, -21), Offset(6 + swing, -16), limb);
    }
    canvas.drawCircle(const Offset(0, -30), 5, Paint()..color = Colors.white);
    final helmet = Paint()..color = color;
    canvas.drawArc(
        const Rect.fromLTWH(-6, -37, 12, 12), math.pi, math.pi, true, helmet);
    canvas.drawLine(
        const Offset(-6, -31), const Offset(9, -31), helmet..strokeWidth = 3);
    canvas.drawCircle(const Offset(-3, -28), 2, helmet);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MotionPainter old) =>
      old.t != t ||
      old.f != f ||
      old.pitching != pitching ||
      old.batterOpacity != batterOpacity ||
      old.teamColor != teamColor;
}
