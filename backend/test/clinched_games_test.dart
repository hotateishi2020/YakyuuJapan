import 'package:test/test.dart';

import '../app/ClinchedGames.dart';

Map<String, dynamic> game({
  required int id,
  required String date,
  required String code,
  required int home,
  required int away,
  required String state,
  int scoreHome = -1,
  int scoreAway = -1,
}) {
  return {
    'id_game': id,
    'date_game': date,
    'code_game': code,
    'id_team_home': home,
    'id_team_away': away,
    'state': state,
    'score_home': scoreHome,
    'score_away': scoreAway,
  };
}

void main() {
  test('3勝で勝ち上がったあとの未実施を削除対象にする', () {
    final games = [
      game(id: 1, date: '2026-10-03', code: 'DS', home: 2, away: 1, state: '試合終了', scoreHome: 1, scoreAway: 0),
      game(id: 2, date: '2026-10-06', code: 'DS', home: 2, away: 1, state: '試合終了', scoreHome: 5, scoreAway: 2),
      game(id: 3, date: '2026-10-08', code: 'DS', home: 1, away: 2, state: '試合終了', scoreHome: 3, scoreAway: 4),
      game(id: 4, date: '2026-10-09', code: 'DS', home: 1, away: 2, state: '予想先発'),
      game(id: 5, date: '2026-10-09', code: 'DS', home: 3, away: 4, state: '試合前'),
    ];
    expect(unplayedClinchedGameIds(games), [4]);
  });

  test('同スコアの隣接重複は1勝に数える', () {
    final games = [
      game(id: 1, date: '2026-10-03', code: 'DS', home: 2, away: 1, state: '試合終了', scoreHome: 1, scoreAway: 0),
      game(id: 2001, date: '2026-10-04', code: 'DS', home: 2, away: 1, state: '試合終了', scoreHome: 1, scoreAway: 0),
      game(id: 3, date: '2026-10-06', code: 'DS', home: 1, away: 2, state: '試合終了', scoreHome: 3, scoreAway: 4),
      game(id: 4, date: '2026-10-09', code: 'DS', home: 1, away: 2, state: '試合前'),
    ];
    expect(unplayedClinchedGameIds(games), isEmpty);
  });

  test('進行中の試合は削除しない', () {
    final games = [
      for (var i = 0; i < 4; i++)
        game(id: i + 1, date: '2026-10-${20 + i}', code: 'WS', home: 10, away: 11, state: '試合終了', scoreHome: 5, scoreAway: 1),
      game(id: 5, date: '2026-10-24', code: 'WS', home: 10, away: 11, state: '7回表', scoreHome: 1, scoreAway: 0),
    ];
    expect(unplayedClinchedGameIds(games), isEmpty);
  });

  test('クライマックスファイナルは1位のアドバンテージを勝数に含める', () {
    final standings = [
      {'id_team': 1, 'id_league': 1, 'int_rank': 1, 'int_win': 80, 'int_lose': 50, 'game_behind': '0'},
      {'id_team': 2, 'id_league': 1, 'int_rank': 2, 'int_win': 75, 'int_lose': 58, 'game_behind': '5'},
    ];
    final games = [
      game(id: 1, date: '2026-10-14', code: 'CSF', home: 1, away: 2, state: '試合終了', scoreHome: 1, scoreAway: 0),
      game(id: 2, date: '2026-10-15', code: 'CSF', home: 1, away: 2, state: '試合終了', scoreHome: 1, scoreAway: 0),
      game(id: 3, date: '2026-10-16', code: 'CSF', home: 2, away: 1, state: '試合終了', scoreHome: 0, scoreAway: 2),
      game(id: 4, date: '2026-10-17', code: 'CSF', home: 1, away: 2, state: '試合前'),
    ];
    expect(unplayedClinchedGameIds(games, standings: standings), [4]);
  });
}
