import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import '../tools/DateTimeTool.dart';
import 'DisplaySnapshot.dart';
import 'FetchMLB.dart';
import 'FetchURL.dart';
import 'OutboundMail.dart';
import 'Postseason.dart';

/// `/fetchGamesNPB` と `/fetchGamesMLB`。Render の Cron がこの URL を呼ぶと試合を取得する。
class GamesFetch {
  static Future<Response> npb(Connection conn) async {
    final watch = Stopwatch()..start();
    if (await FetchURL.isOfficialSeasonBreak(conn)) {
      if (await Postseason.shouldKeepUpdating(conn)) {
        await Postseason.sync(conn);
        await FetchURL.refreshRecentPostseasonDetails(conn);
        await _snapshot(conn);
        watch.stop();
        _mailSuccess('NPB', watch.elapsed, 'postseason');
        return Response.ok('postseason');
      }
      print('シーズンオフのため試合情報のスクレイピングを行いません');
      await _snapshot(conn);
      return Response.ok('offseason', headers: {'x-offseason': '1'});
    }
    final scraped = await FetchURL.fetchGamesNPB(conn);
    if (await Postseason.isRegistrationOpen(conn)) {
      await Postseason.sync(conn);
    }
    await _snapshot(conn);
    watch.stop();
    if (scraped.statusCode == 200) _mailSuccess('NPB', watch.elapsed, 'ok');
    return scraped;
  }

  static Future<Response> mlb(Connection conn) async {
    final watch = Stopwatch()..start();
    final scraped = await FetchMLB.fetchGames(conn);
    await _snapshot(conn);
    watch.stop();
    if (scraped.statusCode == 200 && scraped.headers['x-offseason'] != '1') {
      _mailSuccess('MLB', watch.elapsed, 'ok');
    }
    return scraped;
  }

  static void _mailSuccess(String label, Duration elapsed, String result) {
    unawaited(() async {
      try {
        await sendFetchDurationMail(label: label, elapsed: elapsed, result: result);
      } catch (e) {
        print('試合読み込みの所要時間メールを送れませんでした: $e');
      }
    }());
  }

  static Future<void> _snapshot(Connection conn) async {
    await DisplaySnapshot.refreshGames(conn, DateTimeTool.getThisYear());
  }
}
