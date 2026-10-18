import 'dart:convert';

String _name(String value) => value.replaceAll(RegExp(r'[\s　]'), '').replaceAll('髙', '高').replaceAll('﨑', '崎').replaceAll('凜', '凛').replaceAll('澤', '沢');
String _text(dynamic value) => value is Map ? '${value['simpleText'] ?? (value['runs'] as List? ?? []).map((r) => r['text'] ?? '').join()}' : '';

/// Search is ordered by views, but select numerically rather than trusting order.
List<Map<String, dynamic>> draftFeatureVideos(String page, String name) {
  final match = RegExp(r'(?:var\s+)?ytInitialData\s*=\s*').firstMatch(page);
  if (match == null) throw const FormatException('Missing search results');
  final tail = page.substring(match.end);
  var depth = 0, quoted = false, escaped = false, end = 0;
  for (var i = 0; i < tail.length; i++) {
    final c = tail[i];
    if (quoted) {
      if (escaped) { escaped = false; } else if (c == r'\') { escaped = true; } else if (c == '"') { quoted = false; }
    } else if (c == '"') { quoted = true; } else if (c == '{') { depth++; } else if (c == '}' && --depth == 0) {end = i + 1; break;}
  }
  if (end == 0) throw const FormatException('Incomplete search results');
  final data = jsonDecode(tail.substring(0, end));
  final results = <String, Map<String, dynamic>>{};
  void visit(dynamic node) {
    if (node is List) { for (final v in node) {visit(v);} return; }
    if (node is! Map) return;
    final v = node['videoRenderer'];
    if (v is Map) {
      final id = '${v['videoId']}';
      final title = _text(v['title']);
      final encoded = jsonEncode(v);
      final views = int.tryParse(_text(v['viewCountText']).replaceAll(RegExp(r'[^0-9]'), ''));
      if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id) && _name(title).contains(_name(name)) && views != null &&
          !RegExp(r'全打席|負傷|交錯|試合ハイライト|[表裏]途中から|応援歌|応援風景|吹奏楽|ハモリ|準決勝|回戦‼').hasMatch(title) && !encoded.contains('SHORTS') && !encoded.contains('/shorts/') && !encoded.contains('reelWatchEndpoint') && v['upcomingEventData'] == null && !encoded.contains('BADGE_STYLE_TYPE_LIVE_NOW')) {
        results[id] = {'video_id':id, 'title':title, 'view_count':views,
          'publisher':_text(v['ownerText']), 'url':'https://www.youtube.com/watch?v=$id',
          'thumbnail_url':'https://i.ytimg.com/vi/$id/hqdefault.jpg'};
      }
      return;
    }
    for (final child in node.values) {visit(child);}
  }
  // Search results only; never recommendations in other page sections.
  visit(data['contents']?['twoColumnSearchResultsRenderer']?['primaryContents']);
  return results.values.toList()..sort((a,b) => (b['view_count'] as int).compareTo(a['view_count'] as int));
}
