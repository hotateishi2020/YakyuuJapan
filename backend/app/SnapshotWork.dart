import 'dart:async';
import 'dart:collection';

/// Large snapshot builders share the web process's memory budget.
/// Skip overlapping ticks; persisted snapshots remain readable throughout.
class SnapshotWork {
  static bool _busy = false;
  static final _waiting = Queue<Completer<void>>();
  static bool tryStart() {
    if (_busy) return false;
    _busy = true;
    return true;
  }
  /// Wait before opening DB connections or loading large inputs. FIFO keeps
  /// game refreshes from starving behind periodically scheduled snapshots.
  /// Call only at the outer boundary of a job, never while holding this lock.
  static Future<T> run<T>(Future<T> Function() task) async {
    if (!tryStart()) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    }
    try {
      return await task();
    } finally {
      finish();
    }
  }

  static void finish() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _busy = false;
    }
  }
}
