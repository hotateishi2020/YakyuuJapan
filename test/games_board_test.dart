import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/BlinkBg.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';

void main() {
  test('gameIsPregameState treats スタメン as unstarted', () {
    expect(gameIsPregameState(''), isTrue);
    expect(gameIsPregameState('試合前'), isTrue);
    expect(gameIsPregameState('予想先発'), isTrue);
    expect(gameIsPregameState('スタメン'), isTrue);
    expect(gameIsPregameState('4回裏'), isFalse);
    expect(gameIsPregameState('試合終了'), isFalse);
    expect(gameHasStarted({'state': 'スタメン', 'score_home': -1, 'score_away': -1}), isFalse);
    expect(displayBoardState('予想先発'), '試合前');
    expect(displayBoardState('スタメン'), '試合前');
    expect(displayBoardState(''), '試合前');
    expect(displayBoardState('8回表'), '8回表');
    expect(displayBoardState('試合終了'), '試合終了');
    expect(gameIsInProgress({'state': '6回表'}), isTrue);
    expect(gameIsInProgress({'state': '試合終了'}), isFalse);
    expect(gameIsInProgress({'state': '試合前'}), isFalse);
  });

  test('isHeatedGame marks late close games', () {
    expect(isHeatedGame('6回裏', 3, 2), isFalse);
    expect(isHeatedGame('7回表', 4, 2), isTrue);
    expect(isHeatedGame('7回裏', 5, 2), isFalse);
    expect(isHeatedGame('8回表', 3, 1), isFalse);
    expect(isHeatedGame('8回裏', 2, 1), isTrue);
    expect(isHeatedGame('9回表', 0, 0), isTrue);
    expect(isHeatedGame('10回裏', 4, 2), isTrue);
    expect(isHeatedGame('試合終了', 1, 1), isFalse);
    expect(isHeatedGame('試合前', -1, -1), isFalse);
  });

  test('liveAtBatHalf reads the batting inning from game state', () {
    expect(liveAtBatHalf('4回裏'), (inning: 4, bottom: true));
    expect(liveAtBatHalf('12回表'), (inning: 12, bottom: false));
    expect(liveAtBatHalf('延長12回裏'), (inning: 12, bottom: true));
    expect(liveAtBatHalf('試合終了'), isNull);
    expect(liveAtBatHalf('試合前'), isNull);
    expect(liveBlinkHalf('4回表3アウト'), (inning: 4, bottom: true));
    expect(liveBlinkHalf('4回裏1アウト'), (inning: 4, bottom: true));
    expect(liveBlinkHalf('9回裏3アウト'), (inning: 10, bottom: false));
    expect(liveBlinkHalf('5回表', outs: 3), (inning: 5, bottom: true));
    expect(liveBlinkHalf('5回裏三死'), (inning: 6, bottom: false));
  });

  testWidgets('compact game cards do not overflow', (tester) async {
    final game = <String, dynamic>{
      'date_game': '2026-09-16',
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
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                game,
                {
                  ...game,
                  'id_team_home': 3,
                  'name_team_home': '巨人',
                  'id_team_pitcher_win': 3,
                  'id_team_pitcher_save': 3,
                },
              ],
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

  testWidgets('summary rows are grouped into one game card', (tester) async {
    final base = <String, dynamic>{
      'date_game': '2026-09-28',
      'time_game': '🌙 18:00',
      'name_team_home': 'DeNA',
      'name_team_away': '広島',
      'name_stadium': '横浜',
      'name_pitcher_home': '東克樹',
      'name_pitcher_away': '工藤泰己',
      'score_home': 2,
      'score_away': 3,
      'state': '8回表',
      'id_team_home': 5,
      'id_team_away': 6,
      'color_back_home': '#0066FF',
      'color_back_away': 'red',
      'color_font_home': 'white',
      'color_font_away': 'black',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 420,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  ...base,
                  'id_game_summary': 890,
                  'id_team_summary': 5,
                  'name_full_summary': '東克樹',
                  'flg_pitcher': true,
                  'code_result_pitcher': '',
                  'colors_summary': '',
                  'txt_pitching': '6.1回8安打3失点(3四球3奪三振119球)',
                  'txt_batting': '1打数無安打(1打点)',
                },
                {
                  ...base,
                  'id_game_summary': 887,
                  'id_team_summary': 6,
                  'name_full_summary': '工藤泰己',
                  'flg_pitcher': true,
                  'code_result_pitcher': 'WIN',
                  'colors_summary': '',
                  'txt_pitching': '5回4安打2失点(2四球3奪三振92球)',
                  'txt_batting': '1打数無安打(1打点1四球)',
                },
                {
                  ...base,
                  'id_game_summary': 891,
                  'id_team_summary': 5,
                  'name_full_summary': '中川虎大',
                  'flg_pitcher': true,
                  'code_result_pitcher': '',
                  'colors_summary': '',
                  'txt_pitching': '0.2回無安打無失点',
                  'txt_batting': '0打数無安打',
                },
                {
                  ...base,
                  'id_game_summary': 884,
                  'id_team_summary': 5,
                  'name_full_summary': '成瀬脩人',
                  'flg_pitcher': false,
                  'colors_summary': '/red/',
                  'txt_batting': '1打数1安打(1HR1打点1四球)',
                  'txt_pitching': '0回無安打無失点(無四球0奪三振)',
                  'txt_homerun_total': '11, 12',
                  'titles_predict': '本|red,安|blue',
                },
                {
                  ...base,
                  'id_game_summary': 868,
                  'id_team_summary': 6,
                  'name_full_summary': '菊池涼介',
                  'flg_pitcher': false,
                  'colors_summary': '',
                  'txt_batting': '2打数1安打(1打点1四球1犠打)',
                  'txt_pitching': '0回無安打無失点(無四球0奪三振)',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('DeNA'), findsOneWidget);
    expect(find.text('東克樹'), findsWidgets);
    expect(find.text('工藤泰己'), findsWidgets);
    expect(find.text('成瀬脩人'), findsOneWidget);
    expect(find.text('菊池涼介'), findsOneWidget);
    // 活躍選手のみでは先発と勝敗HS以外の投手は出さない。
    expect(find.text('中川虎大'), findsNothing);
    expect(find.text('6.1回3失点'), findsOneWidget);
    expect(find.text('5回2失点'), findsOneWidget);
    expect(find.text('0.2回無失点'), findsNothing);
    expect(find.text('1打数1安打(1HR1打点1四球)'), findsNothing);
    expect(find.text('11号,12号'), findsNothing);
    expect(find.text('2打数1安打(1打点1四球1犠打)'), findsNothing);
    expect(find.text('1打数無安打(1打点)'), findsNothing);
    expect(find.text('勝'), findsOneWidget);
    expect(find.text('HR'), findsOneWidget);
    final hrMark = tester.getCenter(find.text('HR').first);
    final hrBatter = tester.getCenter(find.text('成瀬脩人').first);
    expect(hrMark.dx, lessThan(hrBatter.dx));
    expect(hrMark.dy, closeTo(hrBatter.dy, 2.0));
    final hrBadge = tester.widget<Container>(
      find.ancestor(of: find.text('HR'), matching: find.byType(Container)).first,
    );
    expect((hrBadge.decoration as BoxDecoration).color, const Color(0xFFDC143C));
    expect(find.text('本'), findsOneWidget);
    expect(find.text('安'), findsOneWidget);
    final predictHon = tester.widget<Container>(
      find.ancestor(of: find.text('本'), matching: find.byType(Container)).first,
    );
    expect((predictHon.decoration as BoxDecoration).color, const Color(0xFFF44336));
    final predictAn = tester.widget<Container>(
      find.ancestor(of: find.text('安'), matching: find.byType(Container)).first,
    );
    expect((predictAn.decoration as BoxDecoration).color, const Color(0xFF0000FF));

    final homeStat = tester.widget<Text>(find.text('6.1回3失点').first);
    expect(homeStat.overflow, isNot(TextOverflow.ellipsis));
    final nameWidget = tester.widget<Text>(find.text('東克樹').first);
    expect(nameWidget.overflow, isNot(TextOverflow.ellipsis));
    final namePainter = TextPainter(
      text: TextSpan(text: '東克樹', style: nameWidget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    expect(tester.getSize(find.text('東克樹').first).width, greaterThanOrEqualTo(namePainter.width - 0.5));

    double columnWidth(Finder text) {
      return tester.getSize(find.ancestor(of: text, matching: find.byType(Container)).first).width;
    }

    expect(find.text('8回表'), findsOneWidget);
    expect(
      tester.getRect(find.text('8回表')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('2 - 3')).top + 0.5),
    );

    final homeColumn = columnWidth(find.text('DeNA').first);
    final scoreColumn = columnWidth(find.text('2 - 3'));
    final awayColumn = columnWidth(find.text('広島').first);
    final centerHeader = columnWidth(find.text('投手'));
    expect(awayColumn, closeTo(homeColumn, 2));
    expect(scoreColumn, greaterThan(170));
    expect(centerHeader, lessThan(scoreColumn));
    expect(centerHeader, lessThan(48));
    expect(centerHeader, greaterThan(24));
    expect(columnWidth(find.text('打者')), closeTo(centerHeader, 1));

    final boardRect = tester.getRect(find.byType(GamesBoardYahooStyle));
    expect(tester.getRect(find.text('東克樹').first).bottom, lessThanOrEqualTo(boardRect.bottom + 0.5));
    expect(tester.getRect(find.text('成瀬脩人').first).bottom, lessThanOrEqualTo(boardRect.bottom + 16));

    final timeTop = tester.getTopLeft(find.textContaining('🌙 18:00').first).dy;
    final pitcherTop = tester.getTopLeft(find.text('投手').first).dy;
    expect(pitcherTop - timeTop, greaterThanOrEqualTo(40));

    final homeStatX = tester.getTopLeft(find.text('6.1回3失点').first).dx;
    final awayStatX = tester.getTopLeft(find.text('5回2失点').first).dx;
    expect(homeStatX, isNot(awayStatX));

    final predictX = tester.getTopLeft(find.text('本').first).dx;
    final batterNameRight = tester.getTopRight(find.text('成瀬脩人').first).dx;
    expect(predictX, greaterThan(batterNameRight));
    expect(tester.getTopLeft(find.text('安').first).dx, greaterThan(tester.getTopRight(find.text('本').first).dx - 0.5));
    expect(homeStatX, closeTo(predictX, 6));

    final nameRight = tester.getTopRight(find.text('東克樹').first).dx;
    expect(homeStatX, greaterThan(nameRight + 3));
    expect(
      tester.getRect(find.text('東克樹').first).overlaps(tester.getRect(find.text('6.1回3失点').first)),
      isFalse,
    );

    final homePitcherX = tester.getTopLeft(find.text('東克樹').first).dx;
    final homeBatterX = tester.getTopLeft(find.text('成瀬脩人').first).dx;
    expect(homePitcherX, closeTo(homeBatterX, 1.0));
    final awayPitcherX = tester.getTopLeft(find.text('工藤泰己').first).dx;
    final awayBatterX = tester.getTopLeft(find.text('菊池涼介').first).dx;
    expect(awayPitcherX, closeTo(awayBatterX, 1.0));

    final statsScrolls = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(statsScrolls, findsWidgets);

    final longBefore = tester.getTopLeft(find.text('6.1回3失点').first).dx;
    final nameBefore = tester.getTopLeft(find.text('東克樹').first).dx;
    await tester.drag(statsScrolls.first, const Offset(-60, 0));
    await tester.pump();
    final longAfter = tester.getTopLeft(find.text('6.1回3失点').first).dx;
    expect(longAfter, lessThan(longBefore - 1));
    expect(tester.getTopLeft(find.text('東克樹').first).dx, closeTo(nameBefore, 0.5));
  });

  test('same matchup rows collapse to one game', () {
    final rows = List.generate(
      8,
      (i) => <String, dynamic>{
        'date_game': '2026-09-28',
        'name_team_home': 'DeNA',
        'name_team_away': '広島',
        'id_team_home': i.isEven ? 5 : 5.0,
        'id_team_away': '6',
        'name_full_summary': '選手$i',
      },
    );
    final grouped = groupGamesByMatchup(rows);
    expect(grouped, hasLength(1));
    expect(grouped.first, hasLength(8));

    final nested = normalizeGames(rows);
    expect(nested, hasLength(1));
    expect(nested.first['name_team_home'], 'DeNA');
    expect((nested.first['summaries'] as List), hasLength(8));
    expect(groupGamesByMatchup(nested), hasLength(1));
  });

  testWidgets('nested summaries still render as one card', (tester) async {
    final nested = normalizeGames(
      List.generate(
        8,
        (i) => <String, dynamic>{
          'date_game': '2026-09-28',
          'time_game': '🌙 18:00',
          'name_team_home': 'DeNA',
          'name_team_away': '広島',
          'name_stadium': '横浜',
          'name_pitcher_home': '東克樹',
          'name_pitcher_away': '工藤泰己',
          'score_home': 2,
          'score_away': 3,
          'state': '8回表',
          'id_team_home': 5,
          'id_team_away': 6,
          'id_team_summary': i < 4 ? 5 : 6,
          'name_full_summary': '選手$i',
          'flg_pitcher': i.isEven,
          'color_back_home': '#0066FF',
          'color_back_away': 'red',
          'color_font_home': 'white',
          'color_font_away': 'black',
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 160,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: nested,
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('DeNA'), findsOneWidget);
    expect(find.text('広島'), findsOneWidget);
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

    await tester.tap(find.text('<< 前の日'));
    await tester.pump();
    expect(find.textContaining('昨日'), findsOneWidget);

    await tester.tap(find.text('次の日 >>'));
    await tester.pump();
    expect(find.textContaining('今日'), findsOneWidget);

    await tester.tap(find.text('次の日 >>'));
    await tester.pump();
    expect(find.textContaining('明日'), findsOneWidget);

    await tester.tap(find.text('<< 前の日'));
    await tester.pump();
    expect(find.textContaining('今日'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NPB and MLB date switchers keep their own day', (tester) async {
    var npbOffset = -1;
    var mlbOffset = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Column(
              children: [
                SizedBox(
                  width: 400,
                  height: 90,
                  child: GameDateSwitcher(
                    games: const [],
                    headerColor: Colors.red,
                    initialDate: '2026-10-07',
                    dateOffset: npbOffset,
                    onDateOffsetChanged: (offset) => npbOffset = offset,
                  ),
                ),
                SizedBox(
                  width: 400,
                  height: 90,
                  child: GameDateSwitcher(
                    games: const [],
                    headerColor: Colors.blue,
                    initialDate: '2026-10-07',
                    dateOffset: mlbOffset,
                    onDateOffsetChanged: (offset) => mlbOffset = offset,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    expect(find.textContaining('昨日'), findsOneWidget);
    expect(find.textContaining('明日'), findsOneWidget);

    await tester.tap(find.text('<< 前の日').last);
    await tester.pump();
    expect(npbOffset, -1);
    expect(mlbOffset, 0);
    expect(find.textContaining('昨日'), findsOneWidget);
    expect(find.textContaining('今日'), findsOneWidget);
  });

  testWidgets('previous day outside the loaded window asks for SQL', (tester) async {
    final needed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 180,
          child: GameDateSwitcher(
            games: const [],
            headerColor: Colors.green,
            initialDate: '2026-10-07',
            shouldLoadGameDate: (date) => date.isBefore(DateTime(2026, 10, 4)),
            onNeedGameDate: (date) async {
              needed.add(
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('<< 前の日'));
    await tester.pump();
    await tester.tap(find.text('<< 前の日'));
    await tester.pump();
    await tester.tap(find.text('<< 前の日'));
    await tester.pump();
    expect(needed, isEmpty);

    await tester.tap(find.text('<< 前の日'));
    await tester.pump();
    expect(needed, ['2026-10-03']);
    expect(find.textContaining('4日前'), findsOneWidget);
  });

  testWidgets('tournament leading stays visible while games are still loading', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 360,
          child: BothLeagueGameDay(
            games: [],
            initialDate: '2026-10-07',
            loadingGames: true,
            leading: [Text('トーナメント')],
          ),
        ),
      ),
    );

    expect(find.text('トーナメント'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('この日の試合はありません'), findsNothing);
  });

  testWidgets('previous day shows loaded games instead of the empty label', (tester) async {
    var games = <Map<String, dynamic>>[
      {
        'date_game': '2026-10-07',
        'time_game': '18:00',
        'name_team_home': '阪神',
        'name_team_away': '巨人',
        'name_stadium': '甲子園',
        'name_pitcher_home': '村上',
        'name_pitcher_away': '戸郷',
        'score_home': 3,
        'score_away': 1,
        'state': '試合終了',
        'id_team_home': 2,
        'id_team_away': 1,
        'id_league_home': 1,
        'id_league_away': 1,
        'color_back_home': '#FFD200',
        'color_back_away': '#FF6600',
        'color_font_home': '#000000',
        'color_font_away': '#000000',
      },
    ];
    Future<void> Function(DateTime date)? loadDate;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 420,
          height: 360,
          child: StatefulBuilder(
            builder: (context, setState) {
              loadDate = (date) async {
                setState(() {
                  games = [
                    ...games,
                    {
                      'date_game': '2026-10-06',
                      'time_game': '18:00',
                      'name_team_home': '広島',
                      'name_team_away': '阪神',
                      'name_stadium': 'マツダ',
                      'name_pitcher_home': '森下',
                      'name_pitcher_away': '才木',
                      'score_home': 2,
                      'score_away': 4,
                      'state': '試合終了',
                      'id_team_home': 5,
                      'id_team_away': 2,
                      'id_league_home': 1,
                      'id_league_away': 1,
                      'color_back_home': '#E50012',
                      'color_back_away': '#FFD200',
                      'color_font_home': '#FFFFFF',
                      'color_font_away': '#000000',
                    },
                  ];
                });
              };
              return BothLeagueGameDay(
                games: games,
                initialDate: '2026-10-07',
                shouldLoadGameDate: (date) => date == DateTime(2026, 10, 6),
                onNeedGameDate: (date) => loadDate!(date),
                leagues: const [
                  (id: 1, name: 'セ・リーグ', color: Color(0xFF0E8E2D)),
                  (id: 2, name: 'パ・リーグ', color: Color(0xFF01B1EA)),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('<< 前の日'));
    await tester.pump();
    expect(find.text('この日の試合はありません'), findsNothing);
    expect(find.text('広島'), findsOneWidget);
    expect(find.text('阪神'), findsOneWidget);
  });

  testWidgets('interleague-only days still show the games', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 420,
          height: 360,
          child: BothLeagueGameDay(
            games: [
              {
                'date_game': '2026-10-07',
                'time_game': '18:00',
                'name_team_home': '阪神',
                'name_team_away': 'ソフトバンク',
                'name_stadium': '甲子園',
                'name_pitcher_home': '村上',
                'name_pitcher_away': '有原',
                'score_home': 3,
                'score_away': 2,
                'state': '試合終了',
                'id_team_home': 2,
                'id_team_away': 7,
                'id_league_home': 1,
                'id_league_away': 2,
                'color_back_home': '#FFD200',
                'color_back_away': '#FFD200',
                'color_font_home': '#000000',
                'color_font_away': '#000000',
              },
            ],
            initialDate: '2026-10-07',
            leagues: [
              (id: 1, name: 'セ・リーグ', color: Color(0xFF0E8E2D)),
              (id: 2, name: 'パ・リーグ', color: Color(0xFF01B1EA)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('この日の試合はありません'), findsNothing);
    expect(find.text('交流戦'), findsOneWidget);
    expect(find.text('阪神'), findsOneWidget);
    expect(find.text('ソフトバンク'), findsOneWidget);
  });

  testWidgets('unstarted games stay side by side', (tester) async {
    Map<String, dynamic> game(String home) => {
          'date_game': '2026-09-29',
          'time_game': '🌙 18:00',
          'name_team_home': home,
          'name_team_away': 'ヤクルト',
          'name_stadium': '東京ドーム',
          'name_pitcher_home': '先発$home',
          'name_pitcher_away': '先発ヤクルト',
          'score_home': -1,
          'score_away': -1,
          'state': '',
          'id_team_home': home == '巨人' ? 1 : 2,
          'id_team_away': 4,
          'color_back_home': 'orange',
          'color_back_away': 'midnightblue',
          'color_font_home': 'black',
          'color_font_away': 'white',
        };

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 120,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [game('巨人'), game('阪神')],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final giants = tester.getTopLeft(find.text('巨人').first);
    final tigers = tester.getTopLeft(find.text('阪神').first);
    expect(giants.dx, lessThan(tigers.dx));
    expect(giants.dy, closeTo(tigers.dy, 1.0));

    final homeName = tester.getCenter(find.text('先発巨人'));
    final homeTeam = tester.getCenter(find.text('巨人').first);
    expect(homeName.dx, closeTo(homeTeam.dx, 28.0));
    final awayName = tester.getCenter(find.text('先発ヤクルト').first);
    final awayTeam = tester.getCenter(find.text('ヤクルト').first);
    expect(awayName.dx, closeTo(awayTeam.dx, 28.0));
  });

  testWidgets('short era title 防 colors the era season chip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            height: 280,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-04',
                  'time_game': '18:00',
                  'name_team_home': 'ヤクルト',
                  'name_team_away': '広島',
                  'name_stadium': '神宮',
                  'name_pitcher_home': '吉村貢司郎',
                  'name_pitcher_away': '栗林良吏',
                  'titles_pitcher_away': '防|red',
                  'txt_season_pitcher_home': '4勝12敗 4.98 87奪三振 規定到達率78.0%',
                  'txt_season_pitcher_away': '7勝6敗 2.68 100奪三振 規定到達率83.6%',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '',
                  'id_team_home': 4,
                  'id_team_away': 6,
                  'color_back_home': 'green',
                  'color_back_away': 'red',
                  'color_font_home': 'white',
                  'color_font_away': 'black',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final eraValue = tester.getCenter(find.text('2.68'));
    Finder eraLabel = find.text('防御率').at(0);
    var nearest = 1000.0;
    for (var i = 0; i < find.text('防御率').evaluate().length; i++) {
      final center = tester.getCenter(find.text('防御率').at(i));
      if (center.dx > eraValue.dx) continue;
      final gap = (center.dy - eraValue.dy).abs() + (eraValue.dx - center.dx) / 1000;
      if (gap < nearest) {
        nearest = gap;
        eraLabel = find.text('防御率').at(i);
      }
    }
    final chip = tester.widget<Container>(find.ancestor(of: eraLabel, matching: find.byType(Container)).first);
    expect((chip.decoration as BoxDecoration).color, const Color(0xFFF44336));
  });

  testWidgets('unstarted starters show season stats under the name and user color on the label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            height: 280,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-02',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '村上頌樹',
                  'name_pitcher_away': '戸郷翔征',
                  'titles_pitcher_home': 'QS|#E53935',
                  'titles_pitcher_away': 'HQS|#1565C0',
                  'txt_season_pitcher_home': '10勝5敗 1.85 142奪三振 規定98.2%',
                  'txt_season_pitcher_away': '8勝7敗 2.41 128奪三振 規定123.4%',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('試合前'), findsOneWidget);
    expect(find.text('勝敗'), findsNWidgets(2));
    expect(find.text('防御率'), findsNWidgets(2));
    expect(find.text('奪三振'), findsNWidgets(2));
    expect(find.text('規定到達率'), findsNWidgets(2));
    expect(find.text('10勝5敗'), findsOneWidget);
    expect(find.text('1.85'), findsOneWidget);
    expect(find.text('142'), findsOneWidget);
    expect(find.text('98.2%'), findsOneWidget);
    expect(find.text('123.4%'), findsOneWidget);
    expect(find.text('QS'), findsNothing);
    expect(find.text('HQS'), findsNothing);
    expect(find.text('打者'), findsNothing);
    expect(tester.getTopLeft(find.text('10勝5敗')).dy, greaterThan(tester.getBottomLeft(find.text('村上頌樹')).dy + 2));
    Finder labelNear(String value) {
      final record = tester.getCenter(find.text(value));
      Finder nearestLabel = find.text('勝敗').at(0);
      var nearest = 1000.0;
      for (var i = 0; i < 2; i++) {
        final center = tester.getCenter(find.text('勝敗').at(i));
        if (center.dx > record.dx) continue;
        final gap = (center.dy - record.dy).abs() + (record.dx - center.dx) / 1000;
        if (gap < nearest) {
          nearest = gap;
          nearestLabel = find.text('勝敗').at(i);
        }
      }
      return nearestLabel;
    }

    final winsLabel = labelNear('10勝5敗');
    final awayLabel = labelNear('8勝7敗');
    Container chipOf(Finder label) => tester.widget<Container>(find.ancestor(of: label, matching: find.byType(Container)).first);
    final homeChip = chipOf(winsLabel);
    final awayChip = chipOf(awayLabel);
    expect(tester.getTopRight(winsLabel).dx, lessThan(tester.getTopLeft(find.text('10勝5敗')).dx + 1));
    expect(tester.getTopLeft(find.text('1.85')).dy, greaterThan(tester.getBottomLeft(find.text('10勝5敗')).dy - 1));
    expect(tester.widget<Text>(winsLabel).style?.color, Colors.white);
    expect((homeChip.decoration as BoxDecoration).color, const Color(0xFFE53935));
    expect((awayChip.decoration as BoxDecoration).color, const Color(0xFF1565C0));
    final homeChipRect = tester.getRect(find.ancestor(of: winsLabel, matching: find.byType(Container)).first);
    expect(tester.getCenter(winsLabel).dx, closeTo(homeChipRect.center.dx, 1));
    Finder rateNear(Finder label) {
      final origin = tester.getCenter(label);
      Finder nearestRate = find.text('規定到達率').at(0);
      var nearest = 1000.0;
      for (var i = 0; i < 2; i++) {
        final center = tester.getCenter(find.text('規定到達率').at(i));
        final gap = (center.dy - origin.dy).abs() + (center.dx - origin.dx).abs() / 1000;
        if (gap < nearest) {
          nearest = gap;
          nearestRate = find.text('規定到達率').at(i);
        }
      }
      return nearestRate;
    }

    final rateRect = tester.getRect(find.ancestor(of: rateNear(winsLabel), matching: find.byType(Container)).first);
    expect(rateRect.width, greaterThan(20));
    expect(homeChipRect.width, greaterThan(20));
    final teamLogo = find.byWidgetPredicate((widget) {
      if (widget is! Image) return false;
      final provider = widget.image;
      return provider is AssetImage && provider.assetName.contains('team_');
    });
    expect(teamLogo, findsWidgets);
  });

  testWidgets('スタメン starters still show season pitcher stats', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            height: 280,
            child: GamesBoardYahooStyle(
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '☀️ 07:00',
                  'name_team_home': 'ブレーブス',
                  'name_team_away': 'ドジャース',
                  'name_stadium': 'トゥルーイストパーク',
                  'name_pitcher_home': 'クリス・セール',
                  'name_pitcher_away': '山本　由伸',
                  'txt_season_pitcher_home': '1勝1敗 4.50 12奪三振 規定到達率20.0%',
                  'txt_season_pitcher_away': '14勝9敗 2.53 182奪三振 規定到達率114.2%',
                  'score_home': -1,
                  'score_away': -1,
                  'state': 'スタメン',
                  'code_game': 'DS',
                  'id_team_home': 144,
                  'id_team_away': 119,
                  'color_back_home': '#CE1141',
                  'color_back_away': '#005A9C',
                  'color_font_home': 'white',
                  'color_font_away': 'white',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('試合前'), findsOneWidget);
    expect(find.text('スタメン'), findsNothing);
    expect(find.textContaining('山本'), findsWidgets);
    expect(find.text('14勝9敗'), findsOneWidget);
    expect(find.text('2.53'), findsOneWidget);
    expect(find.text('182'), findsOneWidget);
    expect(find.text('114.2%'), findsOneWidget);
    expect(find.text('勝敗'), findsNWidgets(2));
    expect(find.text('防御率'), findsNWidgets(2));
    expect(find.text('詳細表示'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('pregame score logos sit beside the 試合前 label at 80% cell height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '18:00',
                  'name_team_home': 'ヤクルト',
                  'name_team_away': '巨人',
                  'name_stadium': '神宮',
                  'name_pitcher_home': '吉村貢司郎',
                  'name_pitcher_away': '戸郷翔征',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '試合前',
                  'id_team_home': 4,
                  'id_team_away': 1,
                  'color_back_home': '#1D4E89',
                  'color_back_away': '#F15A22',
                  'color_font_home': 'white',
                  'color_font_away': 'black',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final state = tester.getRect(find.text('試合前'));
    final vs = tester.getRect(find.text('vs'));
    final homeLogo = tester.getRect(find.byWidgetPredicate((widget) {
      if (widget is! Image) return false;
      final provider = widget.image;
      return provider is AssetImage && provider.assetName == 'backend/assets/images/team_s.png';
    }).first);
    final awayLogo = tester.getRect(find.byWidgetPredicate((widget) {
      if (widget is! Image) return false;
      final provider = widget.image;
      return provider is AssetImage && provider.assetName == 'backend/assets/images/team_g.png';
    }).first);
    expect(state.left - homeLogo.right, inInclusiveRange(2, 28));
    expect(awayLogo.left - state.right, inInclusiveRange(2, 28));
    expect(vs.center.dx, closeTo(state.center.dx, 2));
    expect(homeLogo.height, closeTo(vs.height > 20 ? vs.height : homeLogo.height, 40));
    expect(homeLogo.height / 46.0, closeTo(0.8, 0.15));
  });

  testWidgets('finished game state cell is about twice the old score-on-board height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 520,
            height: 320,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '18:00',
                  'name_team_home': 'ヤクルト',
                  'name_team_away': '巨人',
                  'name_stadium': '神宮',
                  'name_pitcher_home': '吉村貢司郎',
                  'name_pitcher_away': '戸郷翔征',
                  'score_home': 3,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 4,
                  'id_team_away': 1,
                  'color_back_home': '#1D4E89',
                  'color_back_away': '#F15A22',
                  'color_font_home': 'white',
                  'color_font_away': 'black',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('試合終了'), findsOneWidget);
    final homeLogo = tester.getRect(find.byWidgetPredicate((widget) {
      if (widget is! Image) return false;
      final provider = widget.image;
      return provider is AssetImage && provider.assetName == 'backend/assets/images/team_s.png';
    }).first);
    expect(homeLogo.height, closeTo(44 * 0.8, 6));
  });

  testWidgets('starter season ranks show beside wins era and strikeouts when qualified', (tester) async {
    Map<String, dynamic> stat(String title, String name, int rank) {
      return {'title': title, 'name_player': name, 'int_rank': rank, 'id_league': 1};
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 520,
            height: 320,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              playerStats: [
                stat('最多勝', '村上頌樹', 3),
                stat('防御率', '村上頌樹', 2),
                stat('奪三振', '村上頌樹', 21),
                stat('最多勝', '戸郷翔征', 8),
                stat('防御率', '戸郷翔征', 4),
                stat('奪三振', '戸郷翔征', 1),
              ],
              games: [
                {
                  'date_game': '2026-10-04',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '村上頌樹',
                  'name_pitcher_away': '戸郷翔征',
                  'id_league_home': 1,
                  'id_league_away': 1,
                  'txt_season_pitcher_home': '10勝5敗 1.85 142奪三振 規定98.2%',
                  'txt_season_pitcher_away': '8勝7敗 2.41 128奪三振 規定123.4%',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '',
                  'id_team_home': 2,
                  'id_team_away': 1,
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('10勝5敗（リーグ3位）'), findsOneWidget);
    expect(find.textContaining('1.85（リーグ'), findsNothing);
    expect(find.textContaining('142（リーグ'), findsNothing);
    expect(find.textContaining('98.2%（リーグ'), findsNothing);
    expect(find.textContaining('8勝7敗（リーグ8位）'), findsOneWidget);
    expect(find.textContaining('2.41（リーグ4位）'), findsOneWidget);
    expect(find.textContaining('128（リーグ'), findsNothing);
    expect(find.textContaining('128'), findsOneWidget);
    expect(find.text('👑'), findsOneWidget);
    expect(find.textContaining('123.4%（リーグ'), findsNothing);
  });

  testWidgets('hold and save show prediction marks beside the pitching line', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 520,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-03',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '村上頌樹',
                  'name_pitcher_away': '戸郷翔征',
                  'score_home': 3,
                  'score_away': 2,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'id_team_summary': 2,
                  'name_full_summary': '岩崎優',
                  'flg_pitcher': true,
                  'code_result_pitcher': 'HOLD',
                  'txt_pitching': '1回無失点',
                  'titles_predict': 'HP|#43A047',
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                },
                {
                  'date_game': '2026-10-03',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '村上頌樹',
                  'name_pitcher_away': '戸郷翔征',
                  'score_home': 3,
                  'score_away': 2,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'id_team_summary': 1,
                  'name_full_summary': '大勢',
                  'flg_pitcher': true,
                  'code_result_pitcher': 'SAVE',
                  'txt_pitching': '1回無失点',
                  'titles_predict': 'SV|#1565C0',
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('HP'), findsOneWidget);
    expect(find.text('SV'), findsOneWidget);
    final homeLine = find.text('1回無失点').at(0);
    final awayLine = find.text('1回無失点').at(1);
    expect(tester.getTopLeft(find.text('HP')).dx, greaterThan(tester.getTopRight(homeLine).dx - 0.5));
    expect(tester.getCenter(find.text('HP')).dy, closeTo(tester.getCenter(homeLine).dy, 6));
    expect(tester.getTopLeft(find.text('SV')).dx, greaterThan(tester.getTopRight(awayLine).dx - 0.5));
  });

  testWidgets('started games stack and keep player text readable', (tester) async {
    Map<String, dynamic> game(String home, int teamId) => {
          'date_game': '2026-09-28',
          'time_game': '🌙 18:00',
          'name_team_home': home,
          'name_team_away': '広島',
          'name_stadium': '横浜',
          'name_pitcher_home': '先発$home',
          'name_pitcher_away': '先発広島',
          'score_home': 2,
          'score_away': 3,
          'state': '8回表',
          'id_team_home': teamId,
          'id_team_away': 6,
          'id_team_summary': teamId,
          // 活躍選手のみでは先発（または勝敗HS）だけ出す。
          'name_full_summary': '先発$home',
          'flg_pitcher': true,
          'txt_pitching': '6.1回8安打3失点(3四球3奪三振119球)',
          'color_back_home': '#0066FF',
          'color_back_away': 'red',
          'color_font_home': 'white',
          'color_font_away': 'black',
        };

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [game('DeNA', 5), game('阪神', 2)],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final dena = tester.getTopLeft(find.text('DeNA').first);
    final tigers = tester.getTopLeft(find.text('阪神').first);
    expect(dena.dy, lessThan(tigers.dy));
    expect(find.byType(SingleChildScrollView), findsWidgets);

    final nameStyle = tester.widget<Text>(find.text('先発DeNA').first).style;
    expect(nameStyle?.fontSize, greaterThanOrEqualTo(8));
  });

  testWidgets('narrow cards keep full player names and clip stats', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            height: 180,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-09-28',
                  'time_game': '🌙 18:00',
                  'name_team_home': '巨人',
                  'name_team_away': '広島',
                  'name_stadium': '東京ドーム',
                  'name_pitcher_home': '小笠原慎之介',
                  'name_pitcher_away': '先発広島',
                  'score_home': 2,
                  'score_away': 3,
                  'state': '8回表',
                  'id_team_home': 1,
                  'id_team_away': 6,
                  'id_team_summary': 1,
                  'name_full_summary': '小笠原慎之介',
                  'flg_pitcher': true,
                  'txt_pitching': '6.1回8安打3失点(3四球3奪三振119球)',
                  'color_back_home': '#0066FF',
                  'color_back_away': 'red',
                  'color_font_home': 'white',
                  'color_font_away': 'black',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final nameText = tester.widget<Text>(find.text('小笠原慎之介').first);
    final painter = TextPainter(
      text: TextSpan(text: '小笠原慎之介', style: nameText.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    expect(tester.getSize(find.text('小笠原慎之介').first).width, greaterThanOrEqualTo(painter.width - 0.5));

    final nameRight = tester.getTopRight(find.text('小笠原慎之介').first).dx;
    final statFinder = find.text('6.1回3失点', skipOffstage: false);
    final statLeft = tester.getTopLeft(statFinder).dx;
    expect(statLeft, greaterThan(nameRight));
    expect(
      tester.getRect(find.text('小笠原慎之介').first).overlaps(tester.getRect(statFinder)),
      isFalse,
    );
  });

  test('settled central and pacific games stop game refresh and finished games allow stats', () {
    Map<String, dynamic> game({
      required int homeLeague,
      required int awayLeague,
      required String state,
      required String id,
    }) =>
        {
          'date_game': '2026-09-29',
          'id_game': id,
          'id_league_home': homeLeague,
          'id_league_away': awayLeague,
          'state': state,
          'name_team_home': 'home$id',
          'name_team_away': 'away$id',
        };

    final playing = [
      game(homeLeague: 1, awayLeague: 1, state: '8回表', id: '1'),
      game(homeLeague: 2, awayLeague: 2, state: '試合終了', id: '2'),
    ];
    expect(centralPacificGamesAreSettled(playing, '2026-09-29'), isFalse);
    expect(centralPacificGamesAllFinished(playing, '2026-09-29'), isFalse);

    final cancelled = [
      game(homeLeague: 1, awayLeague: 1, state: '試合終了', id: '1'),
      game(homeLeague: 2, awayLeague: 2, state: '試合中止', id: '2'),
    ];
    expect(centralPacificGamesAreSettled(cancelled, '2026-09-29'), isTrue);
    expect(centralPacificGamesAllFinished(cancelled, '2026-09-29'), isFalse);

    final finished = [
      game(homeLeague: 1, awayLeague: 1, state: '試合終了', id: '1'),
      game(homeLeague: 2, awayLeague: 2, state: '試合終了', id: '2'),
      game(homeLeague: 1, awayLeague: 1, state: '試合前', id: '3')..['date_game'] = '2026-09-30',
    ];
    expect(centralPacificGamesAreSettled(finished, '2026-09-29'), isTrue);
    expect(centralPacificGamesAllFinished(finished, '2026-09-29'), isTrue);
    expect(centralPacificGamesAreSettled(const [], '2026-09-29'), isFalse);
  });

  testWidgets('batting results line up to the right of the player name', (tester) async {
    const plays = '一ゴ|out 犠打|sacbunt 四球|walk スクイズ|squeeze 犠飛|sacfly 中安|single 左2|double 右3|triple 8回裏先制2点タイムリーツーベース|timely 1回表代打逆転サヨナラ19号ソロホームラン|hr';
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 520,
            height: 160,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-09-30',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': 'ヤクルト',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '髙橋遥人',
                  'name_pitcher_away': '奥川恭伸',
                  'score_home': 5,
                  'score_away': 0,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 4,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#003366',
                  'color_font_home': '#000000',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 2,
                      'name_full_summary': '大山悠輔',
                      'flg_pitcher': false,
                      'txt_batting': '4打数2安打(1HR1打点)',
                      'txt_plays': plays,
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('4打数2安打(1HR1打点)'), findsNothing);
    expect(find.text('19号代打逆転サヨナラソロホームラン'), findsOneWidget);
    expect(find.textContaining('^'), findsNothing);
    expect(find.text('先制2点タイムリーツーベース'), findsOneWidget);
    expect(find.text('右３'), findsOneWidget);
    expect(find.text('左２'), findsOneWidget);
    expect(find.text('中安'), findsOneWidget);
    expect(find.text('一ゴ'), findsNothing);
    expect(find.text('犠飛'), findsOneWidget);
    expect(find.text('スクイズ'), findsOneWidget);
    expect(find.text('四球'), findsNothing);
    expect(find.text('犠打'), findsOneWidget);

    Color backgroundOf(String label) {
      final chip = tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
      );
      return (chip.decoration as BoxDecoration).color!;
    }

    expect(backgroundOf('19号代打逆転サヨナラソロホームラン'), const Color(0xFFDC143C));
    expect(backgroundOf('先制2点タイムリーツーベース'), const Color(0xFFFF5722));
    expect(backgroundOf('右３'), const Color(0xFFFFB300));
    expect(backgroundOf('左２'), const Color(0xFFFFB300));
    expect(tester.widget<Text>(find.text('左２')).style?.color, Colors.black87);
    expect(tester.widget<Text>(find.text('右３')).style?.color, Colors.black87);
    expect(backgroundOf('中安'), const Color(0xFFFFEB3B));
    expect(backgroundOf('犠飛'), const Color(0xFF8E24AA));
    expect(backgroundOf('スクイズ'), const Color(0xFF8E24AA));
    expect(backgroundOf('犠打'), const Color(0xFF8E24AA));

    final nameRight = tester.getTopRight(find.text('大山悠輔')).dx;
    final labels = ['犠打', 'スクイズ', '犠飛', '中安', '左２', '右３', '先制2点タイムリーツーベース', '19号代打逆転サヨナラソロホームラン'];
    var previousRight = nameRight;
    for (final label in labels) {
      final left = tester.getTopLeft(find.text(label)).dx;
      expect(left, greaterThan(previousRight - 0.5));
      expect((tester.getCenter(find.text(label)).dy - tester.getCenter(find.text('大山悠輔')).dy).abs(), lessThan(1.0));
      previousRight = tester.getTopRight(find.text(label)).dx;
    }
  });

  testWidgets('all batters mode shortens outs, homers, and timely hits', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 420,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-03',
                  'time_game': '🌙 18:00',
                  'name_team_home': 'ロッテ',
                  'name_team_away': 'ソフトバンク',
                  'name_stadium': 'ZOZOマリン',
                  'name_pitcher_home': '高野脩汰',
                  'name_pitcher_away': '松本晴',
                  'score_home': 2,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 12,
                  'id_team_away': 7,
                  'id_team_summary': 7,
                  'name_full_summary': '柳田悠岐',
                  'flg_pitcher': false,
                  'txt_plays': '二併殺|out 三ポップ|out 8回裏タイムリーツーベース^中|timely 2回表先制ソロホームラン^右|hr',
                  'txt_scores_away': '0,1,0,0,0,0,0,0,0',
                  'txt_scores_home': '0,0,0,0,0,0,0,1,1x',
                  'int_runs_away': 1,
                  'int_runs_home': 2,
                  'int_hit_away': 5,
                  'int_hit_home': 6,
                  'int_error_away': 0,
                  'int_error_home': 0,
                  'lineup': [
                    {
                      'id_team': 7,
                      'order': 5,
                      'players': [
                        {
                          'name': '柳田悠岐',
                          'pos': '指',
                          'rbi': 2,
                          'plays': '二併殺|out 三ポップ|out 8回裏タイムリーツーベース^中|timely 2回表先制ソロホームラン^右|hr',
                        },
                      ],
                    },
                    {
                      'id_team': 7,
                      'order': 6,
                      'players': [
                        {'name': '周東佑京', 'pos': '遊', 'role': '代打', 'plays': '', 'rbi': 0},
                      ],
                    },
                    {
                      'id_team': 7,
                      'order': 7,
                      'players': [
                        {'name': '柳町達', 'pos': '中', 'plays': ''},
                      ],
                    },
                    {
                      'id_team': 7,
                      'order': 8,
                      'players': [
                        {'name': '甲斐拓也', 'pos': '捕', 'plays': ''},
                      ],
                    },
                    {
                      'id_team': 7,
                      'order': 9,
                      'players': [
                        {'name': '松本晴', 'pos': '投', 'plays': ''},
                      ],
                    },
                  ],
                  'color_back_home': '#000000',
                  'color_back_away': '#FFD200',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#000000',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('先制ソロホームラン'), findsOneWidget);
    expect(find.text('タイムリーツーベース'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('2打点'), findsNothing);
    expect(find.byKey(const ValueKey('rbi-badge-1')), findsWidgets);

    expect(find.text('詳細表示'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    final roster = tester.getRect(find.text('詳細表示'));
    final statsHeader = tester.getRect(find.text('選手成績'));
    final venue = tester.getRect(find.textContaining('ZOZOマリン'));
    final board = tester.getRect(find.byType(GamesBoardYahooStyle));
    final timeRect = tester.getRect(find.textContaining('🌙 18:00').first);
    expect(timeRect.left, lessThan(venue.left));
    expect(timeRect.left, closeTo(board.left + 4, 12));
    expect(roster.top, greaterThan(statsHeader.bottom - 1));
    expect(roster.top, lessThan(statsHeader.bottom + 24));
    expect(roster.left, lessThan(board.center.dx));

    await tester.tap(find.text('詳細表示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('二併'), findsOneWidget);
    expect(find.text('三邪'), findsOneWidget);
    expect(find.text('2打点'), findsNothing);
    expect(find.text('代打：周東佑京'), findsOneWidget);
    expect(find.byKey(const ValueKey('pinch-badge')), findsNothing);
    expect(
      (tester.widget<Container>(find.byKey(const ValueKey('pinch-caption-0'))).decoration as BoxDecoration).color,
      const Color(0xFF5C6BC0),
    );
    expect(find.byKey(const ValueKey('rbi-badge-1')), findsWidgets);
    expect(find.text('中２'), findsOneWidget);
    expect(find.text('右本'), findsOneWidget);
    expect(find.text('二併殺'), findsNothing);
    expect(find.text('三ポップ'), findsNothing);
    expect(find.text('先制ソロホームラン'), findsNothing);
    expect(find.text('タイムリーツーベース'), findsNothing);
    final dp = tester.widget<Text>(find.text('二併'));
    expect(dp.style?.color, const Color(0xFFE53935));

    Color backgroundOf(String label) {
      final chip = tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
      );
      return (chip.decoration as BoxDecoration).color!;
    }

    expect(backgroundOf('三邪'), const Color(0xFF1E88E5));
    expect(backgroundOf('指'), const Color(0xFF8E24AA));
    expect(backgroundOf('遊'), const Color(0xFFFFEB3B));
    expect(backgroundOf('中'), const Color(0xFFC6FF00));
    expect(backgroundOf('捕'), const Color(0xFF1E88E5));
    expect(backgroundOf('投'), const Color(0xFFFF4B7D));
    expect(tester.widget<Text>(find.text('遊')).style?.color, Colors.black87);
    expect(tester.widget<Text>(find.text('指')).style?.color, Colors.white);
  });

  testWidgets('double digit strikeouts blink beside the pitching line', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 520,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-02',
                  'time_game': '🌙 18:00',
                  'name_team_home': 'ロッテ',
                  'name_team_away': 'ソフトバンク',
                  'name_stadium': 'ZOZOマリン',
                  'name_pitcher_home': '田中晴也',
                  'name_pitcher_away': '前田悠伍',
                  'score_home': 3,
                  'score_away': 4,
                  'state': '試合終了',
                  'id_team_home': 12,
                  'id_team_away': 7,
                  'id_team_summary': 7,
                  'name_full_summary': '前田悠伍',
                  'flg_pitcher': true,
                  'txt_pitch_chips': '7.2回3失点|yellow 9奪三振|crimson',
                  'txt_achieve': '２ケタ奪三振|k10',
                  'color_back_home': '#000000',
                  'color_back_away': '#FFD200',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#000000',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('２ケタ奪三振'), findsOneWidget);
    expect(find.ancestor(of: find.text('２ケタ奪三振'), matching: find.byType(BlinkBg)), findsOneWidget);
    expect(tester.getTopLeft(find.text('２ケタ奪三振')).dx, greaterThan(tester.getTopRight(find.text('9K')).dx - 0.5));
  });

  testWidgets('cycle and pitching feats use their colors', (tester) async {
    const pitching = '9回無失点(無安打無四球11奪三振)';
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 180,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-09-30',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': 'ヤクルト',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '髙橋遥人',
                  'name_pitcher_away': '奥川恭伸',
                  'score_home': 1,
                  'score_away': 0,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 4,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#003366',
                  'color_font_home': '#000000',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 2,
                      'name_full_summary': '髙橋遥人',
                      'flg_pitcher': true,
                      'txt_pitching': pitching,
                      'txt_pitch_tone': 'crimson',
                      'txt_achieve': '完全試合|perfect 全打席安打|allhit 全打席出塁|allreach マダックス|maddux HQS|hqs QS|qs',
                    },
                    {
                      'id_game_summary': 2,
                      'id_team_summary': 2,
                      'name_full_summary': '大山悠輔',
                      'flg_pitcher': false,
                      'txt_achieve': 'サイクルヒット|cycle 猛打賞|multihit 全打席安打|allhit 全打席出塁|allreach',
                      'txt_plays': '19号ソロホームラン|hr',
                    },
                    {
                      'id_game_summary': 3,
                      'id_team_summary': 4,
                      'name_full_summary': '山田哲人',
                      'flg_pitcher': false,
                      'txt_achieve': 'サイクル未遂|cyclemis',
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    Color backgroundOf(String label) {
      final blink = find.ancestor(of: find.text(label), matching: find.byType(BlinkBg));
      if (blink.evaluate().isNotEmpty) {
        return tester.widget<BlinkBg>(blink.first).base.color!;
      }
      final chip = tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
      );
      return (chip.decoration as BoxDecoration).color!;
    }

    expect(backgroundOf('完全試合'), const Color(0xFFDC143C));
    expect(backgroundOf('マダックス'), const Color(0xFFDC143C));
    expect(backgroundOf('HQS'), const Color(0xFFFF5722));
    expect(find.text('QS'), findsNothing);
    expect(backgroundOf('サイクルヒット'), const Color(0xFFDC143C));
    expect(backgroundOf('猛打賞'), const Color(0xFFDC143C));
    expect(backgroundOf('全打席安打'), const Color(0xFFDC143C));
    expect(find.text('全打席安打'), findsOneWidget);
    // 全打席安打があるときは全打席出塁は出さない。
    expect(find.text('全打席出塁'), findsNothing);
    expect((tester.getCenter(find.text('全打席安打')).dy - tester.getCenter(find.text('大山悠輔')).dy).abs(), lessThan(1));
    expect(backgroundOf('サイクル未遂'), const Color(0xFFDC143C));
    expect(find.text('9回無失点'), findsOneWidget);
    expect(backgroundOf('9回無失点'), const Color(0xFFDC143C));
    expect(tester.getTopLeft(find.text('19号ソロホームラン')).dx, greaterThan(tester.getTopRight(find.text('大山悠輔')).dx));
    expect(tester.getTopLeft(find.text('サイクルヒット')).dx, greaterThan(tester.getTopRight(find.text('19号ソロホームラン')).dx - 0.5));
    expect(tester.getTopLeft(find.text('猛打賞')).dx, greaterThan(tester.getTopRight(find.text('サイクルヒット')).dx - 0.5));
    expect(tester.getTopLeft(find.text('全打席安打')).dx, greaterThan(tester.getTopRight(find.text('猛打賞')).dx - 0.5));
    expect(find.byType(BlinkBg), findsWidgets);
  });

  testWidgets('pitching metrics sit side by side with their own colors', (tester) async {
    const chips = '9回無失点|crimson 被安打3|yorange 四死球0|crimson 10奪三振|crimson 98球|';
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 160,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-09-30',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': 'ヤクルト',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '髙橋遥人',
                  'name_pitcher_away': '奥川恭伸',
                  'score_home': 1,
                  'score_away': 0,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 4,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#003366',
                  'color_font_home': '#000000',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 2,
                      'name_full_summary': '髙橋遥人',
                      'flg_pitcher': true,
                      'txt_pitching': '9回無失点(3安打無四球10奪三振98球)',
                      'txt_pitch_chips': chips,
                      'txt_achieve': '完封|shutout HQS|hqs QS|qs',
                      'titles_predict': '本|#FF0000',
                    },
                    {
                      'id_game_summary': 2,
                      'id_team_summary': 2,
                      'name_full_summary': '岩崎優',
                      'flg_pitcher': true,
                      'code_result_pitcher': 'HOLD',
                      'txt_pitch_chips': '0.1回無失点|crimson 被安打10|gray 12BB|gray 12K|green',
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('9回無失点(3安打無四球10奪三振98球)'), findsNothing);

    Color backgroundOf(String label) {
      final chip = tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
      );
      return (chip.decoration as BoxDecoration).color!;
    }

    expect(backgroundOf('9回無失点'), const Color(0xFFDC143C));
    expect(backgroundOf('0四死'), const Color(0xFFDC143C));
    expect(backgroundOf('被安打3'), const Color(0xFF78909C));
    expect(tester.widget<Text>(find.text('9回無失点')).style?.color, isNot(Colors.red));
    expect(backgroundOf('10K'), const Color(0xFFDC143C));
    expect(tester.widget<Text>(find.text('0四死')).textAlign, TextAlign.center);
    expect(tester.widget<Text>(find.text('10K')).textAlign, TextAlign.center);
    Size chipSize(String label) {
      return tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(Container)).first);
    }

    expect(chipSize('9回無失点').width, closeTo(chipSize('0.1回無失点').width, 0.5));
    expect(chipSize('被安打3').width, closeTo(chipSize('被安打10').width, 0.5));
    expect(chipSize('0四死').width, closeTo(chipSize('12四死').width, 0.5));
    expect(chipSize('10K').width, closeTo(chipSize('12K').width, 0.5));
    expect(find.text('QS'), findsNothing);
    final labels = ['9回無失点', '被安打3', '0四死', '10K', '98球', '完封', 'HQS', '本'];
    var previousRight = tester.getTopRight(find.text('髙橋遥人')).dx;
    for (final label in labels) {
      expect(tester.getTopLeft(find.text(label).first).dx, greaterThan(previousRight - 0.5));
      previousRight = tester.getTopRight(find.text(label).first).dx;
    }
  });

  testWidgets('runs alert paints innings chip not pitcher name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 160,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-06',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': 'ヤクルト',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '岩崎優',
                  'name_pitcher_away': 'A',
                  'score_home': 1,
                  'score_away': 4,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 4,
                  'color_back_home': '#FFD200',
                  'color_font_home': '#000000',
                  'color_back_away': '#003366',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 2,
                      'name_full_summary': '岩崎優',
                      'flg_pitcher': true,
                      'code_result_pitcher': 'HOLD',
                      'txt_pitch_chips': '1回2失点|alert 被安打2|gray 四死球0|crimson 0奪三振|green',
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    Color backgroundOf(String label) {
      final chip = tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
      );
      return (chip.decoration as BoxDecoration).color!;
    }

    expect(backgroundOf('1回2失点'), Colors.black);
    expect(tester.widget<Text>(find.text('1回2失点')).style?.color, Colors.red);
    expect(tester.widget<Text>(find.text('岩崎優')).style?.color, isNot(Colors.red));
  });

  testWidgets('walks alert paints 四死 chip black with red text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 160,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': 'ヤクルト',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '岩崎優',
                  'name_pitcher_away': 'A',
                  'score_home': 1,
                  'score_away': 4,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 4,
                  'color_back_home': '#FFD200',
                  'color_font_home': '#000000',
                  'color_back_away': '#003366',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 2,
                      'name_full_summary': '岩崎優',
                      'flg_pitcher': true,
                      'code_result_pitcher': 'HOLD',
                      'txt_pitch_chips': '1回無失点|crimson 被安打1|green 2四死|gray 0K|green',
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    Color backgroundOf(String label) {
      final chip = tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
      );
      return (chip.decoration as BoxDecoration).color!;
    }

    expect(find.text('2四死'), findsOneWidget);
    expect(backgroundOf('2四死'), Colors.black);
    expect(tester.widget<Text>(find.text('2四死')).style?.color, Colors.red);
    expect(tester.widget<Text>(find.text('岩崎優')).style?.color, isNot(Colors.red));
  });

  testWidgets('inning scores sit between team names with nine columns', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 240,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              horizontal: true,
              games: [
                {
                  'date_game': '2026-10-02',
                  'time_game': '🌙 18:00',
                  'name_team_home': 'ヤクルト',
                  'name_team_away': '巨人',
                  'name_stadium': '神宮',
                  'score_home': 1,
                  'score_away': 1,
                  'state': '4回裏',
                  'id_team_home': 4,
                  'id_team_away': 1,
                  'txt_scores_home': '0,0,1,0',
                  'txt_scores_away': '0,1,0,0',
                  'int_runs_home': 1,
                  'int_runs_away': 1,
                  'int_hit_home': 5,
                  'int_hit_away': 1,
                  'int_error_home': 1,
                  'int_error_away': 0,
                  'color_back_home': '#1D4E89',
                  'color_back_away': '#F15A22',
                  'color_font_home': 'white',
                  'color_font_away': 'black',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 4,
                      'name_full_summary': '山野太一',
                      'flg_pitcher': true,
                      'txt_pitching': '3回1失点',
                    },
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final batterRect = tester.getRect(find.text('打者'));
    final scoreRect = tester.getRect(find.text('R'));
    expect(scoreRect.bottom, lessThan(batterRect.top + 1));
    expect(tester.getRect(find.text('E')).right, lessThan(tester.getRect(find.text('巨人').first).left + 1));
    expect(tester.getRect(find.text('E')).left, greaterThan(tester.getRect(find.text('ヤクルト').first).right - 1));
    expect(find.text('8'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('1 - 1'), findsOneWidget);
    expect(find.text('4回裏'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('4回裏')).dy, lessThan(tester.getTopLeft(find.text('1 - 1')).dy + 2));
    expect(find.byKey(const ValueKey('live-inning-cell')), findsOneWidget);
    // 到来済みの0点回と失策の0。まだ来ていない5回以降は空。
    expect(find.text('0'), findsNWidgets(7));

    Color cellColor(Finder text) {
      final box = tester.widget<Container>(find.ancestor(of: text, matching: find.byType(Container)).first);
      return (box.decoration! as BoxDecoration).color!;
    }

    expect(cellColor(find.text('R')), const Color(0xFF555555));
    expect(tester.widget<Text>(find.text('R')).style?.color, Colors.white);
    expect(cellColor(find.text('H')), const Color(0xFF555555));
    expect(cellColor(find.text('E')), const Color(0xFF555555));

    double cellW(String label) {
      return tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(Container)).first).width;
    }

    expect(cellW('R'), closeTo(cellW('1'), 0.6));
    expect(cellW('H'), closeTo(cellW('1'), 0.6));
    expect(cellW('E'), closeTo(cellW('1'), 0.6));

    bool logo(String asset) {
      return find.byWidgetPredicate((widget) {
        if (widget is! Image) return false;
        final provider = widget.image;
        return provider is AssetImage && provider.assetName == asset;
      }).evaluate().isNotEmpty;
    }

    expect(logo('backend/assets/images/team_s.png'), isTrue);
    expect(logo('backend/assets/images/team_g.png'), isTrue);
    bool isAsset(Widget widget, String asset) {
      if (widget is! Image) return false;
      final provider = widget.image;
      return provider is AssetImage && provider.assetName == asset;
    }

    Rect closestLogo(String asset, Rect target) {
      final finder = find.byWidgetPredicate((widget) => isAsset(widget, asset));
      Rect? best;
      var bestGap = 1e9;
      for (var i = 0; i < finder.evaluate().length; i++) {
        final r = tester.getRect(finder.at(i));
        final gap = (r.center.dy - target.center.dy).abs();
        if (gap < bestGap) {
          bestGap = gap;
          best = r;
        }
      }
      return best!;
    }

    final scoreText = tester.getRect(find.text('1 - 1'));
    final inningState = tester.getRect(find.text('4回裏'));
    final homeLogos = closestLogo('backend/assets/images/team_s.png', inningState);
    final awayLogos = closestLogo('backend/assets/images/team_g.png', inningState);
    final homeName = tester.getRect(find.text('ヤクルト').first);
    final awayName = tester.getRect(find.text('巨人').first);
    expect(homeName.right, lessThan(scoreText.left + 1));
    expect(awayName.left, greaterThan(scoreText.right - 1));
    expect(homeLogos.center.dx, lessThan(inningState.left + 1));
    expect(awayLogos.center.dx, greaterThan(inningState.right - 1));
    expect(inningState.left - homeLogos.right, inInclusiveRange(2, 40));
    expect(awayLogos.left - inningState.right, inInclusiveRange(2, 40));
    expect(homeLogos.height, closeTo(44 * 0.8, 8));
    final lineHome = tester.widget<Container>(
      find.ancestor(of: find.byWidgetPredicate((widget) {
        if (widget is! Image) return false;
        final provider = widget.image;
        return provider is AssetImage && provider.assetName == 'backend/assets/images/team_s.png';
      }).at(1), matching: find.byType(Container)).first,
    );
    expect((lineHome.decoration as BoxDecoration).color, Colors.white);
  });

  testWidgets('narrow screens stack home player lines above away', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 480,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-03',
                  'time_game': '18:00',
                  'name_team_home': '楽天',
                  'name_team_away': 'オリックス',
                  'name_stadium': '楽天モバイルパーク',
                  'name_pitcher_home': '古謝樹',
                  'name_pitcher_away': '東晃平',
                  'score_home': 3,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 11,
                  'id_team_away': 10,
                  'color_back_home': '#8B0000',
                  'color_back_away': '#002F6C',
                  'color_font_home': 'white',
                  'color_font_away': 'white',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final home = tester.getTopLeft(find.text('古謝樹'));
    final away = tester.getTopLeft(find.text('東晃平'));
    expect(home.dy, lessThan(away.dy - 8));
    expect(home.dx, closeTo(away.dx, 8));
    final pitcherLabel = tester.getTopLeft(find.text('投手').first);
    expect(pitcherLabel.dx, lessThan(home.dx));
    // 縦書きチーム名ヘッダーが一番左
    final homeTeamChar = tester.getTopLeft(find.text('楽').first);
    expect(homeTeamChar.dx, lessThan(pitcherLabel.dx));
  });

  testWidgets('pregame starting pitchers stay side by side on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-06',
                  'time_game': '18:00',
                  'name_team_home': '楽天',
                  'name_team_away': 'オリックス',
                  'name_stadium': '楽天モバイルパーク',
                  'name_pitcher_home': '古謝樹',
                  'name_pitcher_away': '東晃平',
                  'state': '予想先発',
                  'id_team_home': 11,
                  'id_team_away': 10,
                  'color_back_home': '#8B0000',
                  'color_back_away': '#002F6C',
                  'color_font_home': 'white',
                  'color_font_away': 'white',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final home = tester.getCenter(find.text('古謝樹'));
    final away = tester.getCenter(find.text('東晃平'));
    expect(home.dx, lessThan(away.dx - 8));
    expect((home.dy - away.dy).abs(), lessThan(24));
  });

  testWidgets('narrow pregame pitcher season stats keep label beside value', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 320,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-02',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '村上頌樹',
                  'name_pitcher_away': '戸郷翔征',
                  'txt_season_pitcher_home': '10勝5敗 1.85 142奪三振 規定98.2%',
                  'txt_season_pitcher_away': '8勝7敗 2.41 128奪三振 規定123.4%',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('勝敗'), findsNWidgets(2));
    expect(find.text('10勝5敗'), findsOneWidget);
    Finder labelNear(String value) {
      final record = tester.getCenter(find.text(value));
      Finder nearestLabel = find.text('勝敗').at(0);
      var nearest = 1000.0;
      for (var i = 0; i < 2; i++) {
        final center = tester.getCenter(find.text('勝敗').at(i));
        if (center.dx > record.dx) continue;
        final gap = (center.dy - record.dy).abs() + (record.dx - center.dx) / 1000;
        if (gap < nearest) {
          nearest = gap;
          nearestLabel = find.text('勝敗').at(i);
        }
      }
      return nearestLabel;
    }

    final winsLabel = labelNear('10勝5敗');
    expect(tester.getTopRight(winsLabel).dx, lessThan(tester.getTopLeft(find.text('10勝5敗')).dx + 1));
    expect((tester.getCenter(winsLabel).dy - tester.getCenter(find.text('10勝5敗')).dy).abs(), lessThan(8));
  });

  testWidgets('narrow screens stack pregame match cards', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 520,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-08',
                  'time_game': '18:00',
                  'name_team_home': '阪神',
                  'name_team_away': 'ヤクルト',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': 'ルーカス',
                  'name_pitcher_away': '中村優',
                  'state': '予想先発',
                  'id_team_home': 2,
                  'id_team_away': 4,
                  'id_game': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#00A040',
                  'color_font_home': '#000000',
                  'color_font_away': '#FFFFFF',
                },
                {
                  'date_game': '2026-10-08',
                  'time_game': '18:00',
                  'name_team_home': '巨人',
                  'name_team_away': 'DeNA',
                  'name_stadium': '東京ドーム',
                  'name_pitcher_home': '戸郷翔征',
                  'name_pitcher_away': '東克樹',
                  'state': '予想先発',
                  'id_team_home': 1,
                  'id_team_away': 3,
                  'id_game': 2,
                  'color_back_home': '#FF6600',
                  'color_back_away': '#003399',
                  'color_font_home': '#000000',
                  'color_font_away': '#FFFFFF',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final first = tester.getTopLeft(find.text('ルーカス'));
    final second = tester.getTopLeft(find.text('戸郷翔征'));
    expect(first.dy, lessThan(second.dy - 24));
    expect(first.dx, closeTo(second.dx, 24));
  });

  testWidgets('活躍表示は打球方向と打点・盗塁バッチを出す', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 520,
            height: 180,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-05',
                  'time_game': '🌙 18:00',
                  'name_team_home': 'ブレーブス',
                  'name_team_away': 'ブルワーズ',
                  'name_stadium': 'トゥルーイストパーク',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 3,
                  'score_away': 4,
                  'state': '試合終了',
                  'id_team_home': 101,
                  'id_team_away': 102,
                  'color_back_home': '#CE1141',
                  'color_back_away': '#12284B',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 101,
                      'name_full_summary': 'M.デュボン',
                      'flg_pitcher': false,
                      'txt_plays': '遊タイムリー^遊|timely',
                    },
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 102,
                      'name_full_summary': 'ジャクソン・チョウリオ',
                      'flg_pitcher': false,
                      'txt_plays': '9回裏サヨナラ2点タイムリー^中|timely 盗塁|steal',
                    },
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 102,
                      'name_full_summary': '代走盗塁',
                      'flg_pitcher': false,
                      'txt_plays': '盗塁|steal',
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('タイムリー'), findsOneWidget);
    expect(find.text('サヨナラ2点タイムリー'), findsOneWidget);
    expect(find.text('盗塁'), findsNothing);
    expect(find.byKey(const ValueKey('steal-badge')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('steal-badge')).first).dx,
      greaterThan(tester.getTopLeft(find.text('サヨナラ2点タイムリー')).dx - 4),
    );
    expect(find.byKey(const ValueKey('rbi-badge-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('rbi-badge-2')), findsOneWidget);
  });

  testWidgets('活躍表示の安打は打球方向を出し本塁打とタイムリーには付けない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 560,
            height: 180,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-06',
                  'time_game': '🌙 05:00',
                  'name_team_home': 'ホワイトソックス',
                  'name_team_away': 'ガーディアンズ',
                  'name_stadium': 'プログレッシブフィールド',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 3,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 201,
                  'id_team_away': 202,
                  'color_back_home': '#000000',
                  'color_back_away': '#0C2340',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 201,
                      'name_full_summary': 'L.サラベラ',
                      'flg_pitcher': false,
                      'txt_plays': '安^中|single ヒット^右|single 2回表先制ソロホームラン^左|hr 8回裏タイムリー^遊|timely 遊野選|fc',
                    },
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 202,
                      'name_full_summary': 'ジョ・アデル',
                      'flg_pitcher': false,
                      'txt_plays': '四球|walk 三振|out 8回裏タイムリースリーベース^左|timely',
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('中安'), findsOneWidget);
    expect(find.text('右安'), findsOneWidget);
    expect(find.text('先制ソロホームラン'), findsOneWidget);
    expect(find.text('タイムリー'), findsOneWidget);
    expect(find.text('タイムリースリーベース'), findsOneWidget);
    expect(find.text('遊選'), findsNothing);
    expect(find.text('遊野選'), findsNothing);
    expect(find.textContaining('左ホームラン'), findsNothing);
    expect(find.text('四球'), findsNothing);
    expect(find.text('三振'), findsNothing);
  });

  testWidgets('活躍表示は打順枠の打席を並べ代の二ゴを左飛の右隣に出す', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            height: 200,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-06',
                  'time_game': '🌙 05:00',
                  'name_team_home': 'ホワイトソックス',
                  'name_team_away': 'ガーディアンズ',
                  'name_stadium': 'プログレッシブフィールド',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 2,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 201,
                  'id_team_away': 202,
                  'color_back_home': '#000000',
                  'color_back_away': '#0C2340',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 201,
                      'name_full_summary': 'A.ベニンテンディ',
                      'flg_pitcher': false,
                      'txt_plays': '中安|single 四球|walk 左飛|out 右タイムリー|timely',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 201,
                      'order': 6,
                      'players': [
                        {
                          'name': 'A.ベニンテンディ',
                          'pos': '左',
                          'plays': '中安|single 四球|walk 左飛|out 右タイムリー|timely',
                        },
                        {
                          'name': 'M.バルガス',
                          'pos': '指',
                          'role': '代打',
                          'plays': '二ゴ|out',
                        },
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('A.ベニンテンディ'), findsOneWidget);
    expect(find.text('中安'), findsOneWidget);
    expect(find.text('四球'), findsNothing);
    expect(find.text('左飛'), findsNothing);
    expect(find.text('二ゴ'), findsNothing);
    expect(find.text('タイムリー'), findsOneWidget);
    expect(find.text('代打：M.バルガス'), findsOneWidget);
    expect(find.text('M.バルガス'), findsNothing);
    expect(find.byKey(const ValueKey('pinch-badge')), findsNothing);
    expect(
      (tester.widget<Container>(find.byKey(const ValueKey('pinch-caption-0'))).decoration as BoxDecoration).color,
      const Color(0xFF5C6BC0),
    );
    expect(tester.getTopLeft(find.text('中安')).dx, lessThan(tester.getTopLeft(find.text('タイムリー')).dx));
    expect(
      tester.getTopLeft(find.text('代打：M.バルガス')).dx,
      greaterThan(tester.getTopRight(find.text('タイムリー')).dx - 1),
    );
    final boardRight = tester.getRect(find.byType(GamesBoardYahooStyle)).right;
    for (final label in ['中安', 'タイムリー']) {
      expect(tester.getRect(find.text(label)).right, lessThanOrEqualTo(boardRight + 0.5));
    }
    expect(tester.getRect(find.text('代打：M.バルガス')).right, lessThanOrEqualTo(boardRight + 0.5));
  });

  testWidgets('代守の打席は代マークと代守：名前を出す', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-06',
                  'time_game': '🌙 06:00',
                  'name_team_home': 'ガーディアンズ',
                  'name_team_away': 'ホワイトソックス',
                  'name_stadium': 'プログレッシブフィールド',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 3,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 202,
                  'id_team_away': 201,
                  'id_league_home': 3,
                  'id_league_away': 3,
                  'color_back_home': '#0C2340',
                  'color_back_away': '#000000',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 201,
                      'name_full_summary': 'トミー・ファム',
                      'flg_pitcher': false,
                      'txt_plays': '左飛|out 代打同点タイムリー^右|timely',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 201,
                      'order': 6,
                      'players': [
                        {'name': 'トリスタン・ピーターズ', 'pos': '右', 'plays': '三振|out 左飛|out'},
                        {'name': 'トミー・ファム', 'pos': '右', 'role': '代打', 'plays': '左飛|out 代打同点タイムリー^右|timely'},
                        {'name': 'ブレンドン・ドイル', 'pos': '中', 'role': '代守', 'plays': '二ゴ|out'},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('トミー・ファム'), findsOneWidget);
    expect(find.text('二ゴ'), findsNothing);
    expect(find.text('左飛'), findsNothing);
    expect(find.text('代打同点タイムリー'), findsOneWidget);
    expect(find.text('代守：ブレンドン・ドイル'), findsOneWidget);
    expect(find.text('ブレンドン・ドイル'), findsNothing);
    expect(find.byKey(const ValueKey('pinch-badge')), findsNothing);
    expect(
      (tester.widget<Container>(find.byKey(const ValueKey('pinch-caption-0'))).decoration as BoxDecoration).color,
      const Color(0xFF5C6BC0),
    );
    expect(
      tester.getTopLeft(find.text('代守：ブレンドン・ドイル')).dx,
      greaterThan(tester.getTopRight(find.text('代打同点タイムリー')).dx - 1),
    );
  });

  testWidgets('同じ選手をスタメンの代守として出さない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 360,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-05',
                  'time_game': '🌙 05:00',
                  'name_team_home': 'ブルワーズ',
                  'name_team_away': 'パドレス',
                  'name_stadium': 'アメリカンファミリーフィールド',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 4,
                  'score_away': 2,
                  'state': '試合終了',
                  'id_team_home': 202,
                  'id_team_away': 201,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'color_back_home': '#12284B',
                  'color_back_away': '#2F241D',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 201,
                      'name_full_summary': 'ダスティン・ハリス',
                      'flg_pitcher': false,
                      'txt_plays': '三振|out 遊フライ|out',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 201,
                      'order': 2,
                      'players': [
                        {'name': 'ダスティン・ハリス', 'pos': '左', 'plays': '三振|out'},
                        {'name': 'ダスティンハリス', 'pos': '左', 'role': '代守', 'plays': '遊フライ|out'},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('詳細表示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ダスティン・ハリス'), findsOneWidget);
    expect(find.text('代守：ダスティンハリス'), findsNothing);
    expect(find.text('代守：ダスティン・ハリス'), findsNothing);
    expect(find.byKey(const ValueKey('pinch-caption-0')), findsNothing);
  });

  testWidgets('opening game label blinks in a tight centered band', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            height: 160,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-03-27',
                  'time_game': '18:00',
                  'name_team_home': '阪神',
                  'name_team_away': 'ヤクルト',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'state': '試合前',
                  'id_team_home': 2,
                  'id_team_away': 4,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#003366',
                  'color_font_home': '#000000',
                  'color_font_away': '#FFFFFF',
                  'milestone_home': 'シーズン開幕戦',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('シーズン開幕戦'), findsOneWidget);
    expect(find.ancestor(of: find.text('シーズン開幕戦'), matching: find.byType(BlinkBg)), findsOneWidget);
    final label = tester.getRect(find.text('シーズン開幕戦'));
    final blink = tester.getRect(find.ancestor(of: find.text('シーズン開幕戦'), matching: find.byType(BlinkBg)));
    expect(blink.width, lessThan(label.width + 20));
    expect(blink.center.dx, closeTo(tester.getRect(find.text('阪神').first).center.dx, 24));
  });

  test('same day duplicate ids collapse to one game', () {
    final nested = normalizeGames([
      {
        'id_game': 651,
        'date_game': '2026-10-07',
        'time_game': '☀️ 09:00',
        'name_team_home': 'ドジャース',
        'name_team_away': 'ブレーブス',
        'id_team_home': 101,
        'id_team_away': 102,
        'code_game': 'DS',
        'state': '試合終了',
        'score_home': 2,
        'score_away': 3,
        'id_league_home': 4,
        'id_league_away': 4,
      },
      {
        'id_game': 3325,
        'date_game': '2026-10-07',
        'time_game': '',
        'name_team_home': 'ドジャース',
        'name_team_away': 'ブレーブス',
        'id_team_home': 101,
        'id_team_away': 102,
        'code_game': 'DS',
        'state': '試合終了',
        'score_home': 2,
        'score_away': 3,
        'id_league_home': 4,
        'id_league_away': 4,
      },
    ]);
    expect(nested, hasLength(1));
    expect(nested.first['id_game'], 651);
  });

  test('same day Padres Brewers pregame import duplicate collapses to one game', () {
    final nested = normalizeGames([
      {
        'id_game': 652,
        'date_game': '2026-10-07',
        'time_game': '☀️ 10:30',
        'name_team_home': 'パドレス',
        'name_team_away': 'ブルワーズ',
        'id_team_home': 41,
        'id_team_away': 35,
        'code_game': 'DS',
        'state': '予想先発',
        'score_home': -1,
        'score_away': -1,
        'name_pitcher_home': 'ニック・ピベッタ',
        'name_pitcher_away': 'ダスティン・メイ',
        'id_league_home': 4,
        'id_league_away': 4,
      },
      {
        'id_game': 3326,
        'date_game': '2026-10-07',
        'time_game': '🌙 01:30',
        'name_team_home': 'パドレス',
        'name_team_away': 'ブルワーズ',
        'id_team_home': 41,
        'id_team_away': 35,
        'code_game': 'DS',
        'state': '試合前',
        'id_league_home': 4,
        'id_league_away': 4,
      },
    ]);
    expect(nested, hasLength(1));
    expect(nested.first['id_game'], 652);
  });

  test('same day Padres Brewers finished Yahoo hides historical pregame', () {
    final nested = normalizeGames([
      {
        'id_game': 652,
        'date_game': '2026-10-07',
        'time_game': '☀️ 08:00',
        'name_team_home': 'パドレス',
        'name_team_away': 'ブルワーズ',
        'id_team_home': 41,
        'id_team_away': 35,
        'code_game': 'DS',
        'state': '試合終了',
        'score_home': 3,
        'score_away': 1,
        'id_league_home': 4,
        'id_league_away': 4,
      },
      {
        'id_game': 3326,
        'date_game': '2026-10-07',
        'time_game': '🌙 01:30',
        'name_team_home': 'パドレス',
        'name_team_away': 'ブルワーズ',
        'id_team_home': 41,
        'id_team_away': 35,
        'code_game': 'DS',
        'state': '試合前',
        'id_league_home': 4,
        'id_league_away': 4,
      },
    ]);
    expect(nested, hasLength(1));
    expect(nested.single['id_game'], 652);
    expect(nested.single['state'], '試合終了');
  });

  test('samePlayerStatName matches initials and full names', () {
    expect(samePlayerStatName('S.大谷', '大谷翔平'), isTrue);
    expect(samePlayerStatName('菊池雄星', 'K.菊池'), isTrue);
    expect(samePlayerStatName('M.マチャド', 'マニー・マチャド'), isTrue);
    expect(samePlayerStatName('W.コントレラス', 'ウィリアム・コントレラス'), isTrue);
    expect(samePlayerStatName('東克樹', '村上頌樹'), isFalse);
    expect(samePlayerStatName('ブレーデン・モンゴメリー', 'コルソン・モンゴメリー'), isFalse);
    expect(samePlayerStatName('ヘーゲン・スミス', 'C.スミス'), isFalse);
    expect(samePlayerStatName('C.スミス', 'ヘーゲン・スミス'), isFalse);
    expect(samePlayerStatName('ヘーゲン・スミス', 'H.スミス'), isTrue);
    expect(samePlayerStatName('ケード・スミス', 'C.スミス'), isTrue);
    expect(samePlayerStatName('B.モンゴメリー', 'ブレーデン・モンゴメリー'), isTrue);
  });

  testWidgets('White Sox 9th Montgomery keeps his own batting chips', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 360,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-06',
                  'time_game': '🌙 09:15',
                  'name_team_home': 'ガーディアンズ',
                  'name_team_away': 'ホワイトソックス',
                  'name_stadium': 'プログレッシブフィールド',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 3,
                  'score_away': 4,
                  'state': '試合終了',
                  'id_team_home': 202,
                  'id_team_away': 201,
                  'id_league_home': 3,
                  'id_league_away': 3,
                  'color_back_home': '#0C2340',
                  'color_back_away': '#000000',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'lineup': [
                    {
                      'id_team': 201,
                      'order': 7,
                      'players': [
                        {'name': 'ブレーデン・モンゴメリー', 'pos': '右', 'plays': '空三振|out 右２|double'},
                      ],
                    },
                    {
                      'id_team': 201,
                      'order': 9,
                      'players': [
                        {'name': 'コルソン・モンゴメリー', 'pos': '遊', 'plays': '四球|walk 空三振|out 見三振|out 三邪飛|out'},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('詳細表示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ブレーデン・モンゴメリー'), findsOneWidget);
    expect(find.text('コルソン・モンゴメリー'), findsOneWidget);
    expect(find.text('9'), findsWidgets);
    expect(find.text('四球'), findsOneWidget);
    expect(find.text('三邪'), findsOneWidget);
    expect(tester.getTopLeft(find.text('コルソン・モンゴメリー')).dy, greaterThan(tester.getTopLeft(find.text('ブレーデン・モンゴメリー')).dy));
    expect(tester.getTopLeft(find.text('四球')).dy, greaterThan(tester.getTopLeft(find.text('右２')).dy - 2));
  });

  testWidgets('MLB game cards put Japan flag to the right of Japanese names', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-08',
                  'time_game': '🌙 05:00',
                  'name_team_home': 'ホワイトソックス',
                  'name_team_away': 'ガーディアンズ',
                  'name_stadium': 'ギャランティドレートフィールド',
                  'name_pitcher_home': 'S.今永',
                  'name_pitcher_away': '先発相手',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '予想先発',
                  'code_game': 'DS',
                  'id_team_home': 201,
                  'id_team_away': 202,
                  'id_league_home': 3,
                  'id_league_away': 3,
                  'color_back_home': '#000000',
                  'color_back_away': '#E31937',
                  'color_font_home': 'white',
                  'color_font_away': 'white',
                },
              ],
              playerStats: const [
                {
                  'title': '防御率',
                  'name_player': '今永昇太',
                  'int_rank': 4,
                  'id_league': 3,
                  'flg_japan': true,
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('🌙 05:00'), findsOneWidget);
    expect(find.text('試合前'), findsOneWidget);
    expect(find.text('予想先発'), findsNothing);
    expect(find.textContaining('S.今永'), findsOneWidget);
    expect(find.textContaining('🇯🇵'), findsOneWidget);
    expect(tester.getTopLeft(find.textContaining('🇯🇵')).dx, greaterThan(tester.getTopLeft(find.textContaining('S.今永')).dx));
  });

  testWidgets('postseason game cards put a crown on season stat leaders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            height: 200,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-08',
                  'time_game': '🌙 05:00',
                  'name_team_home': 'ドジャース',
                  'name_team_away': 'パドレス',
                  'name_stadium': 'ドジャー・スタジアム',
                  'name_pitcher_home': '山本由伸',
                  'name_pitcher_away': '先発相手',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '予想先発',
                  'code_game': 'DS',
                  'id_team_home': 301,
                  'id_team_away': 302,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'color_back_home': '#005A9C',
                  'color_back_away': '#2F241D',
                  'color_font_home': 'white',
                  'color_font_away': 'white',
                },
              ],
              playerStats: const [
                {
                  'title': '奪三振',
                  'name_player': '山本由伸',
                  'int_rank': 1,
                  'id_league': 4,
                  'flg_japan': true,
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('👑'), findsOneWidget);
    expect(find.textContaining('🇯🇵'), findsOneWidget);
    expect(tester.getTopLeft(find.textContaining('🇯🇵')).dx, greaterThan(tester.getTopLeft(find.textContaining('山本由伸')).dx));
    expect(tester.getTopLeft(find.textContaining('👑')).dx, greaterThan(tester.getTopLeft(find.textContaining('🇯🇵')).dx));
  });

  testWidgets('NPB regular season cards do not show Japan flag or crown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 180,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-08',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '村上頌樹',
                  'name_pitcher_away': '戸郷翔征',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '試合前',
                  'code_game': 'NM',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'id_league_home': 1,
                  'id_league_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                },
              ],
              playerStats: const [
                {
                  'title': '防御率',
                  'name_player': '村上頌樹',
                  'int_rank': 1,
                  'id_league': 1,
                  'flg_japan': true,
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('🇯🇵'), findsNothing);
    expect(find.textContaining('👑'), findsNothing);
  });

  testWidgets('NPB notable mode still shows batters with hits', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 560,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '村上頌樹',
                  'name_pitcher_away': '戸郷翔征',
                  'score_home': 4,
                  'score_away': 2,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'id_league_home': 1,
                  'id_league_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 2,
                      'name_full_summary': '佐藤輝明',
                      'flg_pitcher': false,
                      'txt_plays': '中安|single 右2|double 左安|single',
                      'txt_achieve': '猛打賞|multihit',
                    },
                    {
                      'id_game_summary': 2,
                      'id_team_summary': 1,
                      'name_full_summary': '岡本和真',
                      'flg_pitcher': false,
                      'txt_plays': '左3点タイムリー|timely',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 2,
                      'order': 4,
                      'players': [
                        {'name': '佐藤 輝明', 'pos': '三', 'plays': '中安|single 右2|double 左安|single'},
                      ],
                    },
                    {
                      'id_team': 1,
                      'order': 4,
                      'players': [
                        {'name': '岡本 和真', 'pos': '一', 'plays': '左3点タイムリー|timely'},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('佐藤輝明'), findsWidgets);
    expect(find.text('岡本和真'), findsWidgets);
    expect(find.text('中安'), findsOneWidget);
    expect(find.textContaining('タイムリー'), findsOneWidget);
  });

  testWidgets('notable batters keep HR left of position and sort by points', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 260,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 5,
                  'score_away': 2,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'id_league_home': 1,
                  'id_league_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 2,
                      'name_full_summary': '近本光司',
                      'flg_pitcher': false,
                      'txt_plays': '中タイムリー|timely',
                    },
                    {
                      'id_game_summary': 2,
                      'id_team_summary': 2,
                      'name_full_summary': '佐藤輝明',
                      'flg_pitcher': false,
                      'txt_plays': '20号ソロホームラン^左|hr',
                    },
                    {
                      'id_game_summary': 3,
                      'id_team_summary': 2,
                      'name_full_summary': '中野拓夢',
                      'flg_pitcher': false,
                      'txt_plays': '四球|walk 三振|out',
                    },
                    {
                      'id_game_summary': 4,
                      'id_team_summary': 2,
                      'name_full_summary': '森下翔太',
                      'flg_pitcher': false,
                      'txt_plays': '犠飛|sacfly',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 2,
                      'order': 1,
                      'players': [
                        {'name': '近本 光司', 'pos': '中', 'plays': '中タイムリー|timely'},
                      ],
                    },
                    {
                      'id_team': 2,
                      'order': 4,
                      'players': [
                        {'name': '佐藤 輝明', 'pos': '三', 'plays': '20号ソロホームラン^左|hr'},
                      ],
                    },
                    {
                      'id_team': 2,
                      'order': 2,
                      'players': [
                        {'name': '中野 拓夢', 'pos': '遊', 'plays': '四球|walk 三振|out'},
                      ],
                    },
                    {
                      'id_team': 2,
                      'order': 5,
                      'players': [
                        {'name': '森下 翔太', 'pos': '右', 'plays': '犠飛|sacfly'},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('佐藤輝明'), findsWidgets);
    expect(find.text('近本光司'), findsWidgets);
    expect(find.text('森下翔太'), findsWidgets);
    expect(find.text('中野拓夢'), findsNothing);
    expect(find.text('HR'), findsOneWidget);
    expect(find.text('三'), findsOneWidget);
    expect(find.text('中'), findsOneWidget);
    expect(find.text('右'), findsOneWidget);
    expect(tester.getTopLeft(find.text('佐藤輝明').first).dy, lessThan(tester.getTopLeft(find.text('近本光司').first).dy));
    expect(tester.getTopLeft(find.text('HR')).dx, lessThan(tester.getTopLeft(find.text('三')).dx));
    expect(tester.getTopLeft(find.text('三')).dx, lessThan(tester.getTopLeft(find.text('佐藤輝明').first).dx));
  });

  testWidgets('MLB Japanese batters show even without extra-base production', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 560,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '🌙 08:00',
                  'name_team_home': 'ドジャース',
                  'name_team_away': 'パドレス',
                  'name_stadium': 'ドジャー・スタジアム',
                  'name_pitcher_home': '山本由伸',
                  'name_pitcher_away': 'キング',
                  'score_home': 2,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 301,
                  'id_team_away': 302,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'color_back_home': '#005A9C',
                  'color_back_away': '#2F241D',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 301,
                      'name_full_summary': 'M. Rojas',
                      'flg_pitcher': false,
                      'flg_japan': false,
                      'txt_plays': '四球|walk',
                    },
                    {
                      'id_game_summary': 2,
                      'id_team_summary': 301,
                      'name_full_summary': 'S.大谷',
                      'flg_pitcher': false,
                      'flg_japan': true,
                      'txt_plays': '四球|walk 三振|out',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 301,
                      'order': 1,
                      'players': [
                        {'name': 'S.大谷', 'pos': '指', 'plays': '四球|walk 三振|out'},
                      ],
                    },
                    {
                      'id_team': 301,
                      'order': 2,
                      'players': [
                        {'name': 'M. Rojas', 'pos': '遊', 'plays': '四球|walk'},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('S.大谷'), findsWidgets);
    expect(find.text('M.Rojas'), findsNothing);
    expect(find.text('指'), findsOneWidget);
  });

  testWidgets('NPB notable mode uses lineup hits when batter summaries are missing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 560,
            height: 280,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-06',
                  'time_game': '18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '広島',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '大竹耕太郎',
                  'name_pitcher_away': '工藤泰己',
                  'score_home': 2,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 6,
                  'id_league_home': 1,
                  'id_league_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF0000',
                  'color_font_home': '#000000',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 2,
                      'name_full_summary': '大竹耕太郎',
                      'flg_pitcher': true,
                      'txt_pitching': '6回1失点',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 2,
                      'order': 1,
                      'players': [
                        {'name': '近本 光司', 'pos': '中', 'plays': '左２|double タイムリー^二|timely 四球|walk'},
                      ],
                    },
                    {
                      'id_team': 2,
                      'order': 4,
                      'players': [
                        {'name': '佐藤 輝明', 'pos': '三', 'plays': '先制タイムリー^中|timely 二併殺|out'},
                      ],
                    },
                    {
                      'id_team': 2,
                      'order': 6,
                      'players': [
                        {'name': '髙寺望夢', 'pos': '左', 'plays': '一ライナー|out 三振|out'},
                      ],
                    },
                    {
                      'id_team': 6,
                      'order': 4,
                      'players': [
                        {'name': '坂倉 将吾', 'pos': '一', 'plays': '中安|single タイムリー^中|timely'},
                      ],
                    },
                    {
                      'id_team': 6,
                      'order': 3,
                      'players': [
                        {'name': '菊池 涼介', 'pos': '二', 'plays': '三失|error'},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('近本光司'), findsWidgets);
    expect(find.text('佐藤輝明'), findsWidgets);
    expect(find.text('坂倉将吾'), findsWidgets);
    expect(find.text('髙寺望夢'), findsNothing);
    expect(find.text('菊池涼介'), findsNothing);
    expect(find.textContaining('タイムリー'), findsWidgets);
    expect(find.text('中安'), findsOneWidget);
  });

  testWidgets('活躍打者成績は本塁打タイムリー安打と打点犠打犠飛だけ', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 6,
                  'score_away': 2,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'id_league_home': 1,
                  'id_league_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 2,
                      'name_full_summary': '佐藤輝明',
                      'flg_pitcher': false,
                      'txt_plays': '四球|walk 中安|single 三振|out 2点犠打|sacbunt 犠飛|sacfly 左タイムリー|timely ソロホームラン|hr',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 2,
                      'order': 4,
                      'players': [
                        {
                          'name': '佐藤 輝明',
                          'pos': '三',
                          'plays': '四球|walk 中安|single 三振|out 2点犠打|sacbunt 犠飛|sacfly 左タイムリー|timely ソロホームラン|hr',
                        },
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('佐藤輝明'), findsWidgets);
    expect(find.text('中安'), findsOneWidget);
    expect(find.text('2点犠打'), findsOneWidget);
    expect(find.text('犠飛'), findsOneWidget);
    expect(find.text('タイムリー'), findsOneWidget);
    expect(find.text('ソロホームラン'), findsOneWidget);
    expect(find.text('四球'), findsNothing);
    expect(find.text('三振'), findsNothing);
  });

  testWidgets('error and interference RBI only is not a notable batter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 560,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 3,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'id_league_home': 1,
                  'id_league_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 2,
                      'name_full_summary': '近本光司',
                      'flg_pitcher': false,
                      'txt_plays': '投失|error',
                    },
                    {
                      'id_game_summary': 2,
                      'id_team_summary': 2,
                      'name_full_summary': '中野拓夢',
                      'flg_pitcher': false,
                      'txt_plays': '打妨|dead',
                    },
                    {
                      'id_game_summary': 3,
                      'id_team_summary': 2,
                      'name_full_summary': '森下翔太',
                      'flg_pitcher': false,
                      'txt_plays': '遊選|fc',
                    },
                    {
                      'id_game_summary': 4,
                      'id_team_summary': 1,
                      'name_full_summary': '坂本勇人',
                      'flg_pitcher': false,
                      'txt_plays': '左タイムリー|timely',
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('近本光司'), findsNothing);
    expect(find.text('中野拓夢'), findsNothing);
    expect(find.text('森下翔太'), findsNothing);
    expect(find.text('坂本勇人'), findsOneWidget);
    expect(find.textContaining('タイムリー'), findsOneWidget);
  });

  testWidgets('MLB error and interference RBI only is not a notable batter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 560,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '🌙 08:00',
                  'name_team_home': 'ドジャース',
                  'name_team_away': 'フィリーズ',
                  'name_stadium': 'ドジャー・スタジアム',
                  'name_pitcher_home': '山本由伸',
                  'name_pitcher_away': 'Wheeler',
                  'score_home': 3,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 301,
                  'id_team_away': 302,
                  'id_league_home': 3,
                  'id_league_away': 4,
                  'color_back_home': '#005A9C',
                  'color_back_away': '#E81828',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 301,
                      'name_full_summary': 'M. Rojas',
                      'flg_pitcher': false,
                      'txt_plays': '投失|error',
                    },
                    {
                      'id_game_summary': 2,
                      'id_team_summary': 301,
                      'name_full_summary': 'T. Hernández',
                      'flg_pitcher': false,
                      'txt_plays': '打妨|dead',
                    },
                    {
                      'id_game_summary': 3,
                      'id_team_summary': 302,
                      'name_full_summary': 'S.大谷',
                      'flg_pitcher': false,
                      'txt_plays': '中安|single 左2点タイムリー|timely',
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('M.Rojas'), findsNothing);
    expect(find.text('T.Hernández'), findsNothing);
    expect(find.text('S.大谷'), findsOneWidget);
    expect(find.text('中安'), findsOneWidget);
    expect(find.textContaining('タイムリー'), findsOneWidget);
  });

  testWidgets('player names drop spaces between family and given', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            height: 180,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '18:00',
                  'name_team_home': 'ドジャース',
                  'name_team_away': 'パドレス',
                  'name_stadium': 'ドジャー・スタジアム',
                  'name_pitcher_home': '山本　由伸',
                  'name_pitcher_away': 'M. キング',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '試合前',
                  'id_team_home': 301,
                  'id_team_away': 302,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'color_back_home': '#005A9C',
                  'color_back_away': '#2F241D',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('山本由伸'), findsWidgets);
    expect(find.text('M.キング'), findsWidgets);
    expect(find.text('山本　由伸'), findsNothing);
    expect(find.text('M. キング'), findsNothing);
  });

  testWidgets('multiple pinch players keep all batting chips left of names', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 280,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-06',
                  'time_game': '🌙 05:00',
                  'name_team_home': 'ホワイトソックス',
                  'name_team_away': 'ガーディアンズ',
                  'name_stadium': 'プログレッシブフィールド',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 2,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 201,
                  'id_team_away': 202,
                  'id_league_home': 3,
                  'id_league_away': 3,
                  'color_back_home': '#000000',
                  'color_back_away': '#0C2340',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 201,
                      'name_full_summary': 'A.ベニンテンディ',
                      'flg_pitcher': false,
                      'txt_plays': '中安|single 四球|walk 左飛|out 右タイムリー|timely',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 201,
                      'order': 5,
                      'players': [
                        {'name': 'L.サラベラ', 'pos': '遊', 'plays': '右安|single'},
                      ],
                    },
                    {
                      'id_team': 201,
                      'order': 6,
                      'players': [
                        {
                          'name': 'A.ベニンテンディ',
                          'pos': '左',
                          'plays': '中安|single 四球|walk 左飛|out 右タイムリー|timely',
                        },
                        {
                          'name': 'M.バルガス',
                          'pos': '指',
                          'role': '代打',
                          'plays': '二ゴ|out',
                        },
                        {
                          'name': 'L.ロバート',
                          'pos': '中',
                          'role': '代走',
                          'plays': '三ゴ|out',
                        },
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('詳細表示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('中安'), findsOneWidget);
    expect(find.text('四球'), findsOneWidget);
    expect(find.text('左飛'), findsOneWidget);
    expect(find.text('二ゴ'), findsOneWidget);
    expect(find.text('三ゴ'), findsOneWidget);
    expect(find.text('右安'), findsWidgets);
    expect(find.text('代打 M.バルガス'), findsOneWidget);
    expect(find.text('代走 L.ロバート'), findsOneWidget);
    expect(find.textContaining('：'), findsNothing);
    expect(find.byKey(const ValueKey('pinch-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('pinch-badge-1')), findsOneWidget);
    final caption0 = tester.widget<Container>(find.byKey(const ValueKey('pinch-caption-0')));
    final caption1 = tester.widget<Container>(find.byKey(const ValueKey('pinch-caption-1')));
    expect((caption0.decoration as BoxDecoration).color, const Color(0xFF5C6BC0));
    expect((caption1.decoration as BoxDecoration).color, const Color(0xFF3F51B5));
    expect(tester.widget<Text>(find.text('中安')).style?.fontSize, tester.widget<Text>(find.text('右安').first).style?.fontSize);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.getTopLeft(find.text('二ゴ')).dx, lessThan(tester.getTopLeft(find.text('代打 M.バルガス')).dx));
    expect(tester.getTopLeft(find.text('三ゴ')).dx, lessThan(tester.getTopLeft(find.text('代走 L.ロバート')).dx));
    expect(tester.getTopLeft(find.text('三ゴ')).dx, greaterThan(tester.getTopRight(find.text('二ゴ')).dx - 1));
  });

  testWidgets('NPB all-batters attach steal badges to the batting chip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 280,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-03',
                  'time_game': '🌙 18:00',
                  'name_team_home': 'ソフトバンク',
                  'name_team_away': 'ロッテ',
                  'name_stadium': 'PayPayドーム',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 3,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 7,
                  'id_team_away': 12,
                  'id_league_home': 2,
                  'id_league_away': 2,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#000000',
                  'color_font_home': '#000000',
                  'color_font_away': '#FFFFFF',
                  'lineup': [
                    {
                      'id_team': 7,
                      'order': 1,
                      'players': [
                        {
                          'name': '周東佑京',
                          'pos': '遊',
                          'plays': '中安|single 盗塁|steal',
                        },
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('詳細表示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('中安'), findsOneWidget);
    expect(find.text('盗塁'), findsNothing);
    expect(find.byKey(const ValueKey('steal-badge')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('steal-badge'))).dx,
      greaterThan(tester.getTopLeft(find.text('中安')).dx - 4),
    );
  });

  testWidgets('finished NPB pitcher max velo blinks rorange then crimson', (tester) async {
    Future<void> pumpVelo(int kmh) {
      return tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 520,
              height: 200,
              child: GamesBoardYahooStyle(initialStatsExpanded: true, 
                games: [
                  {
                    'date_game': '2026-10-07',
                    'time_game': '18:00',
                    'name_team_home': '阪神',
                    'name_team_away': '巨人',
                    'name_stadium': '甲子園',
                    'name_pitcher_home': '村上頌樹',
                    'name_pitcher_away': '戸郷翔征',
                    'score_home': 3,
                    'score_away': 1,
                    'state': '試合終了',
                    'id_team_home': 2,
                    'id_team_away': 1,
                    'id_league_home': 1,
                    'id_league_away': 1,
                    'color_back_home': '#FFD200',
                    'color_back_away': '#FF6600',
                    'color_font_home': '#000000',
                    'color_font_away': '#000000',
                    'summaries': [
                      {
                        'id_game_summary': 1,
                        'id_team_summary': 2,
                        'name_full_summary': '村上頌樹',
                        'flg_pitcher': true,
                        'txt_pitch_chips': '6回1失点|green 被安打4|green 1BB|green 6K|green 90球|',
                        'int_velo_max': kmh,
                      },
                    ],
                  },
                ],
                horizontal: true,
              ),
            ),
          ),
        ),
      );
    }

    await pumpVelo(157);
    await tester.pump();
    expect(find.text('157km'), findsOneWidget);
    expect(find.ancestor(of: find.text('157km'), matching: find.byType(BlinkBg)), findsOneWidget);
    expect(tester.getTopLeft(find.text('157km')).dx, greaterThan(tester.getTopLeft(find.text('90球')).dx));
    await pumpVelo(162);
    await tester.pump();
    expect(find.text('162km'), findsOneWidget);
    expect(find.ancestor(of: find.text('162km'), matching: find.byType(BlinkBg)), findsOneWidget);
    expect(find.text('157km'), findsNothing);
  });

  testWidgets('finished MLB pitcher max velo shows mph', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 520,
            height: 200,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '08:00',
                  'name_team_home': 'ドジャース',
                  'name_team_away': 'パドレス',
                  'name_stadium': 'ドジャー・スタジアム',
                  'name_pitcher_home': '山本由伸',
                  'name_pitcher_away': 'キング',
                  'score_home': 4,
                  'score_away': 2,
                  'state': '試合終了',
                  'id_team_home': 301,
                  'id_team_away': 302,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'color_back_home': '#005A9C',
                  'color_back_away': '#2F241D',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 301,
                      'name_full_summary': '山本由伸',
                      'flg_pitcher': true,
                      'txt_pitch_chips': '7回無失点|crimson 被安打3|green 1BB|green 8K|green 99球|',
                      'int_velo_max': 161,
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('100mph'), findsOneWidget);
    expect(find.ancestor(of: find.text('100mph'), matching: find.byType(BlinkBg)), findsOneWidget);
    expect(tester.getTopLeft(find.text('100mph')).dx, greaterThan(tester.getTopLeft(find.text('99球')).dx));
  });

  testWidgets('試合中の詳細表示は未打席のスタメンも9人出す', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 420,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '☀️ 07:00',
                  'name_team_home': 'ブレーブス',
                  'name_team_away': 'ドジャース',
                  'name_stadium': 'トゥルイストパーク',
                  'name_pitcher_home': 'L.トーマス',
                  'name_pitcher_away': '山本',
                  'score_home': 0,
                  'score_away': 0,
                  'state': '2回表',
                  'id_team_home': 41,
                  'id_team_away': 35,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'color_back_home': '#CE1141',
                  'color_back_away': '#005A9C',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'lineup': [
                    for (final entry in [
                      (1, '大谷翔平', '指', '四球|walk'),
                      (2, 'ベッツ', '遊', '中安|single'),
                      (3, 'フリーマン', '一', ''),
                      (4, 'スミス', '捕', ''),
                      (5, 'テオスカー', '右', ''),
                      (6, 'エドマン', '三', ''),
                      (7, 'ペイジズ', '中', ''),
                      (8, 'キケ', '左', ''),
                      (9, 'ロハス', '二', ''),
                    ])
                      {
                        'id_team': 35,
                        'order': entry.$1,
                        'players': [
                          {'name': entry.$2, 'pos': entry.$3, 'plays': entry.$4},
                        ],
                      },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('詳細表示'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    expect(find.text('大谷翔平'), findsWidgets);
    expect(find.text('ベッツ'), findsWidgets);
    expect(find.text('フリーマン'), findsWidgets);
    expect(find.text('スミス'), findsWidgets);
    expect(find.text('テオスカー'), findsWidgets);
    expect(find.text('エドマン'), findsWidgets);
    expect(find.text('ペイジズ'), findsWidgets);
    expect(find.text('キケ'), findsWidgets);
    expect(find.text('ロハス'), findsWidgets);
  });

  testWidgets('詳細表示は打点のあるアウトにも打点バッジを付ける', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 520,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '☀️ 07:00',
                  'name_team_home': 'ブレーブス',
                  'name_team_away': 'ドジャース',
                  'name_stadium': 'トゥルイストパーク',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 1,
                  'score_away': 3,
                  'state': '試合終了',
                  'id_team_home': 28,
                  'id_team_away': 40,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'color_back_home': '#CE1141',
                  'color_back_away': '#005A9C',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'lineup': [
                    {
                      'id_team': 28,
                      'order': 1,
                      'players': [
                        {'name': 'ボールドウィン', 'role': '', 'pos': '捕', 'plays': '三振|out 一ゴロ|out 遊ゴロ|out', 'rbi': 1},
                      ],
                    },
                    for (var order = 2; order <= 9; order++)
                      {
                        'id_team': 28,
                        'order': order,
                        'players': [
                          {'name': '打者$order', 'role': '', 'pos': '投', 'plays': '', 'rbi': 0},
                        ],
                      },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('詳細表示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('rbi-badge-1')), findsOneWidget);
  });

  testWidgets('攻撃中の現在打者の成績ブロックは点滅する', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 520,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '☀️ 07:00',
                  'name_team_home': 'ブレーブス',
                  'name_team_away': 'ドジャース',
                  'name_stadium': 'トゥルイストパーク',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 0,
                  'score_away': 1,
                  'state': '5回裏',
                  'id_team_home': 28,
                  'id_team_away': 40,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'name_batter': 'オルソン',
                  'id_team_batter': 28,
                  'int_batter_order': 3,
                  'color_back_home': '#CE1141',
                  'color_back_away': '#005A9C',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'lineup': [
                    {
                      'id_team': 28,
                      'order': 3,
                      'players': [
                        {'name': 'オルソン', 'role': '', 'pos': '一', 'plays': '右安|single', 'rbi': 0},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('詳細表示'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(find.byKey(const ValueKey('live-batter-stats')), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    final nowBlink = tester.widget<BlinkBg>(find.byKey(const ValueKey('live-batter-stats')));
    expect(nowBlink.duration, const Duration(milliseconds: 380));
    expect(nowBlink.color, const Color(0xFFFF6D00));
    expect(nowBlink.fillMax, 1);
    final now = tester.getRect(find.byKey(const ValueKey('now-play-chip')));
    final blink = tester.getRect(find.byKey(const ValueKey('live-batter-stats')));
    final hit = tester.getRect(find.text('右安'));
    expect(now.left, greaterThan(hit.right));
    expect(now.width, closeTo(hit.width + 6, 2));
    expect(blink.left, greaterThan(hit.right - 1));
    expect(blink.width, closeTo(now.width, 2));
  });

  testWidgets('3アウトでNowは次に攻撃するチームへ移る', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 520,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '☀️ 07:00',
                  'name_team_home': 'ブレーブス',
                  'name_team_away': 'ドジャース',
                  'name_stadium': 'トゥルイストパーク',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 0,
                  'score_away': 1,
                  'state': '5回表3アウト',
                  'id_team_home': 28,
                  'id_team_away': 40,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'int_outs': 3,
                  'name_batter': 'プロファー',
                  'id_team_batter': 28,
                  'int_batter_order': 1,
                  'color_back_home': '#CE1141',
                  'color_back_away': '#005A9C',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'lineup': [
                    {
                      'id_team': 40,
                      'order': 1,
                      'players': [
                        {'name': '大谷', 'role': '', 'pos': '指', 'plays': '三振|out', 'rbi': 0},
                      ],
                    },
                    {
                      'id_team': 28,
                      'order': 1,
                      'players': [
                        {'name': 'プロファー', 'role': '', 'pos': '左', 'plays': '', 'rbi': 0},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Now'), findsOneWidget);
    final now = tester.getCenter(find.byKey(const ValueKey('now-play-chip')));
    final homeName = tester.getCenter(find.text('プロファー').first);
    final awayName = tester.getCenter(find.text('大谷').first);
    expect((now - homeName).distance, lessThan((now - awayName).distance));
  });

  testWidgets('Nowは次打者の打順だけに出し同姓の他打者には出さない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 520,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '☀️ 07:00',
                  'name_team_home': 'ロッテ',
                  'name_team_away': '阪神',
                  'name_stadium': 'ZOZOマリン',
                  'name_pitcher_home': 'A',
                  'name_pitcher_away': 'B',
                  'score_home': 1,
                  'score_away': 0,
                  'state': '5回裏',
                  'id_team_home': 12,
                  'id_team_away': 2,
                  'name_batter': '佐藤二郎',
                  'id_team_batter': 12,
                  'int_batter_order': 5,
                  'color_back_home': '#000000',
                  'color_back_away': '#FFD200',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#000000',
                  'lineup': [
                    {
                      'id_team': 12,
                      'order': 1,
                      'players': [
                        {'name': '佐藤太郎', 'role': '', 'pos': '左', 'plays': '三振|out', 'rbi': 0},
                      ],
                    },
                    {
                      'id_team': 12,
                      'order': 5,
                      'players': [
                        {'name': '佐藤二郎', 'role': '', 'pos': '遊', 'plays': '', 'rbi': 0},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Now'), findsOneWidget);
    final now = tester.getCenter(find.byKey(const ValueKey('now-play-chip')));
    final due = tester.getCenter(find.text('佐藤二郎').first);
    final other = tester.getCenter(find.text('佐藤太郎').first);
    expect((now - due).distance, lessThan((now - other).distance));
  });

  testWidgets('非打撃の得点は直後の打撃の左上に青バッジを付け打点にはしない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 420,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '18:00',
                  'name_team_home': 'パドレス',
                  'name_team_away': 'ブルワーズ',
                  'name_stadium': 'ペトコパーク',
                  'score_home': 1,
                  'score_away': 0,
                  'state': '6回表',
                  'id_team_home': 41,
                  'id_team_away': 35,
                  'color_back_home': '#2F241D',
                  'color_back_away': '#12284B',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'lineup': [
                    {
                      'id_team': 41,
                      'order': 3,
                      'players': [
                        {'name': 'マニー・マチャド', 'pos': '三', 'plays': '中安|single/run', 'rbi': 0},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('run-badge-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('rbi-badge-1')), findsNothing);
    expect(find.text('中安'), findsOneWidget);
  });

  testWidgets('詳細表示のタイムリーとライナーは打球方向を残す', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 420,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '☀️ 08:00',
                  'name_team_home': 'ブルワーズ',
                  'name_team_away': 'パドレス',
                  'name_stadium': 'アメリカンファミリーフィールド',
                  'score_home': 2,
                  'score_away': 1,
                  'state': '6回表',
                  'id_team_home': 35,
                  'id_team_away': 41,
                  'color_back_home': '#12284B',
                  'color_back_away': '#2F241D',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 41,
                      'name_full_summary': 'M.マチャド',
                      'flg_pitcher': false,
                      'txt_plays': '安|single',
                      'txt_batting': '3打数1安打(1打点1四球)',
                    },
                    {
                      'id_game_summary': 2,
                      'id_team_summary': 35,
                      'name_full_summary': 'W.コントレラス',
                      'flg_pitcher': false,
                      'txt_plays': 'ホームラン|hr 安|single 安|single',
                      'txt_batting': '4打数3安打(1本塁打1打点1四球)',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 41,
                      'order': 3,
                      'players': [
                        {'name': 'マニー・マチャド', 'pos': '三', 'plays': '四球|walk タイムリー^左|timely 左ライナー|out 投ゴロ|out'},
                      ],
                    },
                    {
                      'id_team': 35,
                      'order': 3,
                      'players': [
                        {'name': 'ウィリアム・コントレラス', 'pos': '捕', 'plays': '中フライ|out ソロホームラン^左|hr 遊安|single 中安|single 四球|walk'},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('詳細表示'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(find.text('四球'), findsNWidgets(2));
    expect(find.text('左安'), findsOneWidget);
    expect(find.text('左直'), findsOneWidget);
    expect(find.text('投ゴ'), findsOneWidget);
    expect(find.text('中飛'), findsOneWidget);
    expect(find.text('左本'), findsOneWidget);
    expect(find.text('遊安'), findsOneWidget);
    expect(find.text('中安'), findsOneWidget);
    expect(find.text('安'), findsNothing);
    expect(find.text('本'), findsNothing);
    expect(find.text('飛'), findsNothing);
    expect(find.text('直'), findsNothing);
  });

  testWidgets('活躍表示は要約の安で出場記録の打席を上書きしない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 280,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '☀️ 08:00',
                  'name_team_home': 'ブルワーズ',
                  'name_team_away': 'パドレス',
                  'name_stadium': 'アメリカンファミリーフィールド',
                  'score_home': 2,
                  'score_away': 1,
                  'state': '試合終了',
                  'id_team_home': 35,
                  'id_team_away': 41,
                  'color_back_home': '#12284B',
                  'color_back_away': '#2F241D',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 41,
                      'name_full_summary': 'M.マチャド',
                      'flg_pitcher': false,
                      'txt_plays': '安|single',
                      'txt_batting': '3打数1安打(1打点1四球)',
                    },
                    {
                      'id_game_summary': 2,
                      'id_team_summary': 35,
                      'name_full_summary': 'W.コントレラス',
                      'flg_pitcher': false,
                      'txt_plays': 'ホームラン|hr 安|single 安|single',
                      'txt_batting': '4打数3安打(1本塁打1打点1四球)',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 41,
                      'order': 3,
                      'players': [
                        {'name': 'マニー・マチャド', 'pos': '三', 'plays': '四球|walk タイムリー^左|timely 左ライナー|out 投ゴロ|out', 'rbi': 1},
                      ],
                    },
                    {
                      'id_team': 35,
                      'order': 3,
                      'players': [
                        {'name': 'ウィリアム・コントレラス', 'pos': '捕', 'plays': '中フライ|out ソロホームラン^左|hr 遊安|single 中安|single 四球|walk', 'rbi': 1},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('詳細表示'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(find.text('タイムリー'), findsOneWidget);
    expect(find.text('ソロホームラン'), findsOneWidget);
    expect(find.text('遊安'), findsOneWidget);
    expect(find.text('中安'), findsOneWidget);
    expect(find.text('安'), findsNothing);
    expect(find.text('ホームラン'), findsNothing);
    expect(find.textContaining('左ホームラン'), findsNothing);
    expect(find.text('左タイムリー'), findsNothing);
  });

  testWidgets('予告先発のスタッツ1位は金色ヘッダーで追加表示する', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 520,
            height: 320,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              playerStats: [
                {
                  'title': 'WHIP',
                  'name_player': '戸郷翔征',
                  'int_rank': 1,
                  'id_league': 1,
                  'stats': '0.98',
                },
                {
                  'title': '防御率',
                  'name_player': '戸郷翔征',
                  'int_rank': 1,
                  'id_league': 1,
                  'stats': '2.41',
                },
              ],
              games: [
                {
                  'date_game': '2026-10-08',
                  'time_game': '18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '村上頌樹',
                  'name_pitcher_away': '戸郷翔征',
                  'id_league_home': 1,
                  'id_league_away': 1,
                  'txt_season_pitcher_home': '10勝5敗 1.85 142奪三振 規定98.2%',
                  'txt_season_pitcher_away': '8勝7敗 2.41 128奪三振 規定123.4%',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('WHIP'), findsOneWidget);
    expect(find.text('0.98'), findsOneWidget);
    Color chipColor(String label) {
      final chip = tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
      );
      return (chip.decoration as BoxDecoration).color!;
    }
    expect(chipColor('WHIP'), const Color(0xFFFFD700));
    expect(
      [
        for (var i = 0; i < find.text('防御率').evaluate().length; i++)
          ((tester.widget<Container>(
            find.ancestor(of: find.text('防御率').at(i), matching: find.byType(Container)).first,
          ).decoration as BoxDecoration).color),
      ].contains(const Color(0xFFFFD700)),
      isTrue,
    );
    expect(find.text('👑'), findsNWidgets(2));
    Finder crownNear(String value) {
      final origin = tester.getCenter(find.textContaining(value).first);
      Finder nearest = find.text('👑').first;
      var best = 1e9;
      for (var i = 0; i < find.text('👑').evaluate().length; i++) {
        final crown = find.text('👑').at(i);
        final center = tester.getCenter(crown);
        if (center.dx <= origin.dx) continue;
        final gap = (center.dy - origin.dy).abs() * 20 + (center.dx - origin.dx);
        if (gap < best) {
          best = gap;
          nearest = crown;
        }
      }
      return nearest;
    }

    expect(tester.getTopLeft(crownNear('0.98')).dx, greaterThan(tester.getTopRight(find.text('0.98')).dx - 2));
    expect((tester.getCenter(crownNear('0.98')).dy - tester.getCenter(find.text('0.98')).dy).abs(), lessThan(8));
    final eraValue = find.textContaining('2.41');
    expect(tester.getTopLeft(crownNear('2.41')).dx, greaterThan(tester.getTopRight(eraValue).dx - 2));
  });

  testWidgets('失策の得点は青バッジで打点にはしない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 420,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '☀️ 08:00',
                  'name_team_home': 'カブス',
                  'name_team_away': 'パドレス',
                  'score_home': 3,
                  'score_away': 4,
                  'state': '7回表',
                  'id_team_home': 20,
                  'id_team_away': 41,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'color_back_home': '#0E3386',
                  'color_back_away': '#2F241D',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'lineup': [
                    {
                      'id_team': 41,
                      'order': 7,
                      'players': [
                        {'name': 'アンドゥハー', 'pos': '左', 'role': '代打', 'plays': '遊失|error/run', 'rbi': 0},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('run-badge-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('rbi-badge-1')), findsNothing);
    expect(find.text('遊失'), findsOneWidget);
  });

  testWidgets('タティスの打点は2打席目の遊ゴにつける', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 720,
            height: 420,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-07',
                  'time_game': '☀️ 08:00',
                  'name_team_home': 'カブス',
                  'name_team_away': 'パドレス',
                  'score_home': 3,
                  'score_away': 4,
                  'state': '試合終了',
                  'id_team_home': 20,
                  'id_team_away': 41,
                  'id_league_home': 4,
                  'id_league_away': 4,
                  'color_back_home': '#0E3386',
                  'color_back_away': '#2F241D',
                  'color_font_home': '#FFFFFF',
                  'color_font_away': '#FFFFFF',
                  'lineup': [
                    {
                      'id_team': 41,
                      'order': 2,
                      'players': [
                        {
                          'name': 'タティス',
                          'pos': '右',
                          'plays': '三振|out 遊ゴロ|out/rbi 中飛|out 遊ゴロ|out',
                          'rbi': 1,
                        },
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('詳細表示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('rbi-badge-1')), findsOneWidget);
    expect(find.text('遊ゴ'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('rbi-badge-1'))).dx,
      closeTo(tester.getTopLeft(find.text('遊ゴ').first).dx, 16),
    );
  });

  test('クライマックスの見出しはCSステージ名と緑青グラデーション', () {
    final central = npbClimaxHeader(
      leagueId: 1,
      fallbackLabel: 'セ・リーグ',
      games: [
        {'code_game': 'CS1', 'date_game': '2026-10-11', 'id_league_home': 1, 'id_league_away': 1},
      ],
    );
    expect(central.label, 'CS 1st STAGE');
    expect(central.logoAsset, 'backend/assets/images/logo_cs_central.png');
    expect(central.gradient, isNotNull);
    final pacific = npbClimaxHeader(
      leagueId: 2,
      fallbackLabel: 'パ・リーグ',
      games: [
        {'code_game': 'CS2', 'date_game': '2026-10-15', 'id_league_home': 2, 'id_league_away': 2},
      ],
    );
    expect(pacific.label, 'CS FINAL STAGE');
    expect(pacific.logoAsset, 'backend/assets/images/logo_cs_pacific.png');
    final regular = npbClimaxHeader(
      leagueId: 1,
      fallbackLabel: 'セ・リーグ',
      games: [
        {'code_game': 'NM', 'date_game': '2026-09-01'},
      ],
    );
    expect(regular.label, 'セ・リーグ');
    expect(regular.logoAsset, isNull);
  });

  testWidgets('スタメン発表前は守備欄を出さない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 720,
            height: 280,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-08',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '村上',
                  'name_pitcher_away': '戸郷',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '試合前',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('守備'), findsNothing);
  });

  testWidgets('予告先発が無い試合前は投手欄を出さない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 720,
            height: 220,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-08',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'score_home': -1,
                  'score_away': -1,
                  'state': '試合前',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('投手'), findsNothing);
    expect(find.text('試合前'), findsOneWidget);
  });

  testWidgets('予告先発が無い試合前はカード下部を余白で伸ばさない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: GamesBoardYahooStyle(
              games: [
                {
                  'date_game': '2026-10-10',
                  'time_game': '14:00',
                  'name_team_home': 'DeNA',
                  'name_team_away': '巨人',
                  'name_stadium': '東京ドーム',
                  'state': '試合前',
                  'score_home': -1,
                  'score_away': -1,
                  'id_team_home': 3,
                  'id_team_away': 1,
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final height = tester.getSize(find.byKey(const ValueKey('game-card-shell-2026-10-10|DeNA|巨人'))).height;
    expect(height, lessThan(160));
  });

  testWidgets('守備図はスタメンと代守とE/FPを出す', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 900,
            height: 520,
            child: GamesBoardYahooStyle(initialStatsExpanded: true, 
              games: [
                {
                  'date_game': '2026-10-08',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '西武',
                  'name_stadium': 'ベルーナドーム',
                  'path_image_inside': 'backend/assets/images/stadiums/inside/npb-03-belluna.jpg',
                  'path_image_outside': 'backend/assets/images/stadiums/outside/npb-03-belluna.png',
                  'name_pitcher_home': '村上',
                  'name_pitcher_away': '今井',
                  'score_home': 2,
                  'score_away': 1,
                  'state': '8回裏',
                  'id_team_home': 2,
                  'id_team_away': 8,
                  'id_league_home': 1,
                  'id_league_away': 2,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#003399',
                  'color_font_home': '#000000',
                  'color_font_away': '#FFFFFF',
                  'summaries': [
                    {
                      'id_game_summary': 1,
                      'id_team_summary': 8,
                      'name_full_summary': '今井達也',
                      'flg_pitcher': true,
                      'txt_pitching': '7回1失点',
                    },
                  ],
                  'lineup': [
                    {
                      'id_team': 8,
                      'order': 2,
                      'players': [
                        {'name': '源田壮亮', 'pos': '遊', 'field_marks': 'E'},
                        {'name': '外崎修汰', 'pos': '遊', 'role': '代守', 'field_marks': 'FP'},
                      ],
                    },
                    {
                      'id_team': 8,
                      'order': 4,
                      'players': [
                        {'name': '山川穂高', 'pos': '一'},
                      ],
                    },
                    {
                      'id_team': 8,
                      'order': 5,
                      'players': [
                        {'name': '渡部健人', 'pos': '三'},
                      ],
                    },
                    {
                      'id_team': 8,
                      'order': 6,
                      'players': [
                        {'name': '森友哉', 'pos': '捕'},
                      ],
                    },
                    {
                      'id_team': 8,
                      'order': 3,
                      'players': [
                        {'name': 'コルデロ', 'pos': '指'},
                      ],
                    },
                    {
                      'id_team': 8,
                      'order': 1,
                      'players': [
                        {'name': '児玉亮涼', 'pos': '二'},
                      ],
                    },
                    {
                      'id_team': 8,
                      'order': 7,
                      'players': [
                        {'name': '西川愛也', 'pos': '左'},
                      ],
                    },
                    {
                      'id_team': 8,
                      'order': 8,
                      'players': [
                        {'name': '西川龍馬', 'pos': '中'},
                      ],
                    },
                    {
                      'id_team': 8,
                      'order': 9,
                      'players': [
                        {'name': '今井達也', 'pos': '投'},
                        {'name': '平良海馬', 'pos': '投', 'role': '代守'},
                      ],
                    },
                  ],
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('守備'), findsWidgets);
    expect(find.text('源田壮亮'), findsWidgets);
    expect(find.text('(外崎修汰)'), findsOneWidget);
    expect(find.byKey(const ValueKey('field-mark-E')), findsOneWidget);
    expect(find.byKey(const ValueKey('field-mark-FP')), findsOneWidget);
    expect(find.text('ベルーナドーム'), findsOneWidget);
    Color bgOf(String name) {
      final box = tester.widget<Container>(find.byKey(ValueKey('defense-bg-$name')));
      return (box.decoration! as BoxDecoration).color!;
    }

    expect(bgOf('源田壮亮'), const Color(0xFFFFEB3B));
    expect(bgOf('西川愛也'), const Color(0xFFC6FF00));
    expect(bgOf('森友哉'), const Color(0xFF1E88E5));
    expect(bgOf('コルデロ'), const Color(0xFF8E24AA));
    expect(find.byKey(const ValueKey('defense-name-平良海馬')), findsOneWidget);
    expect(find.byKey(const ValueKey('defense-name-今井達也')), findsNothing);
    final first = tester.getCenter(find.byKey(const ValueKey('defense-name-山川穂高')));
    final third = tester.getCenter(find.byKey(const ValueKey('defense-name-渡部健人')));
    final pitcher = tester.getCenter(find.byKey(const ValueKey('defense-name-平良海馬')));
    final catcher = tester.getCenter(find.byKey(const ValueKey('defense-name-森友哉')));
    final dh = tester.getCenter(find.byKey(const ValueKey('defense-name-コルデロ')));
    expect(first.dy, greaterThan(pitcher.dy + 8));
    expect(third.dy, greaterThan(pitcher.dy + 8));
    expect(first.dx, greaterThan(pitcher.dx));
    expect(third.dx, lessThan(pitcher.dx));
    expect(catcher.dy, greaterThan(third.dy + 8));
    expect(dh.dy, greaterThan(third.dy + 8));
    expect(dh.dx, lessThan(catcher.dx - 4));
    final second = tester.getCenter(find.byKey(const ValueKey('defense-name-児玉亮涼')));
    final short = tester.getCenter(find.byKey(const ValueKey('defense-name-源田壮亮')));
    final center = tester.getCenter(find.byKey(const ValueKey('defense-name-西川龍馬')));
    final left = tester.getCenter(find.byKey(const ValueKey('defense-name-西川愛也')));
    expect(second.dx, greaterThan(short.dx + 16));
    expect(center.dy, lessThan(left.dy - 6));

    await tester.tap(find.text('詳細表示'));
    await tester.pump();
    expect(find.text('守備'), findsNothing);
    expect(find.byKey(const ValueKey('defense-name-平良海馬')), findsNothing);
  });

  testWidgets('選手成績は初期表示では畳まれていて開閉できる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 520,
            child: GamesBoardYahooStyle(
              games: [
                {
                  'date_game': '2026-10-08',
                  'time_game': '🌙 18:00',
                  'name_team_home': '阪神',
                  'name_team_away': '巨人',
                  'name_stadium': '甲子園',
                  'name_pitcher_home': '村上頌樹',
                  'name_pitcher_away': '戸郷翔征',
                  'score_home': 1,
                  'score_away': 0,
                  'state': '5回裏',
                  'id_team_home': 2,
                  'id_team_away': 1,
                  'color_back_home': '#FFD200',
                  'color_back_away': '#FF6600',
                  'color_font_home': '#000000',
                  'color_font_away': '#000000',
                },
              ],
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('選手成績'), findsOneWidget);
    expect(find.text('詳細表示'), findsNothing);
    expect(find.text('投手'), findsNothing);
    expect(find.text('村上頌樹'), findsNothing);
    expect(find.text('5回裏'), findsOneWidget);

    final shell = find.byKey(const ValueKey('game-card-shell-2026-10-08|阪神|巨人'));
    final collapsedCard = tester.getSize(shell);
    await tester.tap(find.text('選手成績'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final openingCard = tester.getSize(shell);
    expect(openingCard.height, greaterThan(collapsedCard.height + 8));
    expect(openingCard.height, lessThan(collapsedCard.height + 420));

    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('投手'), findsOneWidget);
    expect(find.text('村上頌樹'), findsWidgets);
    final roster = tester.getRect(find.text('詳細表示'));
    final statsHeader = tester.getRect(find.text('選手成績'));
    expect(roster.top, greaterThan(statsHeader.bottom - 1));
    expect(roster.top, lessThan(statsHeader.bottom + 24));
    final openedCard = tester.getSize(shell);
    expect(openedCard.height, greaterThan(openingCard.height));

    await tester.tap(find.text('選手成績'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final closingCard = tester.getSize(shell);
    expect(closingCard.height, lessThan(openedCard.height));
    expect(closingCard.height, greaterThan(120));

    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('投手'), findsNothing);
    expect(find.text('村上頌樹'), findsNothing);
    expect(find.text('詳細表示'), findsNothing);
  });
}
