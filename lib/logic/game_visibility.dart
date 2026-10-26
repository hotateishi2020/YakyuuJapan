/// Shared by API responses and retained client views. Never mutate cached data.
bool canViewRestrictedGames(int? userId) => userId == 1 || userId == 2;

bool isUnfinishedGame(Map<String, dynamic> row) {
  if (!row.containsKey('state') ||
      !(row.containsKey('id_game') || row.containsKey('score_home') || row.containsKey('name_team_home'))) {
    return false;
  }
  final state = '${row['state'] ?? ''}';
  return !RegExp('終了|コールド|中止|延期|サスペンデッド').hasMatch(state);
}

const _scheduleFields = {
  'id', 'id_game', 'date', 'date_game', 'time_game', 'org',
  'id_team_home', 'id_team_away', 'id_league_home', 'id_league_away',
  'name_team_home', 'name_team_away', 'name_stadium', 'id_stadium',
  'latitude', 'longitude',
  // Calendar aliases are team names/codes, not image URLs or live results.
  'name_home', 'name_away', 'name_home_logo', 'name_away_logo',
  'home_code', 'away_code', 'league_home', 'league_away',
  'time', 'datetime_start', 'game_number', 'regular',
  'color_back_home', 'color_back_away', 'color_font_home', 'color_font_away',
  'code_game', 'code_round', 'code_stage', 'code_series', 'int_game',
};

/// Public responses retain schedules and completed scores, never live details
/// or individual plate results (including nested player appearance records).
dynamic publicGameData(dynamic value) {
  if (value is List) return value.map(publicGameData).toList();
  if (value is! Map) return value;
  final row = Map<String, dynamic>.from(value);
  if (isUnfinishedGame(row)) {
    return <String, dynamic>{
      for (final key in _scheduleFields)
        if (row.containsKey(key)) key: row[key],
      'state': const {'', '試合前', '予告先発', '予想先発', 'スタメン', '見どころ'}.contains('${row['state'] ?? ''}') ? '試合前' : '速報非表示',
      'score_home': -1, 'score_away': -1,
    };
  }
  return <String, dynamic>{
    for (final entry in row.entries)
      if (!const {'plays', 'txt_plays', 'play_rows', 'batting_plays'}.contains(entry.key))
        entry.key: publicGameData(entry.value),
  };
}

List<Map<String, dynamic>> publicGameRows(List<Map<String, dynamic>> rows) =>
    (publicGameData(rows) as List).cast<Map<String, dynamic>>();
