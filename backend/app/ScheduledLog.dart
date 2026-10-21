import 'package:shelf/shelf.dart';
import 'Auth.dart';
import '../tools/Postgres.dart';
import 'DB/t_system_log.dart';
import 'DB/t_system_log_error.dart';
import 'LogDetail.dart';

/// Server timers have no browser session. Use a dedicated system actor.
class ScheduledLog {
  static const userId = -1;

  /// Log attribution only; this header does not grant API permissions.
  static bool isScheduledRequest(Request request) =>
      request.method == 'GET' &&
      request.headers['x-koko-log-source'] == 'scheduler' &&
      !Auth.hasSessionToken(request) &&
      const {
        '/fetchGamesNPB',
        '/fetchGamesMLB',
        '/fetchStatsTeamNPB',
        '/fetchStatsTeamMLB',
        '/fetchStatsPlayerNPB',
        '/fetchStatsPlayerMLB',
      }.contains(request.requestedUri.path);

  static Map<String, dynamic> detail(String action, {Object? error}) => {
        'log_type': LogDetail.serverProcess,
        'user_id': userId,
        'source': 'scheduler',
        'environment': 'server',
        'action': action,
        'function_name': action,
        'status': error == null ? '成功' : '失敗',
        'level': error == null ? 'INFO' : 'ERROR',
      };

  static Future<T> run<T>(String action, Future<T> Function() task) async {
    final started = DateTime.now();
    Object? failure;
    StackTrace? trace;
    try {
      return await task();
    } catch (error, stack) {
      failure = error;
      trace = stack;
      rethrow;
    } finally {
      await record(action,
          error: failure,
          stack: trace,
          durationMs: DateTime.now().difference(started).inMilliseconds);
    }
  }

  static Future<void> record(String action,
      {Object? error, StackTrace? stack, int? durationMs}) async {
    try {
      await Postgres.withConnection((conn) async {
        final logs = buildRecords(action,
            error: error, stack: stack, durationMs: durationMs);
        if (logs.error != null) {
          logs.operation.id_log_error =
              await Postgres.insert(conn, logs.error!);
        }
        await Postgres.insert(conn, logs.operation);
      });
    } catch (error, stack) {
      // Logging failures must not stop the next scheduled run.
      print('定期処理ログ登録失敗: $action: $error\n$stack');
    }
  }

  static ({t_system_log operation, t_system_log_error? error}) buildRecords(
      String action,
      {Object? error,
      StackTrace? stack,
      int? durationMs}) {
    final fields = {...detail(action, error: error), 'duration_ms': durationMs};
    t_system_log_error? errorLog;
    if (error != null) {
      final log = t_system_log_error()
        ..crtby = userId
        ..updby = userId
        ..crtenv = 'server'
        ..updenv = 'server'
        ..crtpgm = LogDetail.clip(action, 30)
        ..updpgm = LogDetail.clip(action, 30)
        ..code_log_system = LogDetail.clip(action, 20)
        ..message_error = LogDetail.clip('$error', 2000)
        ..stacktrace = LogDetail.clip('${stack ?? ''}', 4000)
        ..txt_detail = LogDetail.encode({
          ...fields,
          'log_type': 'エラー',
          'error_type': error.runtimeType.toString(),
          'error_message': '$error',
          'stack_trace': '${stack ?? ''}',
          ...LogDetail.stackFrame('${stack ?? ''}'),
        });
      errorLog = log;
    }
    final log = t_system_log()
      ..crtby = userId
      ..updby = userId
      ..crtenv = 'server'
      ..updenv = 'server'
      ..crtpgm = LogDetail.clip(action, 30)
      ..updpgm = LogDetail.clip(action, 30)
      ..method = 'TIMER'
      ..category = 'scheduler'
      ..code = LogDetail.clip(action, 20)
      ..memo = action
      ..txt_detail = LogDetail.encode(fields);
    return (operation: log, error: errorLog);
  }
}
