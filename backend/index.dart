import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart'; // ← 重要
import 'app/AppSql.dart';
import 'app/FetchURL.dart';
import 'tools/Postgres.dart';
import 'tools/DateTimeTool.dart';
import 'package:intl/intl.dart';

void main() async {
  try {
    final app = Router();

    // ====== API ======
    app.get('/healthz', (Request _) => Response.ok('ok'));

    app.get('/fetchTeamsNPB', (Request request) async {
      print('/fetchTeamsNPB');
      return await commonTryCatch(() async {
        await Postgres.openConnection((conn) async {
          await Postgres.transactionCommit(conn, () async {
            await FetchURL.fetchNPBStandings(conn);
          });
        });
        return Response.ok('ok');
      }); //catch
    });

    app.get('/fetchPlayerStats', (Request request) async {
      return await commonTryCatch(() async {
        await Postgres.openConnection((conn) async {
          await Postgres.transactionCommit(conn, () async {
            await FetchURL.fetchNPBStatsDetails(conn);
          }); //commit
        }); //close
        return Response.ok('ok');
      }); //catch
    });

    app.get('/fetchGames', (Request request) async {
      // 今日の先発情報を更新→取得（必要に応じてコメントアウト可）
      print('/fetchGames');
      return await commonTryCatch(() async {
        await Postgres.openConnection((conn) async {
          await Postgres.transactionCommit(conn, () async {
            await FetchURL.fetchGames(conn, DateTime.now()); //今日の試合

            await FetchURL.fetchGames(
                conn, DateTime.now().add(const Duration(days: 1))); //明日の試合
          }); //DB-Commit
        }); //DB-Close
        return Response.ok('ok');
      });
    });

    //タイトル予想画面の表示
    app.get('/predictions', (Request request) async {
      print('/predictions');
      return await commonTryCatch(() async {
        Map<String, dynamic> json = {};
        await Postgres.openConnection((conn) async {
          final predict_team = await conn
              .execute(AppSql.selectPredictNPBTeams()); //予想者データをDBから取得

          final predict_player = await conn
              .execute(AppSql.selectPredictPlayer()); //個人タイトル予想のデータをDBから取得

          final stats_team = await conn.execute(AppSql.selectStatsTeam());

          final stats_player = await conn.execute(AppSql.selectStatsPlayer(),
              parameters: [DateTimeTool.getThisYear()]);

          final games = await conn.execute(AppSql.selectGames());

          final events = await conn.execute(AppSql.selectEventsDetails());

          json = {
            'predict_team': Postgres.toJson(predict_team),
            'predict_player': Postgres.toJson(predict_player),
            'stats_team': Postgres.toJson(stats_team),
            'stats_player': Postgres.toJson(stats_player),
            'games': Postgres.toJson(games),
            'events': Postgres.toJson(events),
          };
          // print(Postgres.toJson(events));
          print(json);
        }); //connectionOpenClose

        return Response.ok(jsonEncode(json),
            headers: {'content-type': 'application/json; charset=utf-8'});
      }); //catch
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
  } catch (e, st) {
    print('🔥 void main ERROR: $e\n$st');
    stderr.writeln('🔥 /void main ERROR: $e\n$st');
  }
} // void main

Future<Response> commonTryCatch(Function() callback) async {
  try {
    return await callback();
  } catch (e, st) {
    print('🔥 /predictions ERROR: $e\n$st');
    stderr.writeln('🔥 /predictions ERROR: $e\n$st');
    return Response.internalServerError(body: 'データベースエラー: $e');
  }
}
