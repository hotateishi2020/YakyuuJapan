import 'package:test/test.dart';
import '../app/AnnualAwardEvents.dart';

void main() {
  test('2026年の開催日と予想日を区別する', () {
    final events = annualAwardEvents([], 2026);
    expect({for (final e in events) e['title_event']: e['date_from_temp']}, {
      'NPB AWARDS': '2026-11-25', 'ベストナイン発表？': '2026-11-24',
      'ゴールデングラブ発表？': '2026-11-11', '沢村賞発表？': '2026-10-26',
    });
    expect(events.first['is_estimated'], false);
    expect(events.skip(1).every((e) => e['is_estimated'] == true), true);
  });
  test('翌年以降も生成し再読込で重複しない', () {
    for (final year in [2027, 2028, 2030]) {
      final events = annualAwardEvents([], year);
      expect(events, hasLength(4));
      expect(events.every((e) => '${e['date_from_temp']}'.startsWith('$year-')), true);
      expect(events.every((e) => '${e['title_event']}'.endsWith('？')), true);
      expect(annualAwardEvents(events, year), events);
    }
  });
  test('公式日程を優先しキャッシュ内の仮日程を置換、チケット発売日は開催日と混同しない', () {
    final events = annualAwardEvents([
      ...annualAwardEvents([], 2027),
      {'calendar_code': 'npb_awards', 'calendar_kind': 'ticket', 'title_event': 'NPB AWARDS チケット発売', 'date_from_temp': '2027-11-01'},
      {'calendar_code': 'npb_awards', 'calendar_kind': 'tournament', 'title_event': 'NPB AWARDS 2027', 'date_from_temp': '2027-11-23'},
      {'calendar_code': 'npb_golden_glove', 'title_event': 'ゴールデン・グラブ賞 発表', 'date_from_temp': '2027-11-12'},
    ], 2027);
    expect(events.where((e) => e['calendar_code'] == 'npb_awards'), hasLength(2));
    expect(events.singleWhere((e) => e['calendar_code'] == 'npb_best_nine')['date_from_temp'], '2027-11-22');
    expect(events.singleWhere((e) => e['calendar_code'] == 'npb_golden_glove')['date_from_temp'], '2027-11-12');
  });
}
