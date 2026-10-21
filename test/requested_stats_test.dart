import 'package:flutter/material.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/player_stats_grid.dart';

void main() {
  test('予想対象外の代打起用数は予想色が残っていても差し替えない', () {
    final rows = <Map<String, dynamic>>[
      for (var i = 1; i <= 35; i++) {
        'title': '代打起用数', 'int_rank': i, 'stats': 40 - i,
        if (i == 35) ...{'name_player': 'ネビン', 'colors_user': '/red/', 'id_users': '/1/'},
      },
    ];
    expect(isPredictedStatPlayer(rows.last), isFalse);
    expect(personalStatPreview(rows).map((r) => r['int_rank']), List.generate(10, (i) => i + 1));
    sortPersonalStatRows(rows);
    expect(rows, hasLength(30));
    expect(rows.any((r) => r['name_player'] == 'ネビン'), isFalse);
  });

  test('上位10人の下から予想対象を補い既存の予想対象は残す', () {
    final rows = <Map<String, dynamic>>[for (var i = 1; i <= 35; i++) {
      'title': '本塁打', 'int_rank': i, 'stats': 40 - i,
      if ([10, 12, 35].contains(i)) 'id_users': '/1/',
    }];
    sortPersonalStatRows(rows);
    final preview = personalStatPreview(rows);
    expect(preview.map((r) => r['int_rank']).toList(), [1, 2, 3, 4, 5, 6, 7, 10, 12, 35]);
    expect(personalStatPreview(rows, showPredictions: false).map((r) => r['int_rank']).toList(),
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(rows.last['int_rank'], 35);
  });

  testWidgets('長押しで同じ選手の背景をまとめて切り替える', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [
      PlayerStatCell(row: {'id_player': 987654, 'name_player': '対象選手', 'title': '打率', 'stats': '.300', 'color_back': '#123456'}),
      PlayerStatCell(row: {'id_player': 987654, 'name_player': '対象選手', 'title': '本塁打', 'stats': '30', 'color_back': '#123456'}),
      PlayerStatCell(row: {'id_player': 987655, 'name_player': '別選手', 'stats': '20', 'color_back': '#123456'}),
    ]))));
    List<Color> colors() => tester.widgetList<ColoredBox>(find.byKey(const ValueKey('player-stat-bg'))).map((w) => w.color).toList();
    final original = colors();
    await tester.longPress(find.byType(PlayerStatCell).first);
    await tester.pump();
    expect(colors(), [const Color(0xff123456), const Color(0xff123456), original.last]);
    await tester.longPress(find.byType(PlayerStatCell).at(2));
    await tester.pump();
    expect(colors(), [original[0], original[1], const Color(0xff123456)]);
    await tester.longPress(find.byType(PlayerStatCell).first);
    await tester.pump();
    expect(colors(), [const Color(0xff123456), const Color(0xff123456), original.last]);
    await tester.longPress(find.byType(PlayerStatCell).at(1));
    await tester.pump();
    expect(colors(), original);
  });

  test('規定未達も数値順に並べ順位の表示値は保持する', () {
    for (final title in ['打率', '防御率', 'WHIP']) {
      final rows = <Map<String, dynamic>>[
        {'title': title, 'stats': '0.3', 'int_rank': 1},
        {'title': title, 'stats': '0.4', 'int_rank': 1000},
        {'title': title, 'stats': '0.2', 'int_rank': 2},
        {'title': title, 'stats': '—', 'int_rank': 1000},
      ];
      sortPersonalStatRows(rows);
      expect(rows.map((r) => r['stats']).toList(),
        title == '打率' ? ['0.4', '0.3', '0.2', '—'] : ['0.2', '0.3', '0.4', '—']);
      expect(rows.firstWhere((r) => r['stats'] == '0.4')['int_rank'], 1000);
    }
  });

  testWidgets('HPとホールドを別項目として選択できる', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: BothLeaguePersonalStats(segmentOnly: true, stats: [
        {'id_league': 1, 'title': 'ホールド', 'stats': '38', 'name_player': '野手'},
        {'id_league': 1, 'title': 'HP', 'stats': '41', 'int_rank': 1, 'name_player': '投手'},
      ]),
    )));
    final segment = find.byWidgetPredicate((w) => w is StatsSegmentControl && w.labels.contains('HP'));
    expect(segment, findsOneWidget);
    expect(tester.widget<StatsSegmentControl>(segment).labels, ['ホールド', 'HP']);
    await tester.tap(find.descendant(of: segment, matching: find.byType(InkWell)).first);
    await tester.pumpAndSettle();
    expect(find.text('38'), findsOneWidget);
    expect(find.text('41'), findsNothing);
    await tester.tap(find.descendant(of: segment, matching: find.byType(InkWell)).last);
    await tester.pumpAndSettle();
    expect(find.text('41'), findsOneWidget);
    expect(find.text('投手'), findsOneWidget);
    expect(find.text('野手'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('勝率は投手セグメントから選択できる', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: BothLeaguePersonalStats(segmentOnly: true, stats: [
        {'id_league': 1, 'title': '打率', 'stats': '.300', 'name_player': '野手'},
        {'id_league': 1, 'title': '勝率', 'stats': '.750', 'int_rank': 1, 'name_player': '投手'},
      ]),
    )));
    final segment = find.byWidgetPredicate((w) => w is StatsSegmentControl && w.labels.contains('勝率'));
    expect(segment, findsOneWidget);
    await tester.tap(find.descendant(of: segment, matching: find.byType(InkWell)));
    await tester.pumpAndSettle();
    expect(find.text('.750'), findsOneWidget);
    expect(find.text('投手'), findsOneWidget);
    expect(find.text('野手'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('代打起用数に同じ選手・リーグの打率を併記する', () {
    final usage = <String,dynamic>{'id_player': 7, 'id_league': 1, 'title': '代打起用数', 'stats': '24'};
    final rows = <Map<String,dynamic>>[
      {...usage, 'title': '代打打率', 'stats': '.375'},
      {...usage, 'id_player': 8, 'title': '代打打率', 'stats': '.999'},
    ];
    expect(personalStatDisplay(usage, rows), '24（.375）');
    expect(personalStatDisplay(usage, []), '24（—）');
  });
  test('順位表と追加指標はソート後の上位30件に制限する', () {
    final rows = <Map<String,dynamic>>[for (var i = 35; i >= 1; i--)
      {'title': '本塁打', 'int_rank': i, 'stats': '${40-i}'}];
    sortPersonalStatRows(rows);
    expect(rows.length, 30);
    expect(rows.first['int_rank'], 1);
    expect(rows.last['int_rank'], 30);
    final extra = <Map<String,dynamic>>[for (var i = 1; i <= 35; i++)
      {'title': '得点圏打率', 'numeric_value': i / 100}];
    sortPersonalStatRows(extra);
    expect(extra.length, 30);
    expect(extra.first['numeric_value'], .35);
  });
}
