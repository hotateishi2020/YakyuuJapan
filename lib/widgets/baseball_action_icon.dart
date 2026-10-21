import 'package:flutter/material.dart';

/// Compact silhouettes for the batting and pitching selectors.
class BaseballActionIcon extends StatelessWidget {
  const BaseballActionIcon({super.key, required this.pitching, required this.color});

  final bool pitching;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(
          size: const Size(24, 24),
          painter: _BaseballActionPainter(pitching, color),
        ),
      );
}

class _BaseballActionPainter extends CustomPainter {
  const _BaseballActionPainter(this.pitching, this.color);
  final bool pitching;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void limb(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, stroke);
    }

    if (pitching) {
      // Overarm release, forward stride, and a trailing leg.
      canvas.drawCircle(const Offset(12, 5), 2, fill);
      limb([const Offset(11, 9), const Offset(9, 14)]);
      limb([const Offset(11, 9), const Offset(15, 8), const Offset(17, 3)]);
      limb([const Offset(11, 9), const Offset(7, 10), const Offset(5, 7)]);
      limb([const Offset(9, 14), const Offset(14, 16), const Offset(18, 21)]);
      limb([const Offset(9, 14), const Offset(6, 19), const Offset(2, 20)]);
      canvas.drawCircle(const Offset(21, 2), 1.3, fill);
    } else {
      // Rotated torso and extended arms with a distinct, long swinging bat.
      canvas.drawCircle(const Offset(8, 5), 2, fill);
      limb([const Offset(9, 9), const Offset(11, 14)]);
      limb([const Offset(9, 9), const Offset(13, 11), const Offset(17, 8)]);
      limb([const Offset(8, 10), const Offset(12, 13), const Offset(17, 8)]);
      limb([const Offset(11, 14), const Offset(7, 18), const Offset(4, 22)]);
      limb([const Offset(11, 14), const Offset(15, 18), const Offset(19, 21)]);
      canvas.drawLine(const Offset(16, 9), const Offset(22, 2), stroke..strokeWidth = 2);
      canvas.drawArc(const Rect.fromLTWH(13, 1, 10, 12), 0.1, 1.1, false,
          stroke..strokeWidth = 1);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BaseballActionPainter oldDelegate) =>
      oldDelegate.pitching != pitching || oldDelegate.color != color;
}
