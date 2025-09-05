import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class Env {
  static const _apiBaseFromDefine = String.fromEnvironment('API_BASE');

  static String baseUrl() {
    if (_apiBaseFromDefine.isNotEmpty) return _apiBaseFromDefine;

    const isProd = bool.fromEnvironment('dart.vm.product');

    if (kIsWeb) {
      // 本番(Web/Render)は同一オリジン、デバッグ(Web)はローカルAPI
      return isProd ? '' : 'http://127.0.0.1:8080';
    }
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8080';
      if (Platform.isIOS || Platform.isMacOS) return 'http://127.0.0.1:8080';
      if (Platform.isWindows || Platform.isLinux) return 'http://127.0.0.1:8080';
    } catch (_) {}
    return 'http://127.0.0.1:8080';
  }

  static Uri api(String path) {
    final base = baseUrl();
    return base.isEmpty ? Uri.parse(path) : Uri.parse('$base$path');
  }
}
