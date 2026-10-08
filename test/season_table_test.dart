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
    expect(find.text('-'), findsNWidgets(2));
    expect(find.text('ゲーム差'), findsWidgets);
    expect(find.text('1'), findsWidgets);
  });

  test('games behind places the leader at zero', () {
    expect(gamesBehindEntry('阪神', '-'), (name: '阪神', label: '-', gb: 0));
    expect(gamesBehindEntry('巨人', '2.5').gb, 2.5);
    expect(gbMarkLeft(0, 4, 340, 40), 0);
    expect(gbMarkLeft(2, 4, 340, 40), 150);
    expect(gbMarkLeft(4, 4, 340, 40), 300);
  });

  testWidgets('ゲーム差の割合だけロゴを離し、画像の中に勝差を出す', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: GamesBehindChart(rows: [
              {'name_team': '阪神', 'game_behind': '-'},
              {'name_team': '巨人', 'game_behind': '2'},
              {'name_team': '中日', 'game_behind': '4'},
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    final lead = tester.getTopLeft(find.byKey(const ValueKey('gb-mark-阪神')));
    final mid = tester.getTopLeft(find.byKey(const ValueKey('gb-mark-巨人')));
    final last = tester.getTopLeft(find.byKey(const ValueKey('gb-mark-中日')));
    expect(lead.dx, lessThan(mid.dx));
    expect(mid.dx, lessThan(last.dx));
    expect(((mid.dx - lead.dx) - (last.dx - mid.dx)).abs(), lessThan(1));
    expect(find.text('-'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    final label = tester.getRect(find.byKey(const ValueKey('gb-label-阪神')));
    final mark = tester.getRect(find.byKey(const ValueKey('gb-mark-阪神')));
    expect(label.center.dx, closeTo(mark.center.dx, 1));
    expect(label.bottom, lessThanOrEqualTo(mark.bottom + 1));
    expect(label.top, greaterThan(mark.top));
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
    expect(personalStatPositionColor('左'), const Color(0xFFE6EE9C));
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

