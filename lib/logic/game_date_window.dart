/// 当年の初期表示は今日から3日前〜10日後。それより前は「前の日」で都度読む。
const kGamesSqlPastDays = 3;
const kGamesSqlFutureDays = 10;

DateTime? parseYmd(String? raw) {
  final match = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch('${raw ?? ''}');
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

String ymdOf(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

({DateTime from, DateTime to}) defaultGamesSqlWindow(
  DateTime now, {
  int pastDays = kGamesSqlPastDays,
  int futureDays = kGamesSqlFutureDays,
}) {
  final today = DateTime(now.year, now.month, now.day);
  return (
    from: today.subtract(Duration(days: pastDays)),
    to: today.add(Duration(days: futureDays)),
  );
}

({DateTime? from, DateTime? to}) resolveGamesWindow({
  String? fromText,
  String? toText,
  required int year,
  DateTime? now,
}) {
  final from = parseYmd(fromText);
  final to = parseYmd(toText);
  if (from != null && to != null) return (from: from, to: to);
  final today = now ?? DateTime.now();
  if (year == today.year) {
    final window = defaultGamesSqlWindow(today);
    return (from: window.from, to: window.to);
  }
  return (from: from, to: to);
}

bool gameDateNeedsSqlLoad(
  DateTime date,
  DateTime? loadedFrom,
  DateTime? loadedTo,
  Set<String> extraDates, {
  bool hasGamesForDate = true,
}) {
  final day = DateTime(date.year, date.month, date.day);
  if (extraDates.contains(ymdOf(day))) return false;
  if (!hasGamesForDate) return true;
  if (loadedFrom == null || loadedTo == null) return false;
  return day.isBefore(loadedFrom) || day.isAfter(loadedTo);
}

/// [from]〜[to] の試合は [incoming] で置き換え、範囲外の既存行は残す。
List<Map<String, dynamic>> mergeGamesForDateRange(
  List<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> incoming,
  DateTime from,
  DateTime to,
) {
  final keep = [
    for (final game in existing)
      if (_gameDateOutsideRange(game, from, to)) game,
  ];
  return [...keep, ...incoming];
}

bool _gameDateOutsideRange(Map<String, dynamic> game, DateTime from, DateTime to) {
  final date = parseYmd('${game['date_game'] ?? ''}');
  if (date == null) return true;
  return date.isBefore(from) || date.isAfter(to);
}
