import 'dart:async';
import 'FetchMLB.dart';
import 'ScheduledLog.dart';

/// Rechecks today and tomorrow in JST even when nobody has opened a browser.
class MlbScheduleWatch {
  static Timer? _timer;
  static bool _busy = false;

  /// Next 00:00, 06:00, 12:00 or 18:00 JST, expressed in UTC.
  static DateTime nextCheckAt(DateTime now) {
    final japan = now.toUtc().add(const Duration(hours: 9));
    final next = DateTime.utc(japan.year, japan.month, japan.day,
        (japan.hour ~/ 6 + 1) * 6);
    return next.subtract(const Duration(hours: 9));
  }
  static void start({required void Function() onUpdated}) {
    if (_timer != null) return;
    Future<void> run() async {
      if (_busy) return;
      _busy = true;
      try {
        await ScheduledLog.run(
            'mlb_schedule_today_tomorrow', FetchMLB.refreshNearSchedule);
        onUpdated();
      } catch (e) {
        print('MLB当日・翌日日程の再確認失敗（次回再試行）: $e');
      } finally {
        _busy = false;
      }
    }

    void scheduleNext() {
      final now = DateTime.now().toUtc();
      _timer = Timer(nextCheckAt(now).difference(now), () async {
        try {
          await run();
        } finally {
          scheduleNext();
        }
      });
    }
    scheduleNext();
  }
}
