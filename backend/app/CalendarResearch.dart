import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:postgres/postgres.dart';
import 'NpbResearchPolicy.dart';
import 'StrengthUsage.dart';

const calendarCodes = [
  'npb_opening',
  'npb_autumn_camp',
  'npb_fan_festival',
  'npb_intrasquad_game',
  'npb_joint_tryout',
  'npb_contract_renewal',
  'npb_joining_conference',
  'npb_independent_training',
  'npb_rookie_training',
  'npb_spring_camp',
  'npb_preseason',
  'npb_interleague',
  'npb_allstar',
  'npb_fresh_allstar',
  'npb_cs',
  'npb_japan_series',
  'npb_draft',
  'npb_active_draft',
  'npb_awards',
  'npb_best_nine',
  'npb_golden_glove',
  'npb_sawamura',
  'npb_fa_application',
  'npb_fa_negotiation_start',
  'npb_posting_application',
  'npb_posting_negotiation',
  'mlb_spring',
  'mlb_opening',
  'mlb_allstar',
  'mlb_postseason',
  'mlb_world_series',
  'wbc',
  'premier12',
  'samurai_series'
];
Map<String, dynamic> calendarSchema() {
  final fields = <String, dynamic>{
    'code': {'type': 'string', 'enum': calendarCodes},
    'edition': {'type': 'integer'},
    'org': {
      'type': 'string',
      'enum': ['npb', 'mlb', 'international']
    },
    'kind': {
      'type': 'string',
      'enum': ['tournament', 'ticket']
    },
    'status': {
      'type': 'string',
      'enum': ['scheduled', 'cancelled', 'postponed']
    },
    for (final k in [
      'title',
      'source_title',
      'stage',
      'venue',
      'sale_phase',
      'source_url',
      'evidence',
      'announced_on'
    ])
      k: {'type': 'string'},
    for (final k in ['start', 'end'])
      k: {
        'type': ['string', 'null']
      },
  };
  return {
    'type': 'array',
    'items': {
      'type': 'object',
      'additionalProperties': false,
      'required': fields.keys.toList(),
      'properties': fields
    }
  };
}

DateTime? calendarInstant(String? raw) {
  if (raw == null) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    final date = DateTime.tryParse(raw);
    return date != null && researchDate(date) == raw ? date : null;
  }
  // Exact release times require an explicit UTC offset, never server-local time.
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$')
      .hasMatch(raw)) {
    return null;
  }
  return DateTime.tryParse(raw);
}

String calendarDay(String raw) =>
    raw.length == 10 ? raw : researchDate(researchJst(calendarInstant(raw)!));

bool calendarDateSupported(String raw, String body) {
  final parts = raw.substring(0, 10).split('-').map(int.parse).toList();
  final y = parts[0], m = parts[1], d = parts[2];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  final text = compactResearchText(body).toLowerCase();
  if (!text.contains('$y')) return false;
  final match = [
    raw.substring(0, 10),
    '$y/$m/$d',
    '$y年$m月$d日',
    '$m月$d日',
    '$y/${parts[1].toString().padLeft(2, '0')}/${parts[2].toString().padLeft(2, '0')}',
    '${months[m - 1]}$d',
    '${months[m - 1].substring(0, 3)}$d',
    '$d${months[m - 1]}'
  ];
  return match.any((v) => text.contains(v.toLowerCase()));
}

String? validateCalendarEvent(
    Map<String, dynamic> e, DateTime now, String body) {
  if (!researchSource('${e['source_url']}')) return 'untrusted_source';
  if (!calendarCodes.contains(e['code']) ||
      !['npb', 'mlb', 'international'].contains(e['org']) ||
      !['ticket', 'tournament'].contains(e['kind']) ||
      !['scheduled', 'cancelled', 'postponed'].contains(e['status'])) {
    return 'invalid_category';
  }
  if ('${e['code']}'.startsWith('npb_') && e['org'] != 'npb' ||
      '${e['code']}'.startsWith('mlb_') && e['org'] != 'mlb' ||
      ['wbc', 'premier12', 'samurai_series'].contains(e['code']) &&
          e['org'] != 'international') {
    return 'org_mismatch';
  }
  final year = researchJst(now).year;
  if (e['edition'] is! int ||
      e['edition'] < year - 1 ||
      e['edition'] > year + 3) {
    return 'invalid_edition';
  }
  final text = html.parse(body).body?.text ?? '';
  final quote = compactResearchText('${e['evidence'] ?? ''}');
  final title = compactResearchText('${e['source_title'] ?? ''}');
  if (title.length < 2 ||
      quote.length < 10 ||
      !quote.contains(title) ||
      !compactResearchText(text).contains(quote)) {
    return 'evidence_not_found';
  }
  if ('${e['title'] ?? ''}'.trim().isEmpty) return 'missing_title';
  final published = calendarInstant('${e['announced_on']}');
  if (published == null ||
      '${e['announced_on']}'.length != 10 ||
      published.isAfter(DateTime.parse(researchDate(researchJst(now)))) ||
      !calendarDateSupported('${e['announced_on']}', text)) {
    return 'announcement_not_supported';
  }
  if (e['code'] == 'npb_posting_negotiation') {
    // stage is the official full name, venue is the originating NPB team.
    // Keep the same identity when the deadline is corrected or crosses years.
    final player = compactResearchText('${e['stage'] ?? ''}');
    if (player.length < 2 || !quote.contains(player) ||
        !researchTeams.contains(e['venue']) || e['kind'] != 'tournament' ||
        '${e['sale_phase'] ?? ''}'.isNotEmpty) return 'posting_player_not_supported';
    if (!RegExp(r'公示|交渉期間|交渉期限|posted|posting|negotiat', caseSensitive: false).hasMatch(quote)) {
      return 'posting_not_supported';
    }
  }
  if (e['status'] != 'scheduled') {
    if (!RegExp(
            e['status'] == 'cancelled'
                ? r'中止|cancelled|canceled'
                : r'延期|postponed',
            caseSensitive: false)
        .hasMatch(quote)) {
      return 'status_not_supported';
    }
    return null;
  }
  final start = calendarInstant(e['start'] as String?),
      end = calendarInstant(e['end'] as String?);
  if (start == null ||
      end == null ||
      end.isBefore(start) ||
      end.difference(start).inDays > 366) {
    return 'invalid_period';
  }
  if (!calendarDateSupported(e['start'], quote) ||
      !calendarDateSupported(e['end'], quote)) {
    return 'period_not_supported';
  }
  if (e['code'] == 'npb_posting_negotiation' &&
      end.difference(start) > const Duration(days: 45)) {
    return 'posting_period_too_long';
  }
  if (e['kind'] == 'ticket' &&
      !RegExp(r'チケット|入場券|ticket', caseSensitive: false).hasMatch(quote)) {
    return 'ticket_not_supported';
  }
  for (final field in ['start', 'end']) {
    final raw = e[field] as String;
    if (raw.length > 10) {
      final time = raw.substring(11, 16);
      final hour = int.parse(time.substring(0, 2)),
          minute = int.parse(time.substring(3));
      if (!quote.contains(time) &&
          !quote.contains('$hour:${minute.toString().padLeft(2, '0')}') &&
          !quote.contains('$hour時${minute == 0 ? '' : '$minute分'}')) {
        return 'time_not_supported';
      }
      final offset = raw.endsWith('Z') ? 'Z' : raw.substring(raw.length - 6);
      final zone = offset == '+09:00'
          ? r'日本時間|JST'
          : offset == '-04:00'
              ? r'EDT|EasternDaylight'
              : offset == '-05:00'
                  ? r'EST|EasternStandard'
                  : offset == '-07:00'
                      ? r'PDT|PacificDaylight'
                      : offset == '-08:00'
                          ? r'PST|PacificStandard'
                          : offset == 'Z'
                              ? r'UTC|GMT'
                              : RegExp.escape(offset);
      if (!RegExp(zone, caseSensitive: false).hasMatch(quote)) {
        return 'timezone_not_supported';
      }
    }
  }
  return null;
}

String calendarEventKey(Map<String, dynamic> e) => sha256
    .convert(utf8.encode(jsonEncode([
      e['code'],
      e['edition'],
      e['kind'],
      compactResearchText('${e['stage']}'),
      compactResearchText('${e['venue']}'),
      compactResearchText('${e['sale_phase']}'),
    ])))
    .toString();

class CalendarResearch {
  static Future<void> ensure(Connection c) async {
    await c.execute('''CREATE TABLE IF NOT EXISTS t_calendar_research_event (
    event_key text PRIMARY KEY, payload jsonb NOT NULL, validation text NOT NULL,
    run_day date NOT NULL REFERENCES t_npb_research_run(run_day), updated_at timestamptz NOT NULL DEFAULT now())''');
  }

  static Future<bool> exists(Connection c) async =>
      (await c.execute(
              "SELECT to_regclass('public.t_calendar_research_event') IS NOT NULL"))
          .first[0] ==
      true;
  static Future<List<Map<String, dynamic>>> entries(Connection c) async {
    if (!await exists(c)) return [];
    return (await c.execute(
            "SELECT payload FROM t_calendar_research_event WHERE validation='accepted' ORDER BY event_key"))
        .map(
            (r) => usageMap(r[0] is String ? jsonDecode(r[0] as String) : r[0]))
        .toList();
  }

  static bool imminent(List<Map<String, dynamic>> events, DateTime now) =>
      events.any((e) {
        if (e['status'] != 'scheduled' || e['start'] == null) return false;
        final days = DateTime.parse(calendarDay(e['start']))
            .difference(DateTime.parse(researchDate(researchJst(now))))
            .inDays;
        return days >= -1 && days <= 14;
      });
  static List<Map<String, dynamic>> display(
      List<Map<String, dynamic>> entries, String org, int year) {
    final result = <Map<String, dynamic>>[];
    for (final e in entries) {
      if (e['status'] != 'scheduled' ||
          ![org, 'international'].contains(e['org']) ||
          e['start'] == null ||
          e['end'] == null) {
        continue;
      }
      final from = calendarDay(e['start']), to = calendarDay(e['end']);
      if (from.compareTo('${year + 1}-01-01') >= 0 ||
          to.compareTo('$year-01-01') < 0) {
        continue;
      }
      result.add({
        'research_key': calendarEventKey(e),
        'venue': e['venue'],
        'calendar_code': e['code'],
        'calendar_kind': e['kind'],
        'title_event': e['title'],
        'date_from_temp': from,
        'date_to': to,
        'source_url': e['source_url'],
        'detail':
            '${e['start']} 〜 ${e['end']}\n${e['sale_phase']}\n${e['venue']}\n${e['source_url']}',
        'event_category_color_back': e['kind'] == 'ticket'
            ? 'orange'
            : e['org'] == 'international'
                ? 'green'
                : e['org'] == 'mlb'
                    ? 'navy'
                    : 'crimson',
        'event_category_color_font': e['kind'] == 'ticket' ? 'black' : 'white'
      });
    }
    return result;
  }
}
