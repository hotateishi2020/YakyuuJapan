import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';

/// 操作ログとエラーログの共通項目。画面の列と `txt_detail` の中身を揃える。
class LogDetail {
  static const userOperation = '操作';
  static const serverProcess = 'サーバー処理';
  static const browserProcess = 'ブラウザ処理';

  static const clientActions = {
    '初期表示を読み込んだ', '予想タブを開いた',
    'npbタブを開いた', 'mlbタブを開いた',
    '試合情報タブを開いた', 'チーム順位タブを開いた', '個人成績タブを開いた',
    '戦力タブを開いた', '記録タブを開いた', '日程タブを開いた',
    '動画タブを開いた', '日本人タブを開いた', 'タイトルタブを開いた',
    'news・イベント日程ポップアップを開いた', '年度を変更した',
    'アカウント設定のプルダウンを開いた',
  };

  static String clientActionType(String action) =>
      action == '初期表示を読み込んだ' ? browserProcess : userOperation;

  /// Data reads are browser processing; clicks are recorded by /client/action.
  /// Write endpoints represent user submissions, except automatic notifications.
  static String accessType(Request request, {required bool scheduled}) {
    if (scheduled) return serverProcess;
    if (const {'GET', 'HEAD', 'OPTIONS'}.contains(request.method) ||
        const {'/predictions/ready', '/auth/mark-read'}.contains(request.requestedUri.path)) {
      return browserProcess;
    }
    return userOperation;
  }

  static Map<String, String> clientInfo(Request request) {
    final ua = clip(request.headers['user-agent'] ?? '', 1000);
    final lower = ua.toLowerCase();
    var browser = '不明';
    for (final entry in <String, String>{
      'edg/': 'Edge', 'edgios/': 'Edge', 'edga/': 'Edge',
      'opr/': 'Opera', 'samsungbrowser/': 'Samsung Internet',
      'firefox/': 'Firefox', 'fxios/': 'Firefox',
      'chrome/': 'Chrome', 'crios/': 'Chrome', 'safari/': 'Safari',
    }.entries) {
      if (lower.contains(entry.key)) { browser = entry.value; break; }
    }
    final device = lower.contains('ipad') || (lower.contains('android') && !lower.contains('mobile'))
        ? 'タブレット'
        : lower.contains('mobile') || lower.contains('iphone') || request.headers['sec-ch-ua-mobile'] == '?1'
            ? '携帯' : RegExp(r'windows|macintosh|x11|cros').hasMatch(lower) ? 'PC' : '不明';
    final connection = request.context['shelf.io.connection_info'];
    final forwarded = (request.headers['x-forwarded-for'] ?? '').split(',').first.trim();
    final ip = InternetAddress.tryParse(forwarded)?.address ??
        (connection is HttpConnectionInfo ? connection.remoteAddress.address : '');
    return {'ip_address': ip, 'browser': browser, 'device_type': device, 'user_agent': ua};
  }

  /// ログの発生日時。UTC でもローカルでも、表示は日本時間の壁時計にする。
  static String formatJst(Object? value) {
    final parsed = value is DateTime ? value : DateTime.tryParse('${value ?? ''}'.trim());
    if (parsed == null) return '${value ?? ''}'.trim();
    final jst = parsed.toUtc().add(const Duration(hours: 9));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${jst.year}-${two(jst.month)}-${two(jst.day)} ${two(jst.hour)}:${two(jst.minute)}:${two(jst.second)}';
  }

  static String clip(String value, int max) {
    final text = value.trim();
    if (text.length <= max) return text;
    return text.substring(0, max);
  }

  static String errorCode(Object error) {
    try {
      final code = (error as dynamic).code;
      if (code != null && '$code'.trim().isNotEmpty) return clip('$code', 40);
    } catch (_) {}
    return '';
  }

  static Map<String, String> stackFrame(String stack) {
    final named = RegExp(r'#0\s+([^\s(]+).*?([A-Za-z0-9_./\\-]+\.dart):(\d+)').firstMatch(stack);
    if (named != null) {
      return {
        'function_name': named.group(1) ?? '',
        'file_name': _fileOnly(named.group(2) ?? ''),
        'line_number': named.group(3) ?? '',
      };
    }
    final plain = RegExp(r'([A-Za-z0-9_./\\-]+\.dart):(\d+)').firstMatch(stack);
    if (plain != null) {
      return {
        'function_name': '',
        'file_name': _fileOnly(plain.group(1) ?? ''),
        'line_number': plain.group(2) ?? '',
      };
    }
    return {'function_name': '', 'file_name': '', 'line_number': ''};
  }

  static String screenOf(String action) {
    if (action.contains('npb')) return 'NPB';
    if (action.contains('mlb')) return 'MLB';
    if (action.contains('試合情報')) return '試合情報';
    if (action.contains('チーム順位')) return 'チーム順位';
    if (action.contains('個人成績')) return '個人成績';
    if (action.contains('news') || action.contains('イベント')) return 'NEWS・イベント';
    if (action.contains('年度')) return '年度';
    if (action.contains('アカウント')) return 'アカウント';
    if (action.contains('初期表示')) return '初期表示';
    return '';
  }

  static String encode(Map<String, dynamic> fields) => jsonEncode(fields);

  static Map<String, dynamic> decode(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    final text = '${raw ?? ''}'.trim();
    if (text.isEmpty) return {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  static String _fileOnly(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }
}
