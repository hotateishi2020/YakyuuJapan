import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'package:Yakyuu_Japan/View/PredictGroupBoard.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/View/season_titles_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
void main() {
 final session = AuthSession.instance;
 tearDown(() { session.user = null; session.token = null; });
 testWidgets('予想選手はID1・2にロゴのみ、他は最短名のみ', (tester) async {
   session.token = 'test';
   await tester.pumpWidget(MaterialApp(home: Scaffold(body: predictPlayerLabels([
     {'player_name': '選手', 'team_name': 'Dodgers', 'team_shortest': 'LAD'}
   ], const TextStyle(fontSize: 12)))));
   for (final id in [1, 2, 3]) {
     session.user = AuthUser.fromJson({'id': id, 'flg_special': id == 3});
     await tester.pump();
     expect(find.byType(Image), id <= 2 ? findsOneWidget : findsNothing);
     expect(find.text('LAD'), id <= 2 ? findsNothing : findsOneWidget);
   }
   session.token = null;
   await tester.pump();
   expect(find.text('LAD'), findsOneWidget);
 });
 testWidgets('球速は特別フラグでなくID1・2だけに表示', (tester) async {
   session.token = 'test';
   for (final id in [1, 2, 3]) {
     session.user = AuthUser.fromJson({'id': id, 'flg_special': id == 3});
     await tester.pumpWidget(MaterialApp(home: Scaffold(body: GamePlayerAppearance(
       key: ValueKey(id), lines: const [{'int_velo_max': 160}], plays: const []))));
     await tester.pump(const Duration(milliseconds: 100));
     expect(find.text('160km'), id <= 2 ? findsOneWidget : findsNothing);
   }
 });
 testWidgets('MLB個人タイトルは選手名とスタッツ値を表示', (tester) async {
   await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SeasonTitlesGrid(
     org: OrgConfig.mlb, year: 2026, individualOnly: true,
     data: {'titles': [{'year': 2026, 'league': 'ア・リーグ', 'categories': [
       {'label': '本塁打王', 'players': [{'name': '選手', 'team': 'Yankees', 'value': 54, 'unit': '本'}]}
     ]}]}))));
   expect(find.text('54本'), findsOneWidget);
 });
}
