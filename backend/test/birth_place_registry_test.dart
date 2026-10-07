import 'package:test/test.dart';

import '../app/BirthPlaceRegistry.dart';

void main() {
  test('ドミニカはドミニカ共和国に正規化し、旧varchar(5)には入らない', () {
    final parsed = BirthPlaceRegistry.parse('サンペドロ・デ・マコリス, ドミニカ');
    expect(parsed.countryName, 'ドミニカ共和国');
    expect(parsed.countryName!.length, greaterThan(5));
    expect(parsed.placeName, 'サンペドロ・デ・マコリス');
  });

  test('known long country names exceed the old varchar(5) limit', () {
    expect(BirthPlaceRegistry.parse('プエルトリコ').countryName, 'プエルトリコ');
    expect(BirthPlaceRegistry.parse('オーストラリア').countryName, 'オーストラリア');
    expect('プエルトリコ'.length, greaterThan(5));
    expect('オーストラリア'.length, greaterThan(5));
  });
}
