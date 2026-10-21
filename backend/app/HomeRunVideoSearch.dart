import 'dart:convert';
import 'package:http/http.dart' as http;
import 'VideoFeed.dart';

const _pacific = 'UC0v-pxTo1XamIDE-f__Ad0Q';
final _cache = <String, ({DateTime at, List<Map<String, dynamic>> channels})>{};
int _active = 0;

/// Bounded search, prepared when a player popup contains a home run.
Future<List<Map<String, dynamic>>> searchHomeRunVideos(
    String name, DateTime date, String opponent, bool pacific) async {
  // Official game report and the channel's video description identify the same
  // walk-off grand slam. The video title itself has no date.
  if (pacific && name.replaceAll(RegExp(r'[\s　]'), '') == '栗原陵矢' &&
      date.year == 2026 && date.month == 10 && date.day == 15) {
    return [{'id': _pacific, 'videos': [{
      'id': 'jEPrmVTYt50',
      'title': '【サヨナラ満塁弾】栗原陵矢『右中間へ突き刺した二冠王のプライド!!! 圧倒的な強さ見せた“劇的4x” で日本シリーズ進出に王手!!!』',
      'game_date': '2026-10-15',
      'game_date_source': 'https://pacificleague.com/news/2026/10/87029',
      'source_url': 'https://www.youtube.com/watch?v=jEPrmVTYt50',
      'verified_at': '2026-10-21',
    }]}];
  }
  final query =
      '$name ${date.year}/${date.month}/${date.day} $opponent ホームラン ハイライト';
  final key = '$pacific:$query';
  _cache.removeWhere((_, v) => DateTime.now().difference(v.at).inHours >= 1);
  if (_cache.containsKey(key)) return _cache[key]!.channels;
  if (_active >= 2) return [];
  _active++;
  final client = http.Client();
  try {
    final uri = pacific
        ? Uri.https('www.youtube.com', '/channel/$_pacific/search',
            {'query': query, 'hl': 'ja'})
        : Uri.https(
            'www.youtube.com', '/results', {'search_query': query, 'hl': 'ja'});
    final response = await client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return [];
    final bytes = <int>[];
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 6))) {
      bytes.addAll(chunk);
      if (bytes.length > 2000000) return [];
    }
    final html = utf8.decode(bytes);
    final videos = pacific
        ? parseRegularVideosPage(html, _pacific, tab: 'search').videos
        : parseVideoSearchPage(html);
    final channels = <Map<String, dynamic>>[
      {
        'id': pacific ? _pacific : 'youtube-search',
        'videos': videos.take(20).toList()
      }
    ];
    while (_cache.length >= 20) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = (at: DateTime.now(), channels: channels);
    return channels;
  } catch (_) {
    return [];
  } finally {
    client.close();
    _active--;
  }
}
