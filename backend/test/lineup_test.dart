import 'package:test/test.dart';

import '../app/Lineup.dart';
import '../app/Value.dart';

Map<String, dynamic> _row({
  required String result,
  required String batter,
  int id = 1,
  int inning = 1,
  bool bottom = false,
  int order = 6,
  int team = 201,
  int home = 202,
  int away = 201,
  String enter = '',
  String exit = '',
  String direction = '',
}) {
  return {
    'id': id,
    'id_game': 1,
    'id_team': team,
    'id_team_home': home,
    'id_team_away': away,
    'int_inning': inning,
    'flg_bottom': bottom,
    'int_batting_order': order,
    'cnt_out': 0,
    'code_result': result,
    'code_direction_batting': direction,
    'name_full': batter,
    'name_enter': enter,
    'name_exit': exit,
    'code_position_from': '',
  };
}

void main() {
  test('代打のあとに打席だけ残る選手は代守になる', () {
    final lineups = battingLineupsOf(
      [
        _row(id: 1, result: Value.CodeGameResult.STRIKE_OUT, batter: 'トリスタン・ピーターズ', inning: 2),
        _row(id: 2, result: Value.CodeGameResult.OUT_FLY, batter: 'トミー・ファム', inning: 6, direction: 'LEFT'),
        _row(
          id: 3,
          result: Value.CodeGameResult.PINCH_HITTER,
          batter: 'トミー・ファム',
          inning: 6,
          enter: 'トミー・ファム',
          exit: 'トリスタン・ピーターズ',
        ),
        _row(id: 4, result: Value.CodeGameResult.OUT_GROUND, batter: 'ブレンドン・ドイル', inning: 8, direction: 'SECOND'),
      ],
      plays: const {},
      pitchers: const {},
    );
    final slot = lineups[1]!.firstWhere((row) => row['order'] == 6);
    final players = (slot['players'] as List).cast<Map<String, dynamic>>();
    expect(players.map((player) => player['name']).toList(), [
      'トリスタン・ピーターズ',
      'トミー・ファム',
      'ブレンドン・ドイル',
    ]);
    expect(players[1]['role'], '代打');
    expect(players[2]['role'], '代守');
  });

  List<Map<String, dynamic>> _playersOf(Map<int, List<Map<String, dynamic>>> lineups, int order) {
    final slot = lineups[1]!.firstWhere((row) => row['order'] == order);
    return (slot['players'] as List).cast<Map<String, dynamic>>();
  }

  test('先発の守備交代を同じ選手の代守にしない', () {
    final lineups = battingLineupsOf(
      [
        _row(
          id: 1,
          result: Value.CodeGameResult.STRIKE_OUT,
          batter: 'ダスティン・ハリス',
          order: 2,
          inning: 1,
        ),
        _row(
          id: 2,
          result: Value.CodeGameResult.PINCH_FIELDER,
          batter: '相手打者',
          order: 4,
          team: 202,
          inning: 6,
          bottom: true,
          enter: 'ダスティン・ハリス',
        ),
        _row(
          id: 3,
          result: Value.CodeGameResult.OUT_FLY,
          batter: 'ダスティン・ハリス',
          order: 2,
          inning: 7,
          direction: 'LEFT',
        ),
      ],
      plays: const {},
      pitchers: const {},
    );
    final players = _playersOf(lineups, 2);
    expect(players.map((player) => player['name']).toList(), ['ダスティン・ハリス']);
    expect(players.single['role'], '');
  });

  test('打席前の守備交代だけでも先発を代守にしない', () {
    final lineups = battingLineupsOf(
      [
        _row(
          id: 1,
          result: Value.CodeGameResult.PINCH_FIELDER,
          batter: '相手打者',
          order: 1,
          team: 202,
          bottom: true,
          enter: 'ダスティン・ハリス',
        ),
        _row(
          id: 2,
          result: Value.CodeGameResult.STRIKE_OUT,
          batter: 'ダスティン・ハリス',
          order: 2,
          inning: 1,
        ),
      ],
      plays: const {},
      pitchers: const {},
    );
    final players = _playersOf(lineups, 2);
    expect(players.map((player) => player['name']).toList(), ['ダスティン・ハリス']);
    expect(players.single['role'], '');
  });

  test('中黒の有無が違う同じ選手を代守として重ねない', () {
    final lineups = battingLineupsOf(
      [
        _row(id: 1, result: Value.CodeGameResult.STRIKE_OUT, batter: 'ダスティン・ハリス', order: 2),
        _row(
          id: 2,
          result: Value.CodeGameResult.OUT_GROUND,
          batter: 'ダスティンハリス',
          order: 2,
          inning: 3,
          direction: 'SECOND',
        ),
      ],
      plays: const {},
      pitchers: const {},
    );
    final players = _playersOf(lineups, 2);
    expect(players.map((player) => player['name']).toList(), ['ダスティン・ハリス']);
    expect(players.single['role'], '');
  });

  test('フル名の先発に略称の守備交代を代守として重ねない', () {
    final lineups = battingLineupsOf(
      [
        _row(id: 1, result: Value.CodeGameResult.STRIKE_OUT, batter: 'ジャクソン・メリル', order: 5),
        _row(
          id: 2,
          result: Value.CodeGameResult.PINCH_FIELDER,
          batter: '相手打者',
          order: 3,
          team: 202,
          inning: 8,
          bottom: true,
          enter: 'J.メリル',
          exit: 'ジャクソン・メリル',
        ),
        _row(
          id: 3,
          result: Value.CodeGameResult.CHANGE_POSITION,
          batter: '相手打者',
          order: 4,
          team: 202,
          inning: 8,
          bottom: true,
          enter: 'J.メリル',
          exit: 'ジャクソン・メリル',
        ),
      ],
      plays: const {},
      pitchers: const {},
    );
    final players = _playersOf(lineups, 5);
    expect(players.map((player) => player['name']).toList(), ['ジャクソン・メリル']);
    expect(players.single['role'], '');
  });
}
