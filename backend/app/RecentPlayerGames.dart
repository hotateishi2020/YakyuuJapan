import 'package:html/parser.dart' as html;
import 'StrengthUsage.dart';
import 'ClubData.dart';
import 'Achieve.dart';

/// Keep locally verified decision and velocity when official logs omit them.
void mergeRecentPitchingMetadata(Map<String, dynamic> official, Map<String, dynamic> stored) {
  final pitching = usageMaps(stored['lines']).where((l) => l['double_inning_pitch'] != null).toList();
  if (pitching.length != 1) return;
  official['lines'] = [for (final line in usageMaps(official['lines'])) {
    ...line,
    if (line['double_inning_pitch'] != null)
      for (final key in ['code_result_pitcher', 'int_velo_max', 'txt_achieve', 'starter'])
        if (line[key] == null && pitching.single[key] != null) key: pitching.single[key],
  }];
}

/// Older box-score caches omitted runs, walks and the starter flag.
bool needsNpbPitchingRefresh(dynamic raw) {
  final game = usageMap(raw);
  if (game.isEmpty) return true;
  for (final player in usageMap(game['players']).values) {
    for (final line in usageMaps(usageMap(player)['lines'])) {
      if (line['double_inning_pitch'] != null &&
          ['int_runs', 'int_four', 'int_dead_pitching', 'starter', 'code_result_pitcher']
              .any((key) => line[key] == null)) {
        return true;
      }
    }
  }
  return false;
}

Map<String, dynamic>? parseNpbRecentGame(String source, String url) {
  final doc = html.parse(source);
  if (!RegExp('試合終了|コールドゲーム').hasMatch(doc.querySelector('.game_info')?.text ?? '') || (doc.querySelector('.game_info')?.text ?? '').contains('ノーゲーム')) {
    return null;
  }
  final match = RegExp(r'/scores/(\d{4})/(\d{2})(\d{2})/([a-z]+)-([a-z]+)-').firstMatch(url);
  if (match == null) return null;
  final players = <String, Map<String, dynamic>>{};
  var gameInnings = 0;
  for (final side in ['top', 'bottom']) {
    final opponent = npbClubNames[match[side == 'top' ? 4 : 5]];
    final table = doc.querySelector('#table_${side}_b > table');
    final innings = table?.querySelectorAll('thead th.inn').map((e) => usageInt(e.text)).toList() ?? [];
    for (final inning in innings) {
      if (inning > gameInnings) gameInnings = inning;
    }
    for (final tr in table?.querySelector('tbody')?.children ?? []) {
      final c = tr.children;
      if (c.length < 8) continue;
      final id = RegExp(r'/players/(\d+)\.html').firstMatch(c[2].querySelector('a')?.attributes['href'] ?? '')?[1];
      if (id == null) continue;
      final plays = <Map<String, dynamic>>[];
      for (var i = 8; i < c.length; i++) {
        final text = c[i].text.trim();
        if (text.isNotEmpty && text != '-') {
          plays.add({'inning': i - 8 < innings.length ? innings[i - 8] : null, 'result': text, 'bases': RegExp('安|２|３|本').hasMatch(text) ? 1 : 0});
        }
      }
      players[id] = {
        'opponent': opponent, 'source_player_id': id,
        'name': c[2].text.trim(),
        'lines': <Map<String, dynamic>>[
          {'int_batting': usageInt(c[3].text.trim()), 'int_hit1': usageInt(c[5].text.trim()), 'int_rbi': usageInt(c[6].text.trim()), 'int_steal_base': usageInt(c[7].text.trim())}
        ],
        'plays': plays
      };
    }
    var pitcherIndex = 0;
    for (final tr in doc.querySelector('#table_${side}_p > table > tbody')?.children ?? []) {
      final c = tr.children;
      if (c.length < 14) continue;
      final id = RegExp(r'/players/(\d+)\.html').firstMatch(c[1].querySelector('a')?.attributes['href'] ?? '')?[1];
      if (id == null) continue;
      final p = players.putIfAbsent(id, () => {'opponent': opponent, 'source_player_id': id, 'name': c[1].text.trim(), 'lines': <Map<String, dynamic>>[], 'plays': []});
      final outs = inningsToOuts(c[4].text);
      (p['lines'] as List).add({'code_result_pitcher': c[0].text.trim().replaceAll('敗', '負'), 'starter': pitcherIndex++ == 0, 'int_four': usageInt(c[7].text.trim()), 'int_dead_pitching': usageInt(c[8].text.trim()), 'int_runs': usageInt(c[12].text.trim()), 'double_inning_pitch': '${outs ~/ 3}.${outs % 3}', 'int_pitch': usageInt(c[2].text.trim()), 'int_hit': usageInt(c[5].text.trim()), 'int_strike_out': usageInt(c[9].text.trim()), 'int_balk': usageInt(c[11].text.trim()), 'int_runs_earned': usageInt(c[13].text.trim())});
    }
  }
  for (final player in players.values) {
    for (final line in player['lines'] as List<Map<String, dynamic>>) {
      if (line['double_inning_pitch'] == null) continue;
      final marks = pitcherMarks(finished: true, starter: line['starter'] == true,
        innings: num.tryParse('${line['double_inning_pitch']}') ?? 0,
        pitches: usageInt(line['int_pitch']), hits: usageInt(line['int_hit']),
        walks: usageInt(line['int_four']), hbp: usageInt(line['int_dead_pitching']),
        runs: usageInt(line['int_runs']), earned: usageInt(line['int_runs_earned']),
        balks: usageInt(line['int_balk']), gameInnings: gameInnings);
      line['txt_achieve'] = marks;
    }
  }
  final scores = doc.querySelectorAll('#table_linescore tbody td.total-1');
  return {'game_innings': gameInnings, 'datetime_start': '${match[1]}-${match[2]}-${match[3]}', 'home': npbClubNames[match[4]], 'away': npbClubNames[match[5]], 'score_away': scores.isNotEmpty ? num.tryParse(scores.first.text.trim()) : null, 'score_home': scores.length > 1 ? num.tryParse(scores[1].text.trim()) : null, 'source': url, 'players': players};
}

List<Map<String, dynamic>> officialNpbRecentGames(String sourceId, int year, {Map<String,dynamic>? snapshot}) {
  final result = <Map<String, dynamic>>[];
  for (final raw in usageMap((snapshot ?? readClubFile('npb-recent-games-$year.json'))['games']).values) {
    final g = usageMap(raw), p = usageMap(usageMap(g['players'])[sourceId]);
    if (p.isNotEmpty) {
      var innings = usageInt(g['game_innings']);
      for (final player in usageMap(g['players']).values) {
        for (final play in usageMaps(usageMap(player)['plays'])) {
          final inning = usageInt(play['inning']);
          if (inning > innings) innings = inning;
        }
      }
      p['lines'] = [for (final line in usageMaps(p['lines'])) {
        ...line,
        if (line['double_inning_pitch'] != null && innings > 0)
          'txt_achieve': pitcherMarks(finished: true, starter: line['starter'] == true,
            innings: num.tryParse('${line['double_inning_pitch']}') ?? 0,
            pitches: usageInt(line['int_pitch']), hits: usageInt(line['int_hit']),
            walks: usageInt(line['int_four']), hbp: usageInt(line['int_dead_pitching']),
            runs: usageInt(line['int_runs']), earned: usageInt(line['int_runs_earned']),
            balks: usageInt(line['int_balk']), gameInnings: innings),
      }];
      result.add({...g, 'players': null, 'opponent': p['opponent'], 'lines': p['lines'], 'plays': p['plays']});
    }
  }
  result.sort((a, b) => '${b['datetime_start']}'.compareTo('${a['datetime_start']}'));
  return result.take(25).toList();
}
