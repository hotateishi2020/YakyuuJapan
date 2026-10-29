import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/tools/player_detail_cache.dart';

void main() {
  setUp(PlayerDetailCache.clear);
  test('同時取得を共有し、正常なプロフィールだけを再利用する', () async {
    var calls = 0;
    final result = Completer<Map<String,dynamic>>();
    Future<Map<String,dynamic>> fetch() { calls++; return result.future; }
    final a = PlayerDetailCache.read('session:player', fetch);
    final b = PlayerDetailCache.read('session:player', fetch);
    result.complete({'found': true});
    await a; await b;
    await PlayerDetailCache.read('session:player', fetch);
    expect(calls, 1);
    await PlayerDetailCache.read('another-session:player', fetch);
    expect(calls, 2);
  });
  test('準備中と失敗を固定せず、次回取得と明示更新ができる', () async {
    await PlayerDetailCache.read('p', () async => {'found': true,'pending': true});
    expect((await PlayerDetailCache.read('p', () async => {'found': true,'name': 'complete'}))['name'], 'complete');
    expect((await PlayerDetailCache.read('p', () async => {'found': true,'name': 'fresh'}, refresh: true))['name'], 'fresh');
    await expectLater(PlayerDetailCache.read('error', () async => throw StateError('network')), throwsStateError);
    expect(await PlayerDetailCache.read('error', () async => {'found': true}), {'found': true});
  });
  test('クリア前に始まった取得で新しいキャッシュを上書きしない', () async {
    final old = Completer<Map<String,dynamic>>();
    final pending = PlayerDetailCache.read('player', () => old.future);
    PlayerDetailCache.clear();
    await PlayerDetailCache.read('player', () async => {'found': true,'name': 'new'});
    old.complete({'found': true,'name': 'old'});
    await pending;
    final result = await PlayerDetailCache.read('player', () async => throw StateError('cached'));
    expect(result['name'], 'new');
  });
}
