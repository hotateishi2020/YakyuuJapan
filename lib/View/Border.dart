import 'package:flutter/material.dart';

// 枠色がゆっくり点滅するラッパー
class BlinkBorder extends StatefulWidget {
  final Widget child;
  final Color color;
  final double radius;
  final double width;
  final Duration duration;
  final Color? baseBgColor;
  final bool fillUseColor; // true: 背景も color で点滅、false: baseBg とブレンド

  const BlinkBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = 3,
    this.width = 2,
    this.duration = const Duration(milliseconds: 1000),
    this.baseBgColor,
    this.fillUseColor = true,
  });

  @override
  State<BlinkBorder> createState() => _BlinkBorderState();
}

class _BlinkBorderState extends State<BlinkBorder> with SingleTickerProviderStateMixin {
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
        final alpha = (0.35 + 0.45 * _t.value).clamp(0.0, 1.0);
        Color? bg;
        Color? overlay;
        if (widget.fillUseColor) {
          // 前面に半透明オーバーレイを重ねる（子の背景の上に載る）
          final double bgAlpha = (0.12 + 0.23 * _t.value).clamp(0.0, 1.0);
          overlay = widget.color.withOpacity(bgAlpha);
          bg = null;
        } else if (widget.baseBgColor != null) {
          // 背景色そのものをブレンド（子の背景として使う）
          final double mix = (0.35 * _t.value).clamp(0.0, 1.0);
          bg = Color.lerp(widget.baseBgColor!, widget.color, mix);
          overlay = null;
        } else {
          bg = null;
          overlay = null;
        }
        return Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: widget.color.withOpacity(alpha), width: widget.width),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          foregroundDecoration: overlay != null
              ? BoxDecoration(
                  color: overlay,
                  borderRadius: BorderRadius.circular(widget.radius),
                )
              : null,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
