List<Map<String, dynamic>> listMapFromJson(dynamic v) {
  final raw = (v as List?) ?? const [];
  return raw.map((e) => (e as Map).map((k, v) => MapEntry('$k', v))).cast<Map<String, dynamic>>().toList();
}

String lookupField(
  List<Map<String, dynamic>> list,
  String matchKey,
  String matchValue,
  String returnKey, {
  String fallback = '—',
}) {
  final m = list.firstWhere(
    (e) => '${e[matchKey]}' == matchValue,
    orElse: () => const {},
  );
  return (m.isNotEmpty ? (m[returnKey] ?? fallback) : fallback).toString();
}
