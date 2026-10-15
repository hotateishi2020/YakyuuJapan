import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:Yakyuu_Japan/tools/network_error.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

void main() {
  test('ClientExceptionは指定の案内文を返しURLや例外詳細を表示しない', () {
    final error = http.ClientException(
        'Failed to fetch', Uri.parse('http://localhost:8080/private'));
    expect(networkErrorMessage(error, fallback: '通信エラー: $error'),
        'サーバーが起動されていません');
    expect(authNetworkError(error, 'ログイン'), 'サーバーが起動されていません');
  });
  test('ClientException以外の案内は変更しない', () {
    for (final error in [
      const FormatException('invalid JSON'),
      TimeoutException('timeout')
    ]) {
      expect(networkErrorMessage(error, fallback: '元の案内'), '元の案内');
    }
  });
}
