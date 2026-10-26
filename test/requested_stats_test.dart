import 'package:Yakyuu_Japan/View/player_detail_dialog.dart';
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/player_stats_grid.dart';

void main() {
  for (final title in ['打率', '本塁打', '出塁率', 'OPS', '防御率', 'WHIP', '奪三振', 'BB/9', '投球回数']) {
    test('$title は予想表示なしでもランク外の日本人を下段に残す', () {
      final lower = ['防御率', 'WHIP', 'BB/9'].contains(title);
      final rows = <Map<String,dynamic>>[for (var i=1;i<=40;i++) {
        'id_player':i, 'id_league':3, 'title':title,
        'int_rank': i==40 ? 1000 : i,
        'stats':lower ? i : 50-i,
        'flg_japan':[2,35,40].contains(i),
      }];
      sortPersonalStatRows(rows);
      expect(rows.any((r)=>r['id_player']==35),isTrue);
      expect(rows.any((r)=>r['id_player']==40),isTrue);
      final preview=personalStatPreview(rows,includeJapanese:true,showPredictions:false);
      expect(preview,hasLength(10));
      expect(preview.where((r)=>r['flg_japan']==true && r['preview_separator']!=true).map((r)=>r['id_player']),[2,35,40]);
      expect(preview.last['id_player'],40);
      expect(preview.where((r)=>r['preview_separator']==true),hasLength(1));
    });
  }

  test('省略記号で上位の日本人選手を隠さない', () {
    final rows=<Map<String,dynamic>>[for(var i=1;i<=12;i++) {
      'id_player':i,'id_league':4,'title':'OPS','stats':20-i,'int_rank':i,
      'flg_japan':[9,12].contains(i),
    }];
    final shown=personalStatPreview(rows,includeJapanese:true,showPredictions:false);
    expect(shown.where((r)=>r['preview_separator']!=true && r['flg_japan']==true).map((r)=>r['id_player']),[9,12]);
  });

  testWidgets('MLBの各項目パネルにランク外の日本人を表示する', (tester) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ScrollLeaguePersonalStats(
      batting:true,showJapanFlag:true,
      rows:[for(var i=1;i<=12;i++) {
        'id_player':i,'id_league':3,'name_player':i==12?'対象選手':'選手$i',
        'title':'OPS','stats':20-i,'int_rank':i,'flg_japan':i==12,
      }],
    ))));
    expect(find.textContaining('対象選手'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('MLBグリッドは得点圏打率を表示せずNPBでは維持する', (tester) async {
    for (final league in [3, 4, 1]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlayerStatsGrid(
        batting: true,
        rows: [
          {'id_league': league, 'id_player': 1, 'name_player': '野手', 'title': '打率', 'stats': '.300'},
          {'id_league': league, 'id_player': 1, 'name_player': '野手', 'title': '得点圏打率', 'stats': '.350'},
        ],
      ))));
      expect(find.text('得点圏打率'), league == 1 ? findsOneWidget : findsNothing);
      expect(find.text('打率'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('MLBの長い名前は左右に余白を残し12pxを下限に1行で省略する', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(
      child: PlayerStatCell(width: 260, showJapanFlag: true, row: {
        'name_player': 'クリストフェル・アレクサンダー・サンチェス',
        'name_team': 'PHI', 'stats': '2.50', 'title': '防御率', 'int_rank': 1,
      }),
    ))));
    final auto = tester.widget<AutoSizeText>(find.byType(AutoSizeText));
    expect(auto.minFontSize, 12);
    expect(auto.maxLines, 1);
    expect(auto.overflow, TextOverflow.ellipsis);
    final text = tester.widget<Text>(find.descendant(of: find.byType(AutoSizeText), matching: find.byType(Text)).first);
    expect(text.style!.fontSize! * text.textScaleFactor!, closeTo(12, .01));
    final padding = tester.widget<Padding>(find.ancestor(
      of: find.byType(AutoSizeText), matching: find.byType(Padding)).first);
    expect(padding.padding, const EdgeInsets.symmetric(horizontal: 6));
    expect(tester.takeException(), isNull);
  });

  test('詳細は上位50人に日本人MLB選手を追加し規定未達も成績順に保持する', () {
    final rows = <Map<String,dynamic>>[for(var i=1;i<=60;i++) {
      'id_player':i,'title':'本塁打','stats':100-i,'int_rank':i,
      'flg_japan': i==55,
    }, {'id_player':99,'title':'本塁打','stats':95.5,'int_rank':1000,'flg_japan':true,'name_player':'対象(65.0%)'}];
    sortPersonalStatRows(rows,limitToThirty:false);
    final detail = personalStatRankingDetail(rows,includeJapanese:true);
    expect(detail,hasLength(52));
    expect(detail[4]['id_player'],99);
    expect(detail[4]['name_player'],'対象(65.0%)');
    expect(detail.last['id_player'],55);
    expect(detail.any((r)=>r['id_player']==50),isTrue);
    expect(detail.any((r)=>r['id_player']==60),isFalse);
    expect(personalStatRankingDetail(rows),hasLength(50));
  });

  testWidgets('ランキング詳細は50人までを既存サイズのスクロール枠で表示する', (tester) async {
    final rows = <Map<String,dynamic>>[for(var i=1;i<=60;i++) {
      'id_player':900000+i,'name_player':'選手$i','title':'最多勝','stats':100-i,'int_rank':i,
    }];
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ScrollLeaguePersonalStats(rows:rows,batting:false))));
    await tester.tap(find.byTooltip('最多勝の全ランキング'));
    await tester.pumpAndSettle();
    final ranking = find.byKey(const ValueKey('personal-stat-ranking-最多勝'));
    final list = tester.widget<ListView>(ranking);
    expect(list.childrenDelegate.estimatedChildCount,50);
    expect((tester.widget<Dialog>(find.byType(Dialog)).child as SizedBox).height!,lessThanOrEqualTo(600*.8));
    await tester.scrollUntilVisible(find.text('選手50'),500,scrollable:find.descendant(of:ranking,matching:find.byType(Scrollable)));
    expect(find.text('選手50'),findsOneWidget);
    expect(find.text('選手51'),findsNothing);
    expect(tester.takeException(),isNull);
  });

  test('長押し選手を予想表示の有無にかかわらず最後の枠に入れる', () {
    final rows = <Map<String,dynamic>>[for (var i=1;i<=40;i++) {
      'id_player': i, 'title':'奪三振', 'int_rank':i, 'stats':100-i,
    }];
    sortPersonalStatRows(rows, limitToThirty: false);
    for (final predictions in [true,false]) {
      final shown = personalStatPreview(rows, showPredictions: predictions, isHighlighted: (r) => r['id_player']==35);
      expect(shown, hasLength(10));
      expect(shown.last['int_rank'],35);
      expect(shown.take(9).map((r)=>r['id_player']),List.generate(9,(i)=>i+1));
    }
    expect(personalStatPreview(rows).last['int_rank'],10);
    expect(personalStatPreview(rows,isHighlighted:(r)=>r['id_player']==3).where((r)=>r['id_player']==3),hasLength(1));
  });
  testWidgets('長押しで別スタッツの12位を末尾に表示し解除で元に戻す', (tester) async {
    tester.view.physicalSize = const Size(900,800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows = <Map<String,dynamic>>[
      {'id_player':800012,'name_player':'対象選手','title':'最多勝','stats':20,'int_rank':1},
      for(var i=1;i<=12;i++) {'id_player':800000+i,'name_player': i==12?'対象選手':'選手$i','title':'奪三振率','stats':20-i,'int_rank':i},
    ];
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ScrollLeaguePersonalStats(rows:rows,batting:false))));
    final panel = find.byKey(const ValueKey('personal-stat-panel-奪三振率'));
    List<PlayerStatCell> cells() => tester.widgetList<PlayerStatCell>(find.descendant(of:panel,matching:find.byType(PlayerStatCell))).toList();
    expect(cells().last.row['int_rank'],10);
    await tester.longPress(find.text('対象選手'));
    await tester.pump();
    expect(cells(),hasLength(10));
    expect(cells().last.row['int_rank'],12);
    await tester.longPress(find.text('対象選手').first);
    await tester.pump();
    expect(cells().last.row['int_rank'],10);
    expect(tester.takeException(),isNull);
  });

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

  testWidgets('投手の勝率を長押しすると他の投手成績も同時に強調される', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [
      PlayerStatCell(row: {'id_player': 605, 'name_player': '髙橋遥人', 'title': '最多勝', 'stats': '14', 'color_back': 'yellow', 'txt_position': '投手'}),
      PlayerStatCell(row: {'id_player': 605, 'name_player': '髙橋遥人', 'title': '勝率', 'stats': '.875', 'color_back': 'yellow', 'txt_position': '投手'}),
      PlayerStatCell(row: {'id_player': 744, 'name_player': '山野太一', 'title': '勝率', 'stats': '.800', 'color_back': 'midnightblue', 'txt_position': '投手'}),
    ]))));
    List<Color> colors() => tester.widgetList<ColoredBox>(find.byKey(const ValueKey('player-stat-bg'))).map((w) => w.color).toList();
    final original = colors();
    for (final target in [
      find.text('.875'),
      find.descendant(of: find.byType(PlayerStatCell).at(1), matching: find.byType(PlayerNameLink)),
      find.byType(PlayerStatCell).first,
    ]) {
      await tester.longPress(target);
      await tester.pump();
      expect(colors()[0], isNot(original[0]));
      expect(colors()[1], colors()[0]);
      expect(colors()[2], original[2]);
      await tester.longPress(target);
      await tester.pump();
      expect(colors(), original);
    }
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
