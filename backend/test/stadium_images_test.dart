import 'package:test/test.dart';

import '../app/StadiumImages.dart';

void main() {
  test('NPBとMLBの球場名から内外の画像パスが引ける', () {
    final tokyo = StadiumImages.lookup('東京ドーム');
    expect(tokyo.inside, contains('npb-04-tokyo.jpg'));
    expect(tokyo.outside, contains('npb-06-tokyo.png'));

    final paypay = StadiumImages.lookup('みずほPayPay');
    expect(paypay.inside, contains('npb-12-fukuoka.jpg'));
    expect(paypay.outside, contains('npb-12-fukuoka.png'));

    final dodger = StadiumImages.lookup('ドジャー・スタジアム');
    expect(dodger.inside, contains('mlb-03-dodger.jpg'));
    expect(dodger.outside, contains('mlb-26-dodger.png'));

    final citi = StadiumImages.lookup('Citi Field');
    expect(citi.inside, contains('mlb-24-citi.jpg'));
    expect(citi.outside, contains('mlb-18-citi.png'));

    final unknown = StadiumImages.lookup('秋田');
    expect(unknown.inside, isEmpty);
    expect(unknown.outside, isEmpty);
  });
}
