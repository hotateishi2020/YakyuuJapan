import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared loading scene. [progress] is a measured fraction; otherwise the
/// percentage is explicitly an estimate and never reaches 100 before completion.
class BaseballLoading extends StatefulWidget {
  const BaseballLoading(
      {super.key,
      this.progress,
      this.compact = false,
      this.color = const Color(0xFF214E78)});
  final double? progress;
  final bool compact;
  final Color color;

  @override
  State<BaseballLoading> createState() => _BaseballLoadingState();
}

class _BaseballLoadingState extends State<BaseballLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion =
      AnimationController(vsync: this, duration: const Duration(seconds: 5));
  Timer? _timer;
  int _seconds = 0;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.progress == null) setState(() => _seconds++);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _motion.stop();
    } else {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final measured = widget.progress;
    final percent = measured != null && measured.isFinite
        ? (measured.clamp(0.0, 1.0) * 100).floor()
        : (95 * (1 - math.exp(-_seconds / 18))).round();
    final estimated = measured == null || !measured.isFinite;
    return Semantics(
      label: '内野でボール回し',
      value: '${estimated ? '目安 ' : ''}$percent%',
      child: SizedBox(
          width: widget.compact ? 140 : 280,
          height: widget.compact ? 100 : 200,
          child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                  width: 280,
                  height: 200,
                  child: Column(children: [
                    Flexible(child: SizedBox(
                        width: 280,
                        height: 168,
                        child: CustomPaint(
                            painter: _InfieldPainter(
                                _motion, widget.color, _reduced)))),
                    ExcludeSemantics(
                        child: Text('${estimated ? '目安 ' : ''}$percent%',
                            key: const ValueKey('baseball-loading-percent'),
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color:
                                    Theme.of(context).colorScheme.onSurface))),
                  ])))),
    );
  }
}

class _InfieldPainter extends CustomPainter {
  _InfieldPainter(this.motion, this.uniform, this.reduced)
      : super(repaint: motion);
  final Animation<double> motion;
  final Color uniform;
  final bool reduced;
  static const players = [
    Offset(140, 35),
    Offset(225, 91),
    Offset(140, 142),
    Offset(55, 91)
  ];
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 280, size.height / 168);
    final paint = Paint()..isAntiAlias = true;
    void oval(Rect rect, Color color) =>
        canvas.drawOval(rect, paint..color = color);
    final diamond = Path()
      ..moveTo(140, 20)
      ..lineTo(252, 91)
      ..lineTo(140, 162)
      ..lineTo(28, 91)
      ..close();
    canvas.drawPath(diamond, paint..color = const Color(0xFFB9D9B0));
    final dirt = Path()
      ..moveTo(140, 40)
      ..lineTo(222, 91)
      ..lineTo(140, 144)
      ..lineTo(58, 91)
      ..close();
    canvas.drawPath(dirt, paint..color = const Color(0xFFEACB97));
    canvas.drawPath(
        dirt,
        Paint()
          ..color = Colors.white.withValues(alpha: .8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    oval(const Rect.fromLTWH(124, 82, 32, 18), const Color(0xFFF7E0B9));
    canvas.drawLine(
        const Offset(134, 91),
        const Offset(146, 91),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 3);
    final turn = motion.value * 4;
    final from = turn.floor() % 4, to = (from + 1) % 4;
    final phase = turn % 1;
    for (var i = 0; i < players.length; i++) {
      final p = players[i];
      oval(
          Rect.fromCenter(
              center: p + const Offset(0, 15), width: 34, height: 9),
          Colors.black.withValues(alpha: .12));
      final bounce =
          reduced ? 0.0 : (i == to ? math.sin(phase * math.pi) * 2 : 0.0);
      canvas.save();
      canvas.translate(p.dx, p.dy - bounce);
      // Oversized head, round body and short limbs: an original toy-like player.
      final dark = uniform.withValues(alpha: 1);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(-12, -1, 24, 19), const Radius.circular(8)),
          paint..color = Colors.white);
      canvas.drawLine(
          const Offset(0, 1),
          const Offset(0, 13),
          Paint()
            ..color = dark
            ..strokeWidth = 2);
      oval(const Rect.fromLTWH(-13, 12, 12, 7), dark);
      oval(const Rect.fromLTWH(2, 12, 12, 7), dark);
      oval(const Rect.fromLTWH(-17, -28, 34, 31), const Color(0xFFFFD5AD));
      canvas.drawArc(const Rect.fromLTWH(-18, -32, 36, 31), math.pi, math.pi,
          true, paint..color = dark);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(-19, -18, 39, 6), const Radius.circular(3)),
          paint..color = dark);
      oval(const Rect.fromLTWH(-8, -10, 3, 4), const Color(0xFF273444));
      oval(const Rect.fromLTWH(5, -10, 3, 4), const Color(0xFF273444));
      canvas.drawArc(
          const Rect.fromLTWH(-4, -6, 8, 7),
          .2,
          2.7,
          false,
          Paint()
            ..color = const Color(0xFFB16C4C)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      final reach = i == to || i == from ? math.sin(phase * math.pi) * 5 : 0.0;
      oval(Rect.fromLTWH(-22, -1 - reach, 13, 13), const Color(0xFFAC6F39));
      canvas.drawLine(
          Offset(-19, 2 - reach),
          Offset(-14, 8 - reach),
          Paint()
            ..color = const Color(0xFF744822)
            ..strokeWidth = 1.4);
      oval(Rect.fromLTWH(10, 0 - reach, 10, 10), const Color(0xFFFFD5AD));
      canvas.restore();
    }
    final t = Curves.easeInOut.transform(phase);
    final ball = Offset.lerp(players[from], players[to], t)! +
        Offset(0, -12 - math.sin(t * math.pi) * 28);
    oval(
        Rect.fromCenter(
            center: ball + const Offset(0, 18), width: 10, height: 4),
        Colors.black.withValues(alpha: .12));
    canvas.drawCircle(ball, 5.5, Paint()..color = const Color(0xFF607D8B));
    canvas.drawCircle(ball, 4.5, Paint()..color = Colors.white);
    canvas.drawArc(
        Rect.fromCircle(center: ball + const Offset(-3, 0), radius: 3),
        -.9,
        1.8,
        false,
        Paint()
          ..color = const Color(0xFFD8544D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InfieldPainter old) =>
      old.uniform != uniform || old.reduced != reduced;
}
