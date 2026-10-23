import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';

/// 本文の実バイト数をストリームのまま計測する。ヘッダー/TLS/外部API通信は含まない。
/// RSS はサーバープロセス全体で、同時リクエストや GC の影響も含む。
class RequestMetrics {
  static const contextKey = 'koko.requestMetrics';
  final Stopwatch _watch = Stopwatch()..start();
  final int _rssStart = ProcessInfo.currentRss;
  int requestBytes = 0;
  int responseBytes = 0;
  Map<String, Object>? _result;
  final List<Future<void> Function(Map<String, Object>)> _listeners = [];

  static RequestMetrics? of(Request request) => request.context[contextKey] as RequestMetrics?;

  void onComplete(Future<void> Function(Map<String, Object>) listener) {
    final result = _result;
    if (result == null) {
      _listeners.add(listener);
    } else {
      unawaited(_notify(listener, result));
    }
  }

  Future<void> _notify(Future<void> Function(Map<String, Object>) listener, Map<String, Object> result) async {
    try {
      await listener(result);
    } catch (e) {
      stderr.writeln('処理メトリクスのログ保存に失敗: $e');
    }
  }

  void _finish() {
    if (_result != null) return;
    _watch.stop();
    final rss = ProcessInfo.currentRss;
    final result = _result = Map<String, Object>.unmodifiable({
      'duration_ms': _watch.elapsedMilliseconds,
      'request_bytes': requestBytes,
      'response_bytes': responseBytes,
      'transfer_bytes': requestBytes + responseBytes,
      'memory_rss_bytes': rss,
      'memory_delta_bytes': rss - _rssStart,
      'metrics_scope': 'server_process_rss_http_body',
    });
    for (final listener in _listeners) {
      unawaited(_notify(listener, result));
    }
    _listeners.clear();
  }

  static Middleware middleware() => (Handler inner) => (Request request) async {
    final metrics = RequestMetrics();
    final measured = request.change(
      body: request.read().map((chunk) {
        metrics.requestBytes += chunk.length;
        return chunk;
      }),
      context: {contextKey: metrics},
    );
    try {
      final response = await inner(measured);
      Stream<List<int>> body() async* {
        try {
          await for (final chunk in response.read()) {
            metrics.responseBytes += chunk.length;
            yield chunk;
          }
        } finally {
          metrics._finish();
        }
      }
      return response.change(body: body());
    } catch (_) {
      metrics._finish();
      rethrow;
    }
  };
}
