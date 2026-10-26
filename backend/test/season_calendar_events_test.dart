import 'package:test/test.dart';
import '../app/SeasonCalendarEvents.dart';
void main() {
  final japan = {'title_event': '日本シリーズ', 'event_category': 'NPB',
    'date_from_temp': DateTime.utc(2026,10,24), 'date_to': DateTime.utc(2026,11,1)};
  test('従来の期間を復元し年度・組織で絞る', () {
    List<Map<String,dynamic>> events(String org,int year) => seasonCalendarEvents(org:org,year:year,legacy:[japan],researched:[]);
    expect(events('npb',2026).firstWhere((e) => e['title_event'] == '日本シリーズ')['date_to'],'2026-11-01');
    expect(events('npb',2025),isEmpty);
    expect(events('mlb',2025),isEmpty);
  });
  test('公式日程のワールドシリーズ予定期間を日本時間で補完する', () {
    final result=seasonCalendarEvents(org:'mlb',year:2026,legacy:[],researched:[]).where((e) => e['title_event'] == 'ワールドシリーズ').toList();
    expect(result.single['title_event'],'ワールドシリーズ');
    expect(result.single['date_from_temp'],'2026-10-24');
    expect(result.single['date_to'],'2026-11-01');
  });
  test('調査済みの期間を優先し帯を重複させない', () {
    final result=seasonCalendarEvents(org:'npb',year:2026,legacy:[japan],researched:[{...japan,'date_to':'2026-10-31'}]).where((e) => e['title_event'] == '日本シリーズ').toList();
    expect(result,hasLength(1));
    expect(result.single['date_to'],'2026-10-31');
  });
  test('パテレAWARDは2026年12月11日のNPBイベントとして一度だけ追加する', () {
    final events = seasonCalendarEvents(org: 'npb', year: 2026, legacy: [], researched: []);
    final event = events.singleWhere((e) => e['title_event'] == 'パテレAWARD');
    expect(event['date_from_temp'], '2026-12-11');
    expect(event['date_to'], '2026-12-11');
    expect(seasonCalendarEvents(org: 'npb', year: 2026, legacy: [], researched: events), events);
    final existing = {...event, 'title_event': 'パテレアワード2026'};
    expect(seasonCalendarEvents(org: 'npb', year: 2026, legacy: [], researched: [existing])
      .where((e) => '${e['title_event']}'.contains('パテレ')), [existing]);
    for (final scope in [('mlb', 2026), ('npb', 2027)]) {
      expect(seasonCalendarEvents(org: scope.$1, year: scope.$2, legacy: [], researched: [])
        .where((e) => '${e['title_event']}'.contains('パテレ')), isEmpty);
    }
  });
  test('APBCは開催期間の帯として追加し既存スナップショットへの再適用でも重複しない', () {
    for (final org in ['npb', 'mlb']) {
      final events = seasonCalendarEvents(org: org, year: 2026, legacy: [], researched: []);
      final event = events.singleWhere((e) => e['title_event'] == 'アジアプロ野球チャンピオンシップ');
      expect(event['date_from_temp'], '2026-11-12');
      expect(event['date_to'], '2026-11-15');
      expect(event['event_category'], '侍JAPAN');
      expect(seasonCalendarEvents(org: org, year: 2026, legacy: [], researched: events), events);
      expect(seasonCalendarEvents(org: org, year: 2027, legacy: [], researched: [])
        .where((e) => e['title_event'] == 'アジアプロ野球チャンピオンシップ'), isEmpty);
    }
  });
}
