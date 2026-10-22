import 'RecordInterleague.dart';

/// Counts are franchise-based, through the selected season. NPB title records
/// start with the two-league era; pre-1950 single-league wins are separate titles.
List<Map<String, dynamic>> championshipSummary(List<Map<String, dynamic>> seasons,
    int selectedYear, {bool mlb = false, Map<String, dynamic> officialLeagueWinners = const {}}) {
  String franchise(Object? raw) {
    final name = '$raw'.replaceAll(RegExp(r'[\s　・]'), '');
    const predecessors = {
      'h': ['南海', 'ダイエー'], 'l': ['西鉄', '太平洋クラブ', 'クラウンライター'],
      'f': ['東映', '日拓'], 'b': ['阪急'], 'db': ['大洋'],
      'm': ['毎日', '大毎', '東京オリオンズ'], 's': ['国鉄', 'サンケイ', 'アトムズ'],
      't': ['大阪タイガース'],
    };
    for (final e in predecessors.entries) {
      if (e.value.any(name.contains)) return e.key;
    }
    return interleagueClubKey(name);
  }
  List<Map<String, dynamic>> maps(dynamic value) => value is List
      ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList() : [];
  int year(Map s) => int.tryParse('${s['year']}') ?? 0;
  String key(Map t) => '${t['id_team'] ?? t['name']}';
  List<Map<String, dynamic>> teams(Map s) => maps(s['leagues']).expand((l) => maps(l['teams'])).toList();
  final history = seasons.where((s) => year(s) <= selectedYear).toList()
    ..sort((a,b) => year(b).compareTo(year(a)));
  if (history.isEmpty) return [];
  int streak(Set<int> wins, {bool interleague = false}) {
    final ordered = wins.toList()..sort();
    var longest = 0, run = 0;
    int? previous;
    for (final y in ordered) {
      final consecutive = previous != null && (y == previous + 1 ||
          (interleague && previous == 2019 && y == 2021));
      run = consecutive ? run + 1 : 1;
      if (run > longest) longest = run;
      previous = y;
    }
    return longest;
  }
  return [for (final team in teams(history.first)) (() {
    final leagueWins = <int>{}, seriesWins = <int>{}, interWins = <int>{};
    for (final season in history) {
      final y = year(season);
      if (!mlb && y < 1950) continue;
      final official = !mlb ? officialLeagueWinners['$y'] : null;
      if (official is Map && official.values.any((name) => franchise(name) == franchise(team['name']))) {
        leagueWins.add(y);
      }
      final matches = teams(season).where((t) => key(t) == key(team));
      for (final t in matches) {
        if (official is! Map && (t['league_champion'] == true ||
            (!mlb && t['league_champion'] == null && '${t['rank']}' == '1'))) {
          leagueWins.add(y);
        }
        if (t['champion'] == true) seriesWins.add(y);
        if (!mlb && y >= 2005 && y != 2020) {
          final winner = season['interleague_champion'];
          final won = winner is Map && winner.isNotEmpty
              ? winner['id_team'] != null ? key(winner) == key(t)
                : [t['name'], t['short_name']].whereType<String>().any((name) => interleagueClubKey(name) == interleagueClubKey(winner['name']))
              : '${t['interleague_rank']}' == '1';
          if (won) interWins.add(y);
        }
      }
    }
    int? since(Set<int> wins) => wins.isEmpty ? null : selectedYear - wins.reduce((a,b) => a > b ? a : b);
    return {...team, 'champion_years': since(seriesWins), 'league_years': since(leagueWins),
      'champion_count': seriesWins.length, 'champion_streak': streak(seriesWins),
      'league_count': leagueWins.length, 'league_streak': streak(leagueWins),
      if (!mlb) 'interleague_count': interWins.length,
      if (!mlb) 'interleague_streak': streak(interWins, interleague: true)};
  })()];
}
