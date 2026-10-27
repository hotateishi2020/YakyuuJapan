import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/high_school_calendar.dart';

void main() {
  final data = <String, dynamic>{
    'school_prefectures': {'佐賀北': '佐賀', '早稲田佐賀': '佐賀', '長野日大': '長野'},
    'tournaments': [
      {
        'id': 'kyushu',
        'title': '秋季九州大会',
        'scope': 'block',
        'region': '九州',
        'date_from': '2026-10-24',
        'date_to': '2026-11-02',
        'matches': [
          {'home': '佐賀北', 'away': '大分', 'date': '2026-10-27', 'time': '11:30'},
          {'home': '祐誠', 'away': '早稲田佐賀', 'date': '2026-10-28', 'time': '9:00'},
          {'home': 'コザ', 'away': '創成館', 'date': '2026-10-28'},
        ]
      },
      {
        'id': 'national',
        'title': '全国大会',
        'scope': 'national',
        'date_from': '2026-08-05',
        'date_to': '2026-08-22',
        'matches': [
          {
            'home': '佐賀商',
            'home_prefecture': '佐賀',
            'away': '他校',
            'date': '2026-08-06'
          },
          {
            'home': '他校',
            'away': '長野日大',
            'away_prefecture': '長野',
            'date': '2026-08-07'
          },
        ]
      },
    ],
  };
  test('no favorite: no personalized events', () {
    expect(highSchoolCalendarEvents(data, ''), isEmpty);
  });
  test('school and same prefecture games, with one tournament period', () {
    final events = highSchoolCalendarEvents(data, '佐賀北');
    expect(events.length, 5);
    expect(
        events
            .where((e) => '${e['title_event']}'.contains('★'))
            .single['date_from_temp'],
        '2026-10-27');
    expect(events.any((e) => '${e['title_event']}'.contains('早稲田佐賀')), isTrue);
    expect(events.any((e) => '${e['title_event']}'.contains('佐賀商')), isTrue);
    expect(events.any((e) => '${e['title_event']}'.contains('コザ')), isFalse);
  });
  test('different prefecture does not inherit Saga or Kyushu fixtures', () {
    final events = highSchoolCalendarEvents(data, '長野日大');
    expect(events.length, 2);
    expect(events.any((e) => '${e['title_event']}'.contains('佐賀')), isFalse);
  });
  test('unknown school does not match missing prefectures', () {
    expect(highSchoolCalendarEvents(data, '未登録校').length, 1);
  });
  test('unconfirmed advancement remains explicitly conditional', () {
    final catalog = jsonDecode(
        File('backend/assets/data/high_school_calendar.json')
            .readAsStringSync()) as Map<String, dynamic>;
    final events = highSchoolCalendarEvents(catalog, '佐賀北');
    final quarter =
        events.where((e) => e['date_from_temp'] == '2026-10-29').single;
    expect(quarter['title_event'], contains('進出時'));
    expect(quarter['title_event'], contains('佐賀北／大分の勝者'));
  });
  test('bundled catalog has valid unique periods and dated fixtures', () {
    final catalog = jsonDecode(
        File('backend/assets/data/high_school_calendar.json')
            .readAsStringSync()) as Map<String, dynamic>;
    final ids = <String>{};
    for (final t in catalog['tournaments']) {
      expect(ids.add(t['id']), isTrue);
      final from = DateTime.parse(t['date_from']);
      final to = DateTime.parse(t['date_to']);
      expect(to.isBefore(from), isFalse);
      for (final m in t['matches']) {
        final date = DateTime.parse(m['date']);
        expect(date.isBefore(from) || date.isAfter(to), isFalse);
      }
    }
    expect(
        highSchoolCalendarEvents(catalog, '佐賀北')
            .any((e) => '${e['title_event']}'.contains('佐賀北')),
        isTrue);
  });
}
