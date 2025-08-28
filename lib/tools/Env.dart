import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class Env {
  static String baseUrl() {
    // 本番用 API（Render / Railway / CloudRun などにデプロイしたバックエンドのURL）
    const prodUrl = "https://your-api-service.onrender.com";

    // デバッグ環境かどうかを判定
    const bool isProd = bool.fromEnvironment('dart.vm.product');

    if (isProd) {
      // Flutter build --release の時 → 本番 API
      return prodUrl;
    } else {
      // デバッグ実行中
      if (kIsWeb) {
        return "http://127.0.0.1:5050";
      }
      try {
        if (Platform.isAndroid) return "http://10.0.2.2:5050"; // Android エミュ
        if (Platform.isIOS || Platform.isMacOS) return "http://127.0.0.1:5050";
        if (Platform.isWindows || Platform.isLinux)
          return "http://127.0.0.1:5050";
      } catch (_) {}
      return "http://127.0.0.1:5050"; // fallback
    }
  }
}
