import 'package:test/test.dart';
import '../app/RosterMoves.dart';
import '../app/NpbResearchEvents.dart';

void main() {
  test('前年オフの外国人入団を取得し前年の退団は除外する', () {
    String row(String date, String state) =>
        '<tr><td>$date</td><td>$state</td><td>外国人選手</td><td>外野手</td><td>新外国人</td></tr>';
    final events = parseRosterMoves(
      '<section><h3>西武</h3><table class="bb-transferTable"><tbody>'
      '${row('2025/12/22', '入団')}${row('2025/12/22', '退団')}'
      '${row('2025/8/1', '入団')}${row('2024/12/1', '入団')}'
      '</tbody></table></section>', 2026);
    expect(events, hasLength(1));
    expect(events.single['move_method'], '新外国人');
  });
  test('カナリオとマッカスカーに昨オフの入団情報を補完する', () {
    final teams = <Map<String, dynamic>>[
      {'name_team': '西武', 'roster': <Map<String, dynamic>>[{'name': 'Ａ．カナリオ'}]},
      {'name_team': '楽天', 'roster': <Map<String, dynamic>>[{'name': 'Ｃ．マッカスカー'}]},
    ];
    final arrivals = RosterMoves.verified(2026).where((e) => e['kind'] == 'arrival').toList();
    applyRosterMoves(teams, arrivals, 2026);
    for (final team in teams) {
      final roster = team['roster'] as List;
      expect(roster, hasLength(1));
      expect(roster.single['new_arrival'], isTrue);
      expect(roster.single['move_method'], '新外国人');
      expect(roster.single['arrival_year'], 2026);
      expect(roster.single['previous_team']['name'], isNotEmpty);
    }
  });
  test('追加調査が空でも取得済みの戦力外と名簿補完選手を削除しない', () {
    final teams = <Map<String, dynamic>>[{
      'id_team': 1, 'name_team': '西武',
      'roster': <Map<String, dynamic>>[{'name': 'シンクレア', 'player_key': 'npb:1'}]
    }];
    final events = ['シンクレア', '奥村 光一'].map((name) => <String, dynamic>{
      'team': '西武', 'name': name, 'kind': 'departure',
      'status_as_of': '2026-10-01', 'status_source': rosterMovesUrl,
      'departure_type': 'non_tender',
    }).toList();
    applyRosterMoves(teams, events, 2026);
    NpbResearchEvents.apply(teams, [], 2026);
    final roster = teams.single['roster'] as List;
    expect(roster, hasLength(2));
    expect(roster.every((p) => p['departure_confirmed'] == true), isTrue);
    // 一覧自体から撤回された情報は、完全な一覧の再同期時には削除する。
    applyRosterMoves(teams, [], 2026);
    expect(teams.single['roster'], hasLength(1));
    expect(teams.single['roster'][0]['departure_confirmed'], isNull);
  });
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
