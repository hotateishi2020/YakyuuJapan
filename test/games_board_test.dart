import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';

void main() {
  testWidgets('compact game cards do not overflow', (tester) async {
    final game = <String, dynamic>{
      'name_team_home': 'ソフトバンク',
      'name_team_away': '北海道日本ハム',
      'name_stadium': 'PayPayドーム',
      'time_game': '🌙 18:00',
      'name_pitcher_home': '長い名前の先発投手',
      'name_pitcher_away': '長い名前の先発投手',
      'name_pitcher_win': '長い名前の先発投手',
      'name_pitcher_lose': '長い名前の先発投手',
      'name_pitcher_save': '長い名前の抑え投手',
      'score_home': 10,
      'score_away': 12,
      'state': '延長12回裏',
      'id_team_home': 1,
      'id_team_away': 2,
      'id_team_pitcher_win': 1,
      'id_team_pitcher_lose': 2,
      'id_team_pitcher_save': 1,
      'color_back_home': '#F4D03F',
      'color_back_away': '#3F7DD8',
      'color_font_home': '#000000',
      'color_font_away': '#FFFFFF',
      'colors_pitcher_home': '/red/blue/',
      'colors_pitcher_away': '',
      'name_homerun_home': '長い名前のホームラン打者',
      'name_homerun_away': '長い名前のホームラン打者',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            height: 90,
            child: GamesBoardYahooStyle(
              games: [game, Map<String, dynamic>.from(game)],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('勝'), findsNWidgets(2));
    expect(find.text('負'), findsNWidgets(2));
    expect(find.text('S'), findsNWidgets(2));

    final starterX =
        tester.getTopLeft(find.text('長い名前の先発投手').first).dx;
    final saveX = tester.getTopLeft(find.text('長い名前の抑え投手').first).dx;
    expect(starterX, closeTo(saveX, 0.5));
    final markY = tester.getCenter(find.text('勝').first).dy;
    final starterY =
        tester.getCenter(find.text('長い名前の先発投手').first).dy;
    expect(markY, closeTo(starterY, 1.0));
  });

  testWidgets('date buttons move relative to the displayed day', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 180,
          child: GameDateSwitcher(
            games: [],
            headerColor: Colors.green,
            initialDate: '2026-09-16',
          ),
        ),
      ),
    );

    expect(find.textContaining('今日'), findsOneWidget);

    await tester.tap(find.text('前の日'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('昨日'), findsOneWidget);

    await tester.tap(find.text('次の日'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('今日'), findsOneWidget);

    await tester.tap(find.text('次の日'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('明日'), findsOneWidget);

    await tester.tap(find.text('前の日'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('今日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
