import 'package:flutter/material.dart';

Color battingResultColor(String kind, String label) {
  if (label.contains('併殺')) return Colors.black;
  if (label.contains('三振') || label.contains('振逃')) {
    return const Color(0xFF616161);
  }
  if (kind == 'fc' || label.contains('野選')) return const Color(0xFF9E9E9E);
  if (label.contains('邪') || label.contains('ポップ')) {
    return const Color(0xFF1E88E5);
  }
  if (label.contains('ゴロ') || label.contains('フライ') || label.contains('ライナー')) {
    return const Color(0xFF1E88E5);
  }
  return switch (kind) {
    'hr' ||
    'cycle' ||
    'cyclemis' ||
    'multihit' ||
    'allhit' ||
    'allreach' ||
    'perfect' ||
    'nohit' ||
    'maddux' ||
    'shutout' ||
    'cg' =>
      const Color(0xFFDC143C),
    'timely' || 'hqs' => const Color(0xFFFF5722),
    'triple' || 'double' || 'extra' || 'qs' => const Color(0xFFFFB300),
    'single' => const Color(0xFFFFEB3B),
    'walk' => const Color(0xFF43A047),
    'dead' =>
      label.contains('死球') ? const Color(0xFFE53935) : const Color(0xFF78909C),
    'error' => const Color(0xFF78909C),
    'sac' || 'sacfly' || 'squeeze' || 'sacbunt' => const Color(0xFF8E24AA),
    'k10' => const Color(0xFFDC143C),
    'steal' => const Color(0xFFC6FF00),
    'stealout' => const Color(0xFF757575),
    _ => const Color(0xFFEEEEEE),
  };
}

Color battingResultInk(String kind, String label) {
  if (kind == 'dead' && label.contains('死球')) return Colors.black;
  if (label.contains('併殺')) return const Color(0xFFE53935);
  return battingResultColor(kind, label).computeLuminance() > .45
      ? Colors.black87
      : Colors.white;
}
