import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

void main() {
  test('login timeout is reported in Japanese instead of raw TimeoutException', () {
    expect(
      authNetworkError(
        TimeoutException('Future not completed', const Duration(seconds: 20)),
        'ログイン',
      ),
      'ログインがタイムアウトしました。少し待って再度お試しください',
    );
    expect(
      authNetworkError(StateError('socket hang'), 'ログイン'),
      contains('通信エラー:'),
    );
  });
}
