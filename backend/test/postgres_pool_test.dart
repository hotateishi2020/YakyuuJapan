import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../tools/Postgres.dart';

void main() {
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
        SocketException('Failed host lookup: db.example'),
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
