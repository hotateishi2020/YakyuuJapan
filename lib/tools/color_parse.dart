import 'package:flutter/material.dart';

Color parseColorName(String? name, Color fallback) {
  return parseColorNameOrNull(name) ?? fallback;
}

Color? parseColorNameOrNull(String? name) {
  final n = (name ?? '').trim().toLowerCase();
  if (n.isEmpty || n == '—') return null;

  var hex = n;
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.startsWith('0x')) hex = hex.substring(2);
  if (hex.length == 3 && RegExp(r'^[0-9a-f]{3}$').hasMatch(hex)) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6 && RegExp(r'^[0-9a-f]{6}$').hasMatch(hex)) {
    final value = int.tryParse(hex, radix: 16);
    if (value != null) return Color(0xFF000000 | value);
  }
  if (hex.length == 8 && RegExp(r'^[0-9a-f]{8}$').hasMatch(hex)) {
    final value = int.tryParse(hex, radix: 16);
    if (value != null) return Color(value);
  }

  const m = {
    'red': 0xFFF44336,
    'orange': 0xFFFF9800,
    'yellow': 0xFFFFEB3B,
    'green': 0xFF4CAF50,
    'lightgreen': 0xFF8BC34A,
    'blue': 0xFF0000FF,
    'royalblue': 0xFF4169E1,
    'mediumblue': 0xFF0000CD,
    'midnightblue': 0xFF191970,
    'darkblue': 0xFF00008B,
    'dodgerblue': 0xFF1E90FF,
    'navy': 0xFF001F3F,
    'crimson': 0xFFDC143C,
    'gold': 0xFFFFD700,
    'lime': 0xFFCDDC39,
    'gray': 0xFF9E9E9E,
    'grey': 0xFF9E9E9E,
    'black': 0xFF000000,
    'white': 0xFFFFFFFF,
    'tomato': 0xFFFF6347,
    'firebrick': 0xFFB22222,
    'sienna': 0xFFA0522D,
    'khaki': 0xFFF0E68C,
    'lightyellow': 0xFFFFFFE0,
    'teal': 0xFF008080,
    'gainsboro': 0xFFDCDCDC,
    'darkgreen': 0xFF006400,
    'darkslateblue': 0xFF483D8B,
    'darkred': 0xFF8B0000,
    'lightskyblue': 0xFF87CEFA,
  };
  final v = m[n];
  return v == null ? null : Color(v);
}
