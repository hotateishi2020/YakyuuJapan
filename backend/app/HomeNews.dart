import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Only headlines and article links from the public sports feed are retained.
class HomeNews {
  static final feed = Uri.parse('https://news.yahoo.co.jp/rss/categories/sports.xml');
  static List<Map<String, dynamic>> _cached = [];
  static DateTime? _checkedAt;
  static bool _failed = false;
  static Future<Map<String, dynamic>>? _inflight;

  static String? category(String title) {
    if (RegExp('高校野球|甲子園|センバツ|選抜高校|秋季大会|選手権大会.*野球').hasMatch(title)) return '高校野球';
    if (RegExp(r'MLB|大リーグ|メジャーリーグ|大谷|山本由伸|ダルビッシュ|今永|菊池雄星|鈴木誠也|吉田正尚|千賀滉大|佐々木朗希|ドジャース|ヤンキース|メッツ|パドレス|カブス|エンゼルス|ワールドシリーズ', caseSensitive: false).hasMatch(title)) return 'MLB';
    if (RegExp(r'NPB|プロ野球|巨人|阪神|タイガース|DeNA|ベイスターズ|ヤクルト|スワローズ|中日.*(?:選手|投手|監督|ドラゴンズ)|ドラゴンズ|広島.*(?:選手|投手|監督|カープ)|カープ|ソフトバンク|ホークス|日本ハム|ファイターズ|ロッテ|マリーンズ|オリックス|バファローズ|西武|ライオンズ|楽天.*(?:選手|投手|監督|イーグルス)|イーグルス|日本シリーズ', caseSensitive: false).hasMatch(title)) return 'NPB';
    if (RegExp(r'野球|ドラフト|本塁打|ホームラン|安打|奪三振|投手|打者|打率|侍ジャパン|Full-Count|ベースボール', caseSensitive: false).hasMatch(title)) return '野球';
    return null;
  }

  static List<Map<String, dynamic>> parse(String source) {
    final document = XmlDocument.parse(source);
    if (document.rootElement.name.local != 'rss') throw const FormatException('Invalid RSS');
    final seen = <String>{};
    final articles = <Map<String, dynamic>>[];
    for (final item in document.findAllElements('item')) {
      final title = item.getElement('title')?.innerText.trim() ?? '';
      final url = item.getElement('link')?.innerText.trim() ?? '';
      final uri = Uri.tryParse(url);
      final group = category(title);
      if (title.isEmpty || group == null || uri == null || uri.scheme != 'https' || uri.host != 'news.yahoo.co.jp' || uri.userInfo.isNotEmpty || !RegExp(r'^/articles/[a-zA-Z0-9]+$').hasMatch(uri.path) || !seen.add(uri.path)) {
        continue;
      }
      articles.add({'title': title, 'url': url, 'category': group, 'source': 'Yahoo!ニュース', 'published_at': item.getElement('pubDate')?.innerText ?? ''});
    }
    return articles.take(30).toList();
  }

  static Map<String, dynamic> _result() => {'articles': _cached, 'news_failed': _failed};

  static Future<Map<String, dynamic>> read() {
    if (_checkedAt != null && DateTime.now().difference(_checkedAt!) < const Duration(minutes: 5)) {
      return Future.value(_result());
    }
    return _inflight ??= _refresh().whenComplete(() => _inflight = null);
  }

  static Future<Map<String, dynamic>> _refresh() async {
    final client = http.Client();
    try {
      final response = await client.get(feed).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw const FormatException('RSS request failed');
      _cached = parse(utf8.decode(response.bodyBytes));
      _failed = false;
    } catch (_) {
      _failed = true;
    } finally {
      client.close();
      _checkedAt = DateTime.now();
    }
    return _result();
  }
}
