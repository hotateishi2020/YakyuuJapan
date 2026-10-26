import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/tools/home_data_cache.dart';
void main() {
  setUp(HomeDataCache.clear);
  test('同時取得と再訪で共有し年度と種類を分離、明示更新のみ再取得する', () async {
    var calls = 0;
    final pending = Completer<Map<String, dynamic>>();
    Future<Map<String, dynamic>> fetch() { calls++; return pending.future; }
    final a = HomeDataCache.read('npb:2026:titles', fetch);
    final b = HomeDataCache.read('npb:2026:titles', fetch);
    expect(calls, 1);
    pending.complete({'titles': [1]});
    expect(await a, await b);
    await HomeDataCache.read('npb:2026:titles', fetch);
    expect(calls, 1);
    await HomeDataCache.read('npb:2025:titles', fetch);
    await HomeDataCache.read('mlb:2026:titles', fetch);
    await HomeDataCache.read('npb:2026:titles', fetch, refresh: true);
    expect(calls, 4);
  });
  test('失敗と集計待ちはキャッシュせず再試行できる', () async {
    await expectLater(HomeDataCache.read('a', () async => throw StateError('offline')), throwsStateError);
    expect(await HomeDataCache.read('a', () async => {'ok': true}), {'ok': true});
    await HomeDataCache.read('b', () async => {'pending': true});
    expect(await HomeDataCache.read('b', () async => {'ok': true}), {'ok': true});
  });
}
