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
  });

  app.get('/fetchPlayerStats', (Request request) async {
    await Postgres.openConnection((conn) async {
      await Postgres.transactionCommit(conn, () async {
        await FetchURL.fetchNPBPlayers(conn);
      });
    });
  });

  app.get('/fetchGames', (Request request) async {
    // 今日の先発情報を更新→取得（必要に応じてコメントアウト可）
    await Postgres.openConnection((conn) async {
      await Postgres.transactionCommit(conn, () async {
        await FetchURL.fetchTodayPitcherNPB(conn);
      }); //DB-Commit
    }); //DB-Close
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
        print(json);
      }); //connectionOpenClose

      return Response.ok(jsonEncode(json),
          headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e, st) {
      print('🔥 /predictions ERROR: $e\n$st');
      stderr.writeln('🔥 /predictions ERROR: $e\n$st');
      return Response.internalServerError(body: 'データベースエラー: $e');
    }
  });

  final serveStatic =
      (Platform.environment['SERVE_STATIC'] ?? 'false') == 'true';
  Handler handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders()) // devでもCORS許可
      .addHandler(app);

  if (serveStatic) {
    // / で Flutter のビルド成果物（backend/public）を返す
    final staticHandler = createStaticHandler(
      'public',
      defaultDocument: 'index.html',
      listDirectories: false,
    );
    handler = Cascade().add(staticHandler).add(handler).handler;
  } else {
    // 開発時は / にアクセスしたら分かりやすいメッセージ
    app.get('/', (_) => Response.ok('Backend API (dev). Try /predictions'));
  }

  final port = int.parse(Platform.environment['PORT'] ?? '8080'); // dev=8080
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('✅ Server running on http://${server.address.host}:${server.port} '
      '(serveStatic=$serveStatic)');
}
