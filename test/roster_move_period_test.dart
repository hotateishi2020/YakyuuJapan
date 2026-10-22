import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/strength_usage.dart';

void main() {
  test('移籍ラベルの4期間と年をまたぐオフ', () {
    for (final entry in {
      '2025-07-15': '昨季',
      '2025-12-10': '昨オフ',
      '2026-01-15': '昨オフ',
      '2026-07-15': '今季',
      '2026-10-15': '今オフ',
      '2027-01-15': '今オフ',
    }.entries) {
      expect(rosterTimedMoveLabel('トレード', {
        'move_method': 'トレード', 'move_method_year': 2026,
        'move_method_as_of': entry.key,
      }, 2026), '${entry.value} トレード');
    }
  });
  test('翌春の加入は前年秋でも昨季ではなく昨オフ', () {
    expect(rosterMovePeriod({'new_arrival':true,'arrival_year':2027,
      'status_as_of':'2026-09-23'},2027), '昨オフ');
  });
  test('確認日の更新で移籍時期を変えない', () {
    expect(rosterTimedMoveLabel('現役ドラフト', {
      'move_method': '現役ドラフト', 'move_method_year': 2026,
      'move_method_as_of': '2025-12-10', 'status_as_of': '2026-10-22',
    }, 2026), '昨オフ 現役ドラフト');
  });
  test('表示年度基準、FAやポスティング、移籍以外のラベル', () {
    expect(rosterMovePeriod({'status_as_of':'2025-07-15'},2025),'今季');
    expect(rosterTimedMoveLabel('ポスティング？', {},2026),'今オフ ポスティング？');
    expect(rosterTimedMoveLabel('国内FA', {},2026),'今オフ 国内FA');
    expect(rosterTimedMoveLabel('外国人適用除外', {},2026),'外国人適用除外');
  });
}
