import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/record_sawamura.dart';

void main() {
  List names(int year, String league, {List categories = const []}) =>
    ((withRecordSawamura([{'year': year, 'league': league, 'categories': categories}])
      .single['categories'] as List).single['players'] as List).map((p) => p['name']).toList();
  test('沢村賞は受賞当時のリーグに表示し同年複数受賞にも対応する', () {
    expect(names(2025, 'パ・リーグ'), ['伊藤大海']);
    expect(names(2025, 'セ・リーグ'), isEmpty);
    expect(names(2023, 'パ・リーグ'), ['山本由伸']);
    expect(names(2003, 'セ・リーグ'), ['井川慶']);
    expect(names(2003, 'パ・リーグ'), ['斉藤和巳']);
    expect(names(1966, 'セ・リーグ'), ['村山実', '堀内恒夫']);
    expect(names(1947, '日本野球連盟'), ['別所昭']);
  });
  test('未発表・該当者なしは空欄としAPIの受賞データを優先する', () {
    for (final year in [2026, 2024, 2019, 2000, 1984, 1980, 1971, 1946]) {
      expect(names(year, 'セ・リーグ'), isEmpty);
      expect(names(year, 'パ・リーグ'), isEmpty);
    }
    expect(names(2025, 'パ・リーグ', categories: [
      {'label': '沢村栄治賞', 'players': [{'name': '公式データ', 'id_player': 123}]}
    ]), ['公式データ']);
    expect(names(2025, 'パ・リーグ', categories: [
      {'label': '沢村賞', 'players': []}
    ]), isEmpty);
  });
}
