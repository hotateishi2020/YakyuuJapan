import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../app/Auth.dart';

class _UnusedConnection implements Connection {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('未ログインの認証判定で DB にアクセスした');
  }
}

void main() {
  test('トークンがない公開ページでは認証スキーマを読まない', () async {
    final request = Request('GET', Uri.parse('https://example.test/predictions/part'));
    expect(Auth.hasSessionToken(request), isFalse);
    expect(await Auth.userIdOf(_UnusedConnection(), request), isNull);
  });

  test('ヘッダー・クエリ・Cookie の既存の認証方式を維持する', () {
    final uri = Uri.parse('https://example.test/predictions/part');
    expect(Auth.hasSessionToken(Request('GET', uri, headers: {'authorization': 'Bearer test-token'})), isTrue);
    expect(Auth.hasSessionToken(Request('GET', uri.replace(query: 'token=test-token'))), isTrue);
    expect(Auth.hasSessionToken(Request('GET', uri, headers: {'cookie': 'koko_org=npb; koko_auth_token=test-token'})), isTrue);
    expect(Auth.hasSessionToken(Request('GET', uri, headers: {'authorization': 'Bearer ', 'cookie': 'koko_org=npb'})), isFalse);
  });
}
