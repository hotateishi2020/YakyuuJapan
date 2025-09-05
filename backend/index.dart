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
import 'app/Value.dart';
import 'tools/DateTimeTool.dart';
import 'package:postgres/postgres.dart';
import 'app/DB/t_system_log.dart';
import 'app/DB/t_system_log_error.dart';
import 'app/DB/m_user.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

void main() async {
  try {
    final app = Router();
    final log = Value.SystemCode.Log;

    // ====== API ======

    app.get('/fetchStatsTeamNPB', (Request request) async {
      return await commonAPI(
          request, log.Fetch.NAME, log.Fetch.Codes.STATS_TEAM, (conn) async {
        await FetchURL.fetchStatsTeamNPB(conn);
        return Response.ok('ok');
      });
    });

    app.get('/fetchStatsPlayerNPB', (Request request) async {
      return await commonAPI(
          request, log.Fetch.NAME, log.Fetch.Codes.STATS_PLAYER, (conn) async {
        await FetchURL.fetchStatsPlayerNPB(conn);
        return Response.ok('ok');
      });
    });

    app.get('/fetchGamesNPB', (Request request) async {
      // 今日の先発情報を更新→取得（必要に応じてコメントアウト可）
      return await commonAPI(request, log.Fetch.NAME, log.Fetch.Codes.GAMES,
          (conn) async {
        await FetchURL.fetchGamesNPB(conn, DateTime.now()); //今日の試合

        await FetchURL.fetchGamesNPB(
            conn, DateTime.now().add(const Duration(days: 1))); //明日の試合
        return Response.ok('ok');
      });
    });

    //タイトル予想画面の表示
    app.get('/predictions', (Request request) async {
      return await commonTryCatch(
          request, log.Prediction.NAME, log.Prediction.Codes.ENTER_NPB,
          (conn) async {
        //予想データの取得
        Map<String, dynamic> json = {};
        final current_year = DateTimeTool.getThisYear();

        final predict_team = await Postgres.execute(
            conn, AppSql.selectPredictNPBTeams(),
            data: [current_year]); //予想者データをDBから取得
        final predict_player = await Postgres.execute(
            conn, AppSql.selectPredictPlayer(),
            data: [current_year]); //個人タイトル予想のデータをDBから取得
        final stats_team =
            await Postgres.execute(conn, AppSql.selectStatsTeam());
        final stats_player = await Postgres.execute(
            conn, AppSql.selectStatsPlayer(),
            data: [current_year]);
        final games = await Postgres.execute(conn, AppSql.selectGames(),
            data: [current_year]);
        final events =
            await Postgres.execute(conn, AppSql.selectEventsDetails());
        final notification =
            await Postgres.execute(conn, AppSql.selectNotification());

        json = {
          'predict_team': Postgres.toJson(predict_team),
          'predict_player': Postgres.toJson(predict_player),
          'stats_team': Postgres.toJson(stats_team),
          'stats_player': Postgres.toJson(stats_player),
          'games': Postgres.toJson(games),
          'events': Postgres.toJson(events),
          'notification': Postgres.toJson(notification),
        };
        print(Postgres.toJson(predict_player));
        // print(json);
        return Response.ok(jsonEncode(json),
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
    });

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

Future<Response> commonTryCatch(Request request, String category_system,
    String code_system, Future<Response> callback(Connection conn)) async {
  var id_error = 0;
  final user = m_user();
  var response = Response.ok('ok');
  await Postgres.openConnection((conn) async {
    try {
      //ログインユーザー情報
      print(
          '🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
      print("🌐Routing...【" + request.requestedUri.toString() + "】");
      print("");

      await user.loadProperty(conn, 0);
      user.category_system = category_system;
      user.code_system = code_system;
      user.flg_user = false;

      response = await callback(conn);
    } catch (e, st) {
      var flg_db_error = false;
      print(
          "⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️");
      print(
          "👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇");
      print('🔥 /predictions ERROR: $e\n$st');
      stderr.writeln('🔥 /predictions ERROR: $e\n$st');
      print(
          "👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆");
      print(
          "⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️");
      try {
        id_error = await insertLogError(conn, e, st.toString(), user);
      } catch (e, st) {
        //エラーログの登録に失敗
        flg_db_error = true;
        print('🔥 /predictions ERROR: $e\n$st');
        stderr.writeln('🔥 /predictions ERROR: $e\n$st');
      } finally {
        try {
          //callback()内ので発生したエラーをメールで通知
          final username = 'hotateishi2012@yahoo.co.jp';
          final password = '199424';
          sendMail(username, password, 'プログラム上でエラーが発生しました', e.toString());

          if (flg_db_error) {
            //エラーログがDBに残せなかったことをメールで通知
            user.category_system = Value.SystemCode.Log.Error.NAME;
            user.code_system = Value.SystemCode.Log.Error.Codes.MAIL;
            sendMail(username, password, 'エラーログの登録に失敗しました。', e.toString());
          }
        } catch (e, st) {
          //メール送信失敗
          print('🔥 /predictions ERROR: $e\n$st');
          stderr.writeln('🔥 /predictions ERROR: $e\n$st');
          if (flg_db_error) {
            //メール送信失敗のエラーログを残す
            user.category_system = Value.SystemCode.Log.Error.NAME;
            user.code_system = Value.SystemCode.Log.Error.Codes.MAIL;
            id_error = await insertLogError(conn, e, st.toString(), user);
          }
        }
      }

      response = Response.internalServerError(body: 'データベースエラー: $e');
    } finally {
      //操作ログを残す
      await Postgres.transactionCommit(conn, () async {
        final log = t_system_log();
        log.method = request.method;
        log.category = user.category_system;
        log.code = user.code_system;
        log.memo = '';
        log.flg_user = user.flg_user;
        log.url = request.requestedUri.toString();
        log.url_pre = "";
        log.id_log_error = id_error;
        log.flg_check = false;
        log.crtby = user.id;
        log.crtpgm = user.code_system;
        log.updby = user.id;
        log.updpgm = user.code_system;

        await Postgres.insert(conn, log);

        print("");
        print("🌐Responsed Successfully‼️【" +
            request.requestedUri.toString() +
            "】");
        print(
            '🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
      });
    }
  }); // connectionOpenClose
  return response;
} //commonTryCatch

Future<Response> commonAPI(Request request, String category_system,
    String code_system, Future<Response> callback(Connection conn)) async {
  return await commonTryCatch(request, code_system, category_system,
      (conn) async {
    await Postgres.transactionCommit(conn, () async {
      await callback(conn);
    });
    return Response.ok('ok');
  }); //catch
}

void sendMail(
    String mailaddress, String password, String title, String text) async {
  // Yahoo SMTP
  final smtpServer = SmtpServer(
    'smtp.mail.yahoo.co.jp',
    port: 465,
    ssl: true,
    username: mailaddress,
    password: password,
  );

  final message = Message()
    ..from = Address(mailaddress, 'YakyuuJapan')
    ..recipients.add('hotateishi2018@gmail.com')
    ..subject = title
    ..text = text;

  final sendReport = await send(message, smtpServer);
  print('送信成功: ${sendReport.toString()}');
}

Future<int> insertLogError(
    Connection conn, Object e, String stacktrace, m_user user) async {
  final log_error = t_system_log_error();
  log_error.message_error = e.toString();
  log_error.stacktrace = stacktrace;
  log_error.flg_check = false;
  log_error.code_log_system = user.code_system;
  log_error.crtby = user.id;
  log_error.crtpgm = user.code_system;
  log_error.updby = user.id;
  log_error.updpgm = user.code_system;
  return await Postgres.insert(conn, log_error);
}
