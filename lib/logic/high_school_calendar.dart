import 'high_school_schedule.dart';

Future<Map<String, dynamic>> loadHighSchoolCalendar() async =>
    Map<String, dynamic>.from((await loadHighSchoolSchedule())['calendar']);

/// Select only the signed-in user's school and its prefectural representatives.
/// Prefectures belong to schools, independently of the user's residence.
List<Map<String, dynamic>> highSchoolCalendarEvents(
    Map<String, dynamic> catalog, String favoriteSchool) {
  String normalized(String s) => s.replaceAll(RegExp(r'\s'), '');
  final school = normalized(favoriteSchool);
  if (school.isEmpty) return [];
  final prefectures =
      Map<String, dynamic>.from(catalog['school_prefectures'] ?? {});
  final prefecture = '${prefectures[school] ?? ''}';
  const kyushu = {'福岡', '佐賀', '長崎', '熊本', '大分', '宮崎', '鹿児島', '沖縄'};
  final result = <String, Map<String, dynamic>>{};
  for (final raw in (catalog['tournaments'] as List? ?? [])) {
    final tournament = Map<String, dynamic>.from(raw);
    if (tournament['scope'] != 'national' &&
        !(tournament['region'] == '九州' && kyushu.contains(prefecture))) {
      continue;
    }
    final title = '${tournament['title']}';
    final source = '${tournament['source_url'] ?? ''}';
    Map<String, dynamic> event(
            String text, String from, String to, String detail,
            {bool favorite = false}) =>
        {
          'title_event': text,
          'date_from_temp': from,
          'date_to': to,
          'event_category': '高校野球',
          'event_category_color_back': favorite ? 'crimson' : 'green',
          'event_category_color_font': 'white',
          'detail': detail,
          'source_url': source,
        };
    final from = '${tournament['date_from'] ?? ''}';
    final to = '${tournament['date_to'] ?? ''}';
    if (DateTime.tryParse(from) != null && DateTime.tryParse(to) != null) {
      result['${tournament['id']}:period'] = event(title, from, to,
          '$title\n${tournament['venue'] ?? ''}\n${tournament['note'] ?? '雨天順延'}\n$source');
    }
    for (final rawMatch in (tournament['matches'] as List? ?? [])) {
      final match = Map<String, dynamic>.from(rawMatch);
      final home = '${match['home'] ?? ''}', away = '${match['away'] ?? ''}';
      final favorite = normalized(home) == school || normalized(away) == school;
      final samePrefecture = prefecture.isNotEmpty &&
          ['home', 'away'].any((side) =>
              '${match['${side}_prefecture'] ?? prefectures[normalized('${match[side] ?? ''}')] ?? ''}' ==
              prefecture);
      final candidates = (match['candidate_schools'] as List? ?? [])
          .map((s) => normalized('$s'));
      final possible = candidates.any((s) =>
          s == school ||
          (prefecture.isNotEmpty && prefectures[s] == prefecture));
      if (!favorite && !samePrefecture && !possible) continue;
      final date = '${match['date'] ?? ''}';
      if (DateTime.tryParse(date) == null || home.isEmpty || away.isEmpty) {
        continue;
      }
      final time = '${match['time'] ?? ''}';
      final label =
          '${favorite ? '★' : ''}${time.isEmpty ? '' : '$time '}$home－$away${match['conditional'] == true ? '（進出時）' : ''}';
      result['${tournament['id']}:$date:$home:$away'] = event(label, date, date,
          '$title ${match['round'] ?? ''}\n$label\n${match['venue'] ?? tournament['venue'] ?? ''}\n${match['note'] ?? ''}\n${match['source_url'] ?? source}',
          favorite: favorite);
    }
  }
  return result.values.toList();
}
