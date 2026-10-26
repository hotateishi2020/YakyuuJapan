/// Annual planning estimates are explicitly separate from official dates.
/// Rebuild generated rows so newly researched dates replace cached estimates.
List<Map<String, dynamic>> annualAwardEvents(List<Map<String, dynamic>> events, int year) {
  final result = events.where((e) => e['annual_award_generated'] != true).toList();
  if (year < 2026) return result;
  String day(DateTime d) => d.toIso8601String().substring(0, 10);
  DateTime lastWeekday(int month, int weekday) {
    final last = DateTime(year, month + 1, 0);
    return last.subtract(Duration(days: (last.weekday - weekday + 7) % 7));
  }
  Map<String, dynamic>? existing(String code, RegExp title) {
    for (final e in result) {
      final name = '${e['title_event'] ?? ''}';
      if (e['calendar_kind'] == 'ticket' || RegExp('チケット|抽選|発売|受付').hasMatch(name)) continue;
      if (e['calendar_code'] == code || title.hasMatch(name)) return e;
    }
    return null;
  }
  void add(String code, String title, DateTime date, String detail, String source, {bool estimated = true}) {
    result.add({
      'annual_award_generated': true, 'calendar_code': code, 'calendar_kind': 'tournament',
      'is_estimated': estimated, 'title_event': title,
      'date_from_temp': day(date), 'date_to': day(date), 'event_category': 'NPB',
      'event_category_color_back': estimated ? 'orange' : 'crimson',
      'event_category_color_font': estimated ? 'black' : 'white',
      'source_url': source, 'detail': '$detail\n$source',
    });
  }
  final awards = existing('npb_awards', RegExp(r'NPB\s*(AWARDS|アワード)', caseSensitive: false));
  final awardsDate = DateTime.tryParse('${awards?['date_from_temp']}'.split('T').first.split(' ').first)
      ?? (year == 2026 ? DateTime(2026, 11, 25) : lastWeekday(11, DateTime.wednesday));
  if (awards == null) {
    add('npb_awards', year == 2026 ? 'NPB AWARDS' : 'NPB AWARDS？', awardsDate,
      year == 2026 ? 'NPB AWARDS 2026の開催日。' : '未発表のため11月最終水曜日を目安に自動表示。正式日程ではありません。',
      'https://npb.jp/award/${year == 2026 ? 2026 : 2025}/', estimated: year != 2026);
  }
  if (existing('npb_best_nine', RegExp('ベストナイン')) == null) {
    add('npb_best_nine', 'ベストナイン発表？', awardsDate.subtract(const Duration(days: 1)),
      '予想日。2025年の発表がNPB AWARDS前日だったことを参考に自動計算。正式日程ではありません。', 'https://npb.jp/award/2025/');
  }
  if (existing('npb_golden_glove', RegExp('ゴールデン.?グラブ|GG.*発表')) == null) {
    final first = DateTime(year, 11, 1);
    final secondWednesday = first.add(Duration(days: (DateTime.wednesday - first.weekday + 7) % 7 + 7));
    add('npb_golden_glove', 'ゴールデングラブ発表？', secondWednesday,
      '発表日の目安。11月第2水曜日を仮日程として毎年自動表示。公式発表により変更される場合があります。', 'https://mgg.mitsuipr.com/');
  }
  if (existing('npb_sawamura', RegExp('沢村賞')) == null) {
    add('npb_sawamura', '沢村賞発表？', lastWeekday(10, DateTime.monday),
      '例年の目安。2024年10月28日・2025年10月27日の選考を参考に10月最終月曜日を自動表示。正式日程ではありません。', 'https://npb.jp/news/detail/20251027_02.html');
  }
  return result;
}
