import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/season_schedule.dart';

void main() {
  test('先発負担率は割合を百分率へ変換し未取得を区別する', () {
    expect(starterWorkloadLabel(2 / 3), '66.7%');
    expect(starterWorkloadLabel(0), '0.0%');
    expect(starterWorkloadLabel(null), '—');
  });
  test('対戦列は同リーグのみ比較し引分・未対戦・自身を除外する', () {
    final teams = <Map<String, dynamic>>[
      for (var id = 1; id <= 6; id++) {'id_team': id, 'id_league': id == 5 ? 2 : 1},
    ];
    final games = <Map<String, dynamic>>[
      for (final id in [1, 1, 2, 3, 4, 5])
        {'id_team_home': id, 'id_team_away': 6, 'score_home': 1, 'score_away': 0, 'finished': true, 'regular': true},
      for (final id in [1, 2, 2, 3, 4])
        {'id_team_home': id, 'id_team_away': 6, 'score_home': 0, 'score_away': 1, 'finished': true, 'regular': true},
      {'id_team_home': 1, 'id_team_away': 6, 'score_home': 0, 'score_away': 0, 'finished': true, 'regular': true},
    ];
    expect(scheduleOpponentExtreme(teams, games, teams[0], 6), 1);
    expect(scheduleOpponentExtreme(teams, games, teams[1], 6), -1);
    expect(scheduleOpponentExtreme(teams, games, teams[2], 6), 0);
    expect(scheduleOpponentExtreme(teams, games, teams[4], 6), 0);
    expect(scheduleOpponentExtreme(teams, games, teams[5], 6), 0);
    expect(scheduleOpponentExtreme(teams, [], teams[0], 6), 0);
    final tied = [teams[2], teams[3], teams[1]];
    expect(scheduleOpponentExtreme(tied, games, teams[2], 6), 1);
    expect(scheduleOpponentExtreme(tied, games, teams[3], 6), 1);
    expect(scheduleOpponentExtreme(tied.take(2).toList(), games, teams[2], 6), 0);
  });
}
