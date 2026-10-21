import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../app/NpbResearch.dart';
import '../app/NpbResearchPolicy.dart';
import '../app/NpbResearchEvents.dart';

Map<String, dynamic> event(String kind) => {
      'kind': kind,
      'team': '阪神',
      'name': '選手太郎',
      'season': 2026,
      'date': '2026-10-20',
      'source_url': 'https://hanshintigers.jp/news/topics/info_123.html',
      'evidence': '2026年10月20日阪神は選手太郎のポスティング申請を容認しました。',
      'confirmed': true,
      'destination': null,
      'position': '投手',
      'previous_team': null,
      'draft_type': null,
      'draft_rank': null,
      'salary_label': null,
      'negotiation_deadline': null,
    };
void main() {
  test('JST, quiet days, known event dates and discovery', () {
    final calendar = {'draft_selection': '2026-10-22'};
    expect(researchDue(DateTime.utc(2026, 10, 20, 11), calendar), isEmpty);
    expect(researchDue(DateTime.utc(2026, 10, 20, 12), calendar),
        isNot(contains('draft_selection')));
    expect(researchDue(DateTime.utc(2026, 10, 22, 12), calendar),
        contains('draft_selection'));
    expect(researchDue(DateTime.utc(2026, 6, 2, 12), {}), isEmpty);
    expect(researchDue(DateTime.utc(2026, 6, 1, 12), {}), contains('transfer'));
    expect(researchDue(DateTime.utc(2026, 12, 1, 12), {}),
        contains('active_draft'));
    expect(researchJst(DateTime.utc(2026, 12, 31, 16)).year, 2027);
  });
  test('unresolved negotiations override quiet days and close on completion',
      () {
    final open = {...event('posting_approved'), 'date': '2026-02-20'};
    final now = DateTime.utc(2026, 3, 3, 12);
    expect(researchPending([open], now), true);
    expect(researchDue(now, {}, pendingNegotiations: true),
        contains('posting_completed'));
    expect(
        researchPending([
          open,
          {...open, 'kind': 'posting_completed', 'date': '2026-03-01'}
        ], now),
        false);
  });
  test('calendar headings isolate dates', () {
    expect(
        researchCalendar(
            '<h4>ドラフト会議</h4><p>10月22日</p><h4>現役ドラフト</h4><p>12月9日</p>', 2026),
        {'draft_selection': '2026-10-22', 'active_draft': '2026-12-09'});
    expect(
        researchCalendar(
            '<h4>ドラフト会議</h4><p>未定</p><h4>別の行事</h4><p>11月1日</p>', 2026),
        isEmpty);
  });
  test('facts require official HTTPS, exact evidence, date, team and action',
      () {
    final e = event('posting_approved'), now = DateTime.utc(2026, 10, 20, 12);
    final body = '<p>${e['evidence']}</p>';
    expect(validateResearchEvent(e, now, body), isNull);
    expect(
        validateResearchEvent(
            {...e, 'source_url': 'https://npb.jp.evil.test/x'}, now, body),
        'untrusted_source');
    expect(validateResearchEvent({...e, 'date': '2026-10-21'}, now, body),
        'invalid_date');
    expect(validateResearchEvent({...e, 'date': '2026-10-19'}, now, body),
        'date_not_supported');
    expect(
        validateResearchEvent({...e, 'kind': 'posting_completed'}, now, body),
        'action_not_supported');
    expect(validateResearchEvent({...e, 'team': '巨人'}, now, body),
        'team_not_supported');
    expect(validateResearchEvent(e, now, 'unrelated'), 'evidence_not_found');
    final rumor = {...e, 'evidence': '2026年10月20日阪神は選手太郎のポスティング容認を検討中です。'};
    expect(validateResearchEvent(rumor, now, '${rumor['evidence']}'),
        'speculation');
  });
  test('negative official announcements never become confirmed declarations',
      () {
    final e = {
      ...event('fa_declared'),
      'evidence': '2026年10月20日阪神の選手太郎はFA宣言せず残留します。'
    };
    expect(
        validateResearchEvent(
            e, DateTime.utc(2026, 10, 20, 12), '${e['evidence']}'),
        'speculation');
  });
  test('selection does not create arrival; signing replay is idempotent', () {
    final teams = <Map<String, dynamic>>[
      {'id_team': 1, 'name_team': '阪神', 'roster': []}
    ];
    NpbResearchEvents.apply(teams, [event('draft_selection')], 2026);
    expect(teams.single['roster'], isEmpty);
    NpbResearchEvents.apply(teams, [event('draft_signing')], 2026);
    NpbResearchEvents.apply(teams, [event('draft_signing')], 2026);
    expect(teams.single['roster'], hasLength(1));
    expect(teams.single['roster'][0]['new_arrival'], true);
  });
  test('FA and salaries attach only to matching team', () {
    final teams = <Map<String, dynamic>>[
      {
        'id_team': 1,
        'name_team': '阪神',
        'roster': [
          {'name': '選手太郎', 'player_key': 'npb:1'}
        ]
      },
      {
        'id_team': 2,
        'name_team': '巨人',
        'roster': [
          {'name': '選手太郎', 'player_key': 'npb:2'}
        ]
      },
    ];
    NpbResearchEvents.apply(
        teams,
        [
          event('fa_declared'),
          {...event('contract_renewal'), 'salary_label': '1億5000万円'}
        ],
        2026);
    expect(teams.first['roster'][0]['move_status'], 'FA宣言（移籍先未定）');
    expect(teams.last['roster'][0]['move_status'], isNull);
    expect(
        teams.first['contracts'][0]['salary_history'][0]['amount'], 150000000);
    expect(teams.first['roster'][0]['contract_renewed_date'], '2026-10-20');
  });
  test('source redirects cannot escape official domains', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('', 302,
          headers: {'location': 'http://127.0.0.1/secrets'});
    });
    await expectLater(NpbResearch.source(client, 'https://npb.jp/news/'),
        throwsFormatException);
    expect(requests, 1);
    client.close();
  });
  test('API uses search and schema; incomplete output is rejected', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body);
      expect(request.url.toString(), 'https://api.openai.com/v1/responses');
      expect(body['store'], false);
      expect(body['tool_choice'], 'required');
      expect(body['text']['format']['strict'], true);
      return http.Response(
          jsonEncode({'status': 'incomplete', 'output': []}), 200);
    });
    await expectLater(
        NpbResearch.query(client,
            key: 'test-key',
            model: 'test-model',
            day: '2026-10-20',
            since: '2026-10-19',
            topics: ['transfer'],
            calendar: {}),
        throwsStateError);
    client.close();
  });
}
