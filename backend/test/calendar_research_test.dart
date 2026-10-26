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
  test('選手別交渉期間は公示情報を確認し、米国期限を日本時間で年またぎ表示する', () {
    final posting = {
      ...event, 'code': 'npb_posting_negotiation', 'kind': 'tournament',
      'title': '選手太郎 ポスティング交渉期間', 'source_title': '選手太郎',
      'stage': '選手太郎', 'venue': '阪神', 'sale_phase': '',
      'source_url': 'https://mlb.com/news/posted-player', 'announced_on': '2026-12-15',
      'start': '2026-12-16T08:00:00-05:00', 'end': '2027-01-29T17:00:00-05:00',
      'evidence': '2026年12月15日 選手太郎 公示。交渉期間 2026年12月16日 08:00 EST から2027年1月29日 17:00 ESTまで。',
    };
    final instant = DateTime.utc(2026, 12, 16);
    expect(validateCalendarEvent(posting, instant, '${posting['evidence']}'), isNull);
    expect(validateCalendarEvent({...posting, 'stage': '別の選手'}, instant, '${posting['evidence']}'), 'posting_player_not_supported');
    final revised = {...posting, 'end': '2027-01-28T17:00:00-05:00'};
    expect(calendarEventKey(revised), calendarEventKey(posting));
    expect(calendarEventKey({...posting, 'stage': '選手次郎'}), isNot(calendarEventKey(posting)));
    for (final year in [2026, 2027]) {
      final display = CalendarResearch.display([posting], 'npb', year).single;
      expect(display['date_from_temp'], '2026-12-16');
      expect(display['date_to'], '2027-01-30');
    }
    final tooLong = {...posting, 'end': '2027-01-31T17:00:00-05:00',
      'evidence': '${posting['evidence']} 訂正: 2027年1月31日 17:00 ESTまで。'};
    expect(validateCalendarEvent(tooLong, instant, '${tooLong['evidence']}'), 'posting_period_too_long');
  });
  test('球団別キャンプ等の12項目を受理し年度・会場・軍を区別する', () {
    const codes = ['npb_autumn_camp', 'npb_joint_tryout', 'npb_contract_renewal',
      'npb_active_draft', 'npb_joining_conference', 'npb_independent_training',
      'npb_rookie_training', 'npb_spring_camp', 'npb_preseason', 'npb_opening', 'npb_fan_festival', 'npb_intrasquad_game'];
    for (final code in codes) {
      final camp = {...event, 'code': code, 'edition': 2027, 'kind': 'tournament',
        'title': '阪神 春季キャンプ', 'source_title': '春季キャンプ',
        'stage': '阪神/一軍', 'venue': '会場A', 'sale_phase': '',
        'start': '2027-02-01', 'end': '2027-02-28',
        'evidence': '2026年10月19日 春季キャンプ 2027年2月1日から2027年2月28日まで開催。'};
      expect(validateCalendarEvent(camp, now, '${camp['evidence']}'), isNull, reason: code);
      final second = {...camp, 'stage': '阪神/二軍'};
      expect(calendarEventKey(second), isNot(calendarEventKey(camp)));
      expect(calendarEventKey({...camp, 'venue': '会場B'}), isNot(calendarEventKey(camp)));
      final display = CalendarResearch.display([camp, second], 'npb', 2027);
      expect(display, hasLength(2));
      expect(display.first['date_from_temp'], '2027-02-01');
      expect(display.first['date_to'], '2027-02-28');
      expect(CalendarResearch.display([camp], 'npb', 2026), isEmpty);
    }
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
