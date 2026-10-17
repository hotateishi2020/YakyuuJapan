import 'package:test/test.dart';
import 'package:html/parser.dart';
import '../app/MlbScheduleReconcile.dart';
import '../app/JapanClock.dart';

void main() {
  test('取得失敗・未知HTMLを試合なしと扱わない', () {
    expect(mlbScheduleCards(parse('<html>Service unavailable</html>')), isNull);
    expect(mlbScheduleCards(parse('<div id="gm_card"></div>')), isNull);
    expect(mlbScheduleCards(parse('<p>本日の試合はありません</p>')), isEmpty);
  });
  test('中止カードと消えた予定だけを除外し、終了・進行中・記録済みは保護する', () {
    final cards = mlbScheduleCards(parse(
        '''<div id="gm_card"><li class="bb-score__item"><p class="bb-score__homeLogo">ガーディアンズ</p><p class="bb-score__awayLogo">レイズ</p><p class="bb-score__link">試合中止</p></li></div>'''))!;
    final games = <Map<String, dynamic>>[
      for (var i = 1; i <= 5; i++)
        {
          'id': i,
          'home': 'ガーディアンズ',
          'away': 'レイズ',
          'state': ['', '予定', '試合終了', '5回表', '予定', '予定'][i],
          'has_records': i == 4
        },
    ];
    expect(obsoleteMlbGameIds(games, cards), [1, 5]);
    expect(obsoleteMlbGameIds([{'id': 6, 'home': 'ガーディアンズ', 'away': 'レイズ', 'state': '試合中止', 'has_records': false}], cards), [6]);
    expect(obsoleteMlbGameIds(games, []), [1, 5]);
    cards[0]['state'] = '09:00';
    expect(obsoleteMlbGameIds(games, cards), isEmpty);
  });
  test('米国前日の試合も日本の当日として扱う', () {
    final day = JapanClock.fromUtc(DateTime.parse('2026-10-16T22:00:00Z'));
    expect(day, DateTime(2026, 10, 17, 7));
  });
}
