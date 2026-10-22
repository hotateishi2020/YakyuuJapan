import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/other_baseball_board.dart';
import 'package:Yakyuu_Japan/View/high_school_records_board.dart';

void main() {
  final data = jsonDecode(File('backend/assets/data/high_school_records.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final records = (data['tournaments'] as List).cast<Map<String, dynamic>>();
  test('全国・10ブロック・47都道府県を収録し、16強の重複を除く', () {
    expect(data['errors'], isEmpty);
    expect(records.where((r) => r['scope'] == 'national'), hasLength(202));
    expect(
        records
            .where((r) => r['scope'] == 'block')
            .map((r) => r['region'])
            .toSet(),
        containsAll(highSchoolBlocks));
    expect(
        records
            .where((r) => r['scope'] == 'district')
            .map((r) => r['region'])
            .toSet(),
        hasLength(47));
    for (final r in records) {
      final schools = (r['places'] as Map).values.expand((v) => (v as List));
      expect(schools.toSet().length, schools.length,
          reason: '${r['year']} ${r['region']} ${r['season']}');
      expect(schools.length, lessThanOrEqualTo(16));
    }
    final summer = records.firstWhere((r) =>
        r['scope'] == 'national' && r['year'] == 2025 && r['season'] == '夏');
    expect(summer['places']['1'], ['沖縄尚学']);
    expect(summer['places']['16'], hasLength(8));
    final counts = highSchoolChampionshipCounts(
        records.where((r) => r['year'] <= 2025).toList());
    final chukyo = counts.firstWhere((r) => r['school'] == '中京大中京');
    expect(chukyo['total'], 11);
    expect(chukyo['春'], 4);
    expect(chukyo['夏'], 7);
    expect(counts.firstWhere((r) => r['school'] == '東邦')['total'], 5);
    expect(counts.firstWhere((r) => r['school'] == '龍谷大平安')['total'], 4);
    expect(counts.firstWhere((r) => r['school'] == '松山商')['total'], 7);
    expect((data['home_runs'] as List).first['value'], 13);
  });
  testWidgets('九州の組合せを維持し、記録の4タブへ移動できる', (tester) async {
    tester.view.physicalSize = const Size(1100, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: OtherBaseballBoard(year: 2026))));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('ブロック大会').hitTestable().first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AutumnKyushuBracket), findsOneWidget);
    expect(highSchoolBlocks, hasLength(10));
    await tester.tap(find.text('記録').hitTestable());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    for (var attempt = 0;
        attempt < 20 && find.text('通算記録').evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('通算記録'), findsOneWidget);
    expect(find.text('春夏の優勝回数（2026年まで）'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final national = find.text('全国大会').hitTestable().last;
    await tester.tap(national);
    await tester.pumpAndSettle();
    expect(find.text('ベスト16'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
