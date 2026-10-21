import 'package:flutter/material.dart';

Color? personalStatPositionColor(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text.contains('指') || text == 'DH') return const Color(0xFFF3E4F5);
  if (text.contains('投')) return const Color(0xFFFFEAEC);
  if (text.contains('捕')) return const Color(0xFFDFF4FE);
  if (text.contains('外') || text == '左' || text == '中' || text == '右') {
    return const Color(0xFFD9EDDA);
  }
  if (text.contains('内') || text == '一' || text == '二' || text == '三' || text == '遊') {
    return const Color(0xFFFFFAD5);
  }
  return null;
}


/// 個人成績のヘッダー色：野手は彩度を抑えたクリムゾン、投手は藍色。
const statsBattingHeaderColor = Color(0xFFB3445B);
const statsBattingTabColor = Color(0xFFDC143C);
const statsPitchingHeaderColor = Color(0xFF165E83);

const statsBattingHeaderDecoration = BoxDecoration(color: statsBattingHeaderColor);
const statsPitchingHeaderDecoration = BoxDecoration(color: statsPitchingHeaderColor);
