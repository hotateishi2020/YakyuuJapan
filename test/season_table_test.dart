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
    expect(find.text('1'), findsWidgets);
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
}

