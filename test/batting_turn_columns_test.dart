import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/batting_turn_columns.dart';

void main() {
  test('回の途中でも9番から1番で折り返す', () {
    final plates = <({int order, int? inning})>[
      for (var i = 1; i <= 6; i++) (order: i, inning: 1),
      for (final i in [7, 8, 9, 1, 2]) (order: i, inning: 2),
      for (final i in [3, 4, 5]) (order: i, inning: 3),
      for (final i in [6, 7, 8]) (order: i, inning: 4),
      (order: 9, inning: 5),
    ];
    expect(battingTurnColumns(plates), [...List.filled(9, 0), ...List.filled(9, 1)]);
  });
  test('打順別の入力でも同じ回の2打席を別の列に配置する', () {
    final plates = <({int order, int? inning})>[
      for (var order = 1; order <= 9; order++) ...[
        (order: order, inning: 1),
        (order: order, inning: order <= 4 ? 1 : 2),
        if (order == 1) (order: order, inning: 2),
      ],
    ];
    expect(battingTurnColumns(plates), [0, 1, 2, for (var i = 2; i <= 9; i++) ...[0, 1]]);
  });
}
