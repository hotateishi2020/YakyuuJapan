import 'dart:convert';
// import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'dart:io';

// NeonのPostgreSQL接続情報
final connection = PostgreSQLConnection(
  'ep-wandering-bonus-a7vpjxw5-pooler.ap-southeast-2.aws.neon.tech',  // Neonのホスト
  5432,                  // 標準PostgreSQLポート
  'neondb',  // データベース名
  username: 'neondb_owner',  // ユーザー名
  password: 'npg_fAUXQBOVj19K',  // パスワード
  useSSL: true,
);

final app = Router();

void main() async {
  print('b1');
  await connection.open();  // DB接続
  await connection.query("SET search_path TO public");

  // /users エンドポイントでデータをJSON形式で返す
app.get('/predictions', (Request request) async {
  try {
    print('== START /users ==');
    final users = <Map<String, dynamic>>[];

    var sql = '';
    sql += 'SELECT';
    sql += '    t_predict_team.id AS id_predict, ';
    sql += '    m_user.id AS id_user, ';
    sql += '    m_user.name_last, ';
    sql += '    m_team.name_short, ';
    sql += '    m_team.id_league, ';
    sql += '    int_rank, ';
    sql += '    flg_champion ';
    sql += 'FROM t_predict_team ';
    sql += '    LEFT OUTER JOIN m_user ON m_user.id = t_predict_team.id_user ';
    sql += '    LEFT OUTER JOIN m_team ON m_team.id = t_predict_team.id_team ';
    sql += 'ORDER BY m_user.id, id_league, int_rank ';
    print(sql);

    final results = await connection.query(sql);
    print('== Query success ==');

    for (final row in results) {
      users.add({
        'id_predict': row[0],
        'id_user': row[1],
        'name_user_last': row[2],
        'name_team_short': row[3],
        'id_league': row[4],
        'int_rank': row[5],
        'flg_champion': row[6],
      });
    }

    print('== END /users ==');
    return Response.ok(jsonEncode(users), headers: {
      'Content-Type': 'application/json',
    });

  } catch (e, stacktrace) {
    stderr.writeln('🔥 DB ERROR: $e');
    stderr.writeln('📌 STACKTRACE: $stacktrace');
    return Response.internalServerError(body: 'データベースエラー: $e');
  } finally {
    print('== FINALLY executed ==');
  }
});
  // // サーバー起動
  // final server = await io.serve(app, 'localhost', 8080);
  // print('Server running on http://${server.address.host}:${server.port}');

  // ✅ ここが重要：ルーターをHandlerとして使う
  final handler = Pipeline().addMiddleware(logRequests()).addMiddleware(corsHeaders()).addHandler(app);

  // ✅ handler を serve に渡す
  final server = await io.serve(handler, InternetAddress.anyIPv4, 5050);
  print('Server running on http://${server.address.host}:${server.port}');
}