import 'package:test/test.dart';

import '../app/BirthPlaceRegistry.dart';

void main() {
  test('ドミニカはドミニカ共和国に正規化し、旧varchar(5)には入らない', () {
    final parsed = BirthPlaceRegistry.parse('サンペドロ・デ・マコリス, ドミニカ');
    expect(parsed.countryName, 'ドミニカ共和国');
    expect(parsed.countryName!.length, greaterThan(5));
    expect(parsed.placeName, 'サンペドロ・デ・マコリス');
  });

  test('Yahooの都道府県名は日本の出身地になる', () {
    expect(BirthPlaceRegistry.parse('佐賀'), (countryName: '日本', placeName: '佐賀'));
    expect(BirthPlaceRegistry.parse('兵庫'), (countryName: '日本', placeName: '兵庫'));
    expect(BirthPlaceRegistry.parse('佐賀県'), (countryName: '日本', placeName: '佐賀'));
    expect(BirthPlaceRegistry.parse('京都'), (countryName: '日本', placeName: '京都'));
  });

  test('known long country names exceed the old varchar(5) limit', () {
    expect(BirthPlaceRegistry.parse('プエルトリコ').countryName, 'プエルトリコ');
    expect(BirthPlaceRegistry.parse('オーストラリア').countryName, 'オーストラリア');
    expect('プエルトリコ'.length, greaterThan(5));
    expect('オーストラリア'.length, greaterThan(5));
  });
}
