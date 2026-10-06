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
    expect(chips, contains('0四死|'));
    expect(chips, contains('0K|'));
  });

  test('四死球と奪三振は1四死・3Kで出す', () {
    final chips = pitcherStatChips(
      innings: 6,
      runs: 2,
      hits: 5,
      walks: 1,
      hbp: 0,
      strikeouts: 3,
      pitches: 90,
      starter: true,
    );
    expect(chips, contains('1四死|'));
    expect(chips, contains('3K|'));
    expect(chips, isNot(contains('BB')));
    expect(chips, isNot(contains('奪三振')));
  });

  test('9回2失点は赤橙、9回3失点は黄橙、1回2失点は黒アラート', () {
    expect(
      pitcherStatChips(innings: 9, runs: 2, hits: 0, walks: 0, hbp: 0, strikeouts: 0, pitches: 100, starter: true),
      contains('9回2失点|rorange'),
    );
    expect(
      pitcherStatChips(innings: 9, runs: 3, hits: 0, walks: 0, hbp: 0, strikeouts: 0, pitches: 100, starter: true),
      contains('9回3失点|yorange'),
    );
    expect(
      pitcherStatChips(innings: 1, runs: 2, hits: 0, walks: 0, hbp: 0, strikeouts: 0, pitches: 20, starter: false),
      contains('1回2失点|alert'),
    );
    expect(
      pitcherStatChips(innings: 9, runs: 0, hits: 0, walks: 0, hbp: 0, strikeouts: 0, pitches: 100, starter: true),
      contains('9回無失点|crimson'),
    );
  });

  test('1回あたり四死球1.5以上は黒アラート、未満は通常色', () {
    expect(
      pitcherStatChips(innings: 2, runs: 0, hits: 0, walks: 3, hbp: 0, strikeouts: 0, pitches: 40, starter: false),
      contains('3四死|alert'),
    );
    expect(
      pitcherStatChips(innings: 1, runs: 0, hits: 0, walks: 2, hbp: 0, strikeouts: 0, pitches: 30, starter: false),
      contains('2四死|alert'),
    );
    expect(
      pitcherStatChips(innings: 1, runs: 0, hits: 0, walks: 1, hbp: 0, strikeouts: 0, pitches: 20, starter: false),
      isNot(contains('1四死|alert')),
    );
    expect(
      pitcherStatChips(innings: 6, runs: 2, hits: 5, walks: 1, hbp: 0, strikeouts: 3, pitches: 90, starter: true),
      contains('1四死|'),
    );
    expect(
      pitcherStatChips(innings: 6, runs: 2, hits: 5, walks: 1, hbp: 0, strikeouts: 3, pitches: 90, starter: true),
      isNot(contains('1四死|alert')),
    );
  });
}
