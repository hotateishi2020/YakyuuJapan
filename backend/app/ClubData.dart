import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'OrgLeague.dart';
import 'StrengthUsage.dart';

Map<String, dynamic> readClubFile(String name) {
  for (final path in ['data/$name', 'backend/data/$name']) {
    final file = File(path);
    if (file.existsSync()) return usageMap(jsonDecode(file.readAsStringSync()));
  }
  return {};
}

const npbClubNames = {'g': '巨人', 't': '阪神', 'db': 'DeNA', 'c': '広島', 'd': '中日', 's': 'ヤクルト', 'h': 'ソフトバンク', 'f': '日本ハム', 'm': 'ロッテ', 'l': '西武', 'e': '楽天', 'b': 'オリックス'};
String clubKey(Map<String, dynamic> team) {
  final url = '${team['url_npb_players'] ?? ''}';
  final code = RegExp(r'(?:rst_|index_|/teams/)([a-z]+)(?:\.html|/)').firstMatch(url)?[1];
  if (code != null && npbClubNames.containsKey(code)) return code;
  final name = '${team['name_team'] ?? team['name_short'] ?? ''}';
  for (final e in npbClubNames.entries) {
    if (name.contains(e.value) || e.key == 'g' && name.contains('読売')) {
      return e.key;
    }
  }
  return '${team['name_shortest'] ?? team['team_code'] ?? ''}';
}

Future<Map<String, dynamic>> readSeasonSchedule(Connection conn, OrgKind org, int year) async {
  final teams = (await conn.execute('SELECT id,color_back,color_font,name_short,name_shortest,url_npb_players,id_league FROM m_team WHERE id_league IN (${org.leagueIds.join(',')}) AND NOT COALESCE(flg_delete,false)')).map((r) => r.toColumnMap()).toList();
  final snapshot = readClubFile('schedule-$year.json');
  final rows = await conn.execute('''
 SELECT g.id,g.datetime_start::text AS datetime_start,g.id_team_home,g.id_team_away,g.score_home,g.score_away,g.state,g.code_game,g.flg_delete,
 h.color_back AS color_back_home,h.color_font AS color_font_home,h.name_shortest AS name_home,a.name_shortest AS name_away,h.name_short AS name_home_logo,a.name_short AS name_away_logo,h.id_league AS league_home,a.id_league AS league_away
 FROM t_game g JOIN m_team h ON h.id=g.id_team_home JOIN m_team a ON a.id=g.id_team_away
 WHERE h.id_league IN (${org.leagueIds.join(',')}) AND g.datetime_start >= make_date(\$1,1,1) AND g.datetime_start < make_date(\$1+1,1,1)
 ORDER BY g.datetime_start,g.id
 ''', parameters: [year]);
  final games = mergeSeasonSchedule(teams, usageMaps(snapshot[org.code]), rows.map((r) => r.toColumnMap()).toList());
  return {'org': org.code, 'year': year, 'checked_at': snapshot['checked_at'], 'games': games};
}

/// Match official fixtures first. Never invent a second game from a timezone shift.
List<Map<String, dynamic>> mergeSeasonSchedule(List<Map<String, dynamic>> teams, List<Map<String, dynamic>> snapshot, List<Map<String, dynamic>> stored) {
  final byKey = {for (final t in teams) clubKey(t): t};
  final games = <String, Map<String, dynamic>>{};
  for (final raw in snapshot) {
    final h = byKey['${raw['home_code']}'], a = byKey['${raw['away_code']}'];
    if (h == null || a == null) continue;
    final row = {...raw, 'id_team_home': h['id'], 'id_team_away': a['id'], 'color_back_home': h['color_back'], 'color_font_home': h['color_font'], 'name_home': h['name_shortest'], 'name_away': a['name_shortest'], 'name_home_logo': h['name_short'], 'name_away_logo': a['name_short'], 'league_home': h['id_league'], 'league_away': a['id_league']};
    games['${raw['date']}:${h['id']}:${a['id']}:${raw['game_number'] ?? 1}'] = row;
  }

  for (final row in stored) {
    final start = DateTime.tryParse('${row['datetime_start']}'.replaceFirst(' ', 'T'));
    if (start == null) continue;
    var date = '${row['datetime_start']}'.substring(0, 10);
    final pair = games.entries.where((e) => e.value['id_team_home'] == row['id_team_home'] && e.value['id_team_away'] == row['id_team_away']).toList();
    // MLB stores the official UTC start. Prefer exact kickoff matching over calendar date.
    final timed = pair.where((e) {
      final time = DateTime.tryParse('${e.value['time']}');
      return time != null && time.toUtc() == start.toUtc();
    }).toList();
    String? key = timed.length == 1 ? timed.single.key : null;
    if (key != null) date = '${games[key]!['date']}';
    final sameDay = pair.where((e) => e.value['date'] == date).toList();
    if (key == null && sameDay.length > 1) {
      continue; // No external game ID: retain both official doubleheader rows.
    }
    key ??= sameDay.length == 1 ? sameDay.single.key : '$date:${row['id_team_home']}:${row['id_team_away']}:1';
    final existing = games[key], state = '${row['state'] ?? ''}';
    if (row['flg_delete'] == true) {
      final replacement = stored.any((other) => other['flg_delete'] != true &&
          other['id_team_home'] == row['id_team_home'] && other['id_team_away'] == row['id_team_away'] &&
          '${other['datetime_start']}'.startsWith('${row['datetime_start']}'.substring(0, 10)));
      if (!replacement && existing?['finished'] != true) games.remove(key);
      continue;
    }
    final ended = state.contains('終了') || state.contains('コールド');
    final canceled = state.contains('中止') || state.contains('延期');
    if (existing != null && existing['finished'] == true && !ended) continue;
    if (existing == null || existing['finished'] != true || ended || canceled || state.contains('回') || state == '試合中') {
      games[key] = {
        ...?existing,
        ...row,
        'date': date,
        'time': row['datetime_start'],
        'finished': ended,
        'regular': existing?['regular'] ?? ['NM', 'EX'].contains(row['code_game'])
      };
    }
  }
  return games.values.toList()..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
}
