import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/player_detail_dialog.dart';
import 'package:Yakyuu_Japan/View/season_titles_table.dart';
import 'package:Yakyuu_Japan/View/allstar_history_board.dart';
import 'package:Yakyuu_Japan/View/additional_records_board.dart';
import 'package:Yakyuu_Japan/View/strength_careers.dart';
import 'package:Yakyuu_Japan/View/strength_transfers.dart';

void main() {
  const person = <String, dynamic>{'name': '対象選手', 'player_url': 'https://npb.jp/bis/players/12345678.html'};
  final cases = <String, (Widget, String)>{
    'タイトル': (
      const SeasonTitlesTable(year: 2026, groups: {
        'series_mvp': [person]
      }),
      '対象選手'
    ),
    'オールスター': (
      const AllStarHistoryGrid(throughYear: 2026, data: {
        'players': const [
          {...person, 'year': 2026, 'league': 'セ・リーグ', 'position': '先発投手'}
        ]
      }),
      '対象選手'
    ),
    '年齢記録の同率選手': (
      const AgeRecordsBoard(rows: [
        {'label': '100本塁打', 'name': '別選手', 'youngest': 1},
        {...person, 'label': '100本塁打', 'youngest': 1},
      ]),
      '対象選手'
    ),
    '回数記録': (
      const CountRecordsBoard(records: [
        {
          'label': '首位打者',
          'leaders': [
            {...person, 'rank': 1, 'value': 3}
          ]
        }
      ]),
      '対象選手　3回'
    ),
    '経歴': (
      const StrengthCareers(teams: [
        {
          'id_team': 1,
          'name_team': '球団',
          'roster': const [
            {
              ...person,
              'career_history': const [
                {'category': '高校', 'team': '出身高校'}
              ]
            }
          ]
        }
      ]),
      '対象選手'
    ),
    '移籍': (
      const StrengthTransfers(year: 2026, teams: [
        {
          'id_team': 1,
          'name_team': '球団',
          'roster': const [
            {...person, 'fa_rights_type': 'domestic', 'fa_rights_year': 2026, 'contract_end_year': 2026}
          ]
        }
      ]),
      '対象選手'
    ),
  };
  for (final entry in cases.entries) {
    testWidgets('${entry.key}の選手名から共通詳細を開きIDと年度を引き継ぐ', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Uri? requested;
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: PlayerDetailScope(org: 'npb', year: 2025, child: Scaffold(body: entry.value.$1))));
        await tester.pumpAndSettle();
        final target = find.text(entry.value.$2);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.byType(PlayerDetailDialog), findsOneWidget);
        expect(requested?.queryParameters['source_player_id'], '12345678');
        expect(requested?.queryParameters['name'], '対象選手');
        expect(requested?.queryParameters['year'], '2025');
        expect(requested?.queryParameters['org'], 'npb');
        expect(find.text('ポップアップ取得成功'), findsOneWidget);
        await tester.tap(find.byTooltip('閉じる'));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerDetailDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
          () => MockClient((request) async {
                requested = request.url;
                return http.Response(jsonEncode({'found': false, 'message': 'ポップアップ取得成功'}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
              }));
    });
  }
  test('氏名・公式IDの表記差を統一しレコードIDを選手IDにしない', () {
    expect(playerDetailIdentity({'name': '略称', 'name_full': '正式名', 'player_key': 'npb:01234567', 'id': 999}), containsPair('source_player_id', '01234567'));
    final p = playerDetailIdentity({'name': '略称', 'name_full': '正式名', 'id': 999});
    expect(p['name'], '正式名');
    expect(p.containsKey('id_player'), isFalse);
    expect(hasPlayerIdentity({'name': 'ー'}), isFalse);
  });
  testWidgets('優勝球団と未取得表示は選手詳細を開かない', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SeasonTitlesTable(year: 2026, groups: {
      'series_champion': [
        {'name': '阪神', 'team': '阪神'}
      ],
    }))));
    final target = find.text('阪神');
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerDetailDialog), findsNothing);
  });
}
