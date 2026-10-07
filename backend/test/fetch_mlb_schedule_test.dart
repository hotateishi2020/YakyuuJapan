import 'package:test/test.dart';

import '../app/FetchMLB.dart';
import '../app/GameFetchSchedule.dart';
import '../app/GameStatsLoad.dart';

void main() {
  test('完了済みの終了試合は選手成績を取り直さない', () {
    expect(GameStatsLoad.needsRefresh(live: false, loaded: true), isFalse);
    expect(GameStatsLoad.needsRefresh(live: false, loaded: false), isTrue);
    expect(GameStatsLoad.needsRefresh(live: true, loaded: true), isTrue);
    expect(GameStatsLoad.needsRefresh(live: true, loaded: false), isTrue);
  });

  test('MLB日程は今日と昨日を先に回す', () {
    final now = DateTime(2026, 10, 7, 7, 50);
    final dates = FetchMLB.scheduleDates(now);
    expect(dates.first.day, 7);
    expect(dates[1].day, 6);
    expect(dates.map((date) => date.day).toList(), isNot(equals([4, 5, 6, 7])));
    expect(dates.any((date) => date.day == 8), isTrue);
  });

  test('明日以降の日程は10分に1回だけ取る', () {
    GameFetchSchedule.resetForTest();
    final now = DateTime(2026, 10, 7, 8, 0);
    expect(GameFetchSchedule.takeFuture('mlb', now), isTrue);
    expect(GameFetchSchedule.takeFuture('mlb', now.add(const Duration(minutes: 9))), isFalse);
    expect(GameFetchSchedule.takeFuture('mlb', now.add(const Duration(minutes: 10))), isTrue);
    expect(GameFetchSchedule.takeFuture('npb', now.add(const Duration(minutes: 9))), isTrue);
    final todayOnly = FetchMLB.scheduleDates(now, includeFuture: false);
    expect(todayOnly.every((date) => !GameFetchSchedule.isFutureDay(date, now)), isTrue);
    expect(todayOnly.any((date) => date.day == 8), isFalse);
  });

  test('今日の試合は読み込み後10秒で再取得する', () {
    GameFetchSchedule.resetForTest();
    expect(GameFetchSchedule.todayInterval, const Duration(seconds: 10));
    final now = DateTime(2026, 10, 7, 8, 0);
    expect(FetchMLB.scheduleDates(now, todayOnly: true).map((date) => date.day).toList(), [7]);
    expect(GameFetchSchedule.isTodayQueued('mlb'), isFalse);
    GameFetchSchedule.scheduleTodayAgain('mlb', () async => false);
    expect(GameFetchSchedule.isTodayQueued('mlb'), isTrue);
    GameFetchSchedule.scheduleTodayAgain('mlb', () async => false);
    expect(GameFetchSchedule.isTodayQueued('mlb'), isTrue);
  });

  test('昨日以前は全部読み込み済みなら再取得しない', () {
    final now = DateTime(2026, 10, 7, 8, 0);
    expect(GameFetchSchedule.isPastDay(DateTime(2026, 10, 6), now), isTrue);
    expect(GameFetchSchedule.isPastDay(DateTime(2026, 10, 7), now), isFalse);
    expect(GameFetchSchedule.isPastDay(DateTime(2026, 10, 8), now), isFalse);
    expect(GameStatsLoad.dateFullyLoaded(hasYahooGames: true, hasPending: false), isTrue);
    expect(GameStatsLoad.dateFullyLoaded(hasYahooGames: true, hasPending: true), isFalse);
    expect(GameStatsLoad.dateFullyLoaded(hasYahooGames: false, hasPending: false), isFalse);

    GameFetchSchedule.resetForTest();
    expect(GameFetchSchedule.pastDateDone('mlb', '2026-10-06'), isFalse);
    GameFetchSchedule.markPastDateDone('mlb', '2026-10-06');
    expect(GameFetchSchedule.pastDateDone('mlb', '2026-10-06'), isTrue);
    expect(GameFetchSchedule.pastDateDone('npb', '2026-10-06'), isFalse);
  });
}
