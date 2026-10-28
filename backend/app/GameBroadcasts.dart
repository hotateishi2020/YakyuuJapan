import 'dart:convert';
import 'NaganoBroadcasts.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import 'package:koko_shared/career_regions.dart';

const broadcastClubs = {
  'ソフトバンク': 'www.softbankhawks.co.jp',
  '西武': 'www.seibulions.jp',
  'ロッテ': 'www.marines.co.jp',
  '楽天': 'www.rakuteneagles.jp',
  '日本ハム': 'www.fighters.co.jp',
  'オリックス': 'www.buffaloes.co.jp',
};
final _pages = <String, ({DateTime at, Future<String> body})>{};
Future<String> _get(String url) {
  final old = _pages[url];
  if (old != null && DateTime.now().difference(old.at).inMinutes < 30) return old.body;
  final future = http.get(Uri.parse(url)).timeout(const Duration(seconds: 12)).then((r) {
    if (r.statusCode != 200) throw const HttpException('Broadcast source unavailable');
    return utf8.decode(r.bodyBytes);
  });
  if (_pages.length > 100) _pages.clear();
  _pages[url] = (at: DateTime.now(), body: future);
  return future;
}

bool isGameStreamUrl(String value) {
  final url = Uri.tryParse(value);
  if (url == null || url.scheme != 'https' || url.host.isEmpty) return false;
  // Only explicit event/episode routes; a service landing page is not a game URL.
  return RegExp(r'/(live|lives|episodes|title|watch|event|events|live-event|live-event-detail|livetv|contents)/[^/?]+').hasMatch(url.path);
}

List<Map<String, dynamic>> parseClubBroadcasts(String body, String source, DateTime date, String opponent) {
  final document = html.parse(body);
  final result = <Map<String, dynamic>>[];
  for (final day in document.querySelectorAll('.c-calendar-list-day')) {
    if (int.tryParse(day.querySelector('.c-calendar-list-day-text em')?.text ?? '') != date.day) continue;
    final vs = day.querySelector('.c-broadcast-schedule-vs')?.text ?? '';
    if (!vs.contains(opponent)) continue;
    for (final item in day.querySelectorAll('.c-broadcast-schedule__list-body .c-broadcast-schedule__list-item')) {
      final label = item.querySelector('.c-broadcast-schedule__broadcaster-label')?.text.trim();
      final link = item.querySelector('.c-broadcast-schedule__broadcaster-text a');
      final name = item.querySelector('.c-broadcast-schedule__broadcaster-text')?.text.trim() ?? '';
      if (name.isEmpty || !['ネット', 'ラジオ', 'テレビ'].contains(label)) continue;
      final url = Uri.tryParse(link?.attributes['href'] ?? '');
      final valid = url != null && url.scheme == 'https' && url.host.isNotEmpty;
      result.add({
        'name': name,
        'kind': label == 'ネット'
            ? 'stream'
            : label == 'ラジオ'
                ? 'radio'
                : 'tv',
        'source_url': source,
        'remarks': item.querySelector('.c-broadcast-schedule__remarks')?.text.trim() ?? '',
        if (valid) 'website_url': url.toString(),
        if (valid) 'logo_url': '${url.origin}/favicon.ico',
        if (valid && label == 'ネット' && isGameStreamUrl(url.toString())) 'stream_url': url.toString(),
      });
    }
  }
  return result;
}

// Direct station coverage only. Affiliation alone is not proof of relay carriage.
const _tvRegions = <String, List<String>>{
  'サガテレビ': ['佐賀県'],
  'STS': ['佐賀県'],
  'SBC': ['長野県'],
  '信越放送': ['長野県'],
  'NBS': ['長野県'],
  '長野放送': ['長野県'],
  'TSB': ['長野県'],
  'テレビ信州': ['長野県'],
  'abn': ['長野県'],
  '長野朝日': ['長野県'],
  'RKB': ['福岡県', '佐賀県'],
  'KBC': ['福岡県'],
  'TNC': ['福岡県'],
  'テレビ西日本': ['福岡県'],
  'FBS': ['福岡県'],
  'TVQ': ['福岡県'],
  'TBSテレビ': ['東京都', '神奈川県', '千葉県', '埼玉県', '茨城県', '栃木県', '群馬県'],
  '日本テレビ': ['東京都', '神奈川県', '千葉県', '埼玉県', '茨城県', '栃木県', '群馬県'],
  'テレビ朝日': ['東京都', '神奈川県', '千葉県', '埼玉県', '茨城県', '栃木県', '群馬県'],
  'フジテレビ': ['東京都', '神奈川県', '千葉県', '埼玉県', '茨城県', '栃木県', '群馬県'],
  'テレビ東京': ['東京都', '神奈川県', '千葉県', '埼玉県', '茨城県', '栃木県', '群馬県'],
};
String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s・ー－-]'), '');
List<Map<String, dynamic>> filterGameBroadcasts(List<Map<String, dynamic>> rows, String prefecture, {List<Map<String, dynamic>> radioStations = const []}) {
  final result = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    final name = '${row['name']}';
    var visible = row['kind'] == 'stream';
    var value = row;
    if (!visible && prefecture.isNotEmpty) {
      visible = (row['prefectures'] as List? ?? []).contains(prefecture) || row['nationwide'] == true;
      if (row['kind'] == 'tv') visible |= _tvRegions.entries.any((e) => name.contains(e.key) && e.value.contains(prefecture));
      if (row['kind'] == 'radio') {
        final station = radioStations.where((s) => _norm('${s['name']}') == _norm(name)).firstOrNull;
        if (station != null) {
          visible = true;
          value = {...row, if (station['logo_url'] != null) 'logo_url': station['logo_url']};
        }
      }
    }
    if (visible) result['${row['kind']}:$name'] = value;
  }
  return result.values.toList();
}

Future<List<Map<String, dynamic>>> readGameBroadcasts(DateTime date, String home, String away, String prefecture) async {
  final rows = <Map<String, dynamic>>[];
  final month = '${date.year}${date.month.toString().padLeft(2, '0')}';
  await Future.wait([
    for (final team in [home, away])
      if (broadcastClubs.containsKey(team))
        () async {
          final source = 'https://${broadcastClubs[team]}/news/broadcast/$month/';
          try {
            rows.addAll(parseClubBroadcasts(await _get(source), source, date, team == home ? away : home));
          } catch (_) {}
        }()
  ]);
  if (prefecture == '長野県') {
    try {
      rows.addAll(parseNaganoBroadcasts(await _get(naganoScheduleUrl(date).toString()), date, home, away));
    } catch (_) {}
  }
  // Reviewed entries support all clubs, regional relays, logos and exact event URLs.
  final file = File('data/game-broadcasts.json');
  if (await file.exists()) {
    final records = jsonDecode(await file.readAsString()) as List;
    for (final record in records.whereType<Map>()) {
      if (record['date'] == date.toIso8601String().substring(0, 10) && record['home'] == home && record['away'] == away) {
        rows.addAll((record['broadcasts'] as List).map((v) => Map<String, dynamic>.from(v)));
      }
    }
  }
  final stations = <Map<String, dynamic>>[];
  final index = japanRegions.values.expand((v) => v).toList().indexOf(prefecture);
  if (index >= 0 && rows.any((r) => r['kind'] == 'radio')) {
    try {
      final xml = XmlDocument.parse(await _get('https://radiko.jp/v3/station/list/JP${index + 1}.xml'));
      for (final station in xml.findAllElements('station')) {
        stations.add({'name': station.getElement('name')?.innerText, 'logo_url': station.findElements('logo').where((e) => e.getAttribute('width') == '224').firstOrNull?.innerText});
      }
    } catch (_) {}
  }
  final visible = filterGameBroadcasts(rows, prefecture, radioStations: stations);
  await Future.wait([
    for (final row in visible)
      () async {
        if (!'${row['logo_url']}'.endsWith('/favicon.ico')) return;
        final site = Uri.tryParse('${row['website_url']}');
        if (site == null) return;
        try {
          final doc = html.parse(await _get(site.origin));
          final icon = doc.querySelectorAll('link').where((e) => '${e.attributes['rel']}'.contains('icon') && (e.attributes['type'] == 'image/png' || '${e.attributes['href']}'.contains('.png'))).firstOrNull;
          if (icon != null) row['logo_url'] = site.resolve(icon.attributes['href']!).toString();
        } catch (_) {}
      }()
  ]);
  return visible;
}
