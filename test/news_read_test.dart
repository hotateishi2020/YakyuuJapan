import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/news_read.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

void main() {
  test('既読日時より後の追加だけnew。日時のタイムゾーンも比較する', () {
    final read = DateTime.parse('2026-10-27T04:00:00+09:00');
    expect(newsAddedAfter('2026-10-26T19:00:01Z', read), isTrue);
    expect(newsAddedAfter('2026-10-26T19:00:00Z', read), isFalse);
    expect(newsAddedAfter('2026-10-26T18:59:59Z', read), isFalse);
    expect(newsAddedAfter('2026-10-27T04:00:00+09:00', null), isTrue);
    expect(newsAddedAfter(null, read), isFalse);
  });
  test('日時をユーザー保存データに保持し旧boolを使わない', () {
    final user = AuthUser.fromJson({'id': 1, 'date_read_news': '2026-10-26T19:00:00Z', 'flg_read_news': false});
    final restored = AuthUser.fromJson(user.toJson());
    expect(restored.dateReadNews, DateTime.utc(2026,10,26,19));
    expect(user.toJson().containsKey('flg_read_news'), isFalse);
  });
}
