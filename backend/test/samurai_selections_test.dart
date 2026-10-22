import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../app/SamuraiSelections.dart';

void main() {
  final player = <String, dynamic>{
    'name_full': '山﨑 康晃',
    'date_birth': '1992-10-02'
  };
  final selections = [
    for (final entry in {
      'other': 2014,
      'premier12': 2015,
      'wbc': 2017,
      'olympics': 2021
    }.entries)
      <String, dynamic>{
        'name': '山崎 康晃',
        'birth_date': '1992-10-02',
        'category': entry.key,
        'year': entry.value
      },
  ];
  test('selection color priority and year cutoff', () {
    for (final entry in {
      2013: null,
      2014: 'other',
      2015: 'premier12',
      2017: 'wbc',
      2021: 'wbc'
    }.entries) {
      expect(
          samuraiSelectionDisplay(player, selections,
              year: entry.key)['samurai_category'],
          entry.value);
    }
    expect(
        (samuraiSelectionDisplay(player, selections,
                year: 2021)['samurai_selections'] as List)
            .length,
        4);
  });
  test('Olympics takes priority over Premier12', () {
    expect(
        samuraiSelectionDisplay(
            player, selections.where((s) => s['category'] != 'wbc'),
            year: 2026)['samurai_category'],
        'olympics');
  });
  test('namesakes and absent birthdays cannot match', () {
    for (final birth in ['1993-10-02', '']) {
      expect(
          samuraiSelectionDisplay({...player, 'date_birth': birth}, selections,
              year: 2026)['samurai_category'],
          isNull);
    }
  });
  test(
      'official registry excludes coaches and includes main competition rosters',
      () {
    final data =
        jsonDecode(File('data/samurai_selections.json').readAsStringSync())
            as Map;
    final records = (data['selections'] as List).cast<Map<String, dynamic>>();
    expect(
        records
            .where((r) => r['year'] == 2013 && r['category'] == 'wbc')
            .length,
        28);
    expect(
        records
            .where((r) => r['year'] == 2008 && r['category'] == 'olympics')
            .length,
        24);
    expect(
        records.any((r) =>
            '${r['name']}'.replaceAll(RegExp(r'\s'), '') == '稲葉篤紀' &&
            r['year'] == 2021),
        isFalse);
    expect(
        samuraiSelectionDisplay(
            {'name_full': '坂本勇人', 'date_birth': '1988-12-14'}, records,
            year: 2026)['samurai_category'],
        'wbc');
    expect(
        samuraiSelectionDisplay(
            {'name_full': '栗原陵矢', 'date_birth': '1996-07-04'}, records,
            year: 2021)['samurai_category'],
        'olympics');
  });
}
