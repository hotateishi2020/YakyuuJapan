import 'ExtendedPlayerMetrics.dart';
import 'StrengthUsage.dart';
import 'dart:convert';

/// CSV quoting, escaped quotes, CRLF and UTF-8 BOM. Empty cells stay empty.
List<Map<String, String>> parseStatcastCsv(String source) {
  final records = <List<String>>[];
  var row = <String>[], cell = StringBuffer(), quoted = false;
  source = source.replaceFirst('\uFEFF', '');
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (c == '"') {
      if (quoted && i + 1 < source.length && source[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      row.add(cell.toString());
      cell = StringBuffer();
    } else if ((c == '\n' || c == '\r') && !quoted) {
      if (c == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
      row.add(cell.toString());
      if (row.any((v) => v.isNotEmpty)) records.add(row);
      row = [];
      cell = StringBuffer();
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    records.add(row);
  }
  if (records.isEmpty) return [];
  final header = records.first;
  return [
    for (final r in records.skip(1))
      if (r.length == header.length) {for (var i = 0; i < header.length; i++) header[i]: r[i]}
  ];
}

Future<List<Map<String, dynamic>>> fetchStatcastProfiles(int year, Future<String> Function(String) get, void Function(Map<String, dynamic>) add) async {
  final result = <String, Map<String, dynamic>>{};
  Map<String, dynamic> profile(String id) => result.putIfAbsent(id, () => {'org': 'mlb', 'source_player_id': id});
  void field(String id, String label, String? raw, String source, {String unit = '', double factor = 1, String description = ''}) {
    final n = num.tryParse(raw ?? '');
    if (n == null) return;
    profile(id)[label] = {'value': '${(n * factor).toStringAsFixed(2)}$unit${description.isEmpty ? '' : '（$description）'}', 'source': source, 'as_of': '$year 年シーズン・${DateTime.now().toUtc().toIso8601String()}確認'};
  }

  final bat = 'https://baseballsavant.mlb.com/leaderboard/custom?year=$year&type=batter&filter=&sort=4&sortDir=desc&min=1&selections=player_id,oz_swing_percent,exit_velocity_avg,hp_to_1b&chart=false&csv=true';
  for (final r in parseStatcastCsv(await get(bat))) {
    final id = r['player_id']!;
    final chase = num.tryParse(r['oz_swing_percent'] ?? '');
    if (chase != null && chase >= 0 && chase <= 100) {
      add({
        'org': 'mlb',
        'source_player_id': id,
        'name': r['last_name, first_name'],
        'source': bat,
        'metrics': [metric('ボール球見極め率', 100 - chase, digits: 1, display: '${(100 - chase).toStringAsFixed(1)}%', note: '100 − Statcast O-Swing%。ゾーン外の投球を振らなかった割合。')]
      });
    }
    field(id, '打球速度', r['exit_velocity_avg'], bat, unit: 'km/h', factor: 1.609344, description: '平均・公式mphから換算');
    field(id, '一塁到達タイム', r['hp_to_1b'], bat, unit: '秒', description: 'Statcast HP to 1B');
  }
  final pop = 'https://baseballsavant.mlb.com/leaderboard/poptime?year=$year&team=&csv=true';
  for (final r in parseStatcastCsv(await get(pop))) {
    field(r['entity_id']!, '二塁送球タイム', r['pop_2b_sba'], pop, unit: '秒', description: '二盗企図時の平均Pop Time・捕球から二塁到達');
  }
  final pit = 'https://baseballsavant.mlb.com/leaderboard/custom?year=$year&type=pitcher&filter=&sort=4&sortDir=desc&min=1&selections=player_id,fastball_avg_speed&chart=false&csv=true';
  for (final r in parseStatcastCsv(await get(pit))) {
    field(r['player_id']!, '投球速度', r['fastball_avg_speed'], pit, unit: 'km/h', factor: 1.609344, description: '速球系の平均・最高球速ではない');
  }
  final arsenal = 'https://baseballsavant.mlb.com/leaderboard/pitch-arsenals?type=avg_speed&year=$year&team=&position=&min=1&csv=true';
  const pitchNames = {'ff': 'フォーシーム', 'si': 'シンカー', 'fc': 'カッター', 'sl': 'スライダー', 'ch': 'チェンジアップ', 'cu': 'カーブ', 'fs': 'スプリット', 'kn': 'ナックル', 'st': 'スイーパー', 'sv': 'スラーブ'};
  for (final r in parseStatcastCsv(await get(arsenal))) {
    final pitches = [
      for (final e in pitchNames.entries)
        if (num.tryParse(r['${e.key}_avg_speed'] ?? '') != null) '${e.value} ${(num.parse(r['${e.key}_avg_speed']!) * 1.609344).toStringAsFixed(1)}km/h'
    ];
    if (pitches.isNotEmpty) {
      profile(r['pitcher']!)['変化球の球種'] = {'value': pitches.join(' / '), 'source': arsenal, 'as_of': '$year 年・Statcast分類・球種別平均球速（速球を含む）'};
    }
  }
  final ph = 'https://statsapi.mlb.com/api/v1/stats?stats=statSplits&group=hitting&sitCodes=pH&season=$year&sportIds=1&playerPool=ALL&limit=5000';
  final groups = <String, Map<String, dynamic>>{};
  for (final group in usageMaps(usageMap(jsonDecode(await get(ph)))['stats']))
    for (final split in usageMaps(group['splits'])) {
      final p = usageMap(split['player']), s = usageMap(split['stat']), id = '${p['id']}';
      final g = groups.putIfAbsent(id, () => {'name': p['fullName'], 'ab': 0, 'hits': 0, 'games': 0});
      g['ab'] += usageInt(s['atBats']);
      g['hits'] += usageInt(s['hits']);
      g['games'] += usageInt(s['gamesPlayed']);
    }
  for (final e in groups.entries) {
    add({
      'org': 'mlb',
      'source_player_id': e.key,
      'name': e.value['name'],
      'source': ph,
      'metrics': [metric('代打起用数', e.value['games'], note: 'MLB公式の代打区分の出場試合数。打席未完了の交代は含まれない場合があります。'), metric('代打打率', e.value['ab'] > 0 ? e.value['hits'] / e.value['ab'] : null, digits: 3, note: '代打 ${e.value['hits']}安打 / ${e.value['ab']}打数')]
    });
  }
  return result.values.toList();
}
