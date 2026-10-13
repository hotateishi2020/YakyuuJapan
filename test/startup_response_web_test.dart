@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/tools/startup_response_web.dart';

void main() {
  final uri = Uri.parse('/predictions/part?org=npb&part=standings&year=2026');

  void preload(Object? result) {
    final requests = JSObject();
    requests.setProperty(uri.toString().toJS, Future<JSAny?>.value(result.jsify()).toJS);
    globalContext.setProperty('kokoStartupRequests'.toJS, requests);
  }

  tearDown(() => globalContext.delete('kokoStartupRequests'.toJS));

  test('先行取得した日本語データを一度だけ受け取る', () async {
    preload({'status': 200, 'body': '{"team":"阪神"}'});
    final response = await takeStartupResponse(uri);
    expect(response?.statusCode, 200);
    expect(response?.body, '{"team":"阪神"}');
    expect(await takeStartupResponse(uri), isNull);
  });

  test('先行取得の失敗・未実行時は通常のHTTP取得に戻せる', () async {
    expect(await takeStartupResponse(uri), isNull);
    preload(null);
    expect(await takeStartupResponse(uri), isNull);
    preload({'status': 503, 'body': '{}'});
    expect(await takeStartupResponse(uri), isNull);
  });

  test('別の団体や年度には先行取得した結果を使わない', () async {
    preload({'status': 200, 'body': '{}'});
    expect(await takeStartupResponse(Uri.parse('/predictions/part?org=mlb&part=standings&year=2026')), isNull);
    expect(await takeStartupResponse(uri), isNotNull);
  });

  test('セッションキャッシュがある場合も先行取得を再利用する', () async {
    preload({'status': 200, 'body': '{}'});
    expect(await takeStartupResponse(Uri.parse('$uri&have=1')), isNotNull);
    expect(await takeStartupResponse(uri), isNull);
  });
}
