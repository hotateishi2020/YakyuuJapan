import 'package:postgres/postgres.dart';
import 'package:koko/DB/DBModel.dart';

class Postgres {
  // ✅ 毎回新しい接続を作成する関数
  static Future<Connection> openConnection() async {
    final conn = await Connection.open(
      Endpoint(
        host: 'ep-wandering-bonus-a7vpjxw5-pooler.ap-southeast-2.aws.neon.tech',
        port: 5432,
        database: 'neondb',
        username: 'neondb_owner',
        password: 'npg_fAUXQBOVj19K',
      ),
      settings: const ConnectionSettings(
        sslMode: SslMode.require,
        queryMode: QueryMode.extended,
      ),
    );
    await conn.execute('SET search_path TO public');
    return conn;
  }

// 手動トランザクション制御
  static Future<void> begin(Connection conn) async {
    await conn.execute('BEGIN');
  }

  static Future<void> commit(Connection conn) async {
    await conn.execute('COMMIT');
  }

  static Future<void> rollback(Connection conn) async {
    await conn.execute('ROLLBACK');
  }

  static Future<Result> select(
      Connection conn, String sql, dynamic value) async {
    final results = await conn.execute(sql, parameters: [value]);
    return results;
  }

  //利用者側記述：　　await Postgres.transactionCommit(conn, () async {     }); //transactionCommit
  static Future<void> transactionCommit(
      Connection conn, Future<void> Function() callback) async {
    try {
      await Postgres.begin(conn);
      print("✅ トランザクション開始");

      await callback();

      await Postgres.commit(conn);
      print("✅ トランザクション成功 → COMMIT されました");
    } catch (e, stacktrace) {
      await Postgres.rollback(conn);
      print("❌ ロールバックされました: $e, $stacktrace");
    } finally {}
  }

  static Future<int> execute(Connection conn, String sql,
      {Map<String, dynamic>? data}) async {
    final result = await conn.execute(sql, parameters: data);
    if (result.isNotEmpty && result.first.isNotEmpty) {
      final value = result.first.first;
      if (value is int) return value;
    }
    return 0;
  }

// トランザクション/既存接続で使うINSERT（安全な名前付きパラメータ）
  static Future<int> insert(Connection conn, DBModel model) async {
    final data = model.toMap();
    data.remove("id"); //insertではidを指定しない（DBの方で自動生成されるため）
    final columns = data.keys.toList();
    final values = data.values.toList();

    final columnList = columns.join(', ');
    // $1, $2, $3 ... の形に変換
    final placeholders =
        List.generate(columns.length, (i) => '\$${i + 1}').join(', ');

    final sql = '''
    INSERT INTO ${model.tableName}
      ($columnList)
    VALUES ($placeholders)
    RETURNING id;
  ''';

    final result = await conn.execute(sql, parameters: values);

    if (result.isNotEmpty && result.first.isNotEmpty) {
      final value = result.first.first;
      if (value is int) return value;
    }
    return 0;
  }

  static Future<int> update(Connection conn, DBModel model) async {
    // 1) データを取り出し、id を WHERE 用に確保
    final data = Map<String, dynamic>.from(model.toMap());
    if (!data.containsKey('id')) {
      throw ArgumentError('update には id が必須です');
    }

    // 更新対象のカラム名・値
    final columns = data.keys.toList(); // 挿入順 (LinkedHashMap) を保持
    final values = data.values.toList();

    if (columns.isEmpty) {
      // 変更対象が無い場合は 0 行更新扱い
      return 0;
    }

    // 2) SET 句: col1=$1, col2=$2, ...
    final setClause =
        List.generate(columns.length, (i) => '${columns[i]} = \$${i + 1}')
            .join(', ');

    // 3) パラメータ配列（最後に id を足して WHERE で使う）
    final params = [...values, model.id];

    // 4) SQL（raw 文字列で $ をエスケープ不要に）
    final sql = r'''
    UPDATE %TABLE%
    SET %SET%
    WHERE id = $%N%
    RETURNING id;
  '''
        // 置換（安全のためテーブル名・識別子はアプリ管理のものを想定）
        .replaceFirst('%TABLE%', model.tableName)
        .replaceFirst('%SET%', setClause)
        .replaceFirst('%N%', (columns.length + 1).toString());

    final res = await conn.execute(sql, parameters: params);

    // 更新できたら RETURNING id が返る
    if (res.isNotEmpty && res.first.isNotEmpty && res.first.first is int) {
      return res.first.first as int;
    }
    return 0; // 該当なし
  }
}
