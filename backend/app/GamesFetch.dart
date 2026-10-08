import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import '../tools/DateTimeTool.dart';
import 'DisplaySnapshot.dart';
import 'FetchMLB.dart';
import 'FetchURL.dart';
import 'Postseason.dart';

/// `/fetchGamesNPB` と `/fetchGamesMLB`。Render の Cron がこの URL を呼ぶと試合を取得する。
class GamesFetch {
  static Future<Response> npb(Connection conn) async {
    if (await FetchURL.isOfficialSeasonBreak(conn)) {
      if (await Postseason.shouldKeepUpdating(conn)) {
        await Postseason.sync(conn);
        await FetchURL.refreshRecentPostseasonDetails(conn);
        await _snapshot(conn);
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
    return scraped;
  }

  static Future<Response> mlb(Connection conn) async {
    final scraped = await FetchMLB.fetchGames(conn);
    await _snapshot(conn);
    return scraped;
  }

  static Future<void> _snapshot(Connection conn) async {
    await DisplaySnapshot.refreshGames(conn, DateTimeTool.getThisYear());
  }
}
