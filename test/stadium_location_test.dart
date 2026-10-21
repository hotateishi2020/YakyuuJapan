import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/stadium_location.dart';

void main() {
  test('球場所在地を市区町村までに省略する', () {
    const cases = {
      '北海道北広島市Fビレッジ1番地': '北海道北広島市',
      '宮城県仙台市宮城野区宮城野2-11-6': '宮城県仙台市宮城野区',
      '東京都文京区後楽1-3-61': '東京都文京区',
      '千葉県市川市': '千葉県市川市',
      '三重県四日市市霞2丁目': '三重県四日市市',
      '山形県東村山郡中山町長崎': '山形県東村山郡中山町',
      '佐賀県杵島郡大町町': '佐賀県杵島郡大町町',
      '福島県郡山市開成1丁目': '福島県郡山市',
      '1 Blue Jays Way, Suite 3200, Toronto, Ontario, M5V1J1, Canada':
          'Toronto, Ontario, Canada',
      '1500 South Capitol Street, SE, Washington, District of Columbia, 20003-1507, USA':
          'Washington, District of Columbia, USA',
    };
    for (final entry in cases.entries) {
      expect(stadiumLocation(entry.key), entry.value);
    }
    expect(stadiumLocation(null), '未収録');
  });
}
