import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/clinched_series.dart';

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
  test('日本シリーズは4勝に達したあとの未実施試合を出さない', () {
    final games = [
      for (var i = 0; i < 4; i++)
        game(id: i + 1, date: '2026-10-${20 + i}', code: 'JS', home: 1, away: 2, state: '試合終了', scoreHome: 3, scoreAway: 1),
      game(id: 5, date: '2026-10-24', code: 'JS', home: 1, away: 2, state: '試合前'),
      game(id: 6, date: '2026-10-25', code: 'JS', home: 2, away: 1, state: '試合前'),
      game(id: 7, date: '2026-10-21', code: 'NM', home: 3, away: 4, state: '試合前'),
    ];
    final shown = dropUnplayedClinchedGames(games);
    expect(shown.map((row) => row['id_game']), [1, 2, 3, 4, 7]);
  });

  test('規定勝数に届くまでは予定の試合を残す', () {
    final games = [
      game(id: 1, date: '2026-10-20', code: 'JS', home: 1, away: 2, state: '試合終了', scoreHome: 1, scoreAway: 0),
      game(id: 2, date: '2026-10-21', code: 'JS', home: 1, away: 2, state: '試合終了', scoreHome: 1, scoreAway: 0),
      game(id: 3, date: '2026-10-22', code: 'JS', home: 1, away: 2, state: '試合終了', scoreHome: 1, scoreAway: 0),
      game(id: 4, date: '2026-10-23', code: 'JS', home: 1, away: 2, state: '試合前'),
    ];
    expect(dropUnplayedClinchedGames(games), hasLength(4));
  });

  test('ファーストステージは2勝で残りを隠す', () {
    final games = [
      game(id: 1, date: '2026-10-10', code: 'CS1', home: 8, away: 9, state: '試合終了', scoreHome: 2, scoreAway: 1),
      game(id: 2, date: '2026-10-11', code: 'CS1', home: 9, away: 8, state: '試合終了', scoreHome: 0, scoreAway: 4),
      game(id: 3, date: '2026-10-12', code: 'CS1', home: 8, away: 9, state: '試合前'),
    ];
    final shown = dropUnplayedClinchedGames(games);
    expect(shown.map((row) => row['id_game']), [1, 2]);
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
    final shown = dropUnplayedClinchedGames(games, standings: standings);
    expect(shown.map((row) => row['id_game']), [1, 2, 3]);
  });

  test('進行中の試合は決着後でも残す', () {
    final games = [
      for (var i = 0; i < 4; i++)
        game(id: i + 1, date: '2026-10-${20 + i}', code: 'WS', home: 10, away: 11, state: '試合終了', scoreHome: 5, scoreAway: 1),
      game(id: 5, date: '2026-10-24', code: 'WS', home: 10, away: 11, state: '7回表', scoreHome: 1, scoreAway: 0),
    ];
    expect(dropUnplayedClinchedGames(games).map((row) => row['id_game']), [1, 2, 3, 4, 5]);
  });
}
