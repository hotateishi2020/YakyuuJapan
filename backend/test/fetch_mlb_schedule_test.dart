import 'package:test/test.dart';

import '../app/FetchMLB.dart';
import '../app/JapanClock.dart';
import '../app/FetchURL.dart';
import '../app/GameFetchSchedule.dart';
import '../app/GameStatsLoad.dart';
import '../app/Value.dart';

void main() {
  test('終了試合で勝利投手がいるのに勝敗マークが無いときは出場成績を取り直す', () {
    expect(
      GameStatsLoad.needsDecisionRefresh(finished: true, hasWinner: true, hasDecisionCode: false),
      isTrue,
    );
    expect(
      GameStatsLoad.needsDecisionRefresh(finished: true, hasWinner: true, hasDecisionCode: true),
      isFalse,
    );
    expect(
      GameStatsLoad.needsDecisionRefresh(finished: false, hasWinner: true, hasDecisionCode: false),
      isFalse,
    );
    expect(
      GameStatsLoad.needsDecisionRefresh(finished: true, hasWinner: false, hasDecisionCode: false),
      isFalse,
    );
  });

  test('出場成績の投手表の先頭列を勝敗HSにする', () {
    expect(pitcherDecisionCode('勝'), Value.CodeGameResultPitcher.WIN);
    expect(pitcherDecisionCode('敗'), Value.CodeGameResultPitcher.LOSE);
    expect(pitcherDecisionCode('H'), Value.CodeGameResultPitcher.HOLD);
    expect(pitcherDecisionCode('Ｓ'), Value.CodeGameResultPitcher.SAVE);
    expect(pitcherDecisionCode(''), '');
  });

  test('優勝決定シリーズはリーグ別のLCSコードになる', () {
    expect(FetchMLB.mlbGameCode('NL優勝決定シリーズ', 4, 4), 'NLCS');
    expect(FetchMLB.mlbGameCode('AL優勝決定シリーズ', 3, 3), 'ALCS');
    expect(FetchMLB.mlbGameCode('リーグチャンピオンシップ', 4, 4), 'LCS');
    expect(FetchMLB.mlbGameCode('地区シリーズ', 4, 4), 'DS');
    expect(FetchMLB.mlbGameCode('交流戦', 3, 4), 'EX');
  });

  test('優勝決定シリーズはリーグ別のLCSになる', () {
    expect(FetchMLB.mlbGameCode('NL優勝決定シリーズ', 4, 4), 'NLCS');
    expect(FetchMLB.mlbGameCode('AL優勝決定シリーズ', 3, 3), 'ALCS');
    expect(FetchMLB.mlbGameCode('リーグチャンピオンシップ', 4, 4), 'LCS');
    expect(FetchMLB.mlbGameCode('地区シリーズ', 4, 4), 'DS');
    expect(FetchMLB.mlbGameCode('ワールドシリーズ', 3, 4), 'WS');
  });

  test('完了済みの終了試合は選手成績を取り直さない', () {
    expect(GameStatsLoad.needsRefresh(finished: true, loaded: true), isFalse);
    expect(GameStatsLoad.needsRefresh(finished: true, loaded: false), isTrue);
    expect(GameStatsLoad.needsRefresh(finished: false, loaded: true), isFalse);
    expect(GameStatsLoad.needsRefresh(finished: false, loaded: false), isFalse);
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
    GameFetchSchedule.markInitialDisplayReady();
    expect(GameFetchSchedule.todayInterval, const Duration(seconds: 10));
    final now = DateTime(2026, 10, 7, 8, 0);
    expect(FetchMLB.scheduleDates(now, todayOnly: true).map((date) => date.day).toList(), [7]);
    expect(GameFetchSchedule.isTodayQueued('mlb'), isFalse);
    GameFetchSchedule.scheduleTodayAgain('mlb', () async => false);
    expect(GameFetchSchedule.isTodayQueued('mlb'), isTrue);
    GameFetchSchedule.scheduleTodayAgain('mlb', () async => false);
    expect(GameFetchSchedule.isTodayQueued('mlb'), isTrue);
  });

  test('日本時間の朝はUTCの前日でも今日の試合日になる', () {
    final morning = JapanClock.fromUtc(DateTime.utc(2026, 10, 12, 22, 48));
    expect(morning.year, 2026);
    expect(morning.month, 10);
    expect(morning.day, 13);
    expect(morning.hour, 7);
  });

  test('未来の日程カードは同じ内容なら取り直さず変わったら取り直す', () {
    GameFetchSchedule.resetForTest();
    GameFetchSchedule.markInitialDisplayReady();
    const key = 'mlb|2026-10-15|/mlb/game/1/index';
    final first = GameFetchSchedule.normalizeCard(key, 'ドジャース 予想先発');
    expect(GameFetchSchedule.futureCardUnchanged(key, first), isFalse);
    GameFetchSchedule.rememberFutureCard(key, first);
    expect(GameFetchSchedule.futureCardUnchanged(key, GameFetchSchedule.normalizeCard(key, 'ドジャース   予想先発')), isTrue);
    expect(GameFetchSchedule.futureCardUnchanged(key, GameFetchSchedule.normalizeCard(key, 'ドジャース 3回裏 1-2')), isFalse);
    expect(GameFetchSchedule.futureCardUnchanged(key, ''), isFalse);
    final now = DateTime(2026, 10, 13, 7, 0);
    expect(GameFetchSchedule.isFutureDay(DateTime(2026, 10, 14), now), isTrue);
    expect(GameFetchSchedule.isFutureDay(DateTime(2026, 10, 13), now), isFalse);
    GameFetchSchedule.armFutureWatch('mlb', () async {});
    expect(GameFetchSchedule.isFutureQueued('mlb'), isTrue);
    GameFetchSchedule.armFutureWatch('mlb', () async {});
    expect(GameFetchSchedule.isFutureQueued('mlb'), isTrue);
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
