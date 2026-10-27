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
  const ReplayField({super.key, required this.frame});
  final ReplayFrame frame;
  @override
  State<ReplayField> createState() => _ReplayFieldState();
}

class _ReplayFieldState extends State<ReplayField>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3400));
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

  Widget tag(String text, Color bg, {Key? key}) => Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Colors.black)));
  @override
  Widget build(BuildContext context) => AspectRatio(
      aspectRatio: 1.45,
      child: LayoutBuilder(
          builder: (context, c) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AnimatedBuilder(
                  animation: motion,
                  builder: (context, _) {
                    final f = widget.frame, t = motion.value;
                    final travels = replayRunnerTravel(f);
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
                                child:
                                    tag('${e.key} ${e.value}', Colors.white))),
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
                                        ? '走者'
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
                              Colors.lightBlue.shade100,
                              key: const Key('replay-next'))),
                      Positioned(
                          left: c.maxWidth * .54,
                          top: c.maxHeight * .84,
                          width: c.maxWidth * .42,
                          child: tag('打 ${f.batter.isEmpty ? '—' : f.batter}',
                              Colors.amber,
                              key: const Key('replay-batter'))),
                      Positioned(right:6,bottom:4,child:Semantics(
                        label:f.outs<0?'アウト数未記録':'${f.outs}アウト',
                        child:Container(key:const Key('replay-outs'),
                          padding:const EdgeInsets.symmetric(horizontal:5,vertical:2),
                          decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(4)),
                          child:Text(f.outs<0?'OUT —':'OUT ${List.filled(f.outs.clamp(0,3),'🔴').join()}',
                            style:const TextStyle(color:Colors.white,fontSize:12))))),
                      // Ball and runners are painted over all field labels.
                      Positioned.fill(
                          child: IgnorePointer(
                              child: CustomPaint(
                                  painter: _MotionPainter(f, t, travels)))),
                      if (f.after)
                        Positioned(
                            left: 8,
                            right: 8,
                            top: c.maxHeight * .23,
                            child: IgnorePointer(
                                child: Opacity(
                                    opacity: (t * 4).clamp(0, 1),
                                    child: Center(
                                        child: Container(
                                            key: const Key('replay-result'),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 5),
                                            decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: .72),
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: Text(replayResultTitle(f),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: c.maxWidth < 450
                                                        ? 25
                                                        : 36,
                                                    shadows: const [
                                                      Shadow(
                                                          color: Colors.red,
                                                          blurRadius: 5)
                                                    ]))))))),
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
  }

  @override
  bool shouldRepaint(_FieldPainter old) => false;
}

class _MotionPainter extends CustomPainter {
  _MotionPainter(this.f, this.t, this.travels);
  final ReplayFrame f;
  final double t;
  final List<RunnerTravel> travels;
  Offset target() =>
      _positions[replayPosition(f.direction)] ?? const Offset(.5, .24);
  @override
  void paint(Canvas canvas, Size size) {
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
    if (!change) {
      if (running) {
        phase = code == 'ERROR_RUNNING'
            ? '送球エラー'
            : code == 'PASS_BALL'
                ? '捕逸'
                : code == 'WILD_PITCH'
                    ? '暴投'
                    : '送球';
        final end = code == 'STEAL_BASE_SAFE' || code == 'STEAL_BASE_OUT'
            ? _bases[2]
            : const Offset(.8, .9);
        ball = Offset.lerp(_bases[0], end, t)!;
      } else if (t < .22) {
        ball = Offset.lerp(_mound, _bases[0], t / .22)!;
      } else if (contact) {
        var end = target();
        if (homer) end = Offset(end.dx, .02);
        final progress = ((t - .22) / .43).clamp(0.0, 1.0);
        ball = Offset.lerp(_bases[0], end, progress)!;
        if (fly) ball -= Offset(0, math.sin(progress * math.pi) * .24);
        if (ground) {
          ball -= Offset(0, math.sin(progress * math.pi * 5).abs() * .018);
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
        ball = _bases[0];
      }
      if (t < 1) {
        final p = _pixel(ball, size);
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
      for (final r in travels) {
        final progress = ((t - .22) / .78).clamp(0.0, 1.0) * (r.to - r.from);
        final base = (r.from + progress.floor()).clamp(0, 3);
        final p = Offset.lerp(
            _bases[base], _bases[base + 1], progress - progress.floor())!;
        canvas.drawCircle(
            _pixel(p, size), 7, Paint()..color = Colors.orangeAccent);
        canvas.drawCircle(
            _pixel(p, size),
            7,
            Paint()
              ..color = Colors.white
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_MotionPainter old) => old.t != t || old.f != f;
}
