import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fits one top-to-bottom line of text without reducing it below [minFontSize].
///
/// Each grapheme stays together, including combining marks and joined emoji.
/// The caller provides the complete label's tooltip and semantics.
class StrengthVerticalLabel extends StatelessWidget {
  const StrengthVerticalLabel(
    this.text, {
    super.key,
    required this.style,
    this.minFontSize = 10,
    this.maxFontSize = 12,
    this.textScaler,
  })  : assert(minFontSize > 0),
        assert(maxFontSize >= minFontSize);

  final String text;
  final TextStyle style;
  final double minFontSize;
  final double maxFontSize;
  final TextScaler? textScaler;

  // Opening brackets face down and closing brackets face up in vertical text.
  // Rotate the original glyph rather than replacing long vowels with a pipe.
  static const _rotatedGlyphs = <String>{
    'ー',
    'ｰ',
    '―',
    '—',
    '–',
    '−',
    '‐',
    '‑',
    '－',
    '-',
    '…',
    '‥',
    '(',
    ')',
    '（',
    '）',
    '[',
    ']',
    '［',
    '］',
    '{',
    '}',
    '｛',
    '｝',
    '「',
    '」',
    '『',
    '』',
    '｢',
    '｣',
    '【',
    '】',
    '〔',
    '〕',
    '〈',
    '〉',
    '《',
    '》',
    '｟',
    '｠',
  };

  @override
  Widget build(BuildContext context) {
    final glyphs = text.characters.toList(growable: false);
    if (glyphs.isEmpty) return const SizedBox.shrink();
    final inheritedStyle = DefaultTextStyle.of(context).style.merge(style);
    final scaler = textScaler ?? MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    return LayoutBuilder(builder: (context, constraints) {
      var fontSize = maxFontSize;
      while (true) {
        final fittedStyle = inheritedStyle.copyWith(fontSize: fontSize);
        final measurements = <Size>[];
        var width = 0.0;
        var height = 0.0;
        for (final glyph in glyphs) {
          final painter = TextPainter(
            text: TextSpan(text: glyph, style: fittedStyle),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          // A glyph's advance can be narrower than its visible ink, especially
          // while Flutter web switches from a fallback to a Japanese font.
          // Give each glyph a full, rounded-up character cell so that a narrow
          // advance or fractional layout width cannot clip part of a kanji.
          final extent = math
              .max(scaler.scale(fontSize),
                  math.max(painter.width, painter.height))
              .ceilToDouble();
          final size = Size.square(extent);
          measurements.add(size);
          width = math.max(width, size.width);
          height += size.height;
          painter.dispose();
        }

        if (width <= constraints.maxWidth && height <= constraints.maxHeight) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < glyphs.length; i++)
                SizedBox(
                  width: measurements[i].width,
                  height: measurements[i].height,
                  child: RotatedBox(
                    quarterTurns: _rotatedGlyphs.contains(glyphs[i]) ? 1 : 0,
                    child: Center(
                      child: Text(
                        glyphs[i],
                        style: fittedStyle,
                        textScaler: scaler,
                        textDirection: direction,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ),
                ),
            ]),
          );
        }
        if (fontSize == minFontSize) return const SizedBox.shrink();
        fontSize = math.max(minFontSize, fontSize - 0.5);
      }
    });
  }
}
