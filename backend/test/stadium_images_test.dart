import 'dart:convert';
import 'dart:io';
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

    final citizens = StadiumImages.lookup('Citizens Bank Park');
    expect(citizens.inside, contains('mlb-21-citizens.jpg'));
    expect(citizens.outside, contains('mlb-19-citizens.png'));

    final unknown = StadiumImages.lookup('秋田');
    expect(unknown.inside, isEmpty);
    expect(unknown.outside, isEmpty);
  });
  test('farm stadiums have distinct generated inside and outside assets', () {
    final data = jsonDecode(File('data/stadium-catalog.json').readAsStringSync());
    final farms = (data['stadiums'] as List).where((r) => r['stadium_level'] == 'farm');
    expect(farms.length, 12);
    final paths = <String>{};
    for (final row in farms) {
      final images = StadiumImages.lookup(row['name']);
      expect(images.generated, isTrue);
      for (final path in [images.inside, images.outside]) {
        expect(paths.add(path), isTrue);
        expect(File('../$path').existsSync(), isTrue, reason: path);
      }
    }
    expect(StadiumImages.lookup('東京ドーム').generated, isFalse);
  });
  test('regional stadiums have unique generated inside and outside assets', () {
    final data = jsonDecode(File('data/stadium-catalog.json').readAsStringSync());
    final rows = (data['stadiums'] as List).where((r) => r['stadium_level'] == 'regional');
    expect(rows.length, 162);
    final paths = <String>{};
    for (final row in rows) {
      final images = StadiumImages.lookup(row['name']);
      expect(images.generated, isTrue, reason: row['name']);
      for (final path in [images.inside, images.outside]) {
        expect(paths.add(path), isTrue, reason: path);
        expect(File('../$path').existsSync(), isTrue, reason: path);
      }
    }
  });
  test('all catalog stadium images are bundled', () {
    final data = jsonDecode(File('data/stadium-catalog.json').readAsStringSync());
    for (final row in data['stadiums']) {
      final images = StadiumImages.lookup((row['name'] as String).replaceAll('MAZDA', 'マツダ'));
      for (final path in [images.inside, images.outside]) {
        expect(path, isNotEmpty, reason: row['name']);
        expect(File('../$path').existsSync(), isTrue, reason: path);
      }
    }
  });
}
