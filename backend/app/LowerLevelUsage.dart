import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import '../tools/Postgres.dart';
import 'StrengthUsage.dart';

List<String> farmGameUrls(String source, int year) {
  final urls = <String>{};
  for (final row in html.parse(source).querySelectorAll('tr')) {
    if (int.tryParse(row.querySelector('.score1')?.text.trim() ?? '') == null || int.tryParse(row.querySelector('.score2')?.text.trim() ?? '') == null) {
      continue;
    }
    for (final a in row.querySelectorAll('a[href]')) {
      final path = a.attributes['href']!;
      if (RegExp('^/scores_farm/$year/[0-9]{4}/[a-z]+-[a-z]+-[0-9]+/\$').hasMatch(path)) {
        urls.add('https://npb.jp${path}box.html');
      }
    }
  }
  return urls.toList();
}

/// Actual defensive appearances, including substitutions and position changes.
/// PH/PR/DH alone never count as a defensive appearance.
List<Map<String, dynamic>> parseFarmGame(String source, String url) {
  final doc = html.parse(source);
  final info = doc.querySelector('.game_info')?.text ?? '';
  if (info.contains('ノーゲーム')) return [];
  if (!RegExp('試合終了|コールドゲーム').hasMatch(info)) {
    throw StateError('試合終了を確認できません: $url');
  }
  final match = RegExp(r'/([a-z]+)-([a-z]+)-\d+/').firstMatch(url)!;
  final rows = <Map<String, dynamic>>[];
  for (final side in ['top', 'bottom']) {
    final code = side == 'top' ? match[2] : match[1];
    // Farm-only clubs have no NPB player IDs and are outside the 12-team roster.
    if (['a', 'v'].contains(code)) continue;
    final table = doc.querySelector('#table_${side}_p tbody');
    if (table == null) throw StateError('投手記録がありません: $url');
    var index = 0;
    for (final tr in table.children) {
      final cells = tr.querySelectorAll('td');
      if (cells.length < 5) continue;
      final id = RegExp(r'/players/(\d+)\.html').firstMatch(cells[1].querySelector('a')?.attributes['href'] ?? '')?[1];
      if (id == null) throw StateError('投手IDがありません: $url');
      rows.add({'source_player_id': id, 'team_code': code, 'starter': index++ == 0, 'positions': <String>[], 'pitcher': true});
    }
  }
  const positions = {'捕': 'C', '一': '1B', '二': '2B', '三': '3B', '遊': 'SS', '左': 'LF', '中': 'CF', '右': 'RF'};
  for (final side in ['top', 'bottom']) {
    if (['a', 'v'].contains(side == 'top' ? match[2] : match[1])) continue;
    final table = doc.querySelector('#table_${side}_b tbody');
    if (table == null) throw StateError('打者出場記録がありません: $url');
    for (final tr in table.children) {
      final cells = tr.querySelectorAll('td');
      if (cells.length < 3) continue;
      final id = RegExp(r'/players/(\d+)\.html').firstMatch(cells[2].querySelector('a')?.attributes['href'] ?? '')?[1];
      if (id == null) throw StateError('打者IDがありません: $url');
      rows.add({
        'source_player_id': id,
        'team_code': side == 'top' ? match[2] : match[1],
        'positions': [
          for (final e in positions.entries)
            if (cells[1].text.contains(e.key)) e.value
        ],
        'pitcher': false,
      });
    }
  }
  return rows;
}

Map<String, Map<String, dynamic>> aggregateLowerUsage(List<Map<String, dynamic>> games, String code) {
  final result = <String, Map<String, dynamic>>{};
  final seen = <String>{};
  for (final game in games) {
    if (!seen.add('${game['game_key']}')) continue;
    final appearances = <String>{};
    for (final row in usageMaps(game['players']).where((p) => p['team_code'] == code)) {
      final key = 'npb:${row['source_player_id']}';
      final p = result.putIfAbsent(key, () => {'appearances': 0, 'starts': 0, 'relief': 0, 'positions': <String, int>{}, 'source': game['game_key']});
      if (appearances.add(key)) {
        p['appearances'] = usageInt(p['appearances']) + 1;
      }
      if (row['pitcher'] == true) {
        final role = row['starter'] == true ? 'starts' : 'relief';
        p[role] = usageInt(p[role]) + 1;
      }
      final counts = p['positions'] as Map<String, int>;
      for (final slot in (row['positions'] as List? ?? []).toSet()) {
        counts['$slot'] = (counts['$slot'] ?? 0) + 1;
      }
    }
  }
  return result;
}

class LowerLevelUsage {
  static Future<List<Map<String, dynamic>>> fetch(http.Client client, int year) async {
    await Postgres.withConnection((c) => c.execute('''CREATE TABLE IF NOT EXISTS t_strength_lower_games (
      int_year integer NOT NULL, game_key text NOT NULL, payload jsonb NOT NULL,
      PRIMARY KEY(int_year,game_key))'''));
    final urls = <String>{};
    for (var m = 3; m <= 10; m++) {
      urls.addAll(farmGameUrls(await StrengthUsage.get(client, 'https://npb.jp/farm/$year/schedule_${m.toString().padLeft(2, '0')}_detail.html'), year));
    }
    if (urls.isEmpty) throw StateError('2軍公式戦の日程が取得できません');
    final saved = await Postgres.withConnection((c) => c.execute('SELECT game_key,payload FROM t_strength_lower_games WHERE int_year=\$1', parameters: [year]));
    final games = {for (final r in saved) '${r[0]}': usageMap(r[1] is String ? jsonDecode(r[1] as String) : r[1])};
    final missing = urls.where((u) => !games.containsKey(u)).toList();
    for (var i = 0; i < missing.length; i += 4) {
      final batch = await Future.wait(missing.skip(i).take(4).map((u) async => {'game_key': u, 'players': parseFarmGame(await StrengthUsage.get(client, u), u)}));
      await Postgres.withConnection((c) => c.execute('''INSERT INTO t_strength_lower_games(int_year,game_key,payload)
        SELECT \$1,p->>'game_key',p FROM jsonb_array_elements(\$2::jsonb) p
        ON CONFLICT(int_year,game_key) DO UPDATE SET payload=EXCLUDED.payload''', parameters: [year, jsonEncode(batch)]));
      for (final g in batch) {
        games['${g['game_key']}'] = g;
      }
      if (i % 100 == 0 || i + 4 >= missing.length) {
        print('2軍出場記録 ${i + batch.length}/${missing.length}');
      }
    }
    return [for (final u in urls) games[u]!];
  }

  /// Persist separately so normal roster refreshes retain verified lower-team usage.
  static Future<void> save(int year, List<Map<String, dynamic>> teams, List<Map<String, dynamic>> games, Map<String, String> codes, {int level = 2, String coverage = 'official_season'}) async {
    await StrengthUsage.ensure();
    for (final team in teams) {
      final code = codes['${team['name_team']}'];
      if (code == null) continue;
      final stats = aggregateLowerUsage(games, code);
      final updates = [
        for (final player in usageMaps(team['roster']))
          if (stats.containsKey('${player['player_key']}'))
            {
              'player_key': player['player_key'],
              'record': {
                ...stats['${player['player_key']}']!,
                'as_of': DateTime.now().toIso8601String(),
                'coverage': coverage,
              }
            }
      ];
      if (updates.isEmpty) continue;
      await Postgres.withConnection((c) => c.execute('''INSERT INTO t_strength_player_status(code_org,int_year,id_team,player_key,payload)
        SELECT 'npb',\$1,\$2,p->>'player_key',jsonb_build_object('lower_level_usage',jsonb_build_object(\$3::text,p->'record'))
        FROM jsonb_array_elements(\$4::jsonb) p
        ON CONFLICT(code_org,int_year,id_team,player_key) DO UPDATE SET payload=
        t_strength_player_status.payload || jsonb_build_object('lower_level_usage',
          COALESCE(t_strength_player_status.payload->'lower_level_usage','{}'::jsonb) || (EXCLUDED.payload->'lower_level_usage')),updated_at=NOW()''', parameters: [year, team['id_team'], '$level', jsonEncode(updates)]));
      print('${team['name_team']} $level軍起用 ${updates.length}人登録');
    }
  }
}
