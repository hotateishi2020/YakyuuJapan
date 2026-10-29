import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../View/GamesBoard.dart';
import '../logic/postseason_bracket.dart';

/// Keeps the existing bracket geometry intact and adds the champion above its
/// final. Decorations cannot intercept taps on the bracket below.
class ChampionshipVictory extends StatefulWidget {
  const ChampionshipVictory({super.key, required this.champion,
    required this.width, required this.height, required this.finalTop,
    required this.title, required this.background, required this.child, this.mlb = false});
  final BracketTeam? champion;
  final double width, height, finalTop;
  final String title;
  final Gradient background;
  final bool mlb;
  final Widget child;

  static const headroom = 146.0;

  @override
  State<ChampionshipVictory> createState() => _ChampionshipVictoryState();
}

class _ChampionshipVictoryState extends State<ChampionshipVictory>
    with TickerProviderStateMixin {
  late final _rise = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final _fireworks = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));

  void _syncMotion() {
    final active = widget.champion != null && TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (active) {
      if (!_fireworks.isAnimating) _fireworks.repeat();
      if (_rise.value < 1 && !_rise.isAnimating) _rise.forward();
    } else {
      _fireworks.stop();
      _rise.stop();
      if (MediaQuery.disableAnimationsOf(context)) _rise.value = 1;
    }
  }

  @override
  void didChangeDependencies() { super.didChangeDependencies(); _syncMotion(); }

  @override
  void didUpdateWidget(covariant ChampionshipVictory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.champion?.id != widget.champion?.id) _rise.value = 0;
    _syncMotion();
  }

  @override
  void dispose() { _rise.dispose(); _fireworks.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final champion = widget.champion;
    if (champion == null) return widget.child;
    final visual = teamLogoVisual(champion.name, abbrev: champion.nameShortest, mlb: widget.mlb);
    final still = MediaQuery.disableAnimationsOf(context);
    return SizedBox(width: widget.width, height: widget.height + ChampionshipVictory.headroom,
      child: Stack(children: [
        Positioned.fill(child: DecoratedBox(key: const Key('champion-background'),
          decoration: BoxDecoration(gradient: widget.background))),
        Positioned(top: ChampionshipVictory.headroom, left: 0,
          width: widget.width, height: widget.height, child: widget.child),
        Positioned(left: widget.width / 2 - 3, top: 116, width: 6,
          height: ChampionshipVictory.headroom + widget.finalTop - 116,
          child: AnimatedBuilder(animation: _rise, builder: (_, __) => Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(heightFactor: Curves.easeOutCubic.transform(_rise.value),
              widthFactor: 1, child: const ColoredBox(key: Key('champion-advance-line'), color: Color(0xFFFFD600)))))),
        Positioned(left: widget.width / 2 - 240, top: 0, width: 480, height: 142,
          child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(
            key: const Key('champion-fireworks'),
            painter: _FireworksPainter(_fireworks, still: still))))),
        Positioned(top: 9, left: widget.width / 2 - 90, width: 180, height: 112,
          child: Semantics(label: '${widget.title} ${champion.name}', image: true,
            child: Column(children: [
              SizedBox(height: 18, child: FittedBox(fit: BoxFit.scaleDown,
                child: Text(widget.title, maxLines: 1, style: const TextStyle(color: Color(0xFFFFDE74),
                  fontSize: 15, letterSpacing: 2, fontWeight: FontWeight.w900)))),
              const SizedBox(height: 6),
              Container(key: ValueKey('champion-logo-${champion.id}'),
                width: 80, height: 80, padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFD56A), width: 3),
                  boxShadow: const [BoxShadow(color: Color(0x66FFD56A), blurRadius: 23)]),
                child: ExcludeSemantics(child: teamLogoImage(asset: visual.asset, networkUrl: visual.networkUrl))),
            ]))),
      ]));
  }
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter(this.animation, {required this.still}) : super(repaint: animation);
  final Animation<double> animation;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    const bursts = [(.15, .36, .00), (.83, .38, .48), (.30, .68, .72), (.69, .72, .24)];
    const colors = [Color(0xFFFFD66D), Color(0xFF9FEFFF), Color(0xFFFFA8CE), Color(0xFFFFFFFF)];
    for (var b = 0; b < bursts.length; b++) {
      final burst = bursts[b];
      final phase = still ? .48 : (animation.value + burst.$3) % 1;
      final origin = Offset(size.width * burst.$1, size.height * burst.$2);
      final launch = (phase / .22).clamp(0.0, 1.0);
      if (phase < .22) {
        final tip = Offset(origin.dx, size.height + (origin.dy - size.height) * launch);
        canvas.drawLine(tip + const Offset(0, 13), tip,
          Paint()..color = colors[b].withValues(alpha: .8)..strokeWidth = 1.6..strokeCap = StrokeCap.round);
        continue;
      }
      final progress = ((phase - .22) / .78).clamp(0.0, 1.0);
      final radius = 5 + 42 * Curves.easeOut.transform(progress);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      for (var ray = 0; ray < 18; ray++) {
        final angle = ray * math.pi * 2 / 18 + b * .17;
        final direction = Offset(math.cos(angle), math.sin(angle));
        final gravity = Offset(0, 12 * progress * progress);
        final tip = origin + direction * radius + gravity;
        canvas.drawLine(origin + direction * radius * .72 + gravity, tip,
          Paint()..color = colors[b].withValues(alpha: opacity)..strokeWidth = 1.8..strokeCap = StrokeCap.round);
        canvas.drawCircle(tip, 1.4, Paint()..color = Colors.white.withValues(alpha: opacity));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter oldDelegate) => oldDelegate.still != still || oldDelegate.animation != animation;
}
