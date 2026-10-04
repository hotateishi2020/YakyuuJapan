import 'package:test/test.dart';

import '../app/Achieve.dart';

void main() {
  test('0回1球でも色付きチップを返す', () {
    final chips = pitcherStatChips(
      innings: 0,
      runs: 1,
      hits: 1,
      walks: 0,
      hbp: 0,
      strikeouts: 0,
      pitches: 1,
      starter: false,
    );
    expect(chips, isNotEmpty);
    expect(chips, contains('0回1失点|'));
    expect(chips, contains('被安打1|'));
    expect(chips, contains('1球|'));
  });
}
