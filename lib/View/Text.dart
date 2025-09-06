import 'package:flutter/material.dart';

class OneLineShrinkText extends StatelessWidget {
  final String text;
  final double baseSize;
  final double minSize;
  final FontWeight? weight;
  final TextAlign align;
  final Color? color;
  final double verticalPadding;
  final bool fast; // if true, use FittedBox(BoxFit.scaleDown)
  final List<Shadow>? shadows;

  const OneLineShrinkText(
    this.text, {
    super.key,
    this.baseSize = 12,
    this.minSize = 1,
    this.weight,
    this.align = TextAlign.center,
    this.color,
    this.verticalPadding = 0,
    this.fast = true,
    this.shadows,
  });

  Alignment _toAlignment(TextAlign a) {
    switch (a) {
      case TextAlign.left:
      case TextAlign.start:
        return Alignment.centerLeft;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.center:
      default:
        return Alignment.center;
    }
  }

  bool _fits(String t, double size, double maxW, double maxH) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, fontWeight: weight)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW.isFinite && maxW > 0 ? maxW : double.infinity);
    final w = tp.size.width;
    final h = tp.size.height;
    final okW = !(maxW.isFinite && maxW > 0) || w <= maxW + 0.5;
    final okH = !(maxH.isFinite && maxH > 0) || h <= maxH + 0.5;
    return okW && okH;
  }

  @override
  Widget build(BuildContext context) {
    if (fast) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding * 0.5),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: _toAlignment(align),
          child: Text(
            text.isNotEmpty ? text : '—',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: align,
            style: TextStyle(fontSize: baseSize, fontWeight: weight, color: color, shadows: shadows),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth;
      final maxH = constraints.maxHeight.isFinite ? (constraints.maxHeight - verticalPadding).clamp(0.0, constraints.maxHeight) : constraints.maxHeight;

      double lo = minSize;
      double hi = baseSize;
      double chosen = baseSize;

      if ((maxW.isFinite && maxW > 0) || (maxH.isFinite && maxH > 0)) {
        for (int i = 0; i < 12; i++) {
          final mid = (lo + hi) / 2;
          if (_fits(text, mid, maxW, maxH)) {
            chosen = mid;
            lo = mid;
          } else {
            hi = mid;
          }
        }
      }

      return Text(
        text.isNotEmpty ? text : '—',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        textAlign: align,
        style: TextStyle(fontSize: chosen, fontWeight: weight, color: color, shadows: shadows),
      );
    });
  }
}
