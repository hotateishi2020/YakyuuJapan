import 'package:postgres/postgres.dart';
import 'DBModel.dart';

class Postgres {
  // ✅ 毎回新しい接続を作成する関数
  //利用者側記述：　　await Postgres.openConnection((conn) async {     }); //connectionOpenClose
  static Future openConnection(Future<void> callback(Connection conn)) async {
    final conn = await Connection.open(
      Endpoint(
        // host: 'ep-wandering-bonus-a7vpjxw5-pooler.ap-southeast-2.aws.neon.tech',
        host: 'ep-wandering-bonus-a7vpjxw5.ap-southeast-2.aws.neon.tech',
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

    try {
      await conn.execute('SET search_path TO public');

      await callback(conn);
    } catch (e, st) {
      throw (e, st);
    } finally {
      await conn.close();
    }
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
      throw (e, stacktrace);
    }
  }

  static Future<void> begin(Connection conn) async {
    await conn.execute('BEGIN');
  }

  static Future<void> commit(Connection conn) async {
    await conn.execute('COMMIT');
  }

  static Future<void> rollback(Connection conn) async {
    await conn.execute('ROLLBACK');
  }

  static Future<Result> execute(Connection conn, String sql,
      {Object? data}) async {
    try {
      final result = await conn.execute(sql, parameters: data);
      return result;
    } catch (e, stacktrace) {
      print(
          "🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥");
      print("SQLの実行に失敗しました。失敗したSQL文はこちらです👇");
      print(sql);
      print("失敗したパラメータはこちらです👇");
      print(data);
      print(
          "🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥");
      // rethrow with original stack
      Error.throwWithStackTrace(e, stacktrace);
    }
  }

// トランザクション/既存接続で使うINSERT（安全な名前付きパラメータ）
  static Future<int> insert(Connection conn, DBModel model) async {
    final data = model.toMap();
    data.remove("id"); //insertではidを指定しない（DBの方で自動生成されるため）
    data.remove("crtat");
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

  static Future<List<int>> insertMulti(
      Connection conn, List<DBModel> models) async {
    if (models.isEmpty) return const <int>[];

    // 1) カラム順は最初のモデルから確定（id は自動採番想定なので除外）
    final first = Map.of(models.first.toMap())
      ..remove('id')
      ..remove('crtat');
    final columns = first.keys.toList();
    final columnList = columns.join(', ');

    // 2) パラメータの平坦化と ($1,$2,...) の生成
    final allParams = <Object?>[];
    final valuesClause = StringBuffer();
    var paramIndex = 1;

    for (var i = 0; i < models.length; i++) {
      final m = Map.of(models[i].toMap())..remove('id');

      // 念のためカラムの整合性をチェック（足りない/余分はエラーにする）

      // 既定のカラム順で値を積む
      final rowValues = columns.map((c) => m[c]).toList();
      allParams.addAll(rowValues);

      // ($1,$2,...) のひとかたまりを作る
      final rowPlaceholders = List.generate(
        columns.length,
        (_) => '\$${paramIndex++}',
      ).join(', ');

      if (i > 0) valuesClause.write(', ');
      valuesClause.write('($rowPlaceholders)');
    }

    final sql = '''
    INSERT INTO ${models.first.tableName}
      ($columnList)
    VALUES ${valuesClause.toString()}
    RETURNING id;
  ''';

    final result = await conn.execute(sql, parameters: allParams);

    // RETURNING id の配列を作って返す
    final ids = <int>[];
    for (final row in result) {
      final v = row.first;
      if (v is int) {
        ids.add(v);
      } else if (v is BigInt) {
        ids.add(v.toInt());
      } else if (v is num) {
        ids.add(v.toInt());
      }
    }
    return ids;
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

  static List<Map<String, dynamic>> toJson(Result result) {
    // カラム名を schema から取得
    final columns =
        result.schema?.columns.map((c) => c.columnName).toList() ?? [];

    return result.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < columns.length; i++) {
        var value = row[i];
        if (value is DateTime) {
          value =
              value.toIso8601String(); //DateTimeはそのままjsonデータにはできないので、文字列に変換する。
        }
        map[columns[i].toString()] = value;
      }
      return map;
    }).toList();
  }

  static DBModel? find(List<DBModel> models, String key, dynamic value) {
    for (var model in models) {
      if (model.toMap()[key] == value) {
        return model;
      }
    }
    return null;
  }

  static int findIndex(List<DBModel> models, String key, dynamic value) {
    for (var i = 0; i < models.length; i++) {
      if (models[i].toMap()[key] == value) {
        return i;
      }
    }
    return -1;
  }
}
