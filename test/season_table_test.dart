import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/BlinkBg.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';

void main() {
  test('wildcard standings show from September until opening day', () {
    expect(showMlbWildcardStandings(seasonYear: 2026, now: DateTime(2026, 9, 1)), isTrue);
    expect(showMlbWildcardStandings(seasonYear: 2026, now: DateTime(2026, 10, 5)), isTrue);
    expect(showMlbWildcardStandings(seasonYear: 2026, now: DateTime(2027, 3, 15)), isTrue);
    expect(showMlbWildcardStandings(seasonYear: 2026, now: DateTime(2026, 4, 1)), isFalse);
    expect(showMlbWildcardStandings(seasonYear: 2026, now: DateTime(2026, 8, 31)), isFalse);
    expect(showMlbWildcardStandings(seasonYear: 2025, now: DateTime(2026, 5, 1)), isTrue);
  });

  testWidgets('ワイルドカード順位の1位の勝差はハイフン', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic> team({
      required int id,
      required String name,
      required String area,
      required int wins,
      required int losses,
      required String behind,
    }) {
      return {
        'id_league': 3,
        'id_team': id,
        'name_team': name,
        'code_area': area,
        'int_rank': 1,
        'int_win': wins,
        'int_lose': losses,
        'int_draw': 0,
        'int_game': wins + losses,
        'game_behind': behind,
        'pct_win': '.500',
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: SeasonTableBlock(
          org: OrgConfig.mlb,
          onlyLeagueId: 3,
          pane: SeasonPane.standings,
          seasonYear: 2025,
          standings: [
            team(id: 1, name: 'ヤンキース', area: 'EAST', wins: 10, losses: 2, behind: '3'),
            team(id: 2, name: 'ガーディアンズ', area: 'CENTER', wins: 9, losses: 3, behind: '3'),
            team(id: 3, name: 'アストロズ', area: 'WEST', wins: 8, losses: 4, behind: '3'),
            team(id: 4, name: 'レッドソックス', area: 'EAST', wins: 9, losses: 4, behind: '3'),
            team(id: 5, name: 'タイガース', area: 'CENTER', wins: 8, losses: 5, behind: '3'),
          ],
          stats: const [],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ワイルドカード順位'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('ゲーム差'), findsNothing);
    expect(find.byType(GamesBehindChart), findsNWidgets(3));
    expect(find.text('1'), findsWidgets);
  });

  test('games behind places the leader at zero', () {
    expect(gamesBehindEntry('阪神', '-'), (name: '阪神', abbrev: '', label: '-', gb: 0));
    expect(gamesBehindEntry('巨人', '2.5').gb, 2.5);
    final layout = layoutGamesBehindChart([
      gamesBehindEntry('ソフトバンク', '優勝'),
      gamesBehindEntry('西武', '11.5'),
      gamesBehindEntry('日本ハム', '1.5'),
    ]);
    expect(layout.links.map((link) => link.label).toList(), ['11.5', '1.5']);
    expect(layout.logos[1].top, greaterThan(layout.logos[0].top));
    expect(layout.logos[2].top, greaterThan(layout.logos[1].top));
    expect(layout.logos[2].top - layout.logos[1].top, lessThan(layout.logos[1].top - layout.logos[0].top));
  });

  test('ゲーム差0は横に並べ、線も数字も出さない', () {
    final layout = layoutGamesBehindChart([
      gamesBehindEntry('1位', '-'),
      gamesBehindEntry('2位', '0'),
      gamesBehindEntry('3位', '0'),
    ]);
    expect(layout.links, isEmpty);
    expect(layout.logos[0].top, layout.logos[1].top);
    expect(layout.logos[1].top, layout.logos[2].top);
    expect(layout.logos[1].left, greaterThan(layout.logos[0].left));
    expect(layout.logos[2].left, greaterThan(layout.logos[1].left));
  });

  test('狭いゲーム差が続くときは左右交互に迂回する', () {
    final layout = layoutGamesBehindChart([
      gamesBehindEntry('1位', '-'),
      gamesBehindEntry('2位', '0.5'),
      gamesBehindEntry('3位', '0.5'),
      gamesBehindEntry('4位', '0.5'),
    ]);
    expect(layout.links.every((link) => link.side), isTrue);
    expect(layout.links[0].sideRight, isTrue);
    expect(layout.links[1].sideRight, isFalse);
    expect(layout.links[2].sideRight, isTrue);
  });

  test('ゲーム差の図は指定した高さに収める', () {
    final layout = layoutGamesBehindChart([
      gamesBehindEntry('1位', '-'),
      gamesBehindEntry('2位', '11.5'),
      gamesBehindEntry('3位', '1.5'),
      gamesBehindEntry('4位', '13.5'),
      gamesBehindEntry('5位', '1.5'),
      gamesBehindEntry('6位', '6'),
    ], targetHeight: 380);
    expect(layout.height, closeTo(380, 1));
  });

  testWidgets('ゲーム差はロゴの間隔で表し、狭いときは横へ迂回する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: GamesBehindChart(rows: [
              {'name_team': '阪神', 'game_behind': '-'},
              {'name_team': '巨人', 'game_behind': '0.5'},
              {'name_team': '中日', 'game_behind': '3'},
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    final lead = tester.getRect(find.byKey(const ValueKey('gb-mark-阪神')));
    final mid = tester.getRect(find.byKey(const ValueKey('gb-mark-巨人')));
    final last = tester.getRect(find.byKey(const ValueKey('gb-mark-中日')));
    expect(lead.left, mid.left);
    expect(mid.left, last.left);
    expect(lead.top, lessThan(mid.top));
    expect(mid.top, lessThan(last.top));
    final tight = mid.top - lead.bottom;
    final wide = last.top - mid.bottom;
    expect(wide, greaterThan(tight * 3));
    final small = tester.getRect(find.byKey(const ValueKey('gb-gap-阪神-巨人')));
    final big = tester.getRect(find.byKey(const ValueKey('gb-gap-巨人-中日')));
    expect(small.left, greaterThan(lead.right - 1));
    expect(big.top, greaterThan(mid.bottom - 1));
    expect(big.bottom, lessThan(last.top + 1));
    expect(big.left, greaterThan(mid.center.dx));
  });

  testWidgets('ゲーム差の図は1位から6位までのロゴを縦に並べる', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: GamesBehindChart(rows: [
              {'name_team': '6位', 'int_rank': 6, 'game_behind': '10'},
              {'name_team': '2位', 'int_rank': 2, 'game_behind': '1'},
              {'name_team': '1位', 'int_rank': 1, 'game_behind': '-'},
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('gb-mark-6位')), findsOneWidget);
    final first = tester.getTopLeft(find.byKey(const ValueKey('gb-mark-1位')));
    final second = tester.getTopLeft(find.byKey(const ValueKey('gb-mark-2位')));
    final sixth = tester.getTopLeft(find.byKey(const ValueKey('gb-mark-6位')));
    expect(first.dy, lessThan(second.dy));
    expect(second.dy, lessThan(sixth.dy));
  });

  testWidgets('MLBのゲーム差は略称に対応するロゴを出す', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: GamesBehindChart(rows: [
              {'name_team': 'ジャイアンツ', 'name_shortest': 'SF', 'game_behind': '-'},
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    final image = tester.widget<Image>(find.descendant(of: find.byKey(const ValueKey('gb-mark-ジャイアンツ')), matching: find.byType(Image)));
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, contains('/sf.png'));
  });

  testWidgets('個人成績の項目に盗塁成功率は出さない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: SegmentedLeaguePersonalStats(
              batting: [
                {'title': '盗塁', 'stats': '12', 'int_rank': 1, 'name_player': '山田', 'name_team': 'ヤ'},
                {'title': '盗塁成功率', 'stats': '80.0', 'int_rank': 1, 'name_player': '山田', 'name_team': 'ヤ'},
              ],
              pitching: [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final labels = tester.widget<StatsSegmentControl>(find.byType(StatsSegmentControl)).labels;
    expect(labels, ['盗塁']);
    expect(find.text('80.0'), findsNothing);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('個人成績のリーグ見出しは高さ33', (tester) async {
    Future<void> expectHeader(Widget child, String label) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 420, width: 800, child: child),
          ),
        ),
      );
      await tester.pump();
      final boxes = tester.widgetList<SizedBox>(
        find.ancestor(of: find.text(label), matching: find.byType(SizedBox)),
      );
      expect(boxes.any((box) => box.height == 33), isTrue, reason: label);
    }

    const row = {
      'title': '打率',
      'stats': '.300',
      'int_rank': 1,
      'name_player': '山田',
      'name_team': 'ヤ',
      'flg_pitcher': false,
    };
    await expectHeader(
      BothLeaguePersonalStats(
        stats: [
          {...row, 'id_league': 1},
          {...row, 'id_league': 2, 'name_player': '柳田'},
        ],
      ),
      'セ',
    );
    await expectHeader(
      BothLeaguePersonalStats(
        layout: PersonalStatsLayout.scroll,
        stats: [
          {...row, 'id_league': 1},
          {...row, 'id_league': 2, 'name_player': '柳田'},
        ],
      ),
      'パ',
    );
    await expectHeader(
      DualBandBothLeaguePersonalStats(
        org: OrgConfig.mlb,
        stats: [
          {...row, 'id_league': 3},
          {...row, 'id_league': 4, 'name_player': '大谷'},
        ],
      ),
      'ア',
    );
  });

  test('個人成績の選手名から姓名の空白を除く', () {
    expect(compactPersonalStatName('村上 宗隆'), '村上宗隆');
    expect(compactPersonalStatName('Jack Lamabe'), 'JackLamabe');
    expect(compactPersonalStatName('村上　宗隆(12.3%)'), '村上宗隆(12.3%)');
  });

  testWidgets('個人成績セルは空白なしの選手名を出し、今日以外は点滅しない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerStatCell(
            row: {
              'int_rank': 1,
              'name_team': '巨',
              'name_player': '村上 宗隆',
              'stats': '.300',
              'flg_today': false,
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('村上宗隆'), findsOneWidget);
    expect(find.textContaining('村上 宗隆'), findsNothing);
    expect(find.byType(BlinkBg), findsNothing);
  });

  testWidgets('個人成績はその年に引退した選手に💐を付ける', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerStatCell(
            row: {
              'int_rank': 2,
              'name_team': '巨',
              'name_player': '坂本勇人',
              'stats': '.278',
              'flg_retired': true,
            },
          ),
        ),
      ),
    );
    expect(find.text('💐'), findsOneWidget);
  });

  test('個人成績の地色はポジションで分かれる', () {
    expect(personalStatPositionColor('捕手'), const Color(0xFFB3E5FC));
    expect(personalStatPositionColor('外野手'), const Color(0xFFE6EE9C));
    expect(personalStatPositionColor('内野手'), const Color(0xFFFFF59D));
    expect(personalStatPositionColor('投手'), const Color(0xFFFFCDD2));
    expect(personalStatPositionColor('左'), const Color(0xFFA5D6A7));
    expect(personalStatPositionColor(''), isNull);
  });

  testWidgets('佐賀出身と故障者にはマークを付ける', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerStatCell(
            row: {
              'int_rank': 3,
              'name_team': 'ソ',
              'name_player': '甲斐野央',
              'stats': '1.80',
              'flg_saga': true,
              'flg_injury': true,
              'txt_position': '投手',
            },
          ),
        ),
      ),
    );
    expect(find.text('佐'), findsOneWidget);
    expect(find.text('🤕'), findsOneWidget);
    final bg = tester.widget<ColoredBox>(find.byKey(const ValueKey('player-stat-bg')));
    expect(bg.color, personalStatPositionColor('投手'));
  });
}

