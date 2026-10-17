import 'package:html/parser.dart' as html;
import 'StrengthUsage.dart';
import 'ClubData.dart';

Map<String, dynamic>? parseNpbRecentGame(String source, String url) {
  final doc = html.parse(source);
  if (!RegExp('試合終了|コールドゲーム').hasMatch(doc.querySelector('.game_info')?.text ?? '') || (doc.querySelector('.game_info')?.text ?? '').contains('ノーゲーム')) {
    return null;
  }
  final match = RegExp(r'/scores/(\d{4})/(\d{2})(\d{2})/([a-z]+)-([a-z]+)-').firstMatch(url);
  if (match == null) return null;
  final players = <String, Map<String, dynamic>>{};
  for (final side in ['top', 'bottom']) {
    final table = doc.querySelector('#table_${side}_b > table');
    final innings = table?.querySelectorAll('thead th.inn').map((e) => usageInt(e.text)).toList() ?? [];
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
        'source_player_id': id,
        'name': c[2].text.trim(),
        'lines': <Map<String, dynamic>>[
          {'int_batting': usageInt(c[3].text.trim()), 'int_hit1': usageInt(c[5].text.trim()), 'int_rbi': usageInt(c[6].text.trim()), 'int_steal_base': usageInt(c[7].text.trim())}
        ],
        'plays': plays
      };
    }
    for (final tr in doc.querySelector('#table_${side}_p > table > tbody')?.children ?? []) {
      final c = tr.children;
      if (c.length < 14) continue;
      final id = RegExp(r'/players/(\d+)\.html').firstMatch(c[1].querySelector('a')?.attributes['href'] ?? '')?[1];
      if (id == null) continue;
      final p = players.putIfAbsent(id, () => {'source_player_id': id, 'name': c[1].text.trim(), 'lines': <Map<String, dynamic>>[], 'plays': []});
      final outs = inningsToOuts(c[4].text);
      (p['lines'] as List).add({'double_inning_pitch': '${outs ~/ 3}.${outs % 3}', 'int_pitch': usageInt(c[2].text.trim()), 'int_hit': usageInt(c[5].text.trim()), 'int_strike_out': usageInt(c[9].text.trim()), 'int_runs_earned': usageInt(c[13].text.trim())});
    }
  }
  final scores = doc.querySelectorAll('#table_linescore tbody td.total-1');
  return {'datetime_start': '${match[1]}-${match[2]}-${match[3]}', 'home': npbClubNames[match[4]], 'away': npbClubNames[match[5]], 'score_away': scores.isNotEmpty ? num.tryParse(scores.first.text.trim()) : null, 'score_home': scores.length > 1 ? num.tryParse(scores[1].text.trim()) : null, 'source': url, 'players': players};
}

List<Map<String, dynamic>> officialNpbRecentGames(String sourceId, int year, {Map<String,dynamic>? snapshot}) {
  final result = <Map<String, dynamic>>[];
  for (final raw in usageMap((snapshot ?? readClubFile('npb-recent-games-$year.json'))['games']).values) {
    final g = usageMap(raw), p = usageMap(usageMap(g['players'])[sourceId]);
    if (p.isNotEmpty) {
      result.add({...g, 'players': null, 'lines': p['lines'], 'plays': p['plays']});
    }
  }
  result.sort((a, b) => '${b['datetime_start']}'.compareTo('${a['datetime_start']}'));
  return result.take(25).toList();
}
