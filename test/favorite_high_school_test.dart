import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/favorite_high_school_board.dart';
import 'package:Yakyuu_Japan/View/other_baseball_board.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/widgets/app_section_tabs.dart';

void main() {
  final tournament = <String, dynamic>{
    'year': 2026,
    'matches': [
      {'home': '佐賀北（佐賀2）', 'away': '大分（大分1）', 'date': '10/27', 'time': '11:30'},
      {'home': '佐賀北（佐賀2）', 'away': '沖縄尚学（沖縄2）', 'date': '10/29', 'time': '11:30'},
    ],
  };
  test('user 1 defaults to Saga Kita and other users do not inherit it', () {
    expect(favoriteSchoolForUser(AuthUser.fromJson({'id': 1})), '佐賀北');
    expect(favoriteSchoolForUser(AuthUser.fromJson({'id': 2})), isEmpty);
    expect(
        favoriteSchoolForUser(
            AuthUser.fromJson({'id': 1, 'favorite_high_school': '佐賀商'})),
        '佐賀商');
    expect(
        AuthUser.fromJson({'id': 2, 'favorite_high_school': '佐賀商'})
            .toJson()['favorite_high_school'],
        '佐賀商');
  });
  test(
      'next fixture belongs to the selected school and is not past or finished',
      () {
    expect(nextSchoolMatch(tournament, '佐賀北', DateTime(2026, 10, 22))?['away'],
        '大分（大分1）');
    expect(nextSchoolMatch(tournament, '佐賀商', DateTime(2026, 10, 22)), isNull);
    expect(nextSchoolMatch(tournament, '佐賀北', DateTime(2026, 11, 2)), isNull);
  });
  test(
      'history merges documented early exits without inferring missing results',
      () {
    final extra = (jsonDecode(
            File('backend/assets/data/high_school_results_supplement.json')
                .readAsStringSync())['results'] as List)
        .cast<Map<String, dynamic>>();
    final records = [
      <String, dynamic>{
        'year': 2007,
        'scope': 'national',
        'region': '全国',
        'season': '夏',
        'places': {
          '1': ['佐賀北']
        }
      },
      <String, dynamic>{
        'year': 2024,
        'scope': 'district',
        'region': '佐賀',
        'season': '春',
        'places': {
          '8': ['佐賀北']
        }
      }
    ];
    final result = schoolResults(records, extra, '佐賀北', 2025);
    expect(result.where((r) => r['year'] == 2007), hasLength(1));
    expect(result.first['result'], '2回戦敗退');
    expect(
        result.where((r) => r['year'] == 2000).single['result'], '初戦敗退（2回戦）');
    expect(result.where((r) => r['year'] == 2024).single['result'], 'ベスト8');
    expect(schoolResults(records, extra, '未収録校', 2026), isEmpty);
  });
  testWidgets(
      'Other uses the shared tab component; favorite school precedes national',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OtherBaseballBoard(
                year: 2026, user: AuthUser.fromJson({'id': 1})))));
    await tester.pump();
    expect(find.byType(ControlledSectionTabs), findsWidgets);
    expect(tester.getCenter(find.text('推し高校').first).dx,
        lessThan(tester.getCenter(find.text('全国大会').first).dx));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    for (var i = 0; i < 20 && find.text('推し高校：佐賀北').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('推し高校：佐賀北'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(390, 700));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow shared tabs switch with a picker', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 230,
                child: DefaultTabController(
                    length: 5,
                    child: ControlledSectionTabs(
                        labels: ['推し高校', '全国大会', 'ブロック大会', '地区大会', '記録']))))));
    expect(find.byType(DropdownButton<int>), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('記録').last);
    await tester.pumpAndSettle();
    final tabs = tester.widget<AppSectionTabs>(find.byType(AppSectionTabs));
    expect(tabs.selectedIndex, 4);
    expect(tester.takeException(), isNull);
  });
}
