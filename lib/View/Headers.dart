import 'package:flutter/material.dart';

class Headers {
  static Widget globalHeader(
    double h,
    Color color,
    String title,
    double padding_vertical,
    double padding_horizontal,
  ) {
    return Container(
      height: h,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFE10600), Color(0xFFFF9800)],
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: padding_horizontal, vertical: padding_vertical),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Image.asset(
          'backend/assets/images/logo_yakyuu_japan.png',
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          semanticLabel: title,
        ),
      ),
    );
  }
}
