import 'package:flutter/material.dart';

/// ヘッダー用の点滅 New バッジ。
class BlinkNewMark extends StatefulWidget {
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const BlinkNewMark({
    super.key,
    this.fontSize = 10,
    this.padding = const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
  });

  @override
  State<BlinkNewMark> createState() => _BlinkNewMarkState();
}

class _BlinkNewMarkState extends State<BlinkNewMark> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.25, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'New',
          style: TextStyle(
            color: Colors.white,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
