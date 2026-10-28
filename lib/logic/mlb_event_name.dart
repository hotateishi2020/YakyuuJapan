import 'package:flutter/widgets.dart' show StringCharacters;

/// Japanese MLB names use given・family; Japanese players use family given.
/// Prefer the stored family name, which also preserves compound surnames.
String mlbEventSurname(String name, Iterable<Map<String, dynamic>> players) {
  String compact(String s) => s.replaceAll(RegExp(r'[\s　]+'), '');
  final key = compact(name);
  final matches = <String>{};
  for (final player in players) {
    final last = '${player['name_last'] ?? ''}'.trim();
    if (last.isEmpty) continue;
    if (['name_player', 'name_full', 'name', 'name_last'].any((field) => compact('${player[field] ?? ''}') == key)) {
      matches.add(last);
    }
  }
  if (matches.length == 1) return compact(matches.single);
  final parts = name.trim().split(RegExp(r'[・･·]'));
  if (parts.length > 1) return compact(parts.last);
  final words = name.trim().split(RegExp(r'[\s　]+'));
  if (words.length > 1) return RegExp(r'^[A-Za-z]').hasMatch(name.trim()) ? words.last : words.first;
  return key;
}

String mlbBattingName(String name, Iterable<Map<String, dynamic>> players) =>
    mlbEventSurname(name, players).characters.take(3).toString();

String mlbEventDetail(String detail, Iterable<Map<String, dynamic>> players,
    {bool shortenNames = false}) {
  final separator = detail.indexOf(RegExp(r'[:：]'));
  final prefix = separator < 0 ? '' : detail.substring(0, separator + 1);
  final names = separator < 0 ? detail : detail.substring(separator + 1);
  return prefix + names.splitMapJoin(
      RegExp(r'\([^)]*\)|[→↔︎,:：]+'),
      onMatch: (match) => match[0]!,
      onNonMatch: (name) => shortenNames ? mlbBattingName(name, players) : mlbEventSurname(name, players),
    );
}
