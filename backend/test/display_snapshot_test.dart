import 'package:test/test.dart';

import '../app/DisplaySnapshot.dart';

void main() {
  test('登録済みの期間に含まれる日は再集計しない', () {
    final spans = [(from: '2026-10-05', to: '2026-10-18')];
    expect(spansCover(spans, '2026-10-08', '2026-10-08'), isTrue);
    expect(spansCover(spans, '2026-10-05', '2026-10-18'), isTrue);
    expect(spansCover(spans, '2026-10-04', '2026-10-08'), isFalse);
    expect(spansCover(const [], '2026-10-08', '2026-10-08'), isFalse);
  });

  test('隣り合う期間をつなげて判定する', () {
    final spans = [
      (from: '2026-04-01', to: '2026-04-02'),
      (from: '2026-04-03', to: '2026-04-03'),
    ];
    expect(spansCover(spans, '2026-04-01', '2026-04-03'), isTrue);
    expect(nextYmd('2026-04-30'), '2026-05-01');
  });
}
