import 'package:test/test.dart';
import '../app/SeasonCalendarEvents.dart';
void main() {
  final japan = {'title_event': '日本シリーズ', 'event_category': 'NPB',
    'date_from_temp': DateTime.utc(2026,10,24), 'date_to': DateTime.utc(2026,11,1)};
  test('従来の期間を復元し年度・組織で絞る', () {
    List<Map<String,dynamic>> events(String org,int year) => seasonCalendarEvents(org:org,year:year,legacy:[japan],researched:[]);
    expect(events('npb',2026).single['date_to'],'2026-11-01');
    expect(events('npb',2025),isEmpty);
    expect(events('mlb',2025),isEmpty);
  });
  test('公式日程のワールドシリーズ予定期間を日本時間で補完する', () {
    final result=seasonCalendarEvents(org:'mlb',year:2026,legacy:[],researched:[]);
    expect(result.single['title_event'],'ワールドシリーズ');
    expect(result.single['date_from_temp'],'2026-10-24');
    expect(result.single['date_to'],'2026-11-01');
  });
  test('調査済みの期間を優先し帯を重複させない', () {
    final result=seasonCalendarEvents(org:'npb',year:2026,legacy:[japan],researched:[{...japan,'date_to':'2026-10-31'}]);
    expect(result,hasLength(1));
    expect(result.single['date_to'],'2026-10-31');
  });
}
