import 'package:flutter/widgets.dart' show StringCharacters;

/// Japanese MLB names use given・family; Japanese players use family given.
/// Prefer the stored family name, which also preserves compound surnames.
String mlbEventSurname(String name, Iterable<Map<String, dynamic>> players) {
  String compact(String s) => s.replaceAll(RegExp(r'[\s　]+'), '');
  String identity(String value) => compact(value).replaceAll(RegExp(r'[・･·]'), '');
  String family(String value) {
    final parts = value.trim().split(RegExp(r'[・･·]'));
    if (parts.length > 1) return compact(parts.last);
    final words = value.trim().split(RegExp(r'[\s　]+'));
    if (words.length > 1) {
      // Imported foreign names may use a space instead of the middle dot.
      return compact(RegExp(r'^[A-Za-zＡ-Ｚａ-ｚァ-ヶー]').hasMatch(words.first)
          ? words.last : words.first);
    }
    return compact(value).replaceFirst(RegExp(r'^[A-Za-zＡ-Ｚａ-ｚ]{1,3}[.．]'), '');
  }
  final key = identity(name);
  final matches = <String>{};
  for (final player in players) {
    final last = '${player['name_last'] ?? player['name_last_summary'] ?? ''}'.trim();
    if (last.isEmpty) continue;
    if (['name_player', 'name_full', 'name_full_summary', 'name', 'name_last'].any((field) => identity('${player[field] ?? ''}') == key)) {
      final full = ['name_player', 'name_full', 'name_full_summary', 'name']
          .map((field) => '${player[field] ?? ''}'.trim())
          .where((value) => identity(value) == key && RegExp(r'[・･·\s　]').hasMatch(value))
          .firstOrNull ?? name;
      final firstPart = full.split(RegExp(r'[・･·\s　]+')).first;
      // Some imports put the given name (or the entire full name) in name_last.
      // Keep a real stored surname, including compound surnames, when available.
      final givenImportedAsLast = identity(last) == identity(firstPart) &&
          identity(full) != identity(last) &&
          RegExp(r'^[A-Za-zＡ-Ｚａ-ｚァ-ヶー]').hasMatch(firstPart);
      matches.add(givenImportedAsLast || identity(last) == key ? family(full) : compact(last));
    }
  }
  if (matches.length == 1) return matches.single;
  return family(name);
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
