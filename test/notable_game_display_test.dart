import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

void main() {
  testWidgets('複数首位でも王冠は一つで、名前の長さにかかわらずシーズン成績の軸を揃える', (tester) async {
    final session = AuthSession.instance;
    session.user = AuthUser.fromJson({'id': 1});
    session.token = 'test';
    addTearDown(() {
      session.user = null;
      session.token = null;
    });
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [375.0, 1200.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: GamesBoardYahooStyle(
        key: ValueKey(width),
        initialStatsExpanded: true,
        horizontal: true,
        playerStats: [
          for (final title in ['打率', '本塁打', '打点']) {'name_player': '短名', 'title': title, 'int_rank': 1, 'id_league': 1},
          for (final name in ['短名', 'とても長い選手名'])
            for (final title in ['打席数', '代打起用数', 'GG受賞回数', '盗塁阻止数']) {'name_player': name, 'title': title, 'int_rank': 1, 'id_league': 1},
        ],
        games: [
          for (final name in ['短名', 'とても長い選手名'])
            {
              'id_game': 1,
              'code_game': 'JS',
              'date_game': '2026-10-25',
              'state': '試合終了',
              'id_team_home': 1,
              'id_team_away': 2,
              'id_league_home': 1,
              'name_team_home': 'ホーム',
              'name_team_away': 'ビジター',
              'score_home': 3,
              'score_away': 0,
              'name_full_summary': name,
              'id_team_summary': 1,
              'flg_pitcher': false,
              'txt_batting': '4打数3安打(1HR2打点)',
              'txt_plays': 'ソロホームラン|hr',
              'season_player_stats': [
                for (final player in ['短名', 'とても長い選手名']) ...[
                  {'name_player': player, 'title': '打率', 'stats': '.312'},
                  {'name_player': player, 'title': '本塁打', 'stats': 40},
                ],
              ],
            },
        ],
      ))));
      await tester.pump();
      expect(find.text('👑'), findsOneWidget);
      for (final title in ['打席数', '代打起用数', 'GG受賞回数', '盗塁阻止数']) {
        expect(find.byKey(ValueKey('season-crown-initial-$title')), findsNothing);
      }
      final badges = [
        for (final title in ['打率', '本塁打', '打点']) find.byKey(ValueKey('season-crown-initial-$title'))
      ];
      expect(find.descendant(of: find.byKey(const ValueKey('season-crown-打率')), matching: find.text('率')), findsOneWidget);
      for (var i = 0; i < badges.length; i++) {
        expect(badges[i], findsOneWidget);
        expect(tester.getTopLeft(badges[i]).dy, lessThan(tester.getTopLeft(find.text('👑')).dy));
        if (i > 0) expect(tester.getTopLeft(badges[i]).dx, greaterThan(tester.getTopLeft(badges[i - 1]).dx));
      }
      final short = find.byKey(const ValueKey('game-season-stats-短名'));
      final long = find.byKey(const ValueKey('game-season-stats-とても長い選手名'));
      expect(short, findsOneWidget);
      expect(long, findsOneWidget);
      expect(tester.getTopLeft(short).dx, closeTo(tester.getTopLeft(long).dx, .01));
      expect(tester.getSize(short).width, closeTo(tester.getSize(long).width, .01));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('CS・日本シリーズの活躍ホームランはPS通算号数を先頭に表示', (tester) async {
    final session = AuthSession.instance;
    session.user = AuthUser.fromJson({'id': 1});
    session.token = 'test';
    addTearDown(() {
      session.user = null;
      session.token = null;
    });
    for (final code in ['CSF', 'JS', 'S']) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: GamesBoardYahooStyle(
        key: ValueKey(code),
        initialStatsExpanded: true,
        horizontal: true,
        games: [
          {
            'id_game': 1,
            'code_game': code,
            'date_game': '2026-10-25',
            'state': '試合終了',
            'id_team_home': 1,
            'id_team_away': 2,
            'id_league_home': 1,
            'name_team_home': 'ホーム',
            'name_team_away': 'ビジター',
            'score_home': 3,
            'score_away': 0,
            'postseason_homers_before': const [
              {'id_player': 10, 'name': '対象打者', 'homers': 3}
            ],
            'season_player_stats': const [
              {'id_player': 10, 'name_player': '対象打者', 'title': '打率', 'stats': '.312'},
              {'id_player': 10, 'name_player': '対象打者', 'title': '本塁打', 'stats': 40},
            ],
            'id_player': 10,
            'name_full_summary': '対象打者',
            'id_team_summary': 1,
            'flg_pitcher': false,
            'txt_batting': '4打数2安打(2HR3打点)',
            'txt_plays': '40号ソロホームラン^左|hr/rbi1 41号2ランホームラン^中|hr/rbi2',
          }
        ],
      ))));
      await tester.pump();
      expect(find.text('.312 40本'), findsOneWidget);
      expect(tester.getTopLeft(find.text('.312 40本')).dx, greaterThan(tester.getTopLeft(find.text('対象打者')).dx));
      expect(find.textContaining('PS4号ソロホームラン'), code == 'S' ? findsNothing : findsWidgets);
      expect(find.textContaining('PS5号2ランホームラン'), code == 'S' ? findsNothing : findsWidgets);
      if (code == 'S') expect(find.textContaining('40号ソロホームラン'), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });
  for (final userId in [null, 1, 2, 3]) {
    testWidgets('活躍内容と投手への代打を表示する user=$userId', (tester) async {
      final session = AuthSession.instance;
      session.user = userId == null ? null : AuthUser.fromJson({'id': userId});
      session.token = userId == null ? null : 'test';
      addTearDown(() {
        session.user = null;
        session.token = null;
      });
      await tester.pumpWidget(const MaterialApp(
          home: const Scaffold(
              body: const GamesBoardYahooStyle(
        initialStatsExpanded: true,
        horizontal: true,
        games: const [
          {
            'id_game': 1,
            'date_game': '2026-10-25',
            'state': '試合終了',
            'id_team_home': 1,
            'id_team_away': 2,
            'name_team_home': 'ソフトバンク',
            'name_team_away': 'DeNA',
            'score_home': 1,
            'score_away': 0,
            'name_full_summary': '山川穂高',
            'id_team_summary': 1,
            'flg_pitcher': false,
            'txt_batting': '1打数1安打(1HR1打点)',
            'txt_plays': '代打ソロホームラン|hr',
            'lineup': const [
              {
                'id_team': 1,
                'order': 9,
                'players': const [
                  {'name': '先発投手', 'pos': '投', 'plays': '三振|out'},
                  {'name': '穂高', 'role': '代打', 'plays': '代打ソロホームラン|hr', 'rbi': 1},
                ]
              }
            ],
          }
        ],
      ))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('ソロホームラン'), userId == 1 || userId == 2 ? findsWidgets : findsNothing);
      expect(find.text('代打：山川穂高'), findsNothing);
      expect(find.byKey(const ValueKey('substitution-frame-山川穂高')), findsNothing);
      if (userId == 1 || userId == 2) {
        expect(find.byKey(const ValueKey('notable-pinch-badge-山川穂高')), findsOneWidget);
        expect(find.text('打'), findsWidgets);
        expect(find.descendant(of: find.byKey(const ValueKey('notable-pinch-badge-山川穂高')), matching: find.text('打')), findsOneWidget);
      }
      expect(find.text('代'), findsNothing);
      expect(find.text('投'), findsNothing);
      expect(find.textContaining('1打数'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
