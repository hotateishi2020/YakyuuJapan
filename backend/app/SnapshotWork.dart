/// Large snapshot builders share the web process's memory budget.
/// Skip overlapping ticks; persisted snapshots remain readable throughout.
class SnapshotWork {
  static bool _busy = false;
  static bool tryStart() {
    if (_busy) return false;
    _busy = true;
    return true;
  }
  static void finish() => _busy = false;
}
