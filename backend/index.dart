import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart'; // ← 重要

import 'tools/AppSql.dart';
import 'tools/FetchURL.dart';
import 'tools/Postgres.dart';
import 'tools/DateTimeTool.dart';
import 'package:intl/intl.dart';

Future<Response> _notFoundFallback(Request req) async {
  // 最後の砦：/public/index.html を返す（SPA 想定）
  final file = File('public/index.html');
  if (await file.exists()) {
    return Response.ok(await file.readAsString(), headers: {
      'content-type': 'text/html; charset=utf-8',
    });
  }
  return Response.notFound('Not Found');
}

void main() async {
  final app = Router();

  // ====== API ======
  app.get('/healthz', (Request _) => Response.ok('ok'));

  app.get('/fetchTeamsNPB', (Request request) async {
    await Postgres.openConnection((conn) async {
      await Postgres.transactionCommit(conn, () async {
        await FetchURL.fetchNPBStandings(conn);
      });
    });
    return Response.ok('ok');
  });

  app.get('/fetchPlayerStats', (Request request) async {
    await Postgres.openConnection((conn) async {
      await Postgres.transactionCommit(conn, () async {
        await FetchURL.fetchNPBStatsDetails(conn);
      });
    });
    return Response.ok('ok');
  });

  app.get('/fetchGames', (Request request) async {
    // 今日の先発情報を更新→取得（必要に応じてコメントアウト可）
    await Postgres.openConnection((conn) async {
      await Postgres.transactionCommit(conn, () async {
        await FetchURL.fetchTodayPitcherNPB(conn);
      }); //DB-Commit
    }); //DB-Close
    return Response.ok('ok');
  });

  //タイトル予想画面の表示
  app.get('/predictions', (Request request) async {
    print('action ' 'predictions' 'を実行しています');
    try {
      Map<String, dynamic> json = {};
      await Postgres.openConnection((conn) async {
        //予想者データをDBから取得
        print('予想者情報を取得しています。');
        final results = await conn.execute(AppSql.selectPredictNPBTeams());
        final users = results
            .map((row) => {
                  'id_predict': row[0],
                  'id_user': row[1],
                  'name_user_last': row[2],
                  'name_team_short': row[3],
                  'id_league': row[4],
                  'int_rank': row[5],
                  'flg_champion': row[6],
                })
            .toList();

        //個人タイトル予想のデータをDBから取得
        print('個人タイトル情報を取得しています。');
        final stats = await conn.execute(AppSql.selectPredictPlayer());
        final npbPlayerStats = stats
            .map((row) => {
                  'id_user': row[0],
                  'username': row[1],
                  'league_name': row[2],
                  'title': row[3],
                  'player_name': row[4],
                  'flg_atari': row[5],
                })
            .toList();

        print('試合情報を取得しています。');
        final formatToday = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final resultGame =
            await conn.execute(AppSql.selectGames(), parameters: [formatToday]);
        final games = resultGame
            .map((row) => {
                  'date_game': row[0],
                  'time_game': row[1],
                  'name_team_home': row[2],
                  'name_team_away': row[3],
                  'name_pitcher_home': row[4],
                  'name_pitcher_away': row[5],
                  'name_pitcher_win': row[6],
                  'name_pitcher_lose': row[7],
                  'name_stadium': row[8],
                  'score_home': row[9],
                  'score_away': row[10],
                  'id_league_home': row[11],
                  'id_league_away': row[12],
                })
            .toList();

        print('チーム順位情報を取得しています。');
        final r_team_stats = await Postgres.select(
            conn, AppSql.selectTeamsWhereName(), DateTimeTool.getThisYear());
        final npbStandings = r_team_stats
            .map((row) => {
                  'year': row[0],
                  'rank': row[1],
                  'id_team': row[2],
                  'name_team': row[3],
                  'id_league': row[4],
                  'name_league': row[5],
                })
            .toList();
        json = {
          'users': users,
          'npbstandings': npbStandings,
          'npbPlayerStats': npbPlayerStats,
          'games': games,
        };
      }); //connectionOpenClose

      return Response.ok(jsonEncode(json),
          headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e, st) {
      print('🔥 /predictions ERROR: $e\n$st');
      stderr.writeln('🔥 /predictions ERROR: $e\n$st');
      return Response.internalServerError(body: 'データベースエラー: $e');
    }
  }); //prediction

  // 2) 静的ディレクトリの検出
  final candidates = [Directory('public'), Directory('backend/public')];
  Directory? publicDir;
  for (final d in candidates) {
    if (await d.exists() && File('${d.path}/index.html').existsSync()) {
      publicDir = d;
      break;
    }
  }

  // 3) ハンドラ作成（API → 静的の順で Cascade）
  Handler handler;
  if (publicDir != null) {
    final staticHandler = createStaticHandler(
      publicDir.path,
      defaultDocument: 'index.html',
    );

    // SPA fallback: 静的で 404 のときだけ index.html を返すラッパー
    Future<Response> staticWithSpa(Request req) async {
      final res = await staticHandler(req);
      if (res.statusCode == 404 && req.method == 'GET') {
        final index = File('${publicDir!.path}/index.html');
        if (await index.exists()) {
          return Response.ok(
            index.openRead(),
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
      }
      return res;
    }

    handler = Cascade()
        .add(app.call) // ← まず API
        .add(staticWithSpa) // ← 次に静的（+ SPA fallback）
        .handler;

    handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(corsHeaders())
        .addHandler(handler);

    stdout.writeln('🗂 Serving static from: ${publicDir.path}');
  } else {
    // 静的なし（dev表示）
    handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(corsHeaders())
        .addHandler((req) {
      if (req.url.path.isEmpty) {
        return Response.ok('Backend API (dev). Try /predictions',
            headers: {'content-type': 'text/plain; charset=utf-8'});
      }
      return app.call(req);
    });
  }

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('✅ Server running on http://${server.address.host}:${server.port}'
      ' (serveStatic=${publicDir != null})');
} // void main
