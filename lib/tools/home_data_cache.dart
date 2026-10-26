/// Keep public HOME data across tab changes and coalesce simultaneous requests.
class HomeDataCache {
  static final _entries = <String, Future<Map<String, dynamic>>>{};
  static void clear() => _entries.clear();
  static Future<Map<String, dynamic>> read(String key,
      Future<Map<String, dynamic>> Function() fetch, {bool refresh = false}) {
    if (refresh) _entries.remove(key);
    return _entries.putIfAbsent(key, () {
      if (_entries.length >= 12) _entries.remove(_entries.keys.first);
      late Future<Map<String, dynamic>> pending;
      pending = fetch().then((value) {
        if (value['pending'] == true && identical(_entries[key], pending)) _entries.remove(key);
        return value;
      }, onError: (Object error, StackTrace stack) {
        if (identical(_entries[key], pending)) _entries.remove(key);
        Error.throwWithStackTrace(error, stack);
      });
      return pending;
    });
  }
}
