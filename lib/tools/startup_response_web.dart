import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:http/http.dart' as http;

@JS('kokoStartupRequests')
external JSObject? get _startupRequests;

Future<http.Response?> takeStartupResponse(Uri uri) async {
  try {
    final requests = _startupRequests;
    if (requests == null) return null;
    // セッションキャッシュがあっても、先行取得済みの完全な本文を利用する。
    final query = {...uri.queryParameters}..remove('have');
    final key = uri.replace(queryParameters: query).toString().toJS;
    final pending = requests.getProperty<JSPromise<JSAny?>?>(key);
    if (pending == null) return null;
    requests.delete(key);
    final result = (await pending.toDart)?.dartify();
    if (result is! Map || result['status'] != 200 || result['body'] is! String) return null;
    return http.Response(result['body'] as String, 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  } catch (_) {
    // プリロードの失敗時・非Web環境では、通常の取得に戻す。
    return null;
  }
}
