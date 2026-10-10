import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  Map<String, dynamic> team(int id, String name, int rank, String behind) => {
        'id_league': 1,
        'id_team': id,
        'name_team': name,
        'int_rank': rank,
        'int_win': 10 - rank,
        'int_lose': rank,
        'int_draw': 0,
        'int_game': 10,
        'game_behind': behind,
        'pct_win': '.500',
      };

  final standings = [
    team(1, '巨人', 1, '-'),
    team(2, '阪神', 2, '1.5'),
    team(3, '広島', 3, '3'),
    team(4, 'DeNA', 4, '4'),
    team(5, '中日', 5, '6'),
    team(6, 'ヤクルト', 6, '8'),
  ];

  Future<void> pump(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeasonTableBlock(
            org: OrgConfig.npb,
            onlyLeagueId: 1,
            pane: SeasonPane.standings,
            portraitLayout: true,
            seasonYear: 2026,
            standings: standings,
            stats: const [],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('横幅が広い順位表ではゲーム差を表の右に同じ高さで置く', (tester) async {
    await pump(tester, 1400);
    expect(find.byKey(const Key('standings-gb-beside')), findsOneWidget);
    final row = tester.getRect(find.byKey(const Key('standings-gb-beside')));
    final chart = tester.getRect(find.byType(GamesBehindChart));
    final games = tester.getRect(find.text('試合'));
    final era = tester.getRect(find.text('救援'));
    final name = tester.getRect(find.text('巨人'));
    expect(chart.left, greaterThan(row.center.dx));
    expect(chart.right, lessThanOrEqualTo(row.right + 1));
    expect((chart.height - row.height).abs(), lessThan(1));
    expect(chart.top, closeTo(row.top, 1));
    expect(name.right, lessThan(games.left));
    expect(era.right - games.left, greaterThan(500));
    expect(era.right, lessThan(chart.left + 1));
    final mark = tester.getRect(find.byKey(const ValueKey('gb-mark-巨人')));
    expect(mark.left, greaterThanOrEqualTo(chart.left - 1));
    expect(mark.right, lessThanOrEqualTo(chart.right + 1));
    expect(mark.top, greaterThanOrEqualTo(chart.top - 1));
    expect(mark.bottom, lessThanOrEqualTo(chart.bottom + 1));
  });

  testWidgets('セとパの順位表とゲーム差は同じ幅の枠に収まる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final both = [
      ...standings,
      team(7, 'ソフトバンク', 1, '-'),
      team(8, '日本ハム', 2, '1.5'),
      team(9, 'ロッテ', 3, '3'),
      team(10, '西武', 4, '4'),
      team(11, 'オリックス', 5, '7'),
      team(12, '楽天', 6, '13'),
    ];
    for (final row in both) {
      if ((row['id_team'] as int) >= 7) row['id_league'] = 2;
    }
    Widget block(int leagueId) {
      return SeasonTableBlock(
        org: OrgConfig.npb,
        onlyLeagueId: leagueId,
        pane: SeasonPane.standings,
        portraitLayout: true,
        seasonYear: 2026,
        standings: both,
        stats: const [],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              block(1),
              block(2),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final charts = tester.getRect(find.byType(GamesBehindChart).at(0));
    final charts2 = tester.getRect(find.byType(GamesBehindChart).at(1));
    expect((charts.width - charts2.width).abs(), lessThan(1));
    expect((charts.right - charts2.right).abs(), lessThan(1));
    final era = tester.getRect(find.text('救援').at(0));
    final era2 = tester.getRect(find.text('救援').at(1));
    expect((era.right - era2.right).abs(), lessThan(1));
    expect(era.right, lessThan(charts.left + 1));
    expect(era2.right, lessThan(charts2.left + 1));
    for (final name in ['巨人', 'ソフトバンク']) {
      final mark = tester.getRect(find.byKey(ValueKey('gb-mark-$name')));
      final host = name == '巨人' ? charts : charts2;
      expect(mark.left, greaterThanOrEqualTo(host.left - 1));
      expect(mark.right, lessThanOrEqualTo(host.right + 1));
    }
  });

  testWidgets('横幅が狭い順位表ではゲーム差を表の下に置く', (tester) async {
    await pump(tester, 640);
    expect(find.byKey(const Key('standings-gb-beside')), findsNothing);
    expect(find.byType(GamesBehindChart), findsOneWidget);
    final chart = tester.getRect(find.byType(GamesBehindChart));
    final tableTop = tester.getTopLeft(find.text('巨人'));
    expect(chart.top, greaterThan(tableTop.dy));
  });
}
