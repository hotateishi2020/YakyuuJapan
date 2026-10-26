import 'dart:convert';

/// Remove user picks and their derived colours/match markers, keeping public
/// baseball statistics. Shared by HTTP responses and browser cache restoration.
Object? publicPredictionData(Object? value) {
  // Older snapshots can carry nested JSON as text (notably game summaries).
  if (value is String && (value.trimLeft().startsWith('[') || value.trimLeft().startsWith('{'))) {
    try {
      final decoded = jsonDecode(value);
      final clean = publicPredictionData(decoded);
      return jsonEncode(clean) == jsonEncode(decoded) ? value : jsonEncode(clean);
    } on FormatException { return value; }
  }
  if (value is List) return value.map(publicPredictionData).toList();
  if (value is! Map) return value;
  const privateFields = {
    'predict_team', 'predict_player', 'predictions', 'playerStats', 'predict',
    'colors_user', 'id_users', 'colors_summary', 'titles_predict',
    'colors_pitcher_home', 'colors_pitcher_away', 'flg_predict', 'flg_atari',
    // These legacy markers are joined through user picks, not all starters.
    'color_today', 'flg_today',
  };
  return <String, dynamic>{
    for (final entry in value.entries)
      if (!privateFields.contains(entry.key) &&
          !entry.key.toString().endsWith('_tateishi') &&
          !entry.key.toString().endsWith('_ejima'))
        entry.key.toString(): publicPredictionData(entry.value),
  };
}
