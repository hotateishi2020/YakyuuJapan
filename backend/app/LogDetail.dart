import 'dart:convert';

/// 操作ログとエラーログの共通項目。画面の列と `txt_detail` の中身を揃える。
class LogDetail {
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
