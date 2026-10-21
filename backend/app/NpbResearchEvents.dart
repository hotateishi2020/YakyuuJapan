import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'StrengthUsage.dart';
import 'RosterMoves.dart';
import 'StrengthContracts.dart';

class NpbResearchEvents {
  static Future<void> ensure(Connection c) async {
    await c.execute('''CREATE TABLE IF NOT EXISTS t_npb_research_run (
      run_day date PRIMARY KEY, status text NOT NULL, reason jsonb NOT NULL,
      started_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz,
      response_id text, usage jsonb, error text)''');
    await c.execute('''CREATE TABLE IF NOT EXISTS t_npb_research_event (
      event_key text PRIMARY KEY, run_day date NOT NULL REFERENCES t_npb_research_run(run_day),
      payload jsonb NOT NULL, validation text NOT NULL, created_at timestamptz NOT NULL DEFAULT now())''');
  }

  static Future<List<Map<String, dynamic>>> read(Connection c, int year) async {
    final exists = await c.execute(
        "SELECT to_regclass('public.t_npb_research_event') IS NOT NULL");
    if (exists.first[0] != true) return [];
    return (await c.execute('''SELECT payload FROM t_npb_research_event
      WHERE validation='accepted' AND (payload->>'season')::integer=\$1
      ORDER BY payload->>'date', created_at, event_key''', parameters: [year]))
        .map(
            (r) => usageMap(r[0] is String ? jsonDecode(r[0] as String) : r[0]))
        .toList();
  }

  static Future<void> attach(
      Connection c, int year, List<Map<String, dynamic>> teams) async {
    apply(teams, await read(c, year), year);
  }

  static void apply(List<Map<String, dynamic>> teams,
      List<Map<String, dynamic>> events, int year) {
    final moves = <Map<String, dynamic>>[];
    for (final e in events.where((e) => e['season'] == year)) {
      final kind = e['kind'];
      final base = <String, dynamic>{
        'name': e['name'],
        'team': e['team'],
        'position_group': e['position'],
        'status_as_of': e['date'],
        'status_source': e['source_url'],
        'status_year': year
      };
      final method = kind == 'active_draft'
          ? '現役ドラフト'
          : kind == 'posting_completed'
              ? 'ポスティング'
              : '移籍';
      if (['transfer', 'active_draft', 'posting_completed'].contains(kind)) {
        moves.add({
          ...base,
          'kind': 'departure',
          'departure_type': 'transfer',
          'departure_reason': method,
          'move_method': method,
          'destination_team_name': e['destination']
        });
        moves.add({
          ...base,
          'team': e['destination'],
          'kind': 'arrival',
          'move_method': method,
          'previous_team_name': e['team']
        });
      } else if (['foreign_signing', 'draft_signing'].contains(kind)) {
        moves.add({
          ...base,
          'kind': 'arrival',
          'move_method': kind == 'draft_signing' ? 'ドラフト' : '新外国人',
          'previous_team_name': e['previous_team'] ?? ''
        });
      } else if (kind == 'fa_declared') {
        moves.add({...base, 'kind': 'status', 'move_status': 'FA宣言（移籍先未定）'});
      } else if (kind == 'posting_approved') {
        moves.add({...base, 'kind': 'status', 'move_status': 'ポスティング容認'});
      }
    }
    final before = teams
        .map((t) => <String, dynamic>{
              ...t,
              'roster': usageMaps(t['roster'])
                  .map((p) => Map<String, dynamic>.from(p))
                  .toList()
            })
        .toList();
    applyRosterMoves(teams, moves, year, previous: before);
    for (final team in teams) {
      final contracts = usageMaps(team['contracts']);
      final roster = usageMaps(team['roster']);
      for (final e in events.where(
          (e) => e['season'] == year && e['team'] == team['name_team'])) {
        final players = roster
            .where(
                (p) => usageName('${p['name']}') == usageName('${e['name']}'))
            .toList();
        if (players.length != 1) continue;
        final player = players.single;
        if (e['kind'] == 'contract_renewal') {
          player['contract_renewed_date'] = e['date'];
          player['contract_renewed_source'] = e['source_url'];
          var contract = contracts
              .where((p) => p['player_key'] == player['player_key'])
              .firstOrNull;
          if (contract == null) {
            contract = {
              'player_key': player['player_key'],
              'name': player['name']
            };
            contracts.add(contract);
          }
          final amount = parseYen('${e['salary_label'] ?? ''}');
          if (amount != null) {
            final history = usageMaps(contract['salary_history']);
            // Only overwrite with later sourced research, never with a fabricated amount.
            final previous =
                history.where((s) => s['year'] == year).firstOrNull;
            if (previous == null ||
                '${previous['signed_date'] ?? ''}'.compareTo('${e['date']}') <=
                    0) {
              history.removeWhere((s) => s['year'] == year);
              history.add({
                'year': year,
                'amount': amount,
                'currency': 'JPY',
                'team': e['team'],
                'estimated': true,
                'signed_date': e['date'],
                'source_url': e['source_url'],
                'detail': e['salary_label']
              });
              contract['salary_history'] = history;
            }
          }
        }
      }
      team['contracts'] = contracts;
      team['roster'] = roster;
    }
  }

  static Future<Map<String, dynamic>> drafts(
      Connection c, int throughYear, bool active) async {
    final exists = await c.execute(
        "SELECT to_regclass('public.t_npb_research_event') IS NOT NULL");
    if (exists.first[0] != true) return {};
    final rows = await c.execute(
        "SELECT payload FROM t_npb_research_event WHERE validation='accepted' AND payload->>'kind'=\$1 AND extract(year from (payload->>'date')::date)<=\$2 ORDER BY payload->>'date',created_at,event_key",
        parameters: [active ? 'active_draft' : 'draft_selection', throughYear]);
    return draftYears(
        rows
            .map((r) =>
                usageMap(r[0] is String ? jsonDecode(r[0] as String) : r[0]))
            .toList(),
        active);
  }

  static Map<String, dynamic> draftYears(
      List<Map<String, dynamic>> events, bool active) {
    final years = <String, dynamic>{};
    for (final e in events.where(
        (e) => e['kind'] == (active ? 'active_draft' : 'draft_selection'))) {
      final year = '${DateTime.parse(e['date']).year}';
      final group = years.putIfAbsent(
          year,
          () => <String, dynamic>{
                'source': e['source_url'],
                'picks': <Map<String, dynamic>>[]
              }) as Map<String, dynamic>;
      (group['picks'] as List).add({
        'name': e['name'],
        'team': active ? e['destination'] : e['team'],
        'type': e['draft_type'] ?? '',
        'rank': e['draft_rank'] ?? '',
        'position': e['position'] ?? '',
        'from': active ? e['team'] : e['previous_team'] ?? '',
        'status': active ? '移籍確定' : '指名（入団契約は別途確認）',
        'source': e['source_url'],
        'note': '',
        'competition': null
      });
    }
    return years;
  }
}
