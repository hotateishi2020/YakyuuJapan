import 'package:test/test.dart';
import '../app/CalendarResearch.dart';

void main() {
  final now = DateTime.utc(2026, 10, 20);
  final event = <String, dynamic>{
    'code': 'npb_japan_series',
    'edition': 2026,
    'org': 'npb',
    'kind': 'ticket',
    'status': 'scheduled',
    'title': '日本シリーズ チケット発売',
    'source_title': '日本シリーズ',
    'stage': '',
    'venue': '',
    'sale_phase': '一般発売',
    'source_url': 'https://npb.jp/nippons/2026/ticket.html',
    'announced_on': '2026-10-19',
    'start': '2026-10-21T10:00:00+09:00',
    'end': '2026-10-21T10:00:00+09:00',
    'evidence': '2026年10月19日 日本シリーズ チケット一般発売 2026年10月21日 10:00 日本時間',
  };
  test('official ticket evidence and explicit time are required', () {
    final body = '<p>${event['evidence']}</p>';
    expect(validateCalendarEvent(event, now, body), isNull);
    expect(validateCalendarEvent({...event, 'start': '2026-10-22'}, now, body),
        isNotNull);
    expect(
        validateCalendarEvent(
            {...event, 'source_url': 'https://example.com'}, now, body),
        'untrusted_source');
    expect(validateCalendarEvent({...event, 'start': null}, now, body),
        'invalid_period');
    expect(
        validateCalendarEvent(event, now, 'unrelated'), 'evidence_not_found');
  });
  test('identity survives date changes and cancelled items disappear', () {
    final revised = {...event, 'start': '2026-10-23', 'end': '2026-10-23'};
    expect(calendarEventKey(event), calendarEventKey(revised));
    expect(
        CalendarResearch.display([
          event,
          {...event, 'status': 'cancelled'}
        ], 'npb', 2026),
        hasLength(1));
    expect(CalendarResearch.display([event], 'mlb', 2026), isEmpty);
    expect(CalendarResearch.imminent([event], now), isTrue);
  });
  test('international periods overlap years and ticket dates use JST', () {
    expect(calendarDay('2026-10-21T20:00:00-04:00'), '2026-10-22');
    final cross = {
      ...event,
      'code': 'wbc',
      'org': 'international',
      'start': '2026-12-30',
      'end': '2027-01-02'
    };
    expect(CalendarResearch.display([cross], 'mlb', 2027), hasLength(1));
    expect(CalendarResearch.display([cross], 'npb', 2026), hasLength(1));
    expect(CalendarResearch.display([cross], 'npb', 2028), isEmpty);
    expect(calendarInstant('2026-02-30'), isNull);
    expect(calendarInstant('2026-10-21T10:00:00'), isNull);
  });
  test('cancellation needs evidence', () {
    final cancel = {
      ...event,
      'status': 'cancelled',
      'start': null,
      'end': null,
      'evidence': '2026年10月19日 日本シリーズ チケット発売を中止'
    };
    expect(validateCalendarEvent(cancel, now, '<p>${cancel['evidence']}</p>'),
        isNull);
    expect(
        validateCalendarEvent({...event, 'status': 'cancelled'}, now,
            '<p>${event['evidence']}</p>'),
        'status_not_supported');
  });
}
