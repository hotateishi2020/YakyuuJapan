import 'package:flutter/material.dart';

// 背景と枠線を点滅させる（テキストは前面で固定）
class BlinkBg extends StatefulWidget {
  final Widget child;
  final BoxDecoration base;
  final Color color;
  final double radius;
  final Duration duration;
  final double fillMin;
  final double fillMax;
  final Color borderColor;
  final double borderWidth;

  const BlinkBg({
    super.key,
    required this.child,
    required this.base,
    required this.color,
    this.radius = 4,
    this.duration = const Duration(milliseconds: 1000),
    this.fillMin = 0,
    this.fillMax = 0.85,
    this.borderColor = Colors.orange,
    this.borderWidth = 1,
  });

  @override
  State<BlinkBg> createState() => _BlinkBgState();
}

class _BlinkBgState extends State<BlinkBg> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final span = (widget.fillMax - widget.fillMin).clamp(0.0, 1.0);
        final double backgroundAlpha = (widget.fillMin + span * _t.value).clamp(0.0, 1.0);
        final double borderAlpha = (widget.fillMin + (1 - widget.fillMin) * _t.value).clamp(0.0, 1.0);
        return Stack(children: [
          Positioned.fill(child: Container(decoration: widget.base)),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: backgroundAlpha),
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(
                  color: widget.borderColor.withValues(alpha: borderAlpha),
                  width: widget.borderWidth,
                ),
              ),
            ),
          ),
          child!,
        ]);
      },
      child: widget.child,
    );
  }
}
