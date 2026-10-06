/// MLB は Yahoo（翌朝 JST）と歴史インポート（現地日付）で暦日が1日ずれる。
/// 1〜7時台の開始は前日夜の試合とみなす。00:00 は時刻未設定としてずらさない。
String gameNightDate(Map<String, dynamic> game) {
  final date = _dateOnly(game['date_game']);
  final time = '${game['time_game'] ?? game['datetime_start'] ?? ''}';
  final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(time);
  if (match == null) return date;
  final hour = int.tryParse(match.group(1) ?? '') ?? 12;
  if (hour <= 0 || hour >= 8) return date;
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  final prev = parsed.subtract(const Duration(days: 1));
  final month = prev.month.toString().padLeft(2, '0');
  final day = prev.day.toString().padLeft(2, '0');
  return '${prev.year}-$month-$day';
}

/// 同一日・同一カードの重複試合を1件にまとめる。
/// Yahoo 取得行と歴史インポート行が同じ対戦で二重に入ると、カード増と星の誤計上になる。
List<Map<String, dynamic>> dedupeSameDayMatchupRows(List<Map<String, dynamic>> games) {
  if (games.length <= 1) return games;
  final buckets = <String, List<Map<String, dynamic>>>{};
  final order = <String>[];
  for (final game in games) {
    final key = _dayMatchupKey(game);
    if (!buckets.containsKey(key)) {
      order.add(key);
      buckets[key] = [];
    }
    buckets[key]!.add(game);
  }
  final out = <Map<String, dynamic>>[];
  for (final key in order) {
    out.addAll(_pickDayMatchup(buckets[key]!));
  }
  return _mergeAdjacentScoreDupes(out);
}

String _dateOnly(dynamic value) {
  final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch('${value ?? ''}');
  return match?.group(0) ?? '${value ?? ''}'.trim();
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value'.trim()) ?? 0;
}

bool _finished(Map<String, dynamic> game) => '${game['state'] ?? ''}'.contains('試合終了');

String _scoreKey(Map<String, dynamic> game) => '${game['score_home']}|${game['score_away']}';

String _dayMatchupKey(Map<String, dynamic> game) {
  final home = _asInt(game['id_team_home']);
  final away = _asInt(game['id_team_away']);
  final a = home <= away ? home : away;
  final b = home <= away ? away : home;
  final code = '${game['code_game'] ?? ''}'.trim().toUpperCase();
  return '${gameNightDate(game)}|$a|$b|$code';
}

int _quality(Map<String, dynamic> game) {
  var score = 0;
  final state = '${game['state'] ?? ''}';
  if (state.contains('試合終了')) score += 50;
  if (state.contains('試合中')) score += 40;
  if ('${game['time_game'] ?? ''}'.trim().isNotEmpty) score += 20;
  final summaries = game['summaries'];
  if (summaries is List) score += summaries.length * 5;
  final idGame = _asInt(game['id_game'] ?? game['id']);
  if (idGame > 0 && idGame < 2000) score += 25;
  if ('${game['name_pitcher_home'] ?? ''}'.trim().isNotEmpty) score += 4;
  if ('${game['name_pitcher_away'] ?? ''}'.trim().isNotEmpty) score += 4;
  return score;
}

bool _yahooSource(Map<String, dynamic> game) {
  final id = _asInt(game['id_game'] ?? game['id']);
  return id > 0 && id < 2000;
}

String _matchupCodeKey(Map<String, dynamic> game) {
  final home = _asInt(game['id_team_home']);
  final away = _asInt(game['id_team_away']);
  final a = home <= away ? home : away;
  final b = home <= away ? away : home;
  final code = '${game['code_game'] ?? ''}'.trim().toUpperCase();
  return '$a|$b|$code';
}

List<Map<String, dynamic>> _pickDayMatchup(List<Map<String, dynamic>> group) {
  if (group.length == 1) return group;
  group.sort((a, b) => _quality(b).compareTo(_quality(a)));
  final finished = group.where(_finished).toList();
  final distinctScores = finished.map(_scoreKey).toSet();
  // 同じ夜扱いになってもスコアが違う連戦は別試合（DS の G1/G2 など）。
  if (distinctScores.length > 1) {
    final best = <String, Map<String, dynamic>>{};
    for (final game in finished) {
      final key = _scoreKey(game);
      final prev = best[key];
      if (prev == null || _quality(game) > _quality(prev)) best[key] = game;
    }
    return best.values.toList();
  }
  final hasYahoo = group.any(_yahooSource);
  final hasHistorical = group.any((game) => !_yahooSource(game) && _asInt(game['id_game'] ?? game['id']) >= 2000);
  if (hasYahoo && hasHistorical) {
    return [group.first];
  }
  return [group.first];
}

bool _importSourceMix(Map<String, dynamic> a, Map<String, dynamic> b) {
  return _yahooSource(a) != _yahooSource(b);
}

bool _unstarted(Map<String, dynamic> game) => !_finished(game);

bool _nearSameDay(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (_dateOnly(a['date_game']) == _dateOnly(b['date_game'])) return true;
  final left = DateTime.tryParse(gameNightDate(a));
  final right = DateTime.tryParse(gameNightDate(b));
  if (left == null || right == null) return false;
  return left.difference(right).inDays.abs() <= 1;
}

/// 終了試合の同スコア重複、および Yahoo と歴史インポートの未開始重複を1件にする。
List<Map<String, dynamic>> _mergeAdjacentScoreDupes(List<Map<String, dynamic>> games) {
  if (games.length <= 1) return games;
  final used = List<bool>.filled(games.length, false);
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < games.length; i++) {
    if (used[i]) continue;
    var best = games[i];
    final key = _matchupCodeKey(best);
    for (var j = i + 1; j < games.length; j++) {
      if (used[j] || _matchupCodeKey(games[j]) != key) continue;
      final other = games[j];
      final finishedPair = _finished(best) && _finished(other) && _scoreKey(best) == _scoreKey(other);
      final importPregame = _unstarted(best) && _unstarted(other) && _importSourceMix(best, other);
      if (!finishedPair && !importPregame) continue;
      if (!_nearSameDay(best, other)) continue;
      used[j] = true;
      if (_quality(other) > _quality(best)) best = other;
    }
    out.add(best);
  }
  return out;
}
