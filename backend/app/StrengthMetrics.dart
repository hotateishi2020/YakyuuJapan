import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'StrengthUsage.dart';
import 'ClubDefense.dart';
import 'ClubData.dart' show readClubFile;

List<Map<String, dynamic>> parseNpbMetrics(String source, {required bool pitching}) {
  final result = <Map<String, dynamic>>[];
  for (final tr in html.parse(source).querySelectorAll('tr')) {
    final cells = tr.querySelectorAll('td');
    final link = tr.querySelector('a[href*="/players/"]');
    final id = RegExp(r'/players/(\d+)\.html').firstMatch(link?.attributes['href'] ?? '')?[1];
    if (cells.length < 23) continue;
    int n(int i) => usageInt(cells[i].text.trim());
    double? d(int i) => double.tryParse(cells[i].text.trim());
    final p = <String, dynamic>{
      if (id != null) 'player_key': 'npb:$id',
      if (id != null) 'source_player_id': id,
      pitching ? 'throws' : 'bats': cells[0].text.trim().startsWith('*')
          ? '左'
          : cells[0].text.trim().startsWith('+')
              ? '両'
              : '右',
      'name': (link?.text ?? cells[0].text).replaceAll(RegExp(r'[*+]'), '').trim().replaceAll(RegExp(r'\s+'), '')
    };
    if (pitching) {
      final outs = inningsToOuts(cells[12].text);
      p.addAll({'whip': outs > 0 ? (n(13) + n(15)) * 3 / outs : null, 'holds': n(5), 'saves': n(4)});
    } else {
      p.addAll({'stolen_bases': n(11), 'caught_stealing': n(12), 'pa': n(2), 'home_runs': n(8), 'doubles': n(6), 'triples': n(7), 'singles': n(5) - n(6) - n(7) - n(8), 'walks': n(15), 'rbi': n(10), 'total_bases_walks': n(9) + n(15), 'ops': d(21) != null && d(22) != null ? d(21)! + d(22)! : null});
    }
    result.add(p);
  }
  if (result.isEmpty) throw StateError('公式成績を取得できません');
  return result;
}

/// Position-specific official totals; never assign a player's errors to all
/// positions they appeared at.
List<Map<String, dynamic>> parseNpbFielding(String source) {
  const slots = {'一塁手': '1B', '二塁手': '2B', '三塁手': '3B', '遊撃手': 'SS', '外野手': 'OF', '捕手': 'C', '投手': 'P'};
  final result = <Map<String, dynamic>>[];
  String? slot;
  for (final node in html.parse(source).querySelectorAll('h5, tr')) {
    if (node.localName == 'h5') {
      slot = slots[node.text.trim()];
      continue;
    }
    final cells = node.querySelectorAll('td');
    if (slot == null || cells.length < 7) continue;
    final counts = [for (var i = 1; i <= 5; i++) int.tryParse(cells[i].text.trim())];
    if (counts.any((n) => n == null || n < 0)) continue;
    result.add({'name': cells[0].text.replaceAll(RegExp(r'[\s*]'), ''), 'position': slot,
      'games': counts[0], 'putouts': counts[1], 'assists': counts[2], 'errors': counts[3], 'double_plays': counts[4]});
  }
  if (result.isEmpty) throw StateError('公式守備成績を取得できません');
  return result;
}

Future<Map<String, dynamic>> fetchStrengthMetrics(http.Client client, Map<String, dynamic> team, int year, String org, {String? npbCode}) async {
  List<Map<String, dynamic>> batting, pitching;
  final fielding = <Map<String, dynamic>>[];
  if (org == 'npb') {
    fielding.addAll(parseNpbFielding(await StrengthUsage.get(client, 'https://npb.jp/bis/$year/stats/idf1_$npbCode.html')));
    batting = parseNpbMetrics(await StrengthUsage.get(client, 'https://npb.jp/bis/$year/stats/idb1_$npbCode.html'), pitching: false);
    pitching = parseNpbMetrics(await StrengthUsage.get(client, 'https://npb.jp/bis/$year/stats/idp1_$npbCode.html'), pitching: true);
  } else {
    final data = usageMap(jsonDecode(await StrengthUsage.get(client, 'https://statsapi.mlb.com/api/v1/stats?stats=season&group=hitting,pitching,fielding&season=$year&sportIds=1&teamId=${team['source_team_id']}&playerPool=ALL&limit=5000')));
    batting = [];
    pitching = [];
    for (final group in usageMaps(data['stats'])) {
      for (final row in usageMaps(group['splits'])) {
        if ('${usageMap(row['team'])['id']}' != '${team['source_team_id']}') {
          continue;
        }
        final stat = usageMap(row['stat']), person = usageMap(row['player']);
        final p = <String, dynamic>{'player_key': 'mlb:${person['id']}', 'source_player_id': '${person['id']}', 'name': person['fullName']};
        if (usageMap(group['group'])['displayName'] == 'hitting') {
          p.addAll({'stolen_bases': stat['stolenBases'], 'caught_stealing': stat['caughtStealing'], 'pa': usageInt(stat['plateAppearances']), 'home_runs': usageInt(stat['homeRuns']), 'doubles': usageInt(stat['doubles']), 'triples': usageInt(stat['triples']), 'singles': usageInt(stat['hits']) - usageInt(stat['doubles']) - usageInt(stat['triples']) - usageInt(stat['homeRuns']), 'walks': usageInt(stat['baseOnBalls']), 'rbi': usageInt(stat['rbi']), 'total_bases_walks': usageInt(stat['totalBases']) + usageInt(stat['baseOnBalls']), 'ops': double.tryParse('${stat['ops']}')});
          batting.add(p);
        } else if (usageMap(group['group'])['displayName'] == 'pitching') {
          p.addAll({'whip': double.tryParse('${stat['whip']}'), 'holds': usageInt(stat['holds']), 'saves': usageInt(stat['saves'])});
          pitching.add(p);
        } else if (usageMap(group['group'])['displayName'] == 'fielding') {
          fielding.add({...p, 'position': usageMap(row['position'])['abbreviation'],
            'games': stat['gamesPlayed'], 'putouts': stat['putOuts'], 'assists': stat['assists'], 'errors': stat['errors'], 'double_plays': stat['doublePlays']});
        }
      }
    }
    final rosterKeys = usageMaps(team['roster']).map((p) => p['player_key']).toSet();
    final missing = [...batting, ...pitching].where((p) => !rosterKeys.contains(p['player_key'])).map((p) => p['source_player_id']).toSet();
    if (missing.isNotEmpty) {
      final people = usageMap(jsonDecode(await StrengthUsage.get(client, 'https://statsapi.mlb.com/api/v1/people?personIds=${missing.join(',')}')));
      for (final person in usageMaps(people['people'])) {
        for (final p in [...batting, ...pitching].where((p) => p['source_player_id'] == '${person['id']}')) {
          p['bats'] = usageMap(person['batSide'])['code'];
          p['throws'] = usageMap(person['pitchHand'])['code'];
        }
      }
    }
    if (batting.isEmpty || pitching.isEmpty) throw StateError('MLB球団成績が空です');
  }
  if (org == 'npb') {
    final candidates = [...usageMaps(team['roster']), ...usageMaps(team['pitching_workload'])];
    for (final p in [...batting, ...pitching]) {
      final matches = candidates.where((r) => usageName('${r['name']}') == usageName('${p['name']}')).toList();
      final keys = matches.map((r) => r['player_key']).whereType<String>().toSet();
      if (keys.length == 1) {
        p['player_key'] = keys.single;
      } else {
        p['player_key'] = 'npb:name:${usageName('${p['name']}')}';
      }
    }
  }
  Map<String, dynamic>? defense;
  if (org == 'mlb') {
    try {
      defense = await fetchTeamDefense(client, year, team['source_team_id']);
    } catch (_) {
      // Leave the previous verified snapshot in place when the public source is unavailable.
    }
  }
  final note = readClubFile('club-defense-evidence-$year.json')['$org:$npbCode'];
  return {if (note != null) 'defense_note': note, if (defense != null) 'defense_analysis': defense, 'fielding_stats': fielding, 'batting_stats': batting, 'pitching_stats': pitching, 'metrics_updated_at': DateTime.now().toUtc().toIso8601String()};
}
