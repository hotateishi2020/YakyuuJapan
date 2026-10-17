import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Preserve award order so repeated honors remain adjacent across rows.
List<Rect> packAchievementBadges(List<double> sizes, double width) {
  if (sizes.isEmpty || width <= 0) return [];
  const gap = 2.0;
  final placed = <Rect>[];
  double x = 0, y = 0, rowHeight = 0;
  for (final requested in sizes) {
    final size = math.min(requested, width);
    if (x > 0 && x + size > width) {
      x = 0;
      y += rowHeight + gap;
      rowHeight = 0;
    }
    placed.add(Rect.fromLTWH(x, y, size, size));
    x += size + gap;
    rowHeight = math.max(rowHeight, size);
  }
  return placed;
}

class AchievementLayout extends StatelessWidget {
  const AchievementLayout(
      {super.key, required this.sizes, required this.children});
  final List<double> sizes;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final rects = packAchievementBadges(sizes, constraints.maxWidth);
        final height =
            rects.fold<double>(0, (h, rect) => math.max(h, rect.bottom));
        return SizedBox(
            height: height,
            child: Stack(children: [
              for (var i = 0; i < rects.length; i++)
                Positioned.fromRect(rect: rects[i], child: children[i]),
            ]));
      });
}
