import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'DBModel.dart';

class Postgres {
  // Neon Pooler（接続確立を短縮）。prepared statement 利用のため extended を維持
  static const String _host = 'ep-fragrant-wave-b34kmerl.c-4.ap-southeast-1.aws.neon.tech';
  static const int _port = 5432;
  static const String _database = 'neondb';
  static const String _username = 'neondb_owner';
  static const String _password = 'npg_rID5KHJRZa0E';

  /// 同時に保持する最大アイドル接続数（並列クエリ用に複数確保）
  static const int _maxPoolSize = 8;
  static const Duration _acquireWait = Duration(seconds: 4);
  static const Duration _pingTimeout = Duration(seconds: 1);

  static final Queue<Connection> _idle = Queue<Connection>();
  static int _opened = 0;
  static final List<Completer<Connection>> _waiters = [];
  static final Set<Connection> _overflow = <Connection>{};

  static Endpoint get _endpoint => Endpoint(
        host: _host,
        port: _port,
        database: _database,
        username: _username,
        password: _password,
      );

  static ConnectionSettings get _settings => const ConnectionSettings(
        sslMode: SslMode.require,
        queryMode: QueryMode.extended,
        connectTimeout: Duration(seconds: 8),
      );

  static Future<Connection> _openFresh() async {
    final conn = await Connection.open(_endpoint, settings: _settings);
    await conn.execute('SET search_path TO public');
    await conn.execute("SET TIME ZONE 'Asia/Tokyo'");
    return conn;
  }

  static Future<Connection> _openCounted() async {
    _opened++;
    try {
      return await _openFresh();
    } catch (_) {
      _opened--;
      rethrow;
    }
  }

  static bool isBrokenConnection(Object error) {
    if (error is TimeoutException) return false;
    if (error is SocketException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('connection is not open') ||
        text.contains('connection closed') ||
        text.contains('closed connection') ||
        text.contains('connection reset') ||
        text.contains('connection timed out') ||
        text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('broken pipe') ||
        text.contains("can't assign requested address") ||
        text.contains('cannot assign requested address');
  }

  static Future<bool> _isAlive(Connection conn) async {
    try {
      if (!conn.isOpen) return false;
      await conn.execute('SELECT 1').timeout(_pingTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _closeNow(Connection conn) async {
    final overflow = _overflow.remove(conn);
    if (!overflow) {
      _opened = (_opened - 1).clamp(0, _maxPoolSize);
    }
    try {
      await conn.close().timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

  /// プールから接続を借りる（なければ新規オープン）
  static Future<Connection> acquire({bool urgent = false}) async {
    var discarded = 0;
    while (_idle.isNotEmpty) {
      final conn = _idle.removeLast();
      if (await _isAlive(conn)) return conn;
      await _closeNow(conn);
      discarded++;
      if (urgent || discarded >= 2) break;
    }

    if (_opened < _maxPoolSize) {
      return _openCounted();
    }

    if (urgent) {
      final conn = await _openFresh();
      _overflow.add(conn);
      return conn;
    }

    final waiter = Completer<Connection>();
    _waiters.add(waiter);
    try {
      return await waiter.future.timeout(_acquireWait);
    } on TimeoutException {
      final stillWaiting = _waiters.remove(waiter);
      if (!stillWaiting && waiter.isCompleted) {
        return waiter.future;
      }
      if (_opened < _maxPoolSize) {
        return _openCounted();
      }
      final conn = await _openFresh();
      _overflow.add(conn);
      return conn;
    }
  }

  /// 接続をプールへ返却（壊れていれば破棄）
  static Future<void> release(Connection conn, {bool broken = false}) async {
    if (broken || _overflow.contains(conn) || !conn.isOpen) {
      await _closeNow(conn);
      await _serveWaiter();
      return;
    }

    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(conn);
      return;
    }
    if (_idle.length < _maxPoolSize) {
      _idle.addLast(conn);
      return;
    }
    await _closeNow(conn);
  }

  static Future<void> _serveWaiter() async {
    if (_waiters.isEmpty) return;
    if (_idle.isNotEmpty) {
      _waiters.removeAt(0).complete(_idle.removeLast());
      return;
    }
    if (_opened < _maxPoolSize) {
      final waiter = _waiters.removeAt(0);
      try {
        waiter.complete(await _openCounted());
      } catch (e, st) {
        waiter.completeError(e, st);
      }
    }
  }

  /// 1本の接続で処理し、終了後にプールへ戻す
  static Future<T> withConnection<T>(
    Future<T> Function(Connection conn) callback, {
    bool urgent = false,
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 1; attempt <= 2; attempt++) {
      final conn = await acquire(urgent: urgent);
      var released = false;
      try {
        return await callback(conn);
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        await release(conn, broken: true);
        released = true;
        if (attempt >= 2 || !isBrokenConnection(e)) {
          Error.throwWithStackTrace(e, st);
        }
      } finally {
        if (!released) await release(conn);
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  /// 後方互換: 従来どおり callback に接続を渡す（クローズせずプール返却）
  static Future openConnection(Future<void> Function(Connection conn) callback) async {
    await withConnection((conn) async {
      await callback(conn);
    });
  }

  /// 読み取り専用の複数クエリを並列実行（接続を複数借りる）
  static Future<List<T>> mapParallel<T>(List<Future<T> Function(Connection conn)> jobs) async {
    return Future.wait(jobs.map((job) => withConnection(job)));
  }

  //利用者側記述：　　await Postgres.transactionCommit(conn, () async {     }); //transactionCommit
  static Future<void> transactionCommit(Connection conn, Future<void> Function() callback) async {
    try {
      await Postgres.begin(conn);
      print("✅ トランザクション開始");

      await callback();

      await Postgres.commit(conn);
      print("✅ トランザクション成功 → COMMIT されました");
    } catch (e, stacktrace) {
      try {
        await Postgres.rollback(conn);
      } catch (_) {}
      print("❌ ロールバックされました: $e");
      Error.throwWithStackTrace(e, stacktrace);
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

  static Future<Result> execute(Connection conn, String sql, {Object? data}) async {
    try {
      final result = await conn.execute(sql, parameters: data);
      return result;
    } catch (e, stacktrace) {
      print("🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥");
      print("SQLの実行に失敗しました。失敗したSQL文はこちらです👇");
      print(sql);
      print("失敗したパラメータはこちらです👇");
      print(data);
      print("🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥");
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
    final placeholders = List.generate(columns.length, (i) => '\$${i + 1}').join(', ');

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

  static Future<List<int>> insertMulti(Connection conn, List<DBModel> models) async {
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
    final setClause = List.generate(columns.length, (i) => '${columns[i]} = \$${i + 1}').join(', ');

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

  //取得したデータをMap<String, dynamic>に変換する（カラム名をキーにして値をvalueにする）
  static List<Map<String, dynamic>> toMap(Result result) {
    // カラム名を schema から取得
    final columns = result.schema.columns.map((c) => c.columnName).toList();

    return result.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < columns.length; i++) {
        map[columns[i].toString()] = row[i];
      }
      return map;
    }).toList();
  }

  static List<Map<String, dynamic>> toJson(Result result) {
    // カラム名を schema から取得
    final columns = result.schema.columns.map((c) => c.columnName).toList();

    return result.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < columns.length; i++) {
        var value = row[i];
        if (value is DateTime) {
          value = value.toIso8601String(); //DateTimeはそのままjsonデータにはできないので、文字列に変換する。
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
