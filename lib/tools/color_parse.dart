import 'package:flutter/material.dart';

Color parseColorName(String? name, Color fallback) {
  final n = (name ?? '').toLowerCase().trim();
  const m = {
    'red': 0xFFF44336,
    'green': 0xFF4CAF50,
    'blue': 0xFF0000FF,
    'navy': 0xFF001F3F,
    'royalblue': 0xFF4169E1,
    'orange': 0xFFFF9800,
    'yellow': 0xFFFFEB3B,
    'gold': 0xFFFFD700,
    'lime': 0xFFCDDC39,
    'black': 0xFF000000,
    'gray': 0xFF9E9E9E,
    'grey': 0xFF9E9E9E,
    'crimson': 0xFFDC143C,
    'lightgreen': 0xFF8BC34A,
    'white': 0xFFFFFFFF,
  };
  if (m.containsKey(n)) return Color(m[n]!);
  return fallback;
}

Color? parseColorNameOrNull(String? name) {
  final n = (name ?? '').trim().toLowerCase();
  if (n.isEmpty) return null;
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
  };
  final v = m[n];
  return v == null ? null : Color(v);
}
