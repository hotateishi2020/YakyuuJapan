import 'dart:async';

import '../tools/Postgres.dart';
import 'AceEvaluator.dart';
import 'FetchMLB.dart';
import 'FetchURL.dart';
import 'OrgLeague.dart';

/// 個人成績ランキングは画面の初期表示では取らない。サーバーが定期的に登録する。
class PlayerStatsSchedule {
  static const firstDelay = Duration(minutes: 5);
  static const interval = Duration(minutes: 30);

  static bool _busy = false;
  static Timer? _timer;
  static Future<void> Function()? _runOverride;

  static bool get isBusy => _busy;

  static void start({required void Function() onUpdated}) {
    _timer?.cancel();
    Future<void>.delayed(firstDelay, () {
      unawaited(tick(onUpdated: onUpdated));
      _timer?.cancel();
      _timer = Timer.periodic(interval, (_) {
        unawaited(tick(onUpdated: onUpdated));
      });
    });
  }

  static Future<void> tick({required void Function() onUpdated}) async {
    if (_busy) {
      print('個人成績定期取得: 前回が残っているのでスキップ');
      return;
    }
    _busy = true;
    var updated = false;
    try {
      final run = _runOverride ?? _runAll;
      await run();
      updated = true;
    } catch (e, st) {
      print('個人成績定期取得失敗: $e\n$st');
    } finally {
      _busy = false;
    }
    if (updated) onUpdated();
  }

  static Future<void> _runAll() async {
    await _runNpb();
    await _runMlb();
  }

  static Future<void> _runNpb() async {
    await Postgres.withConnection((conn) async {
      if (await FetchURL.isOfficialSeasonBreak(conn)) {
        print('シーズンオフのため個人成績の定期取得をスキップ (NPB)');
        return;
      }
      print('個人成績定期取得: NPB');
      await FetchURL.fetchStatsPlayerNPB(conn);
      await AceEvaluator.refresh(conn, OrgKind.npb.leagueIds);
    });
  }

  static Future<void> _runMlb() async {
    await Postgres.withConnection((conn) async {
      print('個人成績定期取得: MLB');
      await FetchMLB.fetchStatsPlayer(conn);
      await AceEvaluator.refresh(conn, OrgKind.mlb.leagueIds);
    });
  }

  static void resetForTest({Future<void> Function()? run}) {
    _timer?.cancel();
    _timer = null;
    _busy = false;
    _runOverride = run;
  }
}
