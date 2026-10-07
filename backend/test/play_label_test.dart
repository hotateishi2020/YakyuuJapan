import 'package:test/test.dart';

import '../app/Achieve.dart';
import '../app/PlayLabel.dart';
import '../app/Value.dart';

Map<String, dynamic> _row({
  required String result,
  int inning = 1,
  bool bottom = false,
  int order = 1,
  int outs = 0,
  String direction = '',
  int runs = 0,
  bool goodbye = false,
  String runner = '',
}) {
  return {
    'id': 1,
    'int_inning': inning,
    'flg_bottom': bottom,
    'int_batting_order': order,
    'cnt_out': outs,
    'flg_runner_first': false,
    'flg_runner_second': true,
    'flg_runner_third': true,
    'code_result': result,
    'code_direction_batting': direction,
    'int_runs': runs,
    'flg_goodbye': goodbye,
    'cnt_homerun': 0,
    'code_state_score': '',
    'name_runner': runner,
    'name_full': '打者',
  };
}

void main() {
  test('代走盗塁は盗塁だけ、同じ打席の安打には盗塁を付ける', () {
    expect(
      formatPlayLabels([_row(result: Value.CodeGameResult.STEAL_BASE_SAFE, runner: '代走')]),
      '盗塁|steal',
    );
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.HIT_SINGLE, direction: 'SS'),
        _row(result: Value.CodeGameResult.STEAL_BASE_SAFE),
      ]),
      '遊安|single/steal',
    );
  });

  test('安打は短文に方向を入れ、先制ヒットはマークで方向を残す', () {
    expect(
      formatPlayLabels([_row(result: Value.CodeGameResult.HIT_SINGLE, direction: 'LF')]),
      '左安|single',
    );
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.HIT_SINGLE, direction: 'RF')
          ..['code_state_score'] = 'FIRST',
      ]),
      '先制ヒット^右|single',
    );
  });

  test('打妨と野選の表示を残す', () {
    expect(
      formatPlayLabels([_row(result: Value.CodeGameResult.INTERFERENCE_BATTING)]),
      '打撃妨害|dead',
    );
    expect(
      formatPlayLabels([_row(result: Value.CodeGameResult.FIELDERS_CHOICE, direction: 'SS')]),
      '遊野選|fc',
    );
  });

  test('代打の打席は pinch フラグを付ける', () {
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.PINCH_HITTER),
        _row(result: Value.CodeGameResult.HIT_SINGLE, direction: 'LF', runs: 1),
      ]),
      '代打タイムリー^左|timely/pinch',
    );
  });

  test('三塁打のタイムリーは打球方向を残す', () {
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.HIT_TRIPLE, direction: 'LF', runs: 1, inning: 8),
      ]),
      'タイムリースリーベース^左|timely',
    );
  });

  test('先制2ランホームランは先制と2ランを残す', () {
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.HOME_RUN, direction: 'LEFT', runs: 2)
          ..['code_state_score'] = 'FIRST',
      ]),
      '先制2ランホームラン^左|hr',
    );
  });

  test('サヨナラ2点タイムリーは点数とサヨナラを残す', () {
    expect(
      formatPlayLabels([
        _row(
          result: Value.CodeGameResult.HIT_SINGLE,
          direction: 'CENTER',
          runs: 2,
          goodbye: true,
          inning: 9,
          bottom: true,
        ),
      ]),
      'サヨナラ2点タイムリー^中|timely',
    );
  });

  test('打席が4未満なら全打席安打・全打席出塁を付けない', () {
    expect(plateFeatMarks(plates: 3, reached: 3, hits: 3), isEmpty);
    expect(plateFeatMarks(plates: 4, reached: 4, hits: 4), contains('全打席安打'));
    expect(plateFeatsFromLine(atBats: 3, hits: 3, walks: 0, hbp: 0, sacrifices: 0, errors: 0), isEmpty);
  });

  test('playPlayerKey ignores spaces in NPB names', () {
    expect(playPlayerKey(1, 2, '成瀬　脩人'), playPlayerKey(1, 2, '成瀬脩人'));
    expect(playPlayerKey(1, 2, '佐藤 輝明'), playPlayerKey(1, 2, '佐藤輝明'));
  });
}
