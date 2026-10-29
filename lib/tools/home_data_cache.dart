/// Keep public HOME data across tab changes and coalesce simultaneous requests.
class HomeDataCache {
  static final _entries = <String, Future<Map<String, dynamic>>>{};
  static final _values = <String, Map<String,dynamic>>{};
  static final _loadedAt = <String, DateTime>{};
  static void clear() { _entries.clear(); _values.clear(); _loadedAt.clear(); }
  static void _remove(String key) { _entries.remove(key); _values.remove(key); _loadedAt.remove(key); }
  static Map<String,dynamic>? peek(String key, {Duration? maxAge}) {
    if (maxAge != null && _loadedAt[key] != null && DateTime.now().difference(_loadedAt[key]!) >= maxAge) _remove(key);
    return _values[key];
  }
  static Future<Map<String, dynamic>> read(String key,
      Future<Map<String, dynamic>> Function() fetch, {bool refresh = false, Duration? maxAge}) {
    if (refresh) _remove(key);
    peek(key, maxAge: maxAge);
    return _entries.putIfAbsent(key, () {
      if (_entries.length >= 12) _remove(_entries.keys.first);
      late Future<Map<String, dynamic>> pending;
      pending = fetch().then((value) {
        if (identical(_entries[key], pending)) {
          if (value['pending'] == true) {
            _remove(key);
          } else {
            _values[key] = value;
            _loadedAt[key] = DateTime.now();
          }
        }
        return value;
      }, onError: (Object error, StackTrace stack) {
        if (identical(_entries[key], pending)) _remove(key);
        Error.throwWithStackTrace(error, stack);
      });
      return pending;
    });
  }
}
