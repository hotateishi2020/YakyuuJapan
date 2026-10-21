/// Add confirmed CS outcomes to each league using its recorded series results.
void addTimelineCs(List<Map<String, dynamic>> seasons, List<Map<String, dynamic>> games) {
  int n(Object? value) => int.tryParse('$value') ?? 0;
  bool played(Map<String, dynamic> g) => RegExp(r'終了|コールド|試合中|[0-9０-９]+回').hasMatch('${g['state']}') && !RegExp('中止|延期').hasMatch('${g['state']}');
  bool finished(Map<String, dynamic> g) => RegExp('終了|コールド').hasMatch('${g['state']}') && !RegExp('中止|延期').hasMatch('${g['state']}');
  for (final season in seasons) {
    final year = n(season['year']);
    if (year < 2004) continue;
    for (final league in season['leagues'] as List) {
      league.remove('cs_first_winner');
      league.remove('cs_first_loser');
      league.remove('cs_final_winner');
      league.remove('cs_final_loser');
      final teams = (league['teams'] as List).cast<Map<String, dynamic>>();
      final ids = teams.map((t) => n(t['id_team'])).toSet();
      // Japan Series participation is independent of whether CS was held.
      final japanSeriesTeams = {
        for (final g in games.where((g) => n(g['year']) == year && g['code_game'] == 'JS' && played(g)))
          ...[n(g['id_team_home']), n(g['id_team_away'])],
      };
      final finalist = japanSeriesTeams.where(ids.contains).firstOrNull;
      if (finalist != null) league['cs_final_winner'] = finalist;
      if ((year < 2007 || year == 2020) && n(league['id_league']) != 2) continue;
      league['postseason_format'] = year < 2007 ? 'プレーオフ' : 'CS';
      final pool = games.where((g) => n(g['year']) == year && ids.contains(n(g['id_team_home'])) && ids.contains(n(g['id_team_away']))).toList();
      final first = pool.where((g) => g['code_game'] == 'CS1').toList();
      final finalStage = pool.where((g) => ['CSF', 'CS2', 'CS'].contains(g['code_game'])).toList();
      int rank(int id) => n(teams.firstWhere((t) => n(t['id_team']) == id)['rank']);
      Set<int> entrants(List<Map<String, dynamic>> rows) => {
        for (final g in rows.where(played)) ...[n(g['id_team_home']), n(g['id_team_away'])],
      };
      int? winner(List<Map<String, dynamic>> rows, {required bool finalRound}) {
        final pair = entrants(rows).toList()..sort((a, b) => rank(a).compareTo(rank(b)));
        if (pair.length != 2) return null;
        // The 2004–2006 published league ranks include playoff results.
        // Home field identifies the regular-season higher seed reliably.
        final upper = n(rows.firstWhere(played)['id_team_home']);
        final lower = pair.firstWhere((id) => id != upper);
        var advantage = finalRound && (year == 2006 || year >= 2008) ? 1 : 0;
        if (finalRound && year >= 2026) {
          final a = teams.firstWhere((t) => n(t['id_team']) == upper);
          final b = teams.firstWhere((t) => n(t['id_team']) == lower);
          final behind = ((n(a['wins']) - n(b['wins'])) + (n(b['losses']) - n(a['losses']))) / 2;
          if (behind >= 10 || n(b['wins']) < n(b['losses'])) advantage = 2;
        }
        final target = !finalRound ? 2 : year <= 2007 || year == 2020 ? 3 : advantage == 2 ? 5 : 4;
        final maximum = target * 2 - 1 - advantage;
        var upperWins = advantage, lowerWins = 0, completed = 0;
        for (final g in rows.where(finished)) {
          if (g['score_home'] == null || g['score_away'] == null) continue;
          completed++;
          final h = n(g['score_home']), a = n(g['score_away']);
          if (h == a) continue;
          final id = n(g[h > a ? 'id_team_home' : 'id_team_away']);
          if (id == upper) upperWins++; else lowerWins++;
        }
        if (completed == 0) return null;
        final remaining = (maximum - completed).clamp(0, maximum);
        if (upperWins >= target || upperWins >= lowerWins + remaining) return upper;
        if (lowerWins >= target || lowerWins > upperWins + remaining) return lower;
        return null;
      }
      final firstEntrants = entrants(first);
      final advanced = entrants(finalStage).where(firstEntrants.contains).firstOrNull;
      final firstWinner = advanced ?? winner(first, finalRound: false);
      if (firstWinner != null && first.isNotEmpty) {
        league['cs_first_winner'] = firstWinner;
        final loser = firstEntrants.where((id) => id != firstWinner).firstOrNull;
        if (loser != null) league['cs_first_loser'] = loser;
      }
      if (finalStage.isNotEmpty) {
        final finalWinner = finalist ?? winner(finalStage, finalRound: true);
        if (finalWinner != null) {
          league['cs_final_winner'] = finalWinner;
          final finalists = entrants(finalStage);
          if (finalists.length == 2 && finalists.contains(finalWinner)) {
            league['cs_final_loser'] = finalists.singleWhere((id) => id != finalWinner);
          }
        }
      }
    }
  }
}
