import 'package:flutter/material.dart';

class Headers {
  static Widget globalHeader(double h, Color color, String title, double padding_vertical, double padding_horizontal) {
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: color,
      ),
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.only(left: padding_horizontal),
      child: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
