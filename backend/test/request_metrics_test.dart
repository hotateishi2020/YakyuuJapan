import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import '../app/RequestMetrics.dart';

void main() {
  test('UTF-8と分割送受信の実バイト数を測り、本文を変更しない', () async {
    final saved = Completer<Map<String, Object>>();
    final input = utf8.encode('操作');
    final output = utf8.encode('完了');
    final handler = RequestMetrics.middleware()((request) async {
      RequestMetrics.of(request)!.onComplete((values) async => saved.complete(values));
      expect(await request.readAsString(), '操作');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return Response.ok(Stream.fromIterable([output.sublist(0, 2), output.sublist(2)]));
    });
    final response = await handler(Request('POST', Uri.parse('http://localhost/client/action'), body: Stream.fromIterable([input.sublist(0, 1), input.sublist(1)])));
    expect(saved.isCompleted, isFalse);
    expect(await response.readAsString(), '完了');
    final metrics = await saved.future;
    expect(metrics['request_bytes'], input.length);
    expect(metrics['response_bytes'], output.length);
    expect(metrics['transfer_bytes'], input.length + output.length);
    expect(metrics['duration_ms'], greaterThanOrEqualTo(10));
    expect(metrics['memory_rss_bytes'], greaterThan(0));
    expect(metrics['memory_delta_bytes'], isA<int>());
  });

  test('並列リクエストの通信量を混ぜない', () async {
    final saved = <String, Map<String, Object>>{};
    final handler = RequestMetrics.middleware()((request) async {
      RequestMetrics.of(request)!.onComplete((values) async { saved[request.url.path] = values; });
      return Response.ok(await request.readAsString());
    });
    await Future.wait([for (final text in ['a', 'long-body']) () async {
      final response = await handler(Request('POST', Uri.parse('http://localhost/$text'), body: text));
      await response.readAsString();
    }()]);
    expect(saved['a']!['transfer_bytes'], 2);
    expect(saved['long-body']!['transfer_bytes'], 18);
  });

  test('失敗レスポンスと空本文も記録する', () async {
    final saved = Completer<Map<String, Object>>();
    final handler = RequestMetrics.middleware()((request) async {
      RequestMetrics.of(request)!.onComplete((values) async => saved.complete(values));
      return Response(500);
    });
    final response = await handler(Request('GET', Uri.parse('http://localhost/fail')));
    expect(response.statusCode, 500);
    expect(await response.readAsString(), '');
    expect((await saved.future)['transfer_bytes'], 0);
  });

  test('レスポンスの途中エラーでも一度だけ記録し、エラーを伝える', () async {
    var calls = 0;
    final saved = Completer<Map<String, Object>>();
    final handler = RequestMetrics.middleware()((request) async {
      RequestMetrics.of(request)!.onComplete((values) async { calls++; saved.complete(values); });
      Stream<List<int>> body() async* { yield [1, 2]; throw StateError('stream failed'); }
      return Response.ok(body());
    });
    final response = await handler(Request('GET', Uri.parse('http://localhost/fail')));
    await expectLater(response.read().drain<void>(), throwsStateError);
    expect((await saved.future)['response_bytes'], 2);
    expect(calls, 1);
  });
}
