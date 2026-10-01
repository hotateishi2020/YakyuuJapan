import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:postgres/postgres.dart';
import 'tools/DateTimeTool.dart';
import 'tools/Postgres.dart';
import 'app/DB/t_system_log.dart';
import 'app/DB/t_system_log_error.dart';
import 'app/DB/m_user.dart';
import 'app/AppSql.dart';
import 'app/Achieve.dart';
import 'app/FetchURL.dart';
import 'app/PlayLabel.dart';
import 'app/Value.dart';

/// /predictions 用の短TTLキャッシュ（同一プロセス内）
String? _predictionsCacheBody;
DateTime? _predictionsCacheAt;
const Duration _predictionsCacheTtl = Duration(seconds: 45);

void _clearPredictionsCache() {
  _predictionsCacheBody = null;
  _predictionsCacheAt = null;
}

String _gameMatchupKey(Map<String, dynamic> game) {
  final id = '${game['id_game'] ?? ''}'.trim();
  if (id.isNotEmpty && id != 'null' && id != '0') return 'id:$id';
  return [
    '${game['date_game'] ?? ''}'.trim(),
    '${game['name_team_home'] ?? ''}'.trim(),
    '${game['name_team_away'] ?? ''}'.trim(),
    '${game['id_team_home'] ?? ''}'.trim(),
    '${game['id_team_away'] ?? ''}'.trim(),
  ].join('|');
}

bool _summaryIsPitcher(dynamic value) {
  if (value is bool) return value;
  final text = '$value'.trim().toLowerCase();
  return text == 'true' || text == 't' || text == '1';
}

int _asInt(dynamic value) => int.tryParse('$value') ?? (value is int ? value : 0);

double _asDouble(dynamic value) => double.tryParse('$value') ?? (value is num ? value.toDouble() : 0);

bool _gameFinished(dynamic state) => '$state'.contains('試合終了');

bool _isStarter(Map<String, dynamic> row) {
  final name = '${row['name_full_summary'] ?? ''}'.trim();
  if (name.isEmpty) return false;
  return name == '${row['name_pitcher_home'] ?? ''}'.trim() || name == '${row['name_pitcher_away'] ?? ''}'.trim();
}

String _summaryAchieve(Map<String, dynamic> row, Map<String, String> cycles, Map<String, int> hits, Map<String, String> plateFeats, Map<int, int> maxInning) {
  final key = playPlayerKey(row['id_game'], row['id_team_summary'], row['name_full_summary']);
  final marks = <String>[];
  final cycle = cycles[key] ?? '';
  if (cycle.isNotEmpty) marks.add(cycle);
  if (!_summaryIsPitcher(row['flg_pitcher'])) {
    final hitCount = (hits[key] ?? 0) > _asInt(row['int_hit_batting']) ? (hits[key] ?? 0) : _asInt(row['int_hit_batting']);
    final multi = multiHitMark(hitCount);
    if (multi.isNotEmpty) marks.add(multi);
  }
  final plateFeat = plateFeats[key] ?? '';
  if (plateFeat.isNotEmpty) marks.add(plateFeat);
  if (_summaryIsPitcher(row['flg_pitcher'])) {
    final gameId = _asInt(row['id_game']);
    final pitching = pitcherMarks(
      finished: _gameFinished(row['state']),
      starter: _isStarter(row),
      innings: _asDouble(row['double_inning_pitch']),
      pitches: _asInt(row['int_pitch']),
      hits: _asInt(row['int_hit_allowed']),
      walks: _asInt(row['int_walk_pitch']),
      hbp: _asInt(row['int_hbp_pitch']),
      runs: _asInt(row['int_runs_pitch']),
      earned: _asInt(row['int_runs_earned']),
      balks: _asInt(row['int_balk']),
      gameInnings: maxInning[gameId] ?? 0,
    );
    if (pitching.isNotEmpty) marks.add(pitching);
  }
  return marks.join(' ');
}

String _summaryPitchTone(Map<String, dynamic> row) {
  if (!_summaryIsPitcher(row['flg_pitcher'])) return '';
  if (_asDouble(row['double_inning_pitch']) <= 0) return '';
  final points = pitcherPoints(
    innings: _asDouble(row['double_inning_pitch']),
    strikeouts: _asInt(row['int_strike_out']),
    runs: _asInt(row['int_runs_pitch']),
    hits: _asInt(row['int_hit_allowed']),
    walks: _asInt(row['int_walk_pitch']),
    hbp: _asInt(row['int_hbp_pitch']),
    starter: _isStarter(row),
  );
  return pitcherTone(points);
}

String _summaryPitchChips(Map<String, dynamic> row) {
  if (!_summaryIsPitcher(row['flg_pitcher'])) return '';
  return pitcherStatChips(
    innings: _asDouble(row['double_inning_pitch']),
    runs: _asInt(row['int_runs_pitch']),
    hits: _asInt(row['int_hit_allowed']),
    walks: _asInt(row['int_walk_pitch']),
    hbp: _asInt(row['int_hbp_pitch']),
    strikeouts: _asInt(row['int_strike_out']),
    pitches: _asInt(row['int_pitch']),
    starter: _isStarter(row),
  );
}

List<Map<String, dynamic>> _collapseGames(
  List<Map<String, dynamic>> rows,
  Map<String, String> plays,
  Map<String, String> cycles,
  Map<String, int> hits,
  Map<String, String> plateFeats,
  Map<int, int> maxInning,
) {
  final order = <String>[];
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final key = _gameMatchupKey(row);
    if (!groups.containsKey(key)) {
      order.add(key);
      groups[key] = [];
    }
    groups[key]!.add(row);
  }
  return [
    for (final key in order)
      {
        ...groups[key]!.first,
        'summaries': _summariesOf(groups[key]!, plays, cycles, hits, plateFeats, maxInning),
      },
  ];
}

List<Map<String, dynamic>> _summariesOf(
  List<Map<String, dynamic>> rows,
  Map<String, String> plays,
  Map<String, String> cycles,
  Map<String, int> hits,
  Map<String, String> plateFeats,
  Map<int, int> maxInning,
) {
  final summaries = <Map<String, dynamic>>[
    for (final row in rows)
      if (row['id_game_summary'] != null || '${row['name_full_summary'] ?? ''}'.trim().isNotEmpty)
        {
          'id_game_summary': row['id_game_summary'],
          'id_team_summary': row['id_team_summary'],
          'name_full_summary': row['name_full_summary'],
          'txt_batting': row['txt_batting'],
          'txt_pitching': row['txt_pitching'],
          'txt_homerun_total': row['txt_homerun_total'],
          'flg_pitcher': row['flg_pitcher'],
          'code_result_pitcher': row['code_result_pitcher'],
          'colors_summary': row['colors_summary'],
          'titles_predict': row['titles_predict'],
          'txt_plays': _summaryIsPitcher(row['flg_pitcher'])
              ? ''
              : playsWithHomerNumbers(
                  plays[playPlayerKey(row['id_game'], row['id_team_summary'], row['name_full_summary'])] ?? '',
                  '${row['txt_homerun_total'] ?? ''}',
                ),
          'txt_achieve': _summaryAchieve(row, cycles, hits, plateFeats, maxInning),
          'txt_pitch_tone': _summaryPitchTone(row),
          'txt_pitch_chips': _summaryPitchChips(row),
        },
  ];
  final gameId = rows.isEmpty ? 0 : _asInt(rows.first['id_game']);
  final seen = <String>{
    for (final row in summaries) playPlayerKey(gameId, row['id_team_summary'], row['name_full_summary']),
  };
  final extra = <String>{
    ...cycles.keys,
    ...plateFeats.keys,
    for (final entry in hits.entries)
      if (entry.value >= 3) entry.key,
  };
  for (final key in extra) {
    if (!key.startsWith('$gameId|') || seen.contains(key)) continue;
    final parts = key.split('|');
    if (parts.length < 3) continue;
    final marks = <String>[];
    final cycle = cycles[key] ?? '';
    if (cycle.isNotEmpty) marks.add(cycle);
    final multi = multiHitMark(hits[key] ?? 0);
    if (multi.isNotEmpty) marks.add(multi);
    final plateFeat = plateFeats[key] ?? '';
    if (plateFeat.isNotEmpty) marks.add(plateFeat);
    if (marks.isEmpty) continue;
    summaries.add({
      'id_team_summary': parts[1],
      'name_full_summary': parts.sublist(2).join('|'),
      'flg_pitcher': false,
      'txt_plays': plays[key] ?? '',
      'txt_achieve': marks.join(' '),
    });
  }
  return summaries;
}

void main() async {
  try {
    final app = Router();
    final log = Value.SystemCode.Log;

    // ====== API ======

    app.get('/healthz', (Request _) => Response.ok('ok'));

    app.get('/fetchStatsTeamNPB', (Request request) async {
      final response = await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.STATS_TEAM, (conn) async {
        if (await FetchURL.isOfficialSeasonBreak(conn)) {
          print('シーズンオフのためチーム成績のスクレイピングを行いません');
          return Response.ok('offseason', headers: {'x-offseason': '1'});
        }
        return await FetchURL.fetchStatsTeamNPB(conn);
      });
      if (response.statusCode == 200 && response.headers['x-offseason'] != '1') _clearPredictionsCache();
      return response;
    });

    app.get('/fetchStatsPlayerNPB', (Request request) async {
      final response = await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.STATS_PLAYER, (conn) async {
        if (await FetchURL.isOfficialSeasonBreak(conn)) {
          print('シーズンオフのため個人成績のスクレイピングを行いません');
          return Response.ok('offseason', headers: {'x-offseason': '1'});
        }
        await FetchURL.fetchStatsPlayerNPB(conn);
        return await FetchURL.fetchStatsPlayerNPB(conn);
      });
      if (response.statusCode == 200 && response.headers['x-offseason'] != '1') _clearPredictionsCache();
      return response;
    });

    app.get('/fetchGamesNPB', (Request request) async {
      print('fetchGamesNPB');
      final response = await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.GAMES, (conn) async {
        if (await FetchURL.isOfficialSeasonBreak(conn)) {
          print('シーズンオフのため試合情報のスクレイピングを行いません');
          return Response.ok('offseason', headers: {'x-offseason': '1'});
        }
        return await FetchURL.fetchGamesNPB(conn);
      });
      if (response.statusCode == 200 && response.headers['x-offseason'] != '1') _clearPredictionsCache();
      return response;
    });

    app.get('/insertNewPlayersNPB', (Request request) async {
      print('insertNewPlayersNPB');
      return await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.GAMES, (conn) async {
        return await FetchURL.fetchNPBPlayers(conn);
      });
    });

    //タイトル予想画面の表示（並列取得・短TTLキャッシュ・読み取り専用で高速化）
    app.get('/predictions', (Request request) async {
      return await tryCatchAPIReadonly(request, log.Prediction.NAME, log.Prediction.Codes.ENTER_NPB, () async {
        final now = DateTime.now();
        if (_predictionsCacheBody != null && _predictionsCacheAt != null && now.difference(_predictionsCacheAt!) < _predictionsCacheTtl) {
          return Response.ok(
            _predictionsCacheBody!,
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'x-cache': 'HIT',
            },
          );
        }

        final current_year = DateTimeTool.getThisYear();
        final results = await Postgres.mapParallel([
          (conn) => Postgres.execute(conn, AppSql.selectPredictNPBTeams(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectPredictPlayer(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectStatsTeam(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectStatsPlayer(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectGames(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectGamePlayRows()),
          (conn) => Postgres.execute(conn, AppSql.selectEventsDetails()),
          (conn) => Postgres.execute(conn, AppSql.selectNotification()),
        ]);
        final playRows = Postgres.toJson(results[5]);
        final games = _collapseGames(
          Postgres.toJson(results[4]),
          playLabelsByPlayer(playRows),
          cycleMarksByPlayer(playRows),
          hitCountsByPlayer(playRows),
          plateFeatMarksByPlayer(playRows),
          maxInningByGame(playRows),
        );
        // print(games);
        final payload = <String, dynamic>{
          'predict_team': Postgres.toJson(results[0]),
          'predict_player': Postgres.toJson(results[1]),
          'stats_team': Postgres.toJson(results[2]),
          'stats_player': Postgres.toJson(results[3]),
          'games': games,
          'events': Postgres.toJson(results[6]),
          'notification': Postgres.toJson(results[7]),
        };
        final body = jsonEncode(payload);
        _predictionsCacheBody = body;
        _predictionsCacheAt = DateTime.now();
        return Response.ok(
          body,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'x-cache': 'MISS',
          },
        );
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

      handler = Pipeline().addMiddleware(logRequests()).addMiddleware(corsHeaders()).addHandler(handler);

      stdout.writeln('🗂 Serving static from: ${publicDir.path}');
    } else {
      // 静的なし（dev表示）
      handler = Pipeline().addMiddleware(logRequests()).addMiddleware(corsHeaders()).addHandler((req) {
        if (req.url.path.isEmpty) {
          return Response.ok('Backend API (dev). Try /predictions', headers: {'content-type': 'text/plain; charset=utf-8'});
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

/// 読み取り専用API: トランザクションなし。ログINSERTのみ別接続で行う。
Future<Response> tryCatchAPIReadonly(
  Request request,
  String category_system,
  String code_system,
  Future<Response> Function() callback,
) async {
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  var id_error = 0;
  final user = m_user();
  var response = Response.ok('ok');
  try {
    print("🌐Routing...【" + request.requestedUri.toString() + "】");
    user.category_system = category_system;
    user.code_system = code_system;
    user.flg_user = false;
    response = await callback();
  } catch (e, st) {
    print("⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️");
    print('🔥 /predictions ERROR: $e\n$st');
    stderr.writeln('🔥 /predictions ERROR: $e\n$st');
    try {
      await Postgres.withConnection((conn) async {
        id_error = await insertLogError(conn, e, st.toString(), user);
      });
      print("エラーログのDBに登録しました。");
    } catch (e2, st2) {
      print("エラーログのDB登録に失敗しました。");
      print('🔥 /predictions ERROR: $e2\n$st2');
    }
    try {
      final username = 'hotateishi2012@yahoo.co.jp';
      final password = '199424';
      sendMail(username, password, 'プログラム上でエラーが発生しました', e.toString());
    } catch (_) {}
    response = Response.internalServerError(body: 'データベースエラー: $e');
  } finally {
    // 操作ログは応答をブロックしない（キャッシュHIT時の体感を特に改善）
    unawaited(() async {
      try {
        await Postgres.withConnection((conn) async {
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
        });
        print("操作ログを登録しました。【${user.code_system}】");
      } catch (e, st) {
        print('操作ログ登録失敗: $e\n$st');
      }
    }());
    print("🌐Responsed Successfully‼️【" + request.requestedUri.toString() + "】");
  }
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  return response;
}

Future<Response> tryCatchAPI(Request request, String category_system, String code_system, Future<Response> callback(Connection conn)) async {
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  var id_error = 0;
  final user = m_user();
  var response = Response.ok('ok');
  await Postgres.openConnection((conn) async {
    await Postgres.transactionCommit(conn, () async {
      try {
        //ログインユーザー情報
        print("🌐Routing...【" + request.requestedUri.toString() + "】");
        print("");

        await user.loadProperty(conn, 0);
        user.category_system = category_system;
        user.code_system = code_system;
        user.flg_user = false;

        response = await callback(conn);
      } catch (e, st) {
        var flg_db_error = false;
        print("⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️");
        print("👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇👇");
        print('🔥 /predictions ERROR: $e\n$st');
        stderr.writeln('🔥 /predictions ERROR: $e\n$st');
        print("👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆👆");
        print("⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️");
        try {
          id_error = await insertLogError(conn, e, st.toString(), user);
          print("エラーログのDBに登録しました。");
        } catch (e, st) {
          //エラーログの登録に失敗
          flg_db_error = true;
          print("エラーログのDB登録に失敗しました。");
          print('🔥 /predictions ERROR: $e\n$st');
          stderr.writeln('🔥 /predictions ERROR: $e\n$st');
        } finally {
          try {
            //callback()内ので発生したエラーをメールで通知
            final username = 'hotateishi2012@yahoo.co.jp';
            final password = '199424';
            sendMail(username, password, 'プログラム上でエラーが発生しました', e.toString());
            print("プログラム上でのエラーを通知するメール送信に成功しました。");

            if (flg_db_error) {
              //エラーログがDBに残せなかったことをメールで通知
              user.category_system = Value.SystemCode.Log.Error.NAME;
              user.code_system = Value.SystemCode.Log.Error.Codes.MAIL;
              sendMail(username, password, 'エラーログの登録に失敗しました。', e.toString());
              print("エラーログの登録に失敗したことを通知するメール送信に成功しました。");
            }
          } catch (e, st) {
            //メール送信失敗
            print('🔥 /predictions ERROR: $e\n$st');
            stderr.writeln('🔥 /predictions ERROR: $e\n$st');
            if (flg_db_error) {
              //メール送信失敗のエラーログを残す
              print("プログラム上でのエラーを通知するメール送信に失敗しました。");
              user.category_system = Value.SystemCode.Log.Error.NAME;
              user.code_system = Value.SystemCode.Log.Error.Codes.MAIL;
              id_error = await insertLogError(conn, e, st.toString(), user);
            } else {
              print("DB接続もメール送信もできない状態です。webサーバーのネットワーク接続に問題がある可能性があります。");
              //webサーバーのローカルディレクトリにエラーログを書き込む。
              final log_error = DateTimeTool.getNow("").toString() + "\n" + e.toString() + "\n" + st.toString() + "\n";
              final file = File('error_log.txt');
              file.writeAsStringSync(log_error);
              print("エラーログをローカルディレクトリに書き込みました。");
            }
          }
        }
        response = Response.internalServerError(body: 'データベースエラー: $e');
      } finally {
        //操作ログを残す
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

        print("操作ログを登録しました。【${user.code_system}】");

        print("");
        print("🌐Responsed Successfully‼️【" + request.requestedUri.toString() + "】");
      }
    }); //transactionCommit
  }); // connectionOpenClose
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  return response;
} //commonTryCatch

void sendMail(String mailaddress, String password, String title, String text) async {
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

Future<int> insertLogError(Connection conn, Object e, String stacktrace, m_user user) async {
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
