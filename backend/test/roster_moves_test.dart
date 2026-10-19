import 'package:test/test.dart';
import '../app/RosterMoves.dart';

void main() {
  test('当年の確認済み入退団だけを解析する', () {
    String row(String date, String state, String reason) =>
        '<tr><td>$date</td><td>$state</td><td><a href="/npb/player/1/top">選手 太郎</a> ※</td><td>外野手</td><td>$reason</td></tr>';
    final rows = parseRosterMoves(
        '<section><section><h3>中日</h3><table class="bb-transferTable"><tbody>${row('2026/10/1', '退団', '戦力外')}${row('2026/10/2', '入団', '巨人から移籍')}${row('2026/10/3', '入団', '交渉中')}${row('2025/10/1', '退団', '戦力外')}</tbody></table></section></section>',
        2026);
    expect(rows, hasLength(2));
    expect(rows.first['departure_type'], 'non_tender');
    expect(rows.last['previous_team_name'], '巨人');
  });
  test('名簿から消えた戦力外選手を保持し加入は前所属色付きで重複しない', () {
    final teams = <Map<String, dynamic>>[
      {'id_team': 1, 'name_team': '中日', 'roster': []}
    ];
    final old = <Map<String, dynamic>>[
      {
        'id_team': 1,
        'roster': [
          {
            'player_key': 'npb:1',
            'name': '旧 選手',
            'bats': '左',
            'date_birth': '1990-01-01'
          }
        ]
      }
    ];
    final events = <Map<String, dynamic>>[
      {
        'team': '中日',
        'name': '旧選手',
        'kind': 'departure',
        'departure_type': 'non_tender',
        'status_as_of': '2026-10-01'
      },
      {
        'team': '中日',
        'name': '新選手',
        'kind': 'arrival',
        'previous_team_name': '巨人',
        'status_as_of': '2026-10-02'
      },
    ];
    final identities = <Map<String, dynamic>>[
      {'name_team': '巨人', 'name_shortest': '巨', 'color_back': '#FF6600'}
    ];
    applyRosterMoves(teams, events, 2026,
        previous: old, identities: identities);
    applyRosterMoves(teams, events, 2026,
        previous: old, identities: identities);
    final roster = teams.single['roster'] as List;
    expect(roster, hasLength(2));
    expect(roster.first['bats'], '左');
    expect(roster.first['departure_confirmed'], true);
    expect(roster.last['new_arrival'], true);
    expect(roster.last['previous_team']['label'], '巨');
    expect(roster.last['previous_team']['color_back'], '#FF6600');
  });
  test('翌春の新戦力にも前年秋の契約合意を反映し古い退団は加えない', () {
    final teams = <Map<String, dynamic>>[
      {'id_team': 1, 'name_team': '中日', 'roster': []}
    ];
    applyRosterMoves(
        teams,
        [
          {
            'team': '中日',
            'name': 'ウォード',
            'kind': 'arrival',
            'status_as_of': '2026-09-23'
          },
          {
            'team': '中日',
            'name': '退団選手',
            'kind': 'departure',
            'status_as_of': '2026-10-01'
          }
        ],
        2027);
    expect(teams.single['roster'], hasLength(1));
    expect(teams.single['roster'][0]['arrival_year'], 2027);
  });
}
