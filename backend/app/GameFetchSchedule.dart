/// 明日以降の日程カードは 10 分に 1 回だけ取る。
/// 昨日以前は一度読み込み済みと判断したら、その日は再取得しない。
/// 今日は読み込みが終わって 10 秒後に、今日の分だけ取りに行く。
class GameFetchSchedule {
  static const futureInterval = Duration(minutes: 10);
  static const todayInterval = Duration(seconds: 10);
  static final _lastFuture = <String, DateTime>{};
  static final _pastDone = <String>{};
  static final _todayBusy = <String, bool>{};
  static final _todayQueued = <String, bool>{};
  static final _todayFetch = <String, Future<bool> Function()>{};
  static int _todayEpoch = 0;

  static bool takeFuture(String org, DateTime now) {
    final last = _lastFuture[org];
    if (last != null && now.difference(last) < futureInterval) return false;
    _lastFuture[org] = now;
    return true;
  }

  static bool isFutureDay(DateTime date, DateTime now) {
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    return day.isAfter(today);
  }

  static bool isPastDay(DateTime date, DateTime now) {
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    return day.isBefore(today);
  }

  static String _pastKey(String org, String date) => '$org|$date';

  static bool pastDateDone(String org, String date) => _pastDone.contains(_pastKey(org, date));

  static void markPastDateDone(String org, String date) => _pastDone.add(_pastKey(org, date));

  static bool isTodayBusy(String org) => _todayBusy[org] == true;

  static bool isTodayQueued(String org) => _todayQueued[org] == true;

  static void markTodayBusy(String org, bool busy) => _todayBusy[org] = busy;

  /// 今日の取得が終わって [todayInterval] 後に、今日の分だけもう一度取る。
  static void scheduleTodayAgain(String org, Future<bool> Function() fetchToday) {
    _todayFetch[org] = fetchToday;
    if (_todayQueued[org] == true) return;
    _todayQueued[org] = true;
    final token = _todayEpoch;
    Future<void>.delayed(todayInterval, () async {
      if (token != _todayEpoch) return;
      _todayQueued[org] = false;
      final fetch = _todayFetch[org];
      if (fetch == null) return;
      if (_todayBusy[org] == true) {
        scheduleTodayAgain(org, fetch);
        return;
      }
      _todayBusy[org] = true;
      var keep = true;
      try {
        keep = await fetch();
      } catch (e, st) {
        print('今日の試合再取得失敗 ($org): $e');
        print(st);
      } finally {
        if (token == _todayEpoch) _todayBusy[org] = false;
        if (keep && token == _todayEpoch) scheduleTodayAgain(org, fetch);
      }
    });
  }

  static void resetForTest() {
    _todayEpoch++;
    _lastFuture.clear();
    _pastDone.clear();
    _todayBusy.clear();
    _todayQueued.clear();
    _todayFetch.clear();
  }
}
