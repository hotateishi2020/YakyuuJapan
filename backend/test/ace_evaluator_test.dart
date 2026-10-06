import 'package:test/test.dart';

import '../app/AceEvaluator.dart';

void main() {
  test('エースポイントは防御率を投球回・勝ち数より重く見る', () {
    expect(AceEvaluator.eraWeight, greaterThanOrEqualTo(0.5));
    expect(AceEvaluator.eraWeight, greaterThan(AceEvaluator.ipWeight));
    expect(AceEvaluator.eraWeight, greaterThan(AceEvaluator.winsWeight));
    expect(
      AceEvaluator.ipWeight +
          AceEvaluator.eraWeight +
          AceEvaluator.k9Weight +
          AceEvaluator.ipPerAppWeight +
          AceEvaluator.winsWeight,
      closeTo(1.0, 1e-9),
    );
  });
}
