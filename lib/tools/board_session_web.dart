import 'package:web/web.dart';

const boardSessionKey = 'koko_board_session';

String? readBoardSession() {
  try {
    final value = window.sessionStorage.getItem(boardSessionKey);
    if (value == null || value.isEmpty) return null;
    return value;
  } catch (_) {
    return null;
  }
}

void writeBoardSession(String value) {
  try {
    window.sessionStorage.setItem(boardSessionKey, value);
  } catch (_) {}
}
