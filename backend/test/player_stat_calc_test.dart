import 'package:test/test.dart';

import '../app/FetchURL.dart';

void main() {
  test('盗塁成功率は企図に対する成功の百分率', () {
    expect(FetchURL.stolenBaseSuccessPercent(38, 7), 84.4);
    expect(FetchURL.stolenBaseSuccessPercent(7, 0), 100.0);
    expect(FetchURL.stolenBaseSuccessPercent(0, 0), isNull);
  });

  test('K/BBは奪三振を与四球で割る', () {
    expect(FetchURL.strikeoutsPerWalk(90, 20), 4.5);
    expect(FetchURL.strikeoutsPerWalk(1, 3), 0.33);
    expect(FetchURL.strikeoutsPerWalk(10, 0), isNull);
  });

  test('与四球率は投球回の1/3を戻してから9イニング換算する', () {
    expect(FetchURL.baseballInnings('162.1'), closeTo(162 + 1 / 3, 0.0001));
    expect(FetchURL.walksPerNine(17, '159'), 0.96);
    expect(FetchURL.walksPerNine(32, '162.1'), 1.77);
    expect(FetchURL.walksPerNine(1, '0'), isNull);
  });
}
