import 'ScheduledLog.dart';

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
  static final _futureArmed = <String>{};
  static final _futureBusy = <String, bool>{};
  static final _futureQueued = <String, bool>{};
  static final _futureFetch = <String, Future<void> Function()>{};
  static final _cardPrint = <String, String>{};
  static int _futureEpoch = 0;
  static bool _initialDisplayReady = false;

  /// 起動時は取得処理の登録だけ行い、画面の初期表示完了後にタイマーを動かす。
  static void markInitialDisplayReady() {
    if (_initialDisplayReady) return;
    _initialDisplayReady = true;
    for (final entry in _todayFetch.entries.toList()) {
      scheduleTodayAgain(entry.key, entry.value);
    }
    for (final entry in _futureFetch.entries.toList()) {
      armFutureWatch(entry.key, entry.value);
    }
  }

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

  static bool pastDateDone(String org, String date) =>
      _pastDone.contains(_pastKey(org, date));

  static void markPastDateDone(String org, String date) =>
      _pastDone.add(_pastKey(org, date));

  static bool isTodayBusy(String org) => _todayBusy[org] == true;

  static bool isTodayQueued(String org) => _todayQueued[org] == true;

  static void markTodayBusy(String org, bool busy) => _todayBusy[org] = busy;

  /// 今日の取得が終わって [todayInterval] 後に、今日の分だけもう一度取る。
  static void scheduleTodayAgain(
      String org, Future<bool> Function() fetchToday) {
    _todayFetch[org] = fetchToday;
    if (!_initialDisplayReady) return;
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
        keep = await ScheduledLog.run('games_today_$org', fetch);
      } catch (e, st) {
        print('今日の試合再取得失敗 ($org): $e');
        print(st);
      } finally {
        if (token == _todayEpoch) _todayBusy[org] = false;
        if (keep && token == _todayEpoch) scheduleTodayAgain(org, fetch);
      }
    });
  }

  static bool isFutureBusy(String org) => _futureBusy[org] == true;

  static bool isFutureQueued(String org) => _futureQueued[org] == true;

  /// 初期表示完了後と、その後は [futureInterval] ごとに日程カードを見に行く。
  static void armFutureWatch(String org, Future<void> Function() fetchFuture) {
    _futureFetch[org] = fetchFuture;
    if (!_initialDisplayReady) return;
    if (_futureArmed.contains(org)) return;
    _futureArmed.add(org);
    _queueFuture(org, initial: true);
  }

  static void _queueFuture(String org, {bool initial = false}) {
    if (_futureQueued[org] == true) return;
    _futureQueued[org] = true;
    final token = _futureEpoch;
    Future<void>.delayed(initial ? const Duration(seconds: 20) : futureInterval,
        () async {
      _futureQueued[org] = false;
      if (token != _futureEpoch) return;
      final fetch = _futureFetch[org];
      if (fetch == null) return;
      if (_futureBusy[org] == true) {
        _queueFuture(org);
        return;
      }
      _futureBusy[org] = true;
      try {
        await ScheduledLog.run('games_future_$org', fetch);
      } catch (e, st) {
        print('未来の試合確認に失敗しました ($org): $e');
        print(st);
      } finally {
        if (token == _futureEpoch) _futureBusy[org] = false;
      }
      if (token == _futureEpoch) _queueFuture(org);
    });
  }

  /// 日程カードの見た目。空白の差では変わったことにしない。
  static String normalizeCard(String href, String text) {
    return '$href|${text.replaceAll(RegExp(r'\s+'), '')}';
  }

  /// 前回と同じカードなら詳細は取り直さない。空のカードは毎回見る。
  static bool futureCardUnchanged(String key, String fingerprint) {
    if (fingerprint.replaceAll(RegExp(r'\s+'), '').isEmpty) return false;
    return _cardPrint[key] == fingerprint;
  }

  static void rememberFutureCard(String key, String fingerprint) {
    if (fingerprint.isEmpty) return;
    _cardPrint[key] = fingerprint;
  }

  static void resetForTest() {
    _initialDisplayReady = false;
    _todayEpoch++;
    _futureEpoch++;
    _lastFuture.clear();
    _pastDone.clear();
    _todayBusy.clear();
    _todayQueued.clear();
    _todayFetch.clear();
    _futureArmed.clear();
    _futureBusy.clear();
    _futureQueued.clear();
    _futureFetch.clear();
    _cardPrint.clear();
  }
}
