import 'package:html/parser.dart' as html;
import 'StrengthUsage.dart';

Map<String, dynamic> achievement(String label, int year, String source,
        {String kind = 'milestone', String detail = ''}) =>
    {
      'id': '$year/$label',
      'label': label,
      'year': year,
      'source': source,
      'kind': kind,
      'detail': detail
    };

List<Map<String, dynamic>> statisticalAchievements(
    List<Map<String, dynamic>> seasons,
    String source,
    String scope,
    int throughYear) {
  final result = <Map<String, dynamic>>[];
  final totals = <String, int>{};
  final awarded = <String>{};
  final sorted = [...seasons]
    ..sort((a, b) => usageInt(a['year']).compareTo(usageInt(b['year'])));
  for (final p in sorted) {
    final year = usageInt(p['year']);
    if (year > throughYear) continue;
    void add(String label, {String kind = 'milestone'}) {
      if (awarded.add('$year/$label'))
        result.add(achievement('$scope $label', year, source, kind: kind));
    }

    final hr = usageInt(p['hr']), sb = usageInt(p['sb']);
    if (usageInt(p['rbi']) >= 100) add('シーズン100打点');
    if (hr >= 30 && sb >= 30 && (double.tryParse('${p['avg']}') ?? 0) >= .300)
      add('トリプルスリー', kind: 'record');
    for (final n in [40, 50]) {
      if (hr >= n && sb >= n) add('$n-$n', kind: 'record');
    }
    for (final entry in {
      'hr': (100, '本塁打'),
      'wins': (100, '勝'),
      'hits': (1000, '安打'),
      'saves': (100, 'セーブ'),
      'strikeouts': (1000, '奪三振')
    }.entries) {
      final old = totals[entry.key] ?? 0, now = old + usageInt(p[entry.key]);
      totals[entry.key] = now;
      for (var n = (old ~/ entry.value.$1 + 1) * entry.value.$1;
          n <= now;
          n += entry.value.$1) {
        add('通算$n${entry.value.$2}');
      }
    }
  }
  return result;
}

List<Map<String, dynamic>> npbCareerSeasons(String source) {
  final doc = html.parse(source);
  final combined = <int, Map<String, dynamic>>{};
  for (final selector in ['#tablefix_b', '#tablefix_p']) {
    final table = doc.querySelector(selector);
    if (table == null) continue;
    final headers =
        table.querySelectorAll('thead th').map((e) => e.text.trim()).toList();
    for (final row in table.querySelectorAll('tbody tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length != headers.length) continue;
      final year = int.tryParse(cells.first.text.trim());
      if (year == null) continue;
      // NPB combined season rows must be used once when a player changes teams.
      final p = combined.putIfAbsent(year, () => {'year': year});
      final values = <String, dynamic>{};
      for (final e in {
        '本塁打': 'hr',
        '盗塁': 'sb',
        '打点': 'rbi',
        '安打': 'hits',
        '打率': 'avg',
        '勝利': 'wins',
        'セーブ': 'saves',
        '三振': 'strikeouts'
      }.entries) {
        if (!headers.contains(e.key)) continue;
        if (selector == '#tablefix_b' &&
            ['wins', 'saves', 'strikeouts'].contains(e.value)) continue;
        if (selector == '#tablefix_p' &&
            !['wins', 'saves', 'strikeouts'].contains(e.value)) continue;
        values[e.value] = cells[headers.indexOf(e.key)].text.trim();
      }
      // RegisterStats is NPB's annual aggregate; rows for individual clubs may coexist.
      for (final e in values.entries) {
        if (e.key == 'avg') {
          p[e.key] = e.value;
        } else {
          final value = usageInt(e.value);
          if (value > usageInt(p[e.key])) p[e.key] = value;
        }
      }
    }
  }
  return combined.values.toList();
}

Map<String, List<Map<String, dynamic>>> npbAwardEntries(
    String source, int year, String url) {
  final result = <String, List<Map<String, dynamic>>>{};
  for (final link
      in html.parse(source).querySelectorAll('a[href*="/players/"]')) {
    final id = RegExp(r'/players/(\d+)\.html')
        .firstMatch(link.attributes['href'] ?? '')?[1];
    final label = link.querySelector('h6')?.text.trim();
    if (id == null || label == null || label.isEmpty) continue;
    result.putIfAbsent('npb:$id', () => []).add(achievement(label, year, url,
        kind: 'title',
        detail: link.querySelector('.comment')?.text.trim() ?? ''));
  }
  return result;
}

Map<String, List<Map<String, dynamic>>> npbMonthlyEntries(
    String source, int year, String url) {
  final result = <String, List<Map<String, dynamic>>>{};
  for (final row in html.parse(source).querySelectorAll('tr')) {
    final month = row.querySelector('th')?.text.trim() ?? '';
    if (!month.contains('月')) continue;
    for (final link in row.querySelectorAll('a[href*="/players/"]')) {
      final id = RegExp(r'/players/(\d+)\.html')
          .firstMatch(link.attributes['href'] ?? '')?[1];
      if (id != null)
        result
            .putIfAbsent('npb:$id', () => [])
            .add(achievement('月間MVP（$month）', year, url, kind: 'title'));
    }
  }
  return result;
}

Map<String, List<Map<String, dynamic>>> npbSeriesEntries(
    String source, int year, String url) {
  final result = <String, List<Map<String, dynamic>>>{};
  for (final h in html.parse(source).querySelectorAll('h4')) {
    if (!h.text.contains('選手賞')) continue;
    final label = h.text.contains('最高殊勲')
        ? '日本シリーズMVP'
        : '日本シリーズ ${h.text.split('　').first}';
    for (final a
        in h.nextElementSibling?.querySelectorAll('a[href*="/players/"]') ??
            []) {
      final id = RegExp(r'/players/(\d+)\.html')
          .firstMatch(a.attributes['href'] ?? '')?[1];
      if (id != null)
        result
            .putIfAbsent('npb:$id', () => [])
            .add(achievement(label, year, url, kind: 'title'));
    }
  }
  return result;
}

/// Official qualified batting/ERA rankings; names are resolved only when unique.
Map<String, List<Map<String, dynamic>>> npbQualifiedEntries(
    String source, int year, String url,
    {String? japanChampion}) {
  final doc = html.parse(source),
      result = <String, List<Map<String, dynamic>>>{};
  final champion = doc
          .querySelector('a[name="standings"]')
          ?.parent
          ?.nextElementSibling
          ?.querySelector('td.yearlyMain')
          ?.text ??
      '';
  const aliases = {
    '阪神タイガース': '阪神',
    '読売ジャイアンツ': '巨人',
    '東京ヤクルトスワローズ': 'ヤクルト',
    'ヤクルトスワローズ': 'ヤクルト',
    '横浜DeNAベイスターズ': 'DeNA',
    '横浜ベイスターズ': '横浜',
    '中日ドラゴンズ': '中日',
    '広島東洋カープ': '広島',
    '福岡ソフトバンクホークス': 'ソフトバンク',
    '福岡ダイエーホークス': 'ダイエー',
    '北海道日本ハムファイターズ': '日本ハム',
    '日本ハムファイターズ': '日本ハム',
    'オリックス・バファローズ': 'オリックス',
    '西武ライオンズ': '西武',
    '埼玉西武ライオンズ': '西武',
    '千葉ロッテマリーンズ': 'ロッテ',
    '東北楽天ゴールデンイーグルス': '楽天'
  };
  for (final entry
      in {'indBatting': '規定打席到達', 'indPitching': '規定投球回到達'}.entries) {
    final table =
        doc.querySelector('a[name="${entry.key}"]')?.parent?.nextElementSibling;
    for (final row in table?.querySelectorAll('tr') ?? []) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 4 || int.tryParse(cells.first.text.trim()) == null)
        continue;
      final name = usageName(cells[1].text),
          team = usageName(cells[2].text).replaceAll(RegExp('[（）()]'), '');
      final badges = result.putIfAbsent(name, () => []);
      badges.add(achievement(entry.value, year, url, kind: 'qualification'));
      for (final e in {'リーグ優勝レギュラー': champion, '日本一レギュラー': japanChampion ?? ''}
          .entries) {
        if (aliases[e.value] == team)
          badges.add(achievement(e.key, year, url,
              kind: 'championship',
              detail: '当該年の優勝球団に所属し、規定打席または規定投球回に到達した選手。'));
      }
    }
  }
  return result;
}
