import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

String allStarName(Object? name) => '$name'
    .replaceAllMapped(RegExp(r'[Ａ-Ｚａ-ｚ]'),
        (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xfee0))
    .replaceAll(RegExp(r'[\s　・･.．*]'), '')
    .replaceAll('髙', '高')
    .replaceAll('﨑', '崎')
    .replaceFirst(RegExp(r'^[A-ZＡ-Ｚ](?=[ァ-ヶ])'), '')
    .replaceAll('タイロンウッズ', 'ウッズ');
const infieldPositions = ['一塁手', '二塁手', '三塁手', '遊撃手'];
Map<String, Map<String, dynamic>> parseAllStarFielding(String body) {
  final result = <String, Map<String, dynamic>>{};
  var position = '';
  for (final element in html.parse(body).querySelectorAll('h5, tr')) {
    final heading = element.localName == 'h5'
        ? element.text.trim()
        : element
            .querySelector('th.sthdfplayer')
            ?.text
            .replaceAll(RegExp('[【】]'), '')
            .trim();
    if (heading != null) {
      position = heading;
      continue;
    }
    if (![...infieldPositions, '外野手'].contains(position)) continue;
    final cells = element.querySelectorAll('td');
    final offset = element.querySelector('.stplayer') != null ? 1 : 0;
    if (cells.length < offset + 2) continue;
    final name = allStarName(cells[offset].text);
    final games = int.tryParse(cells[offset + 1].text.trim()) ?? 0;
    if (games > 0 &&
        (result[name] == null ||
            (position != '外野手' &&
                games > (result[name]?['games'] as int? ?? 0)))) {
      result[name] = {'position': position, 'games': games};
    }
  }
  return result;
}

void applyAllStarPositions(List<Map<String, dynamic>> rows, Map positions) {
  for (final row in rows.where((r) => r['position'] == '内野手')) {
    final found = positions['${row['year']}:${allStarName(row['name'])}'];
    if (found is Map &&
        [...infieldPositions, '外野手', '捕手', 'DH'].contains(found['position'])) {
      row.addAll({
        'display_position': found['position'],
        'position_source': found['source'],
        'position_games': found['games'],
        'position_basis': found['basis']
      });
    }
  }
}

Future<void> refreshAllStarPositions(List<Map<String, dynamic>> rows) async {
  const clubs = {
    '読売': 'g',
    '阪神': 't',
    '中日': 'd',
    '広島東洋': 'c',
    '東京ヤクルト': 's',
    'ヤクルト': 's',
    '横浜DeNA': 'db',
    '横浜': 'yb',
    '西武': 'l',
    '埼玉西武': 'l',
    '北海道日本ハム': 'f',
    '日本ハム': 'f',
    '千葉ロッテ': 'm',
    'オリックス': 'b',
    '東北楽天': 'e',
    '福岡ソフトバンク': 'h',
    '福岡ダイエー': 'h',
    '大阪近鉄': 'bu'
  };
  final root = Directory('data').existsSync() ? 'data' : 'backend/data';
  final file = File('$root/allstar_positions.json');
  final result = file.existsSync()
      ? Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()))
      : <String, dynamic>{};
  final requests = <String, List<Map<String, dynamic>>>{};
  for (final row in rows.where((r) => r['position'] == '内野手')) {
    var club = clubs[row['team']];
    if ((row['year'] as int) < 2005) continue;
    if (club == 'b' && (row['year'] as int) <= 2020) club = 'bs';
    if (club != null) {
      requests
          .putIfAbsent(
              'https://npb.jp/bis/${row['year']}/stats/idf1_$club.html',
              () => [])
          .add(row);
    }
  }
  final entries = requests.entries.toList();
  final client = http.Client();
  try {
    for (var i = 0; i < entries.length; i += 4) {
      await Future.wait(entries.skip(i).take(4).map((entry) async {
        try {
          final cache = File(
              '/tmp/koko-allstar-fielding/${Uri.parse(entry.key).path.replaceAll('/', '_')}');
          String body;
          if (cache.existsSync() &&
              (entry.value.first['year'] != DateTime.now().year ||
                  DateTime.now().difference(cache.lastModifiedSync()).inHours <
                      6)) {
            body = cache.readAsStringSync();
          } else {
            final response = await client
                .get(Uri.parse(entry.key))
                .timeout(const Duration(seconds: 20));
            if (response.statusCode != 200) {
              throw StateError('HTTP ${response.statusCode}');
            }
            body = utf8.decode(response.bodyBytes);
            await cache.parent.create(recursive: true);
            await cache.writeAsString(body);
          }
          final fielding = parseAllStarFielding(body);
          for (final row in entry.value) {
            final match = fielding[allStarName(row['name'])];
            if (match != null) {
              result['${row['year']}:${allStarName(row['name'])}'] = {
                ...match,
                'source': entry.key
              };
            }
          }
        } catch (e) {
          stderr.writeln('${entry.key}: $e');
        }
      }));
    }
    // Older seasons do not publish individual fielding tables. Use actual
    // All-Star defensive appearances, matching only an unambiguous roster name.
    final unresolved = rows
        .where((r) =>
            r['position'] == '内野手' &&
            !result.containsKey('${r['year']}:${allStarName(r['name'])}'))
        .toList();
    for (final year in unresolved.map((r) => r['year']).toSet()) {
      for (var game = 1; game <= 3; game++) {
        final url =
            'https://npb.jp/bis/scores/allstargame/boxscore${year}_$game.html';
        try {
          final response = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) continue;
          final appearances =
              parseAllStarAppearances(utf8.decode(response.bodyBytes));
          for (final appearance in appearances) {
            final matches = rows
                .where((r) =>
                    r['year'] == year &&
                    (appearance['team_code'] == null ||
                        historicalTeamCodes('${r['team']}')
                            .contains(appearance['team_code'])) &&
                    (allStarName(r['name']) == appearance['name'] ||
                        allStarName(r['name']).startsWith(appearance['name']!)))
                .toList();
            if (matches.length != 1) continue;
            final row = matches.single;
            if (row['position'] != '内野手') continue;
            result.putIfAbsent(
                '$year:${allStarName(row['name'])}',
                () => {
                      'position': appearance['position'],
                      'source': url,
                      'basis': 'オールスター第$game戦の守備位置',
                    });
          }
        } catch (e) {
          stderr.writeln('$url: $e');
        }
      }
    }
    final regularFile = File('$root/regular-history.json');
    if (regularFile.existsSync()) {
      final archive =
          (jsonDecode(regularFile.readAsStringSync())['rows'] as List);
      const slots = {
        '1B': '一塁手',
        '2B': '二塁手',
        '3B': '三塁手',
        'SS': '遊撃手',
        'C': '捕手',
        'LF': '外野手',
        'CF': '外野手',
        'RF': '外野手',
        'DH': 'DH'
      };
      for (final row in unresolved.where((r) =>
          !result.containsKey('${r['year']}:${allStarName(r['name'])}'))) {
        final teams = archive.where((r) =>
            r['year'] == row['year'] &&
            r['club_name'] ==
                (['横浜', '大洋'].contains(row['team']) ? 'DeNA' : row['team']));
        if (teams.length != 1) continue;
        final matches = <Map<String, dynamic>>[];
        for (final group in teams.single['positions'] as List) {
          if (!slots.containsKey(group['slot'])) continue;
          for (final player in group['players'] as List) {
            final name = allStarName(player['name']);
            if (name.isNotEmpty && allStarName(row['name']).startsWith(name)) {
              matches.add({
                ...Map<String, dynamic>.from(player),
                'position': slots[group['slot']]
              });
            }
          }
        }
        if (matches.map((p) => p['name']).toSet().length != 1) continue;
        matches
            .sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
        if (matches.length > 1 && matches[0]['count'] == matches[1]['count']) {
          continue;
        }
        result['${row['year']}:${allStarName(row['name'])}'] = {
          'position': matches.first['position'],
          'games': matches.first['count'],
          'source': teams.single['source_url'],
          'basis': '同年度の公式戦スタメンで最も多い守備位置',
        };
      }
    }
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    final missing = rows.where((r) =>
        r['position'] == '内野手' &&
        !result.containsKey('${r['year']}:${allStarName(r['name'])}'));
    print(
        'Positions: ${result.length}; unresolved: ${missing.map((r) => "${r['year']} ${r['name']}").join(', ')}');
  } finally {
    client.close();
  }
}

List<Map<String, String>> parseAllStarAppearances(String body) {
  const positions = {
    '一': '一塁手',
    '二': '二塁手',
    '三': '三塁手',
    '遊': '遊撃手',
    '左': '外野手',
    '中': '外野手',
    '右': '外野手',
    '捕': '捕手',
    '指': 'DH'
  };
  final result = <Map<String, String>>[];
  for (final row in html.parse(body).querySelectorAll('tr')) {
    final cells = row.children.where((c) => c.localName == 'td').toList();
    if (cells.length < 10) continue;
    final code = cells.first.text.replaceAll(RegExp(r'[()（）\s]'), '');
    final defensiveCodes = code
        .split('')
        .where((v) => positions.containsKey(v) && v != '指')
        .toList();
    final position = positions[defensiveCodes.isNotEmpty
        ? defensiveCodes.first
        : code.contains('指')
            ? '指'
            : code];
    final name = allStarName(cells[1].text);
    if (position != null && name.isNotEmpty) {
      result.add({
        'name': name,
        'position': position,
        if (RegExp(r'[（(][^）)]+[）)]').hasMatch(cells[2].text))
          'team_code': cells[2].text.replaceAll(RegExp(r'[()（）\s]'), '')
      });
    }
  }
  return result;
}

Set<String> historicalTeamCodes(String team) {
  if (team.contains('近鉄')) return {'近'};
  if (team.contains('DeNA')) return {'デ', '横'};
  const codes = <String, String>{
    '巨人': '巨',
    '読売': '巨',
    '阪神': '神',
    '大阪': '神',
    '中日': '中',
    '名古屋': '名中',
    '横浜': '横',
    '大洋': '洋',
    '洋松': '洋',
    '広島': '広',
    'ヤクルト': 'ヤ',
    'サンケイ': 'サ',
    'アトムズ': 'ア',
    '国鉄': '国',
    'ソフトバンク': 'ソ',
    'ダイエー': 'ダ',
    '南海': '南',
    '日本ハム': '日',
    '日拓': '日拓',
    '東映': '映',
    '東急': '東急',
    '西武': '西',
    '西鉄': '西',
    '太平洋': '太',
    'クラウン': 'ク',
    'オリックス': 'オ',
    '阪急': '急',
    '近鉄': '近',
    '楽天': '楽',
    'ロッテ': 'ロ',
    '東京': '東',
    '毎日': '毎',
    '大毎': '毎大',
    '大映': '大',
    '松竹': '松',
    '高橋': '高',
    'トンボ': 'ト',
  };
  for (final entry in codes.entries) {
    if (team.contains(entry.key)) return entry.value.split('').toSet();
  }
  return {};
}
