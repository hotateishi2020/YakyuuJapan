import 'package:flutter/material.dart';

/// リーグ見出しの横に置くロゴ。
/// セ・パの画像は黒地の下にリーグ名が入っているので、上のマークだけを抜き出す。
class LeagueLogo extends StatelessWidget {
  final String asset;
  final double height;

  const LeagueLogo({super.key, required this.asset, required this.height});

  bool get _markOnly => asset.contains('k-central') || asset.contains('k-pacific');

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset,
      height: _markOnly ? height / 0.58 : height,
      fit: BoxFit.fitHeight,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    if (!_markOnly) return image;
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 0.58,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          1, 0, 0, 0, 0, //
          0, 1, 0, 0, 0, //
          0, 0, 1, 0, 0, //
          2.2, 0, 0, 0, -45,
        ]),
        child: image,
      ),
    );
  }
}
