import 'package:postgres/postgres.dart';
import 'package:koko/DB/DBModel.dart';

class Postgres {

  // ✅ 毎回新しい接続を作成する関数
static Future<PostgreSQLConnection> openConnection() async {
  final conn = PostgreSQLConnection(
    'ep-wandering-bonus-a7vpjxw5-pooler.ap-southeast-2.aws.neon.tech',
    5432,
    'neondb',
    username: 'neondb_owner',
    password: 'npg_fAUXQBOVj19K',
    useSSL: true,
  );
  await conn.open();
  await conn.query('SET search_path TO public');
  return conn;
}

// 手動トランザクション制御
static Future<void> begin(PostgreSQLConnection conn) async {
  await conn.execute('BEGIN');
}

static Future<void> commit(PostgreSQLConnection conn) async {
  await conn.execute('COMMIT');
}

static Future<void> rollback(PostgreSQLConnection conn) async {
  await conn.execute('ROLLBACK');
}

// トランザクション/既存接続で使うINSERT（安全な名前付きパラメータ）
static Future<int> insert(PostgreSQLConnection conn, DBModel model) async {
  final data = model.toMap();
  final columns = data.keys.toList();
  final columnList = columns.join(', ');
  final placeholders = columns.map((c) => '@' + c).join(', ');
  final sql = 'INSERT INTO ' + model.tableName + ' (' + columnList + ') VALUES (' + placeholders + ') RETURNING id;';
  final result = await conn.query(sql, substitutionValues: data);
  if (result.isNotEmpty && result.first.isNotEmpty) {
    final value = result.first.first;
    if (value is int) return value;
  }
  return 0;
}

 
}