import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import '../tools/Postgres.dart';

// 投球回の .1 / .2 は小数ではなく1アウト / 2アウト。
int inningsToOuts(String value) {
  if (RegExp(r'^[\s+＋]+$').hasMatch(value) && value.trim().isNotEmpty) return 0;
  final text = value.replaceAll(RegExp(r'[\s+＋]+'), '');
  final fraction = RegExp(r'^(\d+)?([12])/3$').firstMatch(text);
  if (fraction != null) {
    return (int.tryParse(fraction[1] ?? '') ?? 0) * 3 + int.parse(fraction[2]!);
  }
  final match = RegExp(r'^(\d+)(?:\.([012]))?$').firstMatch(text);
  if (match == null) throw FormatException('投球回の形式が不正です: $value');
  return int.parse(match[1]!) * 3 + int.parse(match[2] ?? '0');
}

String usageName(String value) => value
    .replaceAllMapped(RegExp(r'[！-～]'),
        (match) => String.fromCharCode(match.group(0)!.codeUnitAt(0) - 0xfee0))
    .replaceAll(RegExp(r'[\s　・.．]+'), '')
    .replaceAll('髙', '高')
    .replaceAll('﨑', '崎')
    .replaceAll('海', '海')
    .toLowerCase();

List<Map<String, dynamic>> usageMaps(dynamic value) => value is List
    ? value.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
    : [];
Map<String, dynamic> usageMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
int usageInt(dynamic value) => int.tryParse('$value') ?? 0;

List<String> npbSeasonGames(String source, int year) {
  final result = <String>{};
  for (final row in html.parse(source).querySelectorAll('tr')) {
    if (row.querySelector('.team1') == null ||
        row.querySelector('.score1') == null) continue;
    if (int.tryParse(row.querySelector('.score1')!.text.trim()) == null ||
        int.tryParse(row.querySelector('.score2')?.text.trim() ?? '') == null)
      continue;
    for (final a in row.querySelectorAll('a[href]')) {
      final href = a.attributes['href']!;
      if (RegExp('^/scores/$year/[0-9]{4}/[a-z]+-[a-z]+-[0-9]+/\$')
          .hasMatch(href)) result.add('https://npb.jp${href}box.html');
    }
  }
  return result.toList();
}

List<Map<String, dynamic>> parseNpbUsageGame(String source, String url) {
  final doc = html.parse(source);
  final title = doc.querySelector('.game_tit h3')?.text ?? '';
  if (title.contains('CS ') ||
      title.contains('日本シリーズ') ||
      title.contains('オールスター') ||
      title.contains('オープン戦')) return [];
  if ((doc.querySelector('.game_info')?.text ?? '').contains('ノーゲーム'))
    return [];
  if (!(RegExp('試合終了|コールドゲーム')
      .hasMatch(doc.querySelector('.game_info')?.text ?? '')))
    throw StateError('試合終了を確認できません: $url');
  final match = RegExp(r'/([a-z]+)-([a-z]+)-\d+/').firstMatch(url)!;
  final rows = <Map<String, dynamic>>[];
  for (final side in ['top', 'bottom']) {
    final table = doc.querySelector('#table_${side}_p > table > tbody');
    if (table == null) throw StateError('投手成績がありません: $url');
    var index = 0;
    for (final tr in table.children.where((e) => e.localName == 'tr')) {
      final cells = tr.children.toList();
      if (cells.length < 5) continue;
      final link = cells[1].querySelector('a');
      final id = RegExp(r'/players/(\d+)\.html')
          .firstMatch(link?.attributes['href'] ?? '')?[1];
      if (id == null) throw StateError('投手IDがありません: $url');
      rows.add({
        'source_player_id': id,
        'name': cells[1].text.trim(),
        'team_code': side == 'top' ? match[2] : match[1],
        'starter': index++ == 0,
        'outs': inningsToOuts(cells[4].text),
      });
    }
    if (index == 0) throw StateError('投手が0人です: $url');
  }
  return rows;
}

List<Map<String, dynamic>> aggregateUsageGames(
    List<Map<String, dynamic>> games, String teamCode) {
  final players = <String, Map<String, dynamic>>{};
  final seen = <String>{};
  for (final game in games) {
    if (!seen.add('${game['game_key']}')) continue;
    final rows = usageMaps(game['players'])
        .where((row) => '${row['team_code']}' == teamCode)
        .toList();
    if (rows.isEmpty) continue;
    if (rows.where((p) => p['starter'] == true).length != 1)
      throw StateError('先発投手は各球団1人である必要があります');
    final ids = <String>{};
    for (final row in rows) {
      final id = '${row['source_player_id']}';
      if (!ids.add(id)) throw StateError('同じ試合に投手IDが重複しています');
      final outs = usageInt(row['outs']);
      if (outs < 0) throw StateError('投球アウト数が負です');
      final player = players.putIfAbsent(
          id,
          () => {
                'source_player_id': id,
                'name': row['name'],
                'starts': 0,
                'appearances': 0,
                'starter_outs': 0,
                'relief_outs': 0,
                'total_outs': 0,
              });
      final role = row['starter'] == true ? 'starter_outs' : 'relief_outs';
      player[role] = usageInt(player[role]) + outs;
      player['total_outs'] = usageInt(player['total_outs']) + outs;
      player['appearances'] = usageInt(player['appearances']) + 1;
      if (row['starter'] == true)
        player['starts'] = usageInt(player['starts']) + 1;
    }
  }
  return players.values.toList();
}

List<Map<String, dynamic>> parseUsageRoster(String source, int year) {
  final doc = html.parse(source);
  if (!doc.querySelectorAll('h2').any((e) => e.text.contains('$year年度')))
    throw StateError('名簿の年度が一致しません');
  final result = <String, Map<String, dynamic>>{};
  var registration = '';
  var position = '';
  for (final el in doc.querySelectorAll('.rosterSub, .rosterlisttbl tr')) {
    if (el.classes.contains('rosterSub')) {
      registration = el.text.contains('育成') ? '育成' : '支配下';
      continue;
    }
    final headers = el.querySelectorAll('th');
    if (headers.length >= 2) {
      position = headers[1].text.trim();
      continue;
    }
    if (!{'投手', '捕手', '内野手', '外野手', '指名打者'}.contains(position)) continue;
    final cells = el.children.toList();
    if (cells.length < 7) continue;
    final id = RegExp(r'/players/(\d+)\.html')
        .firstMatch(cells[1].querySelector('a')?.attributes['href'] ?? '')?[1];
    if (id == null) continue;
    result[id] = {
      'source_player_id': id,
      'player_key': 'npb:$id',
      'name': cells[1].text.replaceAll(RegExp(r'\s+'), ''),
      'source_surname': cells[1].text.trim().split(RegExp(r'[\s　]+')).first,
      'date_birth': cells[2].text.trim().replaceAll('.', '-'),
      'position_group': position,
      'throws': cells[5].text.trim(),
      'bats': cells[6].text.trim(),
      'registration': registration,
      'registration_source': 'https://npb.jp/bis/teams/',
    };
  }
  if (result.isEmpty) throw StateError('選手名簿が空です');
  return result.values.toList();
}

Map<String, int> parseUsageAppearances(String source, {required bool pitcher}) {
  final result = <String, int>{};
  for (final table in html.parse(source).querySelectorAll('table')) {
    List<String>? headers;
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.children.toList();
      final texts =
          cells.map((e) => e.text.replaceAll(RegExp(r'\s+'), '')).toList();
      final label = pitcher ? '登板' : '試合';
      if (texts.contains('選手') && texts.contains(label)) {
        headers = texts;
        continue;
      }
      if (headers == null ||
          cells.length != headers.length ||
          cells.isEmpty ||
          cells.first.localName != 'td') continue;
      final name = usageName(texts.first.replaceFirst(RegExp(r'^[*＊]+'), ''));
      result[name] = usageInt(texts[headers.indexOf(label)]);
    }
  }
  return result;
}

class StrengthUsage {
  static Future<void> ensure() => Postgres.withConnection((conn) async {
        await conn
            .execute('''CREATE TABLE IF NOT EXISTS t_strength_game_pitching (
      code_org text NOT NULL, int_year integer NOT NULL, game_key text NOT NULL,
      payload jsonb NOT NULL, updated_at timestamptz NOT NULL DEFAULT NOW(),
      PRIMARY KEY(code_org, int_year, game_key))''');
        await conn.execute('''CREATE TABLE IF NOT EXISTS t_strength_pitching (
      code_org text NOT NULL, int_year integer NOT NULL, id_team integer NOT NULL,
      player_key text NOT NULL, starter_outs integer NOT NULL CHECK(starter_outs >= 0),
      relief_outs integer NOT NULL CHECK(relief_outs >= 0), total_outs integer NOT NULL,
      payload jsonb NOT NULL, updated_at timestamptz NOT NULL DEFAULT NOW(),
      CHECK(total_outs = starter_outs + relief_outs),
      PRIMARY KEY(code_org,int_year,id_team,player_key))''');
        await conn
            .execute('''CREATE TABLE IF NOT EXISTS t_strength_player_status (
      code_org text NOT NULL, int_year integer NOT NULL, id_team integer NOT NULL,
      player_key text NOT NULL, payload jsonb NOT NULL,
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      PRIMARY KEY(code_org,int_year,id_team,player_key))''');
      });

  static Future<String> get(http.Client client, String url) async {
    for (var attempt = 0;; attempt++) {
      try {
        final response = await client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 45));
        if (response.statusCode != 200)
          throw StateError('HTTP ${response.statusCode}: $url');
        return utf8.decode(response.bodyBytes);
      } catch (_) {
        if (attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
  }

  static Future<List<Map<String, dynamic>>> cachedGames(
      http.Client client,
      String org,
      int year,
      List<String> keys,
      Future<List<Map<String, dynamic>>> Function(String key) fetch) async {
    final saved = await Postgres.withConnection((conn) async => conn.execute(
        'SELECT game_key,payload FROM t_strength_game_pitching WHERE code_org=\$1 AND int_year=\$2',
        parameters: [org, year]));
    final games = <String, Map<String, dynamic>>{};
    for (final row in saved) {
      final value = row[1] is String ? jsonDecode(row[1] as String) : row[1];
      games['${row[0]}'] = usageMap(value);
    }
    final missing =
        keys.toSet().where((key) => !games.containsKey(key)).toList();
    final batchSize = org == 'mlb' ? 12 : 4;
    for (var offset = 0; offset < missing.length; offset += batchSize) {
      final batch = await Future.wait(missing
          .skip(offset)
          .take(batchSize)
          .map((key) async => {'game_key': key, 'players': await fetch(key)}));
      await Postgres.withConnection((conn) async {
        await conn.execute(
            '''INSERT INTO t_strength_game_pitching(code_org,int_year,game_key,payload)
          SELECT \$1,\$2,(p->>'game_key'),p FROM jsonb_array_elements(\$3::jsonb) p
          ON CONFLICT(code_org,int_year,game_key) DO UPDATE SET payload=EXCLUDED.payload,updated_at=NOW()''',
            parameters: [org, year, jsonEncode(batch)]);
      });
      for (final game in batch) {
        games['${game['game_key']}'] = game;
      }
      if (offset % (batchSize * 25) == 0 ||
          offset + batchSize >= missing.length)
        print(
            '投球回取得 $org/$year ${offset + batch.length}/${missing.length}（保存済み${saved.length}試合）');
    }
    return [for (final key in keys.toSet()) games[key]!];
  }

  static Future<List<Map<String, dynamic>>> npbGames(
      http.Client client, int year) async {
    await ensure();
    final urls = <String>{};
    for (var month = 3; month <= 10; month++) {
      final url =
          'https://npb.jp/games/$year/schedule_${month.toString().padLeft(2, '0')}_detail.html';
      urls.addAll(npbSeasonGames(await get(client, url), year));
    }
    if (urls.isEmpty) throw StateError('NPB公式戦の日程がありません');
    return cachedGames(client, 'npb', year, urls.toList(),
        (url) async => parseNpbUsageGame(await get(client, url), url));
  }

  static Future<List<Map<String, dynamic>>> mlbGames(
      http.Client client, int year, Map<String, dynamic> schedule) async {
    await ensure();
    final keys = <String>[];
    for (final date in usageMaps(schedule['dates'])) {
      for (final game in usageMaps(date['games'])) {
        final status = usageMap(game['status']);
        if (status['abstractGameState'] == 'Final' &&
            status['detailedState'] != 'Cancelled')
          keys.add('${game['gamePk']}');
      }
    }
    return cachedGames(client, 'mlb', year, keys, (key) async {
      final box = usageMap(jsonDecode(await get(
          client, 'https://statsapi.mlb.com/api/v1/game/$key/boxscore')));
      final result = <Map<String, dynamic>>[];
      for (final side in ['home', 'away']) {
        final team = usageMap(usageMap(box['teams'])[side]);
        final players = usageMap(team['players']);
        final ids = team['pitchers'] as List? ?? [];
        if (ids.isEmpty) throw StateError('MLB投手成績が空です: $key');
        for (var index = 0; index < ids.length; index++) {
          final player = usageMap(players['ID${ids[index]}']);
          final stats = usageMap(usageMap(player['stats'])['pitching']);
          result.add({
            'source_player_id': '${ids[index]}',
            'name': usageMap(player['person'])['fullName'],
            'team_code': '${usageMap(team['team'])['id']}',
            'starter': index == 0,
            'outs': inningsToOuts('${stats['inningsPitched'] ?? '0.0'}')
          });
        }
      }
      return result;
    });
  }

  static Future<void> saveTotals(Session conn, String org, int year,
      List<Map<String, dynamic>> teams) async {
    for (final team in teams) {
      final pitchers = usageMaps(team['pitching_workload']);
      if (pitchers.isEmpty) continue;
      await conn.execute(
          'DELETE FROM t_strength_pitching WHERE code_org=\$1 AND int_year=\$2 AND id_team=\$3',
          parameters: [org, year, team['id_team']]);
      await conn.execute(
          '''INSERT INTO t_strength_pitching(code_org,int_year,id_team,player_key,starter_outs,relief_outs,total_outs,payload)
          SELECT \$1,\$2,\$3,p->>'player_key',(p->>'starter_outs')::int,(p->>'relief_outs')::int,(p->>'total_outs')::int,p
          FROM jsonb_array_elements(\$4::jsonb) p
          ON CONFLICT(code_org,int_year,id_team,player_key) DO UPDATE SET
          starter_outs=EXCLUDED.starter_outs,relief_outs=EXCLUDED.relief_outs,total_outs=EXCLUDED.total_outs,payload=EXCLUDED.payload,updated_at=NOW()''',
          parameters: [org, year, team['id_team'], jsonEncode(pitchers)]);
    }
  }

  static Future<void> attachStatuses(
      String org, int year, List<Map<String, dynamic>> teams) async {
    final records = await Postgres.withConnection((conn) async => conn.execute(
        'SELECT id_team,player_key,payload FROM t_strength_player_status WHERE code_org=\$1 AND int_year=\$2',
        parameters: [org, year]));
    for (final team in teams) {
      final statuses = {
        for (final row in records.where((r) => r[0] == team['id_team']))
          '${row[1]}':
              usageMap(row[2] is String ? jsonDecode(row[2] as String) : row[2])
      };
      team['roster'] = [
        for (final player in usageMaps(team['roster']))
          {...player, ...?statuses['${player['player_key']}']}
      ];
    }
  }
}

Future<Map<String, dynamic>> enrichNpbUsage(
    http.Client client,
    Map<String, dynamic> team,
    int year,
    String code,
    List<Map<String, dynamic>> games,
    {List<Map<String, dynamic>> announcements = const []}) async {
  final workload = aggregateUsageGames(games, code);
  final rosterUrl = year == DateTime.now().year
      ? 'https://npb.jp/bis/teams/rst_$code.html'
      : 'https://npb.jp/bis/$year/teams/rst_$code.html';
  final pages = await Future.wait([
    StrengthUsage.get(client, rosterUrl),
    for (final kind in ['idb1', 'idb2', 'idp2'])
      StrengthUsage.get(
          client, 'https://npb.jp/bis/$year/stats/${kind}_$code.html'),
  ]);
  final roster = parseUsageRoster(pages[0], year);
  for (final player in roster) {
    final status = announcements
        .where((s) =>
            s['team_code'] == code && s['player_key'] == player['player_key'])
        .firstOrNull;
    if (status != null)
      player.addAll({
        for (final key in [
          'departure_confirmed',
          'status_source',
          'status_as_of'
        ])
          key: status[key]
      });
  }
  final byId = {for (final p in roster) '${p['source_player_id']}': p};
  for (final player in workload) {
    final id = '${player['source_player_id']}';
    player['player_key'] = 'npb:$id';
    if (byId.containsKey(id)) {
      player['name'] = byId[id]!['name'];
    } else {
      final profile = html.parse(await StrengthUsage.get(
          client, 'https://npb.jp/bis/players/$id.html'));
      final full = profile.querySelector('#pc_v_name')?.text.trim();
      if (full == null || full.isEmpty) throw StateError('投手の正式名を取得できません: $id');
      player['name'] = full.replaceAll(RegExp(r'\s+'), '');
    }
  }
  final official = usageMap(team['pitchers']).values.expand(usageMaps).toList();
  final byName = {for (final p in official) usageName('${p['name']}'): p};
  for (final player in workload) {
    final season = byName[usageName('${player['name']}')];
    if (season != null) {
      if (season['official_outs'] != null &&
          usageInt(season['official_outs']) != usageInt(player['total_outs']))
        throw StateError(
            '公式投球回と試合別合計が一致しません: ${player['name']} ${season['official_outs']}/${player['total_outs']}');
      player['saves'] = season['saves'];
      player['holds'] = season['holds'];
    }
  }
  for (final p in byName.values) {
    if (!workload
        .any((w) => usageName('${w['name']}') == usageName('${p['name']}')))
      throw StateError('試合別投球回が不足: ${p['name']}');
  }
  final batting1 = parseUsageAppearances(pages[1], pitcher: false);
  final batting2 = parseUsageAppearances(pages[2], pitcher: false);
  final pitching2 = parseUsageAppearances(pages[3], pitcher: true);
  final pitching1 = {
    for (final p in workload)
      usageName('${p['name']}'): usageInt(p['appearances'])
  };
  final keyedRoster = [
    for (final p in roster)
      {
        ...p,
        'level_appearances': {
          '1': (p['position_group'] == '投手'
                  ? pitching1
                  : batting1)[usageName('${p['name']}')] ??
              0,
          '2': (p['position_group'] == '投手'
                  ? pitching2
                  : batting2)[usageName('${p['name']}')] ??
              0
        },
        'level_coverage': [1, 2],
      }
  ];
  final idsByName = {
    for (final p in [...roster, ...workload])
      usageName('${p['name']}'): '${p['player_key']}'
  };
  final oldKeys = <String, String>{};
  for (final p in official) {
    final key = idsByName[usageName('${p['name']}')];
    if (key != null) oldKeys['${p['player_key']}'] = key;
  }
  String playerKey(Map<String, dynamic> player) {
    final normalized = usageName('${player['name']}');
    final exact = idsByName[normalized] ?? oldKeys['${player['player_key']}'];
    if (exact != null) return exact;
    var candidates = roster
        .where((p) => usageName('${p['source_surname']}') == normalized)
        .toList();
    if (candidates.isEmpty)
      candidates = roster
          .where((p) => usageName('${p['name']}').startsWith(normalized))
          .toList();
    return candidates.length == 1
        ? '${candidates.single['player_key']}'
        : '${player['player_key']}';
  }

  return {
    ...team,
    'pitching_workload': workload,
    'pitching_game_count': games
        .where(
            (g) => usageMaps(g['players']).any((p) => p['team_code'] == code))
        .length,
    'roster': keyedRoster,
    for (final field in ['positions', 'batting_order'])
      field: [
        for (final group in usageMaps(team[field]))
          {
            ...group,
            'players': [
              for (final p in usageMaps(group['players']))
                {...p, 'player_key': playerKey(p)}
            ]
          }
      ],
    'notes': [
      ...((team['notes'] as List?) ?? [])
          .where((n) => !('$n'.startsWith('先発回数は'))),
      '投手負担率は公式戦の全投球回が分母。先発・中継ぎ（抑えを含む）を登板ごとに区別して集計。',
    ],
  };
}

List<Map<String, dynamic>> parseNpbStatusAnnouncements(
    String source, String url) {
  final result = <Map<String, dynamic>>[];
  for (final row in html.parse(source).querySelectorAll('tr')) {
    final cells = row.children.toList();
    if (cells.length < 3) continue;
    final date =
        RegExp(r'20\d{2}/\d{1,2}/\d{1,2}').firstMatch(cells.first.text)?[0];
    if (date == null) continue;
    String? teamCode;
    String? playerId;
    for (final a in row.querySelectorAll('a[href]')) {
      final href = a.attributes['href']!;
      teamCode ??= RegExp(r'(?:index|rst|registered)_([a-z]+)\.html')
          .firstMatch(href)?[1];
      playerId ??= RegExp(r'/players/(\d+)\.html').firstMatch(href)?[1];
    }
    if (teamCode == null || playerId == null) continue;
    result.add({
      'team_code': teamCode,
      'player_key': 'npb:$playerId',
      'departure_confirmed': true,
      'status_source': url,
      'status_as_of': date
    });
  }
  return result;
}

Future<List<Map<String, dynamic>>> fetchNpbStatusAnnouncements(
    http.Client client, int year) async {
  final result = <Map<String, dynamic>>[];
  for (final page in ['pn_released', 'pn_retired']) {
    final url = 'https://npb.jp/announcement/$year/$page.html';
    try {
      result.addAll(parseNpbStatusAnnouncements(
          await StrengthUsage.get(client, url), url));
    } catch (error) {
      print('公示取得を保留（未確認として表示）: $url $error');
    }
  }
  return result;
}
