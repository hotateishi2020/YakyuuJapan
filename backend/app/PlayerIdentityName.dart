/// Identity keys only: display spelling is preserved in name_patterns.
/// Never strip given names or initials: a surname alone is not an identity.
String playerIdentityKey(String value) {
  var text = String.fromCharCodes(value.runes.map((r) => r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r)).toLowerCase();
  const variants = {'髙': '高', '﨑': '崎', '神': '神', '塚': '塚', '濵': '浜', '濱': '浜', '邊': '辺', '邉': '辺', '齋': '斎', '齊': '斉', 'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c'};
  for (final entry in variants.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text.replaceAll(RegExp(r'[\s　・･.．,，\-‐‑–—_\x27’`*\u0300-\u036f]'), '');
}

bool hasJapanesePlayerName(String name) => RegExp(r'[ぁ-んァ-ヶ一-龯]').hasMatch(name);

/// Explicit aliases are reusable across Japanese, English and nicknames.
/// Similar names are handled separately as review candidates, never aliases.
bool matchesPlayerPatterns(String query, Iterable<String> patterns) {
  final key = playerIdentityKey(query);
  return key.isNotEmpty && patterns.any((name) => playerIdentityKey(name) == key);
}

/// Translate only known player fields, keeping stable IDs/keys unchanged.
dynamic localizePlayerPayload(dynamic value, Map<String, String> bySourceId, Map<String, String> uniqueAliases) {
  if (value is List) {
    return value.map((v) => localizePlayerPayload(v, bySourceId, uniqueAliases)).toList();
  }
  if (value is! Map) return value;
  final row = <String, dynamic>{for (final entry in value.entries) '${entry.key}': localizePlayerPayload(entry.value, bySourceId, uniqueAliases)};
  final source = '${row['source_player_id'] ?? ''}';
  final key = '${row['player_key'] ?? ''}';
  final display = bySourceId[source] ?? (key.startsWith('mlb:') ? bySourceId[key.substring(4)] : null);
  for (final field in ['name', 'name_player', 'player_name', 'full_name', 'name_full']) {
    if (row[field] is! String) continue;
    final original = row[field] as String;
    // Team/title names cannot match unless they are a registered player alias.
    final replacement = display ?? uniqueAliases[playerIdentityKey(original)];
    if (replacement != null) row[field] = replacement;
  }
  return row;
}
