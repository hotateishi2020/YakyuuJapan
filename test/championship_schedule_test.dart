import 'package:flutter_test/flutter_test.dart';
import 'package:koko_shared/championship_schedule.dart';
import 'package:koko_shared/championship_calendar.dart';

void main() {
  test('clamp series bands and derive FA dates excluding Culture Day', () {
    final games = <Map<String, dynamic>>[
      for (final date in ['2026-10-24', '2026-10-25', '2026-10-27', '2026-10-28'])
        {'date': date, 'code_game': 'JS', 'id_team_home': 1, 'id_team_away': 2,
         'score_home': 4, 'score_away': 2, 'finished': true},
    ];
    final events = championshipCalendarEvents([
      {'title_event': '日本シリーズ', 'date_from_temp': '2026-10-24', 'date_to': '2026-11-01'},
      {'title_event': '高校野球', 'date_from_temp': '2026-10-24', 'date_to': '2026-11-02'},
    ], games);
    expect(events.first['date_to'], '2026-10-28');
    expect(events[1]['date_to'], '2026-11-02');
    final fa = events.singleWhere((e) => e['title_event'] == 'FA権行使期間');
    expect(fa['date_from_temp'], '2026-10-29');
    expect(fa['date_to'], '2026-11-09');
    expect(events.singleWhere((e) => e['title_event'] == 'FA宣言選手公示')['date_from_temp'], '2026-11-10');
    expect(events.singleWhere((e) => e['title_event'] == 'FA他球団交渉解禁')['date_from_temp'], '2026-11-11');
    expect(championshipCalendarEvents(events, games), events);
    expect(championshipCalendarEvents([], games.take(3).toList()), isEmpty);
  });

  for (final code in ['JS', 'WS']) {
    test('$code hides unused fixtures, keeps completed games and other teams', () {
      final games = <Map<String, dynamic>>[
        for (var i = 0; i < 4; i++)
          {'date': '2026-10-${20 + i}', 'code_game': code,
           'id_team_home': i.isEven ? 1 : 2, 'id_team_away': i.isEven ? 2 : 1,
           'score_home': i.isEven ? 3 : 1, 'score_away': i.isEven ? 1 : 3, 'finished': true},
        {'date': '2026-10-25', 'code_game': code, 'id_team_home': 1, 'id_team_away': 2},
        {'date': '2026-10-26', 'regular': false, 'id_team_home': 2, 'id_team_away': 1},
        {'date': '2026-10-26', 'regular': true, 'id_team_home': 2, 'id_team_away': 1},
        {'date': '2026-10-26', 'code_game': code, 'id_team_home': 3, 'id_team_away': 4},
      ];
      final stale = {...games[3], 'date': '2026-10-27', 'id': 999};
      expect(championshipSchedule([...games, stale]), [...games.take(4), ...games.skip(6)]);
      expect(championshipSchedule(games), [...games.take(4), ...games.skip(6)]);
      expect(championshipSchedule(games.skip(1).toList()), games.skip(1).toList());
    });
  }
}
