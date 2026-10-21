import 'package:test/test.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import '../app/AdminNews.dart';

class UnusedConnection implements Connection {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unauthenticated request must not touch DB');
}

void main() {
  test('入力の必須・文字数・URL・型を検証する', () {
    expect(
        validateAdminNews({
          'title': '  お知らせ  ',
          'text_main': '本文',
          'url': 'https://example.com'
        })['title'],
        'お知らせ');
    for (final value in [
      null,
      [],
      {'title': ' '},
      {'title': 'a' * 101},
      {'title': 'a', 'text_main': 'a' * 10001},
      {'title': 'a', 'url': 'javascript:alert(1)'},
      {'title': 'a', 'url': 'https://'},
      {'title': 'a', 'url': 'https://user:pass@example.com'},
      {'title': 42}
    ]) {
      expect(() => validateAdminNews(value), throwsFormatException);
    }
  });
  test('未認証の一覧・登録はDBへ触れず403にする', () async {
    final conn = UnusedConnection();
    expect(
        (await AdminNews.read(
                conn, Request('GET', Uri.parse('http://localhost/admin/news'))))
            .statusCode,
        403);
    expect(
        (await AdminNews.create(
                conn,
                Request('POST', Uri.parse('http://localhost/admin/news'),
                    body: '{}')))
            .statusCode,
        403);
  });
}
