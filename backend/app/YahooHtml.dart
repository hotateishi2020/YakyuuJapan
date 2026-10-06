import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

/// Yahoo 野球ページ共通の HTML 取得・デコード。
class YahooHtml {
  static Future<Document> fetchDocument(Uri url) async {
    final res = await http.get(url, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} for $url');
    }
    return parse(decode(res));
  }

  static String decode(http.Response res) {
    final bytes = res.bodyBytes;
    String? charset;
    final ct = res.headers['content-type'] ?? res.headers['Content-Type'];
    if (ct != null) {
      final m = RegExp(r'charset=([A-Za-z0-9_\-]+)', caseSensitive: false).firstMatch(ct);
      if (m != null) charset = m.group(1)?.toLowerCase();
    }
    charset ??= _detectCharsetFromMeta(bytes);
    if (charset == null || charset.contains('utf')) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return latin1.decode(bytes, allowInvalid: true);
  }

  static String? _detectCharsetFromMeta(Uint8List bytes) {
    final headLen = min(bytes.length, 4096);
    final head = latin1.decode(bytes.sublist(0, headLen), allowInvalid: true);
    final m = RegExp(r'charset\s*=\s*([A-Za-z0-9_\-]+)', caseSensitive: false).firstMatch(head);
    return m?.group(1)?.toLowerCase();
  }
}
