import 'package:test/test.dart';
import '../app/RosterBirthplaces.dart';

void main() {
  test('再集計と移籍後も同じ選手IDの出身地を維持し、新しい情報は上書きしない', () {
    final teams = <Map<String, dynamic>>[
      {
        'id_team': 2,
        'roster': [
          {'player_key': 'npb:1', 'name': '選手'},
          {'player_key': 'npb:2', 'birth_place': '福岡', 'birth_country': '日本'},
          {'name': 'IDなし'},
        ]
      }
    ];
    inheritRosterBirthplaces(teams, [
      {
        'id_team': 1,
        'roster': [
          {
            'player_key': 'npb:1',
            'birth_place': '佐賀',
            'birth_country': '日本',
            'birth_source_url': 'source'
          },
          {'player_key': 'npb:2', 'birth_place': '東京'},
          {'birth_place': '大阪'},
        ]
      }
    ]);
    final roster = teams.single['roster'] as List;
    expect(roster[0]['birth_place'], '佐賀');
    expect(roster[0]['birth_source_url'], 'source');
    expect(roster[1]['birth_place'], '福岡');
    expect(roster[2]['birth_place'], isNull);
  });
}
