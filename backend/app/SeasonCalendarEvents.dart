/// Combine researched events and existing event periods without duplicate bands.
List<Map<String, dynamic>> seasonCalendarEvents({
  required String org,
  required int year,
  required List<Map<String, dynamic>> legacy,
  required List<Map<String, dynamic>> researched,
}) {
  String day(dynamic value) => '${value ?? ''}'.split(' ').first.split('T').first;
  final result = <Map<String, dynamic>>[...researched];
  for (final event in legacy) {
    final category = '${event['event_category']}'.toLowerCase();
    if (category != org && category != '侍japan') continue;
    final from = day(event['date_from_temp']);
    final to = event['date_to'] == null ? from : day(event['date_to']);
    if (DateTime.tryParse(from) == null || to.compareTo('$year-01-01') < 0 || from.compareTo('${year + 1}-01-01') >= 0) {
      continue;
    }
    if (result.any((e) => e['title_event'] == event['title_event'])) continue;
    result.add({...event, 'date_from_temp': from, 'date_to': to});
  }
  // Official 2026 schedule: Oct 23–31 at 8 p.m. ET, hence Oct 24–Nov 1 JST.
  // Research updates take precedence if the announced schedule changes.
  if (org == 'mlb' && year == 2026 && !result.any((e) => e['title_event'] == 'ワールドシリーズ')) {
    const source = 'https://www.mlb.com/news/2026-mlb-playoff-and-world-series-schedule';
    result.add({
      'title_event': 'ワールドシリーズ',
      'date_from_temp': '2026-10-24',
      'date_to': '2026-11-01',
      'event_category': 'MLB',
      'event_category_color_back': 'navy',
      'event_category_color_font': 'white',
      'source_url': source,
      'detail': '日本時間。第7戦までの予定期間（第5〜7戦は必要な場合のみ）。\n$source',
    });
  }
  return result;
}
