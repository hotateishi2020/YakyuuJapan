import 'package:flutter/material.dart';

/// Compact baseball glove with its cumulative Golden Glove award count.
class GoldenGloveBadge extends StatelessWidget {
  const GoldenGloveBadge({super.key, required this.count});
  final int count;
  static double widthFor(int count) => 19 + '$count'.length * 5.0;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'ゴールデングラブ賞 $count回',
        child: Semantics(
          label: 'ゴールデングラブ賞 $count回',
          child: SizedBox(
            width: widthFor(count),
            height: 19,
            child: Stack(children: [
              const Positioned(left: 1, bottom: 0,
                  child: CustomPaint(size: Size(17, 16), painter: _GlovePainter())),
              Positioned(right: 0, top: 0, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: const Color(0xffffdf70),
                  border: Border.all(color: const Color(0xff936300), width: .6),
                  borderRadius: BorderRadius.circular(5)),
                child: Text('$count', textScaler: TextScaler.noScaling,
                  style: const TextStyle(fontSize: 8, height: 1.1,
                    fontWeight: FontWeight.w800, color: Color(0xff513500))),
              )),
            ]),
          ),
        ),
      );
}

class _GlovePainter extends CustomPainter {
  const _GlovePainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 20, size.height / 20);
    final outline = Path()
      ..moveTo(5, 18)..quadraticBezierTo(1, 14, 1, 9)
      ..quadraticBezierTo(1, 6, 3, 7)..lineTo(6, 11)
      ..lineTo(5, 4)..quadraticBezierTo(5, 1, 7, 2)..lineTo(9, 9)
      ..lineTo(8, 2)..quadraticBezierTo(9, -1, 11, 2)..lineTo(12, 9)
      ..lineTo(12, 2)..quadraticBezierTo(14, 0, 15, 3)..lineTo(15, 10)
      ..lineTo(16, 5)..quadraticBezierTo(18, 3, 19, 6)
      ..lineTo(18, 14)..quadraticBezierTo(16, 20, 10, 19)..close();
    canvas.drawPath(outline, Paint()..color = const Color(0xffffc72c));
    final seam = Paint()..color = const Color(0xff996515)
      ..style = PaintingStyle.stroke..strokeWidth = .9;
    canvas.drawPath(outline, seam);
    canvas.drawPath(Path()..moveTo(6, 12)..quadraticBezierTo(12, 8, 16, 12)
      ..quadraticBezierTo(14, 17, 8, 16)..close(), seam);
    canvas.restore();
  }
  @override
  bool shouldRepaint(_GlovePainter oldDelegate) => false;
}
