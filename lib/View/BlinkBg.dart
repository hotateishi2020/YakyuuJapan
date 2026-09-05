import 'package:flutter/material.dart';

// 背景のみをやさしく点滅させる（テキストは前面で固定）
class BlinkBg extends StatefulWidget {
  final Widget child;
  final BoxDecoration base;
  final Color color;
  final double radius;
  final Duration duration;

  const BlinkBg({
    super.key,
    required this.child,
    required this.base,
    required this.color,
    this.radius = 4,
    this.duration = const Duration(milliseconds: 1000),
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
        final double a = (0.12 + 0.23 * _t.value).clamp(0.0, 1.0);
        return Stack(children: [
          Positioned.fill(child: Container(decoration: widget.base)),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: widget.color.withOpacity(a),
                borderRadius: BorderRadius.circular(widget.radius),
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
