import 'championship_schedule.dart';

/// Apply the actual final date to tournament bands and the NPB FA calendar.
List<Map<String, dynamic>> championshipCalendarEvents(
    List<Map<String, dynamic>> events, List<Map<String, dynamic>> games) {
  final ends = championshipEndDates(games);
  final result = <Map<String, dynamic>>[];
  for (final event in events) {
    final title = '${event['title_event'] ?? ''}';
    final start = '${event['date_from_temp'] ?? ''}';
    final year = start.length >= 4 ? start.substring(0, 4) : '';
    final code = title == '日本シリーズ' ? 'JS' : title == 'ワールドシリーズ' ? 'WS' : '';
    final end = ends['$year|$code'];
    result.add(end == null ? event : {...event, 'date_to': end,
      'txt_timing': '$start〜$end', 'detail': 'シリーズ終了日: $end（日本時間）'});
  }
  for (final entry in ends.entries.where((e) => e.key.endsWith('|JS'))) {
    final end = DateTime.parse(entry.value);
    var deadline = end;
    var days = 0;
    while (days < 7) {
      deadline = deadline.add(const Duration(days: 1));
      // Championships finish in October/November. These are the national
      // holidays in that window; Sunday holidays have a Monday substitute.
      bool holiday(DateTime d) => d.month == 11 && (d.day == 3 || d.day == 23);
      final substitute = deadline.weekday == DateTime.monday && holiday(deadline.subtract(const Duration(days: 1)));
      if (deadline.weekday <= DateTime.friday && !holiday(deadline) && !substitute) days++;
    }
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    final dates = [
      ('FA権行使期間', day(end.add(const Duration(days: 1))), day(deadline)),
      ('FA宣言選手公示', day(deadline.add(const Duration(days: 1))), day(deadline.add(const Duration(days: 1)))),
      ('FA他球団交渉解禁', day(deadline.add(const Duration(days: 2))), day(deadline.add(const Duration(days: 2)))),
    ];
    for (final date in dates) {
      result.removeWhere((e) => '${e['date_from_temp']}'.startsWith('${end.year}') &&
        (e['title_event'] == date.$1 || date.$1 == 'FA権行使期間' && RegExp(r'FA.*(申請|宣言|行使).*期間').hasMatch('${e['title_event']}')));
      result.add({'title_event': date.$1, 'date_from_temp': date.$2, 'date_to': date.$3,
        'event_category': 'NPB', 'event_category_color_back': 'red',
        'event_category_color_font': 'white',
        'source_url': 'https://www.kobe-np.co.jp/news/zenkoku/compact/202610/0020980429.shtml',
        'detail': '日本シリーズ終了翌日から土日・祝日を除く7日以内に権利行使。期間翌日に宣言選手公示、翌々日に他球団との交渉解禁。'});
    }
  }
  return result;
}
