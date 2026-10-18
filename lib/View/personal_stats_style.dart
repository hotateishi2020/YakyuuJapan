import 'package:flutter/material.dart';

Color? personalStatPositionColor(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text.contains('指') || text == 'DH') return const Color(0xFFECD5EF);
  if (text.contains('投')) return const Color(0xFFFFDEE2);
  if (text.contains('捕')) return const Color(0xFFCEEEFD);
  if (text.contains('外') || text == '左' || text == '中' || text == '右') {
    return const Color(0xFFC4E4C6);
  }
  if (text.contains('内') || text == '一' || text == '二' || text == '三' || text == '遊') {
    return const Color(0xFFFFF8BF);
  }
  return null;
}


const statsBattingGradDecoration = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFFEBF100),
      Color(0xFFF8941D),
      Color(0xFFF12C51),
    ],
    stops: [0.0, 0.5, 1.0],
  ),
);

/// 投手：左上の深い青→右下のシアン（添付イメージ）
const statsPitchingGradDecoration = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1A1AFF),
      Color(0xFF2E31FF),
      Color(0xFF0090FF),
      Color(0xFF00E5FF),
    ],
    stops: [0.0, 0.32, 0.68, 1.0],
  ),
);

