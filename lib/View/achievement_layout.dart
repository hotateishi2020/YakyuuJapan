import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Place larger badges first. Reuse the earliest available gap in each row
/// before starting a new row, so small badges can fill space beside tall ones.
List<Rect> packAchievementBadges(List<double> sizes, double width) {
  if (sizes.isEmpty || width <= 0) return [];
  const gap = 2.0;
  final placed = <Rect>[];
  for (final requested in sizes) {
    final size = math.min(requested, width);
    final xs = {0.0, for (final rect in placed) rect.right + gap}.toList()
      ..sort();
    final ys = {0.0, for (final rect in placed) rect.bottom + gap}.toList()
      ..sort();
    Rect? target;
    for (final y in ys) {
      for (final x in xs) {
        if (x + size > width + .001) continue;
        final candidate = Rect.fromLTWH(x, y, size, size);
        if (placed.every((rect) => !candidate.overlaps(Rect.fromLTRB(
            rect.left - gap + .001,
            rect.top - gap + .001,
            rect.right + gap - .001,
            rect.bottom + gap - .001)))) {
          target = candidate;
          break;
        }
      }
      if (target != null) break;
    }
    placed.add(target ??
        Rect.fromLTWH(
            0,
            placed.fold<double>(0, (y, r) => math.max(y, r.bottom + gap)),
            size,
            size));
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
