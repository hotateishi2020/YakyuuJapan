import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Captures Flutter's last painted application frame (not browser chrome).
class ErrorSnapshot {
  static final boundaryKey = GlobalKey();

  static Future<String?> capture() async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary ||
          !boundary.hasSize ||
          (kDebugMode && boundary.debugNeedsPaint)) {
        return null;
      }
      final longest = boundary.size.longestSide;
      if (longest <= 0) return null;
      final image = await boundary.toImage(
          pixelRatio: longest > 1280 ? 1280 / longest : 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null || data.lengthInBytes > 1500000) return null;
        return base64Encode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      } finally {
        image.dispose();
      }
    } catch (_) {
      // Logging must survive a failed render/capture.
      return null;
    }
  }
}
