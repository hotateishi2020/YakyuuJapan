import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../tools/Postgres.dart';

class _FakeConnection implements Connection {
  bool open = true;
  int pings = 0;
  int closes = 0;
  Object? pingFailure;
  Duration pingDelay = Duration.zero;

  @override
  bool get isOpen => open;

  @override
  Future<void> close({bool force = false}) async {
    closes++;
    open = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #execute) {
      expect(invocation.positionalArguments.first, 'SELECT 1');
      pings++;
      final failure = pingFailure;
      if (failure != null) return Future<Result>.error(failure);
      return Future<Result>.delayed(
        pingDelay,
        () => Result(rows: [], affectedRows: 0, schema: ResultSchema([])),
      );
    }
    throw StateError('Unexpected DB operation: ${invocation.memberName}');
  }
}

void main() {
  tearDown(() async {
    await Postgres.resetPoolForTest();
  });

  test('直近の正常返却後はSELECT 1なしで同じ接続を再利用する', () async {
    var now = DateTime.utc(2026, 10, 13);
    final conn = _FakeConnection();
    var opens = 0;
    await Postgres.resetPoolForTest(
      open: () async {
        opens++;
        return conn;
      },
      clock: () => now,
    );
    final first = await Postgres.acquire();
    await Postgres.release(first);
    now = now.add(const Duration(seconds: 29));
    final second = await Postgres.acquire();
    expect(identical(second, first), isTrue);
    expect(conn.pings, 0);
    expect(opens, 1);
    await Postgres.release(second);
  });

  test('30秒経過した接続だけpingし再返却後はまた省略する', () async {
    var now = DateTime.utc(2026, 10, 13);
    final conn = _FakeConnection();
    await Postgres.resetPoolForTest(open: () async => conn, clock: () => now);
    await Postgres.release(await Postgres.acquire());
    now = now.add(const Duration(seconds: 30));
    final checked = await Postgres.acquire();
    expect(identical(checked, conn), isTrue);
    expect(conn.pings, 1);
    await Postgres.release(checked);
    now = now.add(const Duration(seconds: 10));
    await Postgres.release(await Postgres.acquire());
    expect(conn.pings, 1);
  });

  test('直近の返却でも閉じている接続は再利用しない', () async {
    final closed = _FakeConnection();
    final replacement = _FakeConnection();
    final connections = [closed, replacement];
    await Postgres.resetPoolForTest(open: () async => connections.removeAt(0));
    await Postgres.release(await Postgres.acquire());
    closed.open = false;
    final actual = await Postgres.acquire();
    expect(identical(actual, replacement), isTrue);
    expect(closed.pings, 0);
    expect(closed.closes, 1);
    await Postgres.release(actual);
  });

  test('1秒を超える正常なpingを接続断と誤判定しない', () async {
    var now = DateTime.utc(2026, 10, 13);
    final conn = _FakeConnection()
      ..pingDelay = const Duration(milliseconds: 1100);
    var opens = 0;
    await Postgres.resetPoolForTest(
      open: () async {
        opens++;
        return conn;
      },
      clock: () => now,
    );
    await Postgres.release(await Postgres.acquire());
    now = now.add(const Duration(seconds: 31));
    final actual = await Postgres.acquire();
    expect(identical(actual, conn), isTrue);
    expect(opens, 1);
    expect(conn.closes, 0);
    expect(conn.pings, 1);
    await Postgres.release(actual);
  });

  test('古い接続のpingが失敗したら破棄して新規接続を使う', () async {
    var now = DateTime.utc(2026, 10, 13);
    final broken = _FakeConnection()
      ..pingFailure = const SocketException('Connection reset');
    final replacement = _FakeConnection();
    final connections = [broken, replacement];
    await Postgres.resetPoolForTest(
      open: () async => connections.removeAt(0),
      clock: () => now,
    );
    await Postgres.release(await Postgres.acquire());
    now = now.add(const Duration(seconds: 31));
    final actual = await Postgres.acquire();
    expect(identical(actual, replacement), isTrue);
    expect(broken.pings, 1);
    expect(broken.closes, 1);
    await Postgres.release(actual);
  });

  test('ping省略後の実クエリで接続断が分かっても従来どおり再試行する', () async {
    final broken = _FakeConnection();
    final replacement = _FakeConnection();
    final connections = [broken, replacement];
    await Postgres.resetPoolForTest(open: () async => connections.removeAt(0));
    await Postgres.release(await Postgres.acquire());
    var attempts = 0;
    final value = await Postgres.withConnection((conn) async {
      attempts++;
      if (identical(conn, broken)) {
        throw const SocketException('Connection reset by peer');
      }
      return 'loaded';
    });
    expect(value, 'loaded');
    expect(attempts, 2);
    expect(broken.pings, 0);
    expect(broken.closes, 1);
    expect(replacement.closes, 0);
  });

  test('brokenとして返却された接続を次の取得へ戻さない', () async {
    final broken = _FakeConnection();
    final replacement = _FakeConnection();
    final connections = [broken, replacement];
    await Postgres.resetPoolForTest(open: () async => connections.removeAt(0));
    await Postgres.release(await Postgres.acquire(), broken: true);
    final actual = await Postgres.acquire();
    expect(identical(actual, replacement), isTrue);
    expect(broken.closes, 1);
    await Postgres.release(actual);
  });

  test('dead Neon sockets are classified as broken connections', () {
    expect(
      Postgres.isBrokenConnection(StateError(
          'Attempting to execute query, but connection is not open')),
      isTrue,
    );
    expect(
      Postgres.isBrokenConnection(StateError(
          'Severity.error Socket error: SocketException: Connection reset by peer')),
      isTrue,
    );
    expect(
      Postgres.isBrokenConnection(
        const SocketException('Failed host lookup: db.example'),
      ),
      isTrue,
    );
    expect(
      Postgres.isBrokenConnection(
        TimeoutException('schema ensure', const Duration(seconds: 8)),
      ),
      isFalse,
    );
    expect(Postgres.isBrokenConnection(StateError('duplicate key')), isFalse);
  });
}
