import 'dart:convert';
import 'package:html/parser.dart' as html;

const naganoStations = <String, String>{
  'NHK総合': 'NHK総合（長野）',
  'NHKEテレ': 'NHK Eテレ（長野）',
  'テレビ信州': 'テレビ信州',
  '長野朝日放送': '長野朝日放送',
  'SBC信越放送': 'SBC信越放送',
  '長野放送': '長野放送',
};
String _normalize(String text) => String.fromCharCodes(
        text.runes.map((c) => c >= 0xff01 && c <= 0xff5e ? c - 0xfee0 : c))
    .toLowerCase()
    .replaceAll(RegExp(r'[\s　・･－-]'), '');
String? naganoStationName(String text) {
  final normalized = _normalize(text);
  for (final entry in naganoStations.entries) {
    if (normalized.contains(_normalize(entry.key))) return entry.value;
  }
  return null;
}

const _teamAliases = <String, List<String>>{
  'DeNA': ['横浜DeNA', 'ベイスターズ'],
  'ソフトバンク': ['ホークス'],
  '巨人': ['読売', 'ジャイアンツ'],
  '阪神': ['タイガース'],
  '広島': ['カープ'],
  '中日': ['ドラゴンズ'],
  'ヤクルト': ['スワローズ'],
  '日本ハム': ['日ハム', 'ファイターズ'],
  '楽天': ['イーグルス'],
  'ロッテ': ['マリーンズ'],
  '西武': ['ライオンズ'],
  'オリックス': ['バファローズ'],
  'ブリュワーズ': ['ブルワーズ', 'ブルーワーズ'],
  'アスレチックス': ['アスレティックス'],
  'ダイヤモンドバックス': ['ダイアモンドバックス'],
};
bool _matchesTeam(String text, String team) {
  if (team.trim().isEmpty) return false;
  final names = {team};
  for (final entry in _teamAliases.entries) {
    if ([entry.key, ...entry.value]
        .any((n) => _normalize(n) == _normalize(team)))
      names.addAll([entry.key, ...entry.value]);
  }
  return names.any((n) => text.contains(_normalize(n)));
}

Uri naganoScheduleUrl(DateTime date) => Uri.https('bangumi.org', '/epg/td', {
      'ggm_group_id': '51',
      'broad_cast_date':
          '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}',
    });

/// Parse the dated Nagano terrestrial EPG, not network affiliations. News and
/// highlights mentioning the same teams are not game broadcasts.
List<Map<String, dynamic>> parseNaganoBroadcasts(
    String body, DateTime date, String home, String away) {
  final doc = html.parse(body);
  final day = naganoScheduleUrl(date).queryParameters['broad_cast_date'];
  try {
    final metadata = jsonDecode(
            doc.querySelector('meta[name="pv"]')?.attributes['content'] ?? '{}')
        as Map;
    if (metadata['broad_cast_date'] != day || metadata['broad_cast'] != 'td')
      return [];
  } catch (_) {
    return [];
  }
  final headers = doc.querySelectorAll('#ch_area .js_channel p');
  final lines = doc.querySelectorAll('#program_area > ul');
  if (headers.length != lines.length) return [];
  final found = <String, Map<String, dynamic>>{};
  for (var i = 0; i < headers.length; i++) {
    final station = naganoStationName(headers[i].text);
    if (station == null) continue;
    for (final item in lines[i].querySelectorAll('li[s][e]')) {
      final start = item.attributes['s']!;
      if (start.length != 12 || !start.startsWith(day!)) continue;
      final title = item.querySelector('.program_title')?.text ?? '';
      final normalized = _normalize(title);
      if (RegExp(r'ハイライト|ニュース|ダイジェスト|結果|振り返|総集編|再放送|録画|🈞')
          .hasMatch(normalized)) continue;
      if (!RegExp(r'プロ野球|野球中継|mlb|メジャーリーグ|日本シリーズ|ワールドシリーズ|クライマックス|リーグ.*シリーズ')
          .hasMatch(normalized)) continue;
      final text = _normalize(
          '$title ${item.querySelector('.program_detail')?.text ?? ''}');
      if (!_matchesTeam(text, home) || !_matchesTeam(text, away)) continue;
      final href = item.querySelector('a.title_link')?.attributes['href'];
      final source = naganoScheduleUrl(date);
      found[station] = {
        'name': station,
        'kind': 'tv',
        'prefectures': ['長野県'],
        'source_url':
            href == null ? source.toString() : source.resolve(href).toString(),
        'website_url': source.toString(),
        'program_title': title,
        'broadcast_start':
            '${start.substring(8, 10)}:${start.substring(10, 12)}',
        'remarks': '長野県の地上波番組表で確認',
      };
    }
  }
  return found.values.toList();
}
