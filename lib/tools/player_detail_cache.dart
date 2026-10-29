/// Brief, session-scoped reuse of successful player profiles. Pending and
/// failed results never prevent a later attempt from loading complete data.
class PlayerDetailCache {
  static const lifetime = Duration(minutes: 2);
  static final _data = <String, ({DateTime expires, Map<String,dynamic> value})>{};
  static final _pending = <String, Future<Map<String,dynamic>>>{};
  static int _epoch = 0;
  static void clear() { _epoch++; _data.clear(); _pending.clear(); }
  static Future<Map<String,dynamic>> read(String key,
      Future<Map<String,dynamic>> Function() fetch, {bool refresh = false}) async {
    final now = DateTime.now();
    _data.removeWhere((_, entry) => !entry.expires.isAfter(now));
    if (refresh) _data.remove(key);
    final cached = _data[key];
    if (cached != null) return cached.value;
    final existing = _pending[key];
    if (existing != null) return existing;
    final future = fetch();
    final epoch = _epoch;
    _pending[key] = future;
    try {
      final result = await future;
      if (epoch == _epoch && identical(_pending[key], future) && result['found'] == true && result['pending'] != true) {
        if (_data.length >= 24) _data.remove(_data.keys.first);
        _data[key] = (expires: now.add(lifetime), value: result);
      }
      return result;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }
}
