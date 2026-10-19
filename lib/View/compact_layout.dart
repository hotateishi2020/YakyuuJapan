import 'package:flutter/material.dart';

bool compactBaseballLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width < 600 || size.height > size.width;
}
