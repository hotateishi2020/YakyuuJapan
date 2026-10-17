import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Fill the highest available space first, keeping child indices unchanged.
List<Rect> packAchievementBadges(List<double> sizes, double width) {
  if (sizes.isEmpty || width <= 0) return [];
  const gap = 2.0;
  final height = sizes.fold<double>(0, (sum, size) => sum + math.min(size, width) + gap);
  var free = [Rect.fromLTWH(0, 0, width + gap, height)];
  final placed = <Rect>[];
  for (final requested in sizes) {
    final size = math.min(requested, width);
    final extent = size + gap;
    final available = free.where((r) => r.width >= extent && r.height >= extent).toList()
      ..sort((a, b) {
        final row = a.top.compareTo(b.top);
        return row != 0 ? row : a.left.compareTo(b.left);
      });
    final space = available.first;
    final occupied = Rect.fromLTWH(space.left, space.top, extent, extent);
    placed.add(Rect.fromLTWH(space.left, space.top, size, size));
    final remaining = <Rect>[];
    for (final rect in free) {
      if (!rect.overlaps(occupied)) {
        remaining.add(rect);
        continue;
      }
      if (occupied.left > rect.left) remaining.add(Rect.fromLTRB(rect.left, rect.top, occupied.left, rect.bottom));
      if (occupied.right < rect.right) remaining.add(Rect.fromLTRB(occupied.right, rect.top, rect.right, rect.bottom));
      if (occupied.top > rect.top) remaining.add(Rect.fromLTRB(rect.left, rect.top, rect.right, occupied.top));
      if (occupied.bottom < rect.bottom) remaining.add(Rect.fromLTRB(rect.left, occupied.bottom, rect.right, rect.bottom));
    }
    // Overlapping free rectangles are useful; contained ones are redundant.
    free = remaining.toSet().where((r) => !remaining.any((other) =>
      other != r && other.left <= r.left && other.top <= r.top &&
      other.right >= r.right && other.bottom >= r.bottom)).toList();
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
