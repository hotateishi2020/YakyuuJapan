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
  test('表示用打席データに実際のイニングを保持する', () {
    final labels = playLabelsByPlayer([
      _row(result: Value.CodeGameResult.HIT_SINGLE, inning: 2, direction: 'LF'),
      _row(result: Value.CodeGameResult.OUT_GROUND, inning: 5, direction: 'SS'),
    ]);
    expect(labels.values.single, '左安|single/inning2/bases6 遊ゴロ|out/inning5/bases6');
  });

  test('交代と非打撃進塁を打撃の上段用情報として保持する', () {
    final codes = ['CHANGE_PITCHER', 'PINCH_HITTER', 'PINCH_RUNNER', 'PINCH_FIELDER', 'CHANGE_POSITION', 'STEAL_BASE_SAFE', 'WILD_PITCH', 'PASS_BALL', 'ERROR_RUNNING'];
    final expected = ['投手', '代打', '代走', '代守', '守備位置転換', '盗塁', '暴投', '捕逸', '送球エラー'];
    for (var i = 0; i < codes.length; i++) {
      final event = _row(result: codes[i])..addAll({'id': 1, 'name_enter': '新 選手', 'name_exit': '旧 選手', 'code_position_from': 'LF', 'code_position_to': 'RF'});
      final result = _row(result: 'OUT_GROUND')..addAll({'id': 2, 'flg_runner_first': true, 'flg_runner_second': true, 'flg_runner_third': true});
      final labels = playLabelsByPlayer([event, result]).values.join(' ');
      expect(labels, contains('/event${Uri.encodeComponent(expected[i])}')); 
      // イベント後の満塁ではなく、打席開始時の二・三塁を表示する。
      expect(labels, contains('/bases6'));
    }
  });

  test('守備位置のDBコードを名字とfrom/toへ変換する', () {
    for (final data in [('近藤', '健介', 'RIGHT', 'LEFT', '右→左'), ('川村', '友斗', 'LEFT', 'RIGHT', '左→右')]) {
      final event = _row(result: 'CHANGE_POSITION')..addAll({
        'id': 1, 'name_enter': '${data.$1}　${data.$2}', 'name_enter_last': data.$1,
        'code_position_from': data.$3, 'code_position_to': data.$4,
      });
      final hit = _row(result: Value.CodeGameResult.HIT_SINGLE)..['id'] = 2;
      final labels = playLabelsByPlayer([event, hit]).values.join(' ');
      expect(labels, contains(Uri.encodeComponent('守備位置転換:${data.$1}(${data.$5})')));
      expect(labels, isNot(contains(Uri.encodeComponent(data.$2))));
    }
  });

  test('代守は移動先だけ、守転は移動元と移動先を表示する', () {
    final events = [
      _row(result: 'PINCH_FIELDER', inning: 9)..addAll({
        'id': 1, 'name_enter': '三森　大貴', 'name_enter_last': '三森',
        'code_position_from': '', 'code_position_to': 'CENTER',
      }),
      _row(result: 'CHANGE_POSITION', inning: 9)..addAll({
        'id': 2, 'name_enter': '蝦名　達夫', 'name_enter_last': '蝦名',
        'code_position_from': 'CENTER', 'code_position_to': 'RIGHT',
      }),
      _row(result: 'STRIKE_OUT', inning: 9)..['id'] = 3,
    ];
    final labels = playLabelsByPlayer(events).values.join(' ');
    expect(labels, contains(Uri.encodeComponent('代守:三森(中)')));
    expect(labels, contains(Uri.encodeComponent('守備位置転換:蝦名(中→右)')));
    expect(labels, isNot(contains(Uri.encodeComponent('三森(→中)'))));
  });

  test('走者の情報がない打席は塁を推測しない', () {
    final row = _row(result: 'OUT_GROUND')
      ..remove('flg_runner_first')..remove('flg_runner_second')..remove('flg_runner_third');
    expect(playLabelsByPlayer([row]).values.single, isNot(contains('/bases')));
  });

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

  test('打点1のゴロは点数を書かず rbi フラグを付ける', () {
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.OUT_GROUND, direction: 'SS', runs: 1),
      ]),
      '遊ゴロ|out/rbi',
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

  test('非打撃の得点は直後の打撃に run を付け打点にはしない', () {
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.WILD_PITCH, runs: 1)..['id'] = 1,
        _row(result: Value.CodeGameResult.HIT_SINGLE, direction: 'LF')..['id'] = 2,
      ]),
      '左安|single/run',
    );
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.PASS_BALL, runs: 1)..['id'] = 1,
        _row(result: Value.CodeGameResult.OUT_GROUND, direction: 'SS')..['id'] = 2,
      ]),
      '遊ゴロ|out/run',
    );
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.STEAL_BASE_SAFE, runner: '走者', runs: 1)..['id'] = 1,
        _row(result: Value.CodeGameResult.HIT_SINGLE, direction: 'CF', outs: 1)..['id'] = 2,
      ]),
      '盗塁|steal 中安|single/run',
    );
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.PICKOFF, runs: 1)..['id'] = 1,
        _row(result: Value.CodeGameResult.WALK_BALL)..['id'] = 2,
      ]),
      '四球|walk/run',
    );
  });

  test('失策で走者が生還しても打点ではなく run を付ける', () {
    expect(
      formatPlayLabels([
        _row(result: Value.CodeGameResult.ERROR_FIELDING, direction: 'SS', runs: 1),
      ]),
      '遊失|error/run',
    );
  });

  test('二死からのアウトは3アウトになり、安打のままなら2アウト', () {
    expect(outsAfterPlate(2, Value.CodeGameResult.OUT_FLY), 3);
    expect(outsAfterPlate(2, Value.CodeGameResult.STRIKE_OUT), 3);
    expect(outsAfterPlate(1, Value.CodeGameResult.OUT_DOUBLE_PLAY), 3);
    expect(outsAfterPlate(2, Value.CodeGameResult.HIT_SINGLE), 2);
    expect(outsAfterPlate(0, Value.CodeGameResult.STRIKE_OUT), 1);
    expect(outsAfterPlate(2, Value.CodeGameResult.STEAL_BASE_OUT), 3);
  });

  test('playPlayerKey ignores spaces in NPB names', () {
    expect(playPlayerKey(1, 2, '成瀬　脩人'), playPlayerKey(1, 2, '成瀬脩人'));
    expect(playPlayerKey(1, 2, '佐藤 輝明'), playPlayerKey(1, 2, '佐藤輝明'));
  });
}
