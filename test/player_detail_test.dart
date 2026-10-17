import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/player_detail_dialog.dart';
import 'package:Yakyuu_Japan/View/player_stats_grid.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';

void main() {
  testWidgets('実データの経歴・起用・契約・功績まで表示してもスマホで崩れない', (t) async {
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final data = File('test/fixtures/player_detail_verified.json').readAsStringSync();
    await http.runWithClient(() async {
      await t.pumpWidget(const MaterialApp(home: PlayerDetailDialog(player: {'id_player': 654}, org: 'npb', year: 2026)));
      await t.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        expect(find.text('出典'), findsNothing);
        await t.drag(find.byType(ListView).first, const Offset(0, -650));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    }, () => MockClient((_) async => http.Response(data, 200, headers: {'content-type': 'application/json; charset=utf-8'})));
  });

  testWidgets('グリッドは数値で並び替え、欠損を末尾に置き選手を重複させない', (t) async {
    final rows = [
      for (final r in [
        {'id': 1, 'name': '甲', 'value': '2'},
        {'id': 2, 'name': '乙', 'value': '10'},
        {'id': 3, 'name': '丙', 'value': '—'}
      ])
        {'id_player': r['id'], 'name_player': r['name'], 'title': '本塁打', 'stats': r['value']},
      {'id_player': 1, 'name_player': '甲', 'title': '打席数', 'stats': '100'}
    ];
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PlayerStatsGrid(rows: rows, batting: true))));
    expect(find.text('甲'), findsOneWidget);
    await t.tap(find.text('本塁打'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('乙')).dy, lessThan(t.getTopLeft(find.text('甲')).dy));
    expect(t.getTopLeft(find.text('丙')).dy, greaterThan(t.getTopLeft(find.text('甲')).dy));
    await t.tap(find.text('本塁打'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('甲')).dy, lessThan(t.getTopLeft(find.text('乙')).dy));
    expect(t.getTopLeft(find.text('丙')).dy, greaterThan(t.getTopLeft(find.text('乙')).dy));
    expect(t.takeException(), isNull);
  });
  testWidgets('横長画面で従来の表とグリッドを切り替える', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: DualBandLeaguePersonalStats(batting: [
      {'id_player': 1, 'name_player': '甲', 'title': '打率', 'stats': '.300'}
    ], pitching: []))));
    await t.tap(find.text('グリッド表'));
    await t.pumpAndSettle();
    expect(find.byType(PlayerStatsGrid), findsWidgets);
    expect(find.text('従来の表'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final width in [390.0, 1400.0]) {
    testWidgets('選手名から詳細を開き、幅$widthで情報を表示', (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await t.pumpWidget(const MaterialApp(home: PlayerDetailScope(org: 'npb', year: 2026, child: Scaffold(body: PlayerNameLink(player: {'id_player': 1, 'name': '甲'}, child: Text('甲'))))));
        await t.tap(find.text('甲'));
        await t.pumpAndSettle();
        expect(find.byType(PlayerDetailDialog), findsOneWidget);
        expect(find.text('AI生成イメージ（共通）'), findsNothing);
        expect(find.text('今季所属'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.drag(find.byType(ListView).first, const Offset(0, -650));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
          () => MockClient((r) async {
                expect(r.url.queryParameters['id_player'], '1');
                return http.Response(
                    jsonEncode({
                      'found': true,
                      'profile': {'name_full': '甲', 'name_team': '今季所属', 'txt_position': '投手'},
                      'season_stats': [
                        {'title': 'BB/9', 'stats': '2.30'}
                      ],
                      'recent_games': [
                        {
                          'datetime_start': '2026-10-10',
                          'home': '甲球団',
                          'away': '乙球団',
                          'lines': [
                            {'int_batting': 4, 'int_hit1': 2, 'int_homerun': 1}
                          ],
                          'plays': []
                        }
                      ],
                      'roster': {},
                      'verified': {},
                      'careers': []
                    }),
                    200,
                    headers: {'content-type': 'application/json; charset=utf-8'});
              }));
    });
  }
}
