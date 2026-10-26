import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

void main() {
  for (final userId in [null, 1, 3]) {
    testWidgets('活躍内容と投手への代打を表示する user=$userId', (tester) async {
      final session = AuthSession.instance;
      session.user = userId == null ? null : AuthUser.fromJson({'id': userId});
      session.token = userId == null ? null : 'test';
      addTearDown(() { session.user = null; session.token = null; });
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: GamesBoardYahooStyle(
        initialStatsExpanded: true,
        horizontal: true,
        games: [{
          'id_game': 1, 'date_game': '2026-10-25', 'state': '試合終了',
          'id_team_home': 1, 'id_team_away': 2,
          'name_team_home': 'ソフトバンク', 'name_team_away': 'DeNA',
          'score_home': 1, 'score_away': 0,
          'name_full_summary': '山川穂高', 'id_team_summary': 1,
          'flg_pitcher': false, 'txt_batting': '1打数1安打(1HR1打点)',
          'txt_plays': '代打ソロホームラン|hr',
          'lineup': [{'id_team': 1, 'order': 9, 'players': [
            {'name': '先発投手', 'pos': '投', 'plays': '三振|out'},
            {'name': '穂高', 'role': '代打', 'plays': '代打ソロホームラン|hr', 'rbi': 1},
          ]}],
        }],
      ))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('ソロホームラン'), findsWidgets);
      expect(find.text('代打：山川穂高'), findsNothing);
      expect(find.byKey(const ValueKey('substitution-frame-山川穂高')), findsNothing);
      expect(find.byKey(const ValueKey('notable-pinch-badge-山川穂高')), findsOneWidget);
      expect(find.text('打'), findsWidgets);
      expect(find.descendant(of: find.byKey(const ValueKey('notable-pinch-badge-山川穂高')), matching: find.text('打')), findsOneWidget);
      expect(find.text('代'), findsNothing);
      expect(find.text('投'), findsNothing);
      expect(find.textContaining('1打数'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
