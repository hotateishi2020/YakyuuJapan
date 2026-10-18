import '../app/GameFetchSchedule.dart';
import 'package:test/test.dart';
import '../app/MlbScheduleWatch.dart';

void main() {
  test('再確認は当日から10日後まで年をまたいでも11日分', () {
    final dates = GameFetchSchedule.recheckDates(DateTime(2026, 12, 27, 18));
    expect(dates, hasLength(11));
    expect(dates.first, DateTime(2026, 12, 27));
    expect(dates.last, DateTime(2027, 1, 6));
  });
  test('日本時間の0・6・12・18時に予約する', () {
    for (final pair in [
      ['2026-10-16T14:59:00Z', '2026-10-16T15:00:00Z'],
      ['2026-10-16T15:00:00Z', '2026-10-16T21:00:00Z'],
      ['2026-10-16T21:01:00Z', '2026-10-17T03:00:00Z'],
      ['2026-10-17T03:00:00Z', '2026-10-17T09:00:00Z'],
      ['2026-12-31T14:59:59Z', '2026-12-31T15:00:00Z'],
      ['2026-10-17T17:30:00+09:00', '2026-10-17T09:00:00Z'],
    ]) {
      expect(MlbScheduleWatch.nextCheckAt(DateTime.parse(pair[0])), DateTime.parse(pair[1]));
    }
  });
}
