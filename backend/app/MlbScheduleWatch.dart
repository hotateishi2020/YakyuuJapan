import 'GameScheduleWatch.dart';

/// Compatibility for existing callers; both leagues now use the shared clock.
class MlbScheduleWatch {
  static DateTime nextCheckAt(DateTime now) => GameScheduleWatch.nextCheckAt(now);
  static void start({required void Function() onUpdated}) => GameScheduleWatch.start(onUpdated: onUpdated);
}
