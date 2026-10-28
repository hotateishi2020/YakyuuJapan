import 'VideoChannels.dart';
import 'VideoTeamRouting.dart';

/// Uses explicit matchup/date evidence, never upload date alone.
List<Map<String, dynamic>> gameHighlightVideos(Map<String, dynamic> game, List<dynamic> channels) {
  if (!RegExp('終了|コールド').hasMatch('${game['state']}')) return [];
  final date = DateTime.tryParse('${game['date_game']}'.split(RegExp('[ T]')).first);
  if (date == null) return [];
  final mlb = [3, 4].contains(game['id_league_home']);
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s・･]'), '');
  List<String> aliases(String name) {
    final groups = mlb ? mlbVideoTeams.values : teamVideoKeywords.values;
    final key = norm(name);
    for (final group in groups) {
      if (group.any((word) => norm(word) == key)) return group;
    }
    return [name];
  }

  final home = aliases('${game['name_team_home'] ?? ''}');
  final away = aliases('${game['name_team_away'] ?? ''}');
  if (home.first.isEmpty || away.first.isEmpty) return [];
  final found = <String, Map<String, dynamic>>{};
  for (final channel in channels.whereType<Map>()) {
    for (final v in (channel['videos'] as List? ?? []).whereType<Map>()) {
      final id = '${v['id'] ?? ''}';
      final title = '${v['title'] ?? ''}';
      final text = norm(title);
      if (!RegExp(r'^[\w-]{11}$').hasMatch(id) || !RegExp(r'ハイライト|highlights', caseSensitive: false).hasMatch(title) || !home.any((s) => text.contains(norm(s))) || !away.any((s) => text.contains(norm(s)))) {
        continue;
      }
      final published = DateTime.tryParse('${v['published_at']}');
      bool dated(DateTime d) {
        final dates = RegExp(r'(?:(20\d{2})[年/.-])?(\d{1,2})[月/.-](\d{1,2})(?:日)?(?!\d)').allMatches(title);
        for (final match in dates) {
          if (match[1] == null && RegExp(r'^/\d{2,4}(?!\d)').hasMatch(title.substring(match.end))) continue;
          if (int.parse(match[2]!) != d.month || int.parse(match[3]!) != d.day) continue;
          if (match[1] != null) {
            if (int.parse(match[1]!) == d.year) return true;
          } else if (published != null && published.difference(d).inHours >= -24 && published.difference(d).inHours <= 96) {
            return true;
          }
        }
        // MLB commonly uses M/D/YY in its English titles.
        return RegExp('(?<![0-9])0?${d.month}/0?${d.day}/(?:${d.year}|${d.year % 100})(?![0-9])').hasMatch(title);
      }

      // English MLB recaps label the US calendar date; Japanese recaps use JST.
      final titleDate = mlb && RegExp(r'game highlights', caseSensitive: false).hasMatch(title) ? date.subtract(const Duration(days: 1)) : date;
      if (!dated(titleDate)) continue;
      found[id] = {'id': id, 'title': title, 'thumbnail_url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg', 'source_name': v['source_name'] ?? channel['name']};
    }
  }
  return found.values.toList();
}
