const pacificHighlightChannel = 'UC0v-pxTo1XamIDE-f__Ad0Q';
String _normalize(String value) => value.replaceAll(RegExp(r'[\s　・･]'), '').toLowerCase();

bool hasHomeRun(Map<String, dynamic> game) {
  final plays = game['plays'] is List ? game['plays'] as List : const [];
  if (plays.any((p) => p is Map && (num.tryParse('${p['bases']}') == 4 || RegExp(r'本塁打|ホームラン|home.?run|HR|[左中右]([越中間前]*)本', caseSensitive: false).hasMatch(_normalize('${p['result']}'))))) {
    return true;
  }
  final lines = game['lines'] is List ? game['lines'] as List : const [];
  return lines.any((l) => l is Map && (num.tryParse('${l['int_homerun']}') ?? 0) > 0);
}

/// Only link directly when the player's name, home-run subject and game date
/// are explicit. A publication date alone does not identify the game.
String? matchingHomeRunVideo(List<dynamic> channels, String name, DateTime date, {required bool pacific}) {
  final matches = <String>{};
  final normalizedName = _normalize(name);
  if (normalizedName.length < 2) return null;
  for (final c in channels.whereType<Map>()) {
    if (pacific && c['id'] != pacificHighlightChannel) continue;
    for (final v in (c['videos'] is List ? c['videos'] as List : const []).whereType<Map>()) {
      final id = '${v['id'] ?? ''}', title = _normalize('${v['title']}');
      if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id) || !title.contains(normalizedName) || !RegExp(r'ホームラン|本塁打|home.?run|hr|満塁弾|グランドスラム|号').hasMatch(title)) {
        continue;
      }
      final full = RegExp('${date.year}[年/.-]0?${date.month}[月/.-]0?${date.day}(?:日|[^0-9]|\$)').hasMatch(title);
      final published = DateTime.tryParse('${v['published_at']}');
      final short = RegExp('(?:^|[^0-9])0?${date.month}[月/.-]0?${date.day}(?:日|[^0-9]|\$)').hasMatch(title);
      final verifiedDate = DateTime.tryParse('${v['game_date']}');
      final verified = v['game_date_source'] != null && verifiedDate?.year == date.year && verifiedDate?.month == date.month && verifiedDate?.day == date.day;
      if (full || short && published?.year == date.year || verified) matches.add(id);
    }
  }
  return matches.length == 1 ? matches.single : null;
}
