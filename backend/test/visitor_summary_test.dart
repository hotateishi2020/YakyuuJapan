import 'dart:convert';
import 'package:test/test.dart';
import '../app/VisitorSummary.dart';

void main() {
  test('管理者除外、ユーザーIDとゲスト環境ごとの期間内重複除外', () {
    final now = DateTime.utc(2026, 10, 23, 12);
    Map<String, dynamic> row(int id, int days, String ip, String ua) => {'crtby': id, 'crtat': now.subtract(Duration(days: days)), 'txt_detail': jsonEncode({'ip_address': ip, 'user_agent': ua})};
    expect(visitorSummary([
      row(1, 0, 'a', 'Chrome'), row(2, 0, 'a', 'Chrome'),
      row(3, 0, 'a', 'Chrome'), row(3, 0, 'b', 'Safari'),
      row(0, 0, 'a', 'Chrome'), row(0, 0, 'a', 'Chrome'),
      row(0, 3, 'a', 'Safari'), row(0, 20, 'b', 'Chrome'),
      row(-1, 0, 'c', 'Chrome'), row(0, 31, 'd', 'Chrome'), row(0, 0, '', ''),
    ], now), {'1': 2, '7': 3, '30': 4});
  });
}
