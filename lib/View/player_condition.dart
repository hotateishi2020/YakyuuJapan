import 'package:flutter/material.dart';

class PlayerHandBadge extends StatelessWidget {
  const PlayerHandBadge({super.key, required this.hand, required this.size});
  final String hand;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: hand == '右' ? Colors.black : Colors.white,
          border: Border.all(color: Colors.black54),
          borderRadius: BorderRadius.circular(2)),
      child: Text(hand.isEmpty ? '—' : hand,
          style: TextStyle(
              fontSize: size * .75,
              height: 1,
              color: hand == '右' ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold)));
}

class PlayerConditionFace extends StatelessWidget {
  const PlayerConditionFace(
      {super.key, required this.level, required this.size});
  final int? level;
  final double size;
  static Color colorFor(int? level) => switch (level) {
        2 => const Color(0xFFFF80AB),
        1 => const Color(0xFFEF5350),
        0 => const Color(0xFFFFEB3B),
        -1 => const Color(0xFF81D4FA),
        -2 => const Color(0xFF7E57C2),
        _ => const Color(0xFFFFEB3B),
      };
  @override
  Widget build(BuildContext context) => SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
          decoration:
              BoxDecoration(color: colorFor(level), shape: BoxShape.circle),
          child: Icon(
              switch (level) {
                2 => Icons.sentiment_very_satisfied,
                1 => Icons.sentiment_satisfied,
                0 => Icons.sentiment_neutral,
                -1 => Icons.sentiment_dissatisfied,
                -2 => Icons.sentiment_very_dissatisfied,
                _ => Icons.sentiment_neutral
              },
              size: size,
              color: Colors.black)));
}
