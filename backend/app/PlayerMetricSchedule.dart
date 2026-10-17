import '../tools/Postgres.dart';
import 'MlbSeasonPositions.dart';
import 'dart:async';
import '../tool_refresh_player_metrics.dart' as metrics;
import '../tool_refresh_pinch_metrics.dart' as pinch;
import 'ScheduledLog.dart';

/// No request-time scraping. Refresh official snapshots after startup at six-hour intervals.
class PlayerMetricSchedule {
  static Timer? _timer;
  static bool _busy = false;
  static void start({void Function()? onUpdated}) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 6), (_) async {
      if (_busy) return;
      _busy = true;
      try {
        await ScheduledLog.run('player_extended_metrics', () async {
          final year = '${DateTime.now().year}';
          await metrics.main([year]);
          await pinch.main([year]);
          await Postgres.withConnection(
              (conn) => refreshMlbSeasonPositions(conn, int.parse(year)));
          onUpdated?.call();
          return {'year': year, 'updated': true};
        });
      } catch (e) {
        print('追加個人指標更新: $e');
      } finally {
        _busy = false;
      }
    });
  }
}
