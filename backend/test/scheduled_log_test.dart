import 'dart:convert';
import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import '../app/ScheduledLog.dart';

void main() {
  test('外部定期実行の全6APIをシステムとして識別する', () {
    for (final org in ['NPB', 'MLB']) {
      for (final kind in ['Games', 'StatsTeam', 'StatsPlayer']) {
        final uri = Uri.parse('https://example.test/fetch$kind$org');
        expect(
            ScheduledLog.isScheduledRequest(Request('GET', uri,
                headers: {'x-koko-log-source': 'scheduler'})),
            isTrue);
        expect(ScheduledLog.isScheduledRequest(Request('GET', uri)), isFalse);
      }
    }
  });

  test('ユーザーのセッションと通常APIは定期実行として扱わない', () {
    final uri = Uri.parse('https://example.test/fetchGamesNPB');
    for (final headers in [
      {'authorization': 'Bearer user-token'},
      {'cookie': 'koko_auth_token=user-token'},
    ]) {
      expect(
          ScheduledLog.isScheduledRequest(Request('GET', uri, headers: {
            'x-koko-log-source': 'scheduler',
            ...headers,
          })),
          isFalse);
    }
    expect(
        ScheduledLog.isScheduledRequest(Request(
            'GET', uri.replace(queryParameters: {'token': 'user-token'}),
            headers: {'x-koko-log-source': 'scheduler'})),
        isFalse);
    expect(
        ScheduledLog.isScheduledRequest(Request(
            'GET', Uri.parse('https://example.test/predictions/part'),
            headers: {'x-koko-log-source': 'scheduler'})),
        isFalse);
    expect(
        ScheduledLog.isScheduledRequest(
            Request('POST', uri, headers: {'x-koko-log-source': 'scheduler'})),
        isFalse);
  });

  test('定期処理の成功ログはシステムのIDを登録する', () {
    final logs = ScheduledLog.buildRecords('games_today_npb', durationMs: 120);
    expect(logs.error, isNull);
    expect(logs.operation.crtby, -1);
    expect(logs.operation.updby, -1);
    expect(logs.operation.flg_user, isFalse);
    final detail = jsonDecode(logs.operation.txt_detail);
    expect(detail['user_id'], -1);
    expect(detail['status'], '成功');
    expect(detail['duration_ms'], 120);
  });

  test('定期処理の失敗は操作・エラー両方にシステムIDと失敗内容を残す', () {
    final logs = ScheduledLog.buildRecords('player_stats',
        error: StateError('取得失敗'), stack: StackTrace.current);
    expect(logs.operation.crtby, -1);
    expect(logs.error!.crtby, -1);
    expect(logs.error!.updby, -1);
    expect(jsonDecode(logs.operation.txt_detail)['status'], '失敗');
    expect(jsonDecode(logs.error!.txt_detail)['user_id'], -1);
    expect(logs.error!.message_error, contains('取得失敗'));
    expect(logs.error!.stacktrace, isNotEmpty);
  });
}
