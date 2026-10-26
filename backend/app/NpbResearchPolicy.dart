import 'package:html/parser.dart' as html;

const researchKinds = [
  'draft_selection',
  'draft_signing',
  'foreign_signing',
  'fa_declared',
  'contract_renewal',
  'posting_approved',
  'posting_completed',
  'transfer',
  'active_draft'
];
const researchDomains = [
  'npb.jp',
  'mgg.mitsuipr.com',
  'pacificleague.com',
  'jpbpa.net',
  'npb.or.jp',
  'wbsc.org',
  'japan-baseball.jp',
  '2026wbc.jp',
  'giants.jp',
  'hanshintigers.jp',
  'dragons.jp',
  'baystars.co.jp',
  'yakult-swallows.co.jp',
  'carp.co.jp',
  'softbankhawks.co.jp',
  'seibulions.jp',
  'rakuteneagles.jp',
  'buffaloes.co.jp',
  'fighters.co.jp',
  'marines.co.jp',
  'mlb.com'
];
const researchTeams = [
  '巨人',
  '阪神',
  '中日',
  'DeNA',
  'ヤクルト',
  '広島',
  'ソフトバンク',
  '西武',
  '楽天',
  'オリックス',
  '日本ハム',
  'ロッテ'
];
DateTime researchJst(DateTime utc) => utc.toUtc().add(const Duration(hours: 9));
String researchDate(DateTime date) => date.toIso8601String().substring(0, 10);
bool researchSource(String value) {
  final url = Uri.tryParse(value);
  return url != null &&
      url.scheme == 'https' &&
      url.userInfo.isEmpty &&
      (!url.hasPort || url.port == 443) &&
      researchDomains.any((d) => url.host == d || url.host.endsWith('.$d'));
}

/// Dates are read from the current year's official calendar, not guessed from
/// last year's weekday. Unknown dates retain seasonal discovery polling.
Map<String, String> researchCalendar(String body, int year) {
  final document = html.parse(body);
  final result = <String, String>{};
  for (final heading in document.querySelectorAll('h3, h4, h5')) {
    final title = heading.text;
    final kind = title.contains('現役ドラフト')
        ? 'active_draft'
        : title.contains('ドラフト会議')
            ? 'draft_selection'
            : null;
    if (kind == null) continue;
    var sibling = heading.nextElementSibling;
    for (var i = 0;
        sibling != null && i < 4;
        i++, sibling = sibling.nextElementSibling) {
      if (['h3', 'h4', 'h5'].contains(sibling.localName)) break;
      final match = RegExp(r'(\d{1,2})月(\d{1,2})日').firstMatch(sibling.text);
      if (match == null) continue;
      result[kind] = researchDate(
          DateTime.utc(year, int.parse(match[1]!), int.parse(match[2]!)));
      break;
    }
  }
  return result;
}

/// The server checks every hour, but only an eligible JST evening can spend
/// an API request. Off-season: daily; quiet months: Monday; July: daily.
List<String> researchDue(DateTime now, Map<String, String> calendar,
    {bool pendingNegotiations = false}) {
  final jst = researchJst(now);
  if (jst.hour < 21) return [];
  final today = researchDate(jst);
  final busy = jst.month >= 10 || jst.month <= 3 || jst.month == 7;
  final eventDay = calendar.values.any((date) {
    final difference =
        DateTime.parse(today).difference(DateTime.parse(date)).inDays;
    return difference >= 0 && difference <= 2;
  });
  if (!busy &&
      !eventDay &&
      !pendingNegotiations &&
      jst.weekday != DateTime.monday) {
    return [];
  }
  return [
    for (final kind in researchKinds)
      if (!(calendar.containsKey(kind) &&
              today.compareTo(calendar[kind]!) < 0) &&
          !(kind == 'contract_renewal' && jst.month > 2 && jst.month < 10) &&
          !(kind == 'fa_declared' &&
              jst.month > 3 &&
              (jst.month < 10 || (jst.month == 10 && jst.day < 25))) &&
          !(kind == 'draft_selection' &&
              !calendar.containsKey(kind) &&
              jst.month != 10) &&
          !(kind == 'active_draft' &&
              !calendar.containsKey(kind) &&
              jst.month != 11 &&
              jst.month != 12))
        kind
  ];
}

Map<String, dynamic> researchSchema() {
  final fields = <String, dynamic>{
    'kind': {'type': 'string', 'enum': researchKinds},
    'name': {'type': 'string'},
    'team': {'type': 'string', 'enum': researchTeams},
    'date': {'type': 'string'},
    'season': {'type': 'integer'},
    'source_url': {'type': 'string'},
    'evidence': {'type': 'string'},
    'confirmed': {'type': 'boolean'},
    for (final key in [
      'destination',
      'position',
      'previous_team',
      'draft_type',
      'draft_rank',
      'salary_label',
      'negotiation_deadline'
    ])
      key: {
        'type': ['string', 'null']
      },
  };
  return {
    'type': 'object',
    'additionalProperties': false,
    'required': ['events'],
    'properties': {
      'events': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': fields.keys.toList(),
          'properties': fields
        }
      }
    }
  };
}

String compactResearchText(String text) => text.replaceAll(RegExp(r'\s|　'), '');
String? validateResearchEvent(
    Map<String, dynamic> event, DateTime now, String sourceBody) {
  if (!researchKinds.contains(event['kind']) ||
      !researchTeams.contains(event['team'])) {
    return 'unknown_kind_or_team';
  }
  if (event['confirmed'] != true) return 'unconfirmed';
  if (!researchSource('${event['source_url']}')) return 'untrusted_source';
  final date = DateTime.tryParse('${event['date']}');
  final today = DateTime.parse(researchDate(researchJst(now)));
  if (date == null ||
      researchDate(date) != event['date'] ||
      date.isAfter(today) ||
      date.isBefore(today.subtract(const Duration(days: 370)))) {
    return 'invalid_date';
  }
  if (event['season'] is! int ||
      (event['season'] as int) < date.year ||
      (event['season'] as int) > date.year + 1) {
    return 'invalid_season';
  }
  final name = compactResearchText('${event['name'] ?? ''}');
  final evidence = compactResearchText('${event['evidence'] ?? ''}');
  final text = compactResearchText(html.parse(sourceBody).body?.text ?? '');
  if (name.length < 2 ||
      evidence.length < 10 ||
      !evidence.contains(name) ||
      !text.contains(evidence)) {
    return 'evidence_not_found';
  }
  if (!evidence.contains(compactResearchText('${event['team']}'))) {
    return 'team_not_supported';
  }
  final dates = [
    researchDate(date),
    '${date.year}/${date.month}/${date.day}',
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
    '${date.year}年${date.month}月${date.day}日',
    '${date.year}.${date.month}.${date.day}',
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}'
  ];
  if (!dates.any(text.contains)) return 'date_not_supported';
  if (['posting_approved', 'posting_completed'].contains(event['kind']) &&
      !evidence.contains('ポスティング')) {
    return 'posting_not_supported';
  }
  if (event['negotiation_deadline'] != null) {
    final end = DateTime.tryParse('${event['negotiation_deadline']}');
    if (end == null ||
        researchDate(end) != event['negotiation_deadline'] ||
        end.isBefore(date) ||
        end.difference(date).inDays > 120) {
      return 'invalid_deadline';
    }
    if (![
      researchDate(end),
      '${end.year}年${end.month}月${end.day}日',
      '${end.year}/${end.month}/${end.day}'
    ].any(text.contains)) {
      return 'deadline_not_supported';
    }
  }
  // Merely having a valid URL is insufficient. Keep uncertain statements out of
  // roster state, and require an affirmative action for each event type.
  if (RegExp(
          '見込み|可能性|検討|調査|未定|報道による|交渉中|容認しない|認めない|否定|不成立|見送|破談|至らず|合意していない|締結していない|契約しない|行使しない|宣言しない|宣言せず|承認しない|申請しない|申請せず')
      .hasMatch(evidence)) {
    return 'speculation';
  }
  final actions = <String, String>{
    'draft_selection': '指名|交渉権',
    'draft_signing': '入団|契約締結',
    'foreign_signing': '契約|入団|獲得',
    'fa_declared': 'FA宣言|ＦＡ宣言|権利.*行使',
    'contract_renewal': '契約更改|契約.*締結|契約.*合意',
    'posting_approved': '容認|承認|申請|手続',
    'posting_completed': '契約.*合意|契約.*締結|入団',
    'transfer': '移籍|トレード|契約.*合意|入団',
    'active_draft': '現役ドラフト',
  };
  if (!RegExp(actions[event['kind']]!, caseSensitive: false).hasMatch(evidence)) {
    return 'action_not_supported';
  }
  if (['transfer', 'active_draft', 'posting_completed']
          .contains(event['kind']) &&
      (event['destination'] == null ||
          !evidence.contains(compactResearchText('${event['destination']}')))) {
    return 'destination_not_supported';
  }
  if (event['kind'] == 'draft_selection' &&
      (event['draft_rank'] == null ||
          !evidence.contains('${event['draft_rank']}'))) {
    return 'draft_rank_not_supported';
  }
  if (event['salary_label'] != null &&
      !evidence.contains(compactResearchText('${event['salary_label']}'))) {
    return 'salary_not_supported';
  }
  return null;
}

/// Operational follow-up, not a calculation of the legally applicable deadline.
bool researchPending(List<Map<String, dynamic>> events, DateTime now) {
  final today = DateTime.parse(researchDate(researchJst(now)));
  for (final event in events
      .where((e) => ['posting_approved', 'fa_declared'].contains(e['kind']))) {
    final announced = DateTime.tryParse('${event['date']}');
    if (announced == null || announced.isAfter(today)) continue;
    final resolved = events.any((e) =>
        ['posting_completed', 'transfer'].contains(e['kind']) &&
        compactResearchText('${e['name']}') ==
            compactResearchText('${event['name']}') &&
        e['team'] == event['team'] &&
        '${e['date']}'.compareTo('${event['date']}') >= 0);
    if (resolved) continue;
    final deadline = DateTime.tryParse('${event['negotiation_deadline']}');
    if (deadline != null &&
        !today.isAfter(deadline.add(const Duration(days: 2)))) {
      return true;
    }
    if (deadline == null && today.difference(announced).inDays <= 60) {
      return true;
    }
  }
  return false;
}
