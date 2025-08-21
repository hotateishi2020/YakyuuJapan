import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:koko/tools/Sql.dart';
import 'package:koko/tools/FetchURL.dart';
import 'package:koko/tools/Postgres.dart';

final app = Router();

void main() async {
  print('index.dart:main');

  // エンドポイント
  app.get('/predictions', (Request request) async {
    final conn = await Postgres.openConnection(); // ✅ 毎回新しい接続

    try {
      print('== 順位予測のデータを取得開始 ==');

      // FetchURL.fetchNPBPlayers(); // NPBの順位を取得してDBに保存
      // FetchURL.fetchNPBStatsDetails(); //NPBの個人成績をDBに保存

      final results = await conn.query(Sql.selectPredictNPBTeams());
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

      final npbStandings = await FetchURL.fetchNPBStandings();

      final statsRows = await conn.query(Sql.selectPredictPlayer());
      final npbPlayerStats = statsRows
          .map((row) => {
                'id_user': row[0],
                'username': row[1],
                'league_name': row[2],
                'title': row[3],
                'player_name': row[4],
                'flg_atari': row[5],
              })
          .toList();

      print(npbPlayerStats);

      final json = {
        'users': users,
        'npbstandings': npbStandings,
        'npbPlayerStats': npbPlayerStats,
      };

      return Response.ok(jsonEncode(json), headers: {
        'Content-Type': 'application/json',
      });
    } catch (e, stacktrace) {
      stderr.writeln('🔥 DB ERROR: $e');
      stderr.writeln('📌 STACKTRACE: $stacktrace');
      return Response.internalServerError(body: 'データベースエラー: $e');
    } finally {
      await conn.close(); // ✅ 接続を必ずクローズ
      print('== 順位予測のデータを取得完了 ==');
    }
  });

  // ミドルウェア + サーバー起動
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(app);

  final server = await io.serve(handler, InternetAddress.anyIPv4, 5050);
  print('✅ Server running on http://${server.address.host}:${server.port}');
}
