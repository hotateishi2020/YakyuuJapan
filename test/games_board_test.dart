import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/BlinkBg.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';

void main() {
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
            child: GamesBoardYahooStyle(
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
            height: 160,
            child: GamesBoardYahooStyle(
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
    expect(find.text('DeNA'), findsNWidgets(2));
    expect(find.text('東克樹'), findsWidgets);
    expect(find.text('工藤泰己'), findsWidgets);
    expect(find.text('成瀬脩人'), findsOneWidget);
    expect(find.text('菊池涼介'), findsOneWidget);
    expect(find.text('中川虎大'), findsOneWidget);
    expect(find.text('6.1回8安打3失点(3四球3奪三振119球)'), findsOneWidget);
    expect(find.text('5回4安打2失点(2四球3奪三振92球)'), findsOneWidget);
    expect(find.text('0.2回無安打無失点'), findsOneWidget);
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
    expect(find.text('安'), findsNWidgets(2));
    final predictHon = tester.widget<Container>(
      find.ancestor(of: find.text('本'), matching: find.byType(Container)).first,
    );
    expect((predictHon.decoration as BoxDecoration).color, const Color(0xFFF44336));
    final predictAn = tester.widget<Container>(
      find.ancestor(of: find.text('安'), matching: find.byType(Container)).first,
    );
    expect((predictAn.decoration as BoxDecoration).color, const Color(0xFF0000FF));

    final homeStat = tester.widget<Text>(find.text('6.1回8安打3失点(3四球3奪三振119球)').first);
    expect(homeStat.overflow, isNot(TextOverflow.ellipsis));
    final nameWidget = tester.widget<Text>(find.text('中川虎大').first);
    expect(nameWidget.overflow, isNot(TextOverflow.ellipsis));
    final namePainter = TextPainter(
      text: TextSpan(text: '中川虎大', style: nameWidget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    expect(tester.getSize(find.text('中川虎大').first).width, greaterThanOrEqualTo(namePainter.width - 0.5));
    expect(tester.getSize(find.text('中川虎大').first).width, greaterThan(tester.getSize(find.text('東克樹').first).width));

    double columnWidth(Finder text) {
      return tester.getSize(find.ancestor(of: text, matching: find.byType(Container)).first).width;
    }

    final homeColumn = columnWidth(find.text('DeNA').first);
    final scoreColumn = columnWidth(find.text('2 - 3'));
    final awayColumn = columnWidth(find.text('広島').first);
    final centerHeader = columnWidth(find.text('投手'));
    expect(awayColumn, closeTo(homeColumn, 2));
    expect(scoreColumn, closeTo(148, 2));
    expect(centerHeader, lessThan(scoreColumn));

    final boardRect = tester.getRect(find.byType(GamesBoardYahooStyle));
    expect(tester.getRect(find.text('中川虎大').first).bottom, lessThanOrEqualTo(boardRect.bottom + 0.5));
    expect(tester.getRect(find.text('成瀬脩人').first).bottom, lessThanOrEqualTo(boardRect.bottom + 0.5));

    final timeTop = tester.getTopLeft(find.textContaining('🌙 18:00').first).dy;
    final pitcherTop = tester.getTopLeft(find.text('投手').first).dy;
    expect(pitcherTop - timeTop, greaterThanOrEqualTo(40));

    final homeStatX = tester.getTopLeft(find.text('6.1回8安打3失点(3四球3奪三振119球)').first).dx;
    final shortStatX = tester.getTopLeft(find.text('0.2回無安打無失点').first).dx;
    expect(homeStatX, closeTo(shortStatX, 1.0));

    final predictX = tester.getTopLeft(find.text('本').first).dx;
    final batterNameRight = tester.getTopRight(find.text('成瀬脩人').first).dx;
    expect(predictX, greaterThan(batterNameRight));
    expect(tester.getTopLeft(find.text('安').first).dx, greaterThan(tester.getTopRight(find.text('本').first).dx - 0.5));

    final nameRight = tester.getTopRight(find.text('東克樹').first).dx;
    expect(homeStatX, greaterThan(nameRight + 3));
    expect(
      tester.getRect(find.text('東克樹').first).overlaps(tester.getRect(find.text('6.1回8安打3失点(3四球3奪三振119球)').first)),
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
    expect(statsScrolls, findsNWidgets(3));

    final longBefore = tester.getTopLeft(find.text('6.1回8安打3失点(3四球3奪三振119球)').first).dx;
    final shortBefore = tester.getTopLeft(find.text('0.2回無安打無失点').first).dx;
    final nameBefore = tester.getTopLeft(find.text('東克樹').first).dx;
    await tester.drag(statsScrolls.first, const Offset(-60, 0));
    await tester.pump();
    final longAfter = tester.getTopLeft(find.text('6.1回8安打3失点(3四球3奪三振119球)').first).dx;
    final shortAfter = tester.getTopLeft(find.text('0.2回無安打無失点').first).dx;
    expect(longAfter, lessThan(longBefore - 1));
    expect(shortAfter, closeTo(longAfter + (shortBefore - longBefore), 1.0));
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
            child: GamesBoardYahooStyle(
              games: nested,
              horizontal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('DeNA'), findsNWidgets(2));
    expect(find.text('広島'), findsNWidgets(2));
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
    expect(find.textContaining('昨日'), findsOneWidget);

    await tester.tap(find.text('次の日'));
    await tester.pump();
    expect(find.textContaining('今日'), findsOneWidget);

    await tester.tap(find.text('次の日'));
    await tester.pump();
    expect(find.textContaining('明日'), findsOneWidget);

    await tester.tap(find.text('前の日'));
    await tester.pump();
    expect(find.textContaining('今日'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(tester.takeException(), isNull);
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
            child: GamesBoardYahooStyle(
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
    expect(homeName.dx, closeTo(homeTeam.dx, 16.0));
    final awayName = tester.getCenter(find.text('先発ヤクルト').first);
    final awayTeam = tester.getCenter(find.text('ヤクルト').first);
    expect(awayName.dx, closeTo(awayTeam.dx, 16.0));
  });

  testWidgets('unstarted starters show season stats under the name and user color on the label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            height: 280,
            child: GamesBoardYahooStyle(
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
    expect(rateRect.width, closeTo(homeChipRect.width, 0.5));
    final teamLogo = find.byWidgetPredicate((widget) {
      if (widget is! Image) return false;
      final provider = widget.image;
      return provider is AssetImage && provider.assetName.contains('team_');
    });
    final logoBox = tester.widget<SizedBox>(find.ancestor(of: teamLogo.first, matching: find.byType(SizedBox)).first);
    expect(logoBox.height, closeTo(46 * 0.9, 0.1));
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
            child: GamesBoardYahooStyle(
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
    expect(find.textContaining('128（リーグ1位）'), findsOneWidget);
    expect(find.textContaining('123.4%（リーグ'), findsNothing);
  });

  testWidgets('hold and save show prediction marks beside the pitching line', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 520,
            height: 220,
            child: GamesBoardYahooStyle(
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
          'name_full_summary': '投手$home',
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
            child: GamesBoardYahooStyle(
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

    final nameStyle = tester.widget<Text>(find.text('投手DeNA').first).style;
    expect(nameStyle?.fontSize, greaterThanOrEqualTo(8));
  });

  testWidgets('narrow cards keep full player names and clip stats', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 180,
            child: GamesBoardYahooStyle(
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
    final statFinder = find.text('6.1回8安打3失点(3四球3奪三振119球)', skipOffstage: false);
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
            child: GamesBoardYahooStyle(
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
    expect(find.text('1回表19号代打逆転サヨナラソロホームラン'), findsOneWidget);
    expect(find.textContaining('^'), findsNothing);
    expect(find.text('8回裏先制2点タイムリーツーベース'), findsOneWidget);
    expect(find.text('右3'), findsOneWidget);
    expect(find.text('左2'), findsOneWidget);
    expect(find.text('中安'), findsOneWidget);
    expect(find.text('一ゴ'), findsNothing);
    expect(find.text('犠飛'), findsOneWidget);
    expect(find.text('スクイズ'), findsOneWidget);
    expect(find.text('四球'), findsOneWidget);
    expect(find.text('犠打'), findsOneWidget);

    Color backgroundOf(String label) {
      final chip = tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
      );
      return (chip.decoration as BoxDecoration).color!;
    }

    expect(backgroundOf('1回表19号代打逆転サヨナラソロホームラン'), const Color(0xFFDC143C));
    expect(backgroundOf('8回裏先制2点タイムリーツーベース'), const Color(0xFFFF5722));
    expect(backgroundOf('右3'), const Color(0xFFFFB300));
    expect(backgroundOf('左2'), const Color(0xFFFFB300));
    expect(backgroundOf('中安'), const Color(0xFFFFEB3B));
    expect(backgroundOf('四球'), const Color(0xFF43A047));
    expect(backgroundOf('犠飛'), const Color(0xFF8E24AA));
    expect(backgroundOf('スクイズ'), const Color(0xFF8E24AA));
    expect(backgroundOf('犠打'), const Color(0xFF8E24AA));

    final nameRight = tester.getTopRight(find.text('大山悠輔')).dx;
    final labels = ['犠打', '四球', 'スクイズ', '犠飛', '中安', '左2', '右3', '8回裏先制2点タイムリーツーベース', '1回表19号代打逆転サヨナラソロホームラン'];
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
            child: GamesBoardYahooStyle(
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
    expect(find.text('2回表先制ソロホームラン'), findsOneWidget);
    expect(find.text('8回裏タイムリーツーベース'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('2打点'), findsNothing);

    await tester.tap(find.text('活躍選手'));
    await tester.pump();
    await tester.tap(find.text('全員').last);
    await tester.pump();

    expect(find.text('二併'), findsOneWidget);
    expect(find.text('三邪'), findsOneWidget);
    expect(find.text('2打点'), findsOneWidget);
    expect(find.text('代打: 周東佑京'), findsOneWidget);
    expect(find.textContaining('：'), findsNothing);
    expect(tester.widget<Text>(find.text('2打点')).style?.fontWeight, FontWeight.bold);
    expect(tester.getTopLeft(find.text('2打点')).dx, greaterThan(tester.getTopRight(find.text('右本')).dx - 0.5));
    expect(find.text('中2'), findsOneWidget);
    expect(find.text('右本'), findsOneWidget);
    expect(find.text('二併殺'), findsNothing);
    expect(find.text('三ポップ'), findsNothing);
    expect(find.text('2回表先制ソロホームラン'), findsNothing);
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
    expect(backgroundOf('中'), const Color(0xFF43A047));
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
            child: GamesBoardYahooStyle(
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
    expect(tester.getTopLeft(find.text('２ケタ奪三振')).dx, greaterThan(tester.getTopRight(find.text('9奪三振')).dx - 0.5));
  });

  testWidgets('cycle and pitching feats use their colors', (tester) async {
    const pitching = '9回無失点(無安打無四球11奪三振)';
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 180,
            child: GamesBoardYahooStyle(
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
    expect(backgroundOf('全打席出塁'), const Color(0xFFDC143C));
    expect(find.text('全打席安打'), findsOneWidget);
    expect(find.text('全打席出塁'), findsOneWidget);
    expect((tester.getCenter(find.text('全打席安打')).dy - tester.getCenter(find.text('大山悠輔')).dy).abs(), lessThan(1));
    expect((tester.getCenter(find.text('全打席出塁')).dy - tester.getCenter(find.text('髙橋遥人')).dy).abs(), greaterThan(8));
    expect(backgroundOf('サイクル未遂'), const Color(0xFFDC143C));
    expect(backgroundOf(pitching), const Color(0xFFDC143C));
    expect(tester.getTopLeft(find.text('19号ソロホームラン')).dx, greaterThan(tester.getTopRight(find.text('大山悠輔')).dx));
    expect(tester.getTopLeft(find.text('サイクルヒット')).dx, greaterThan(tester.getTopRight(find.text('19号ソロホームラン')).dx - 0.5));
    expect(tester.getTopLeft(find.text('猛打賞')).dx, greaterThan(tester.getTopRight(find.text('サイクルヒット')).dx - 0.5));
    expect(tester.getTopLeft(find.text('全打席安打')).dx, greaterThan(tester.getTopRight(find.text('猛打賞')).dx - 0.5));
    expect(tester.getTopLeft(find.text('全打席出塁')).dx, greaterThan(tester.getTopRight(find.text('全打席安打')).dx - 0.5));
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
            child: GamesBoardYahooStyle(
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
    expect(backgroundOf('四死球0'), const Color(0xFFDC143C));
    expect(backgroundOf('被安打3'), const Color(0xFFFFB300));
    expect(backgroundOf('10奪三振'), const Color(0xFFDC143C));
    expect(find.text('QS'), findsNothing);
    final labels = ['9回無失点', '被安打3', '四死球0', '10奪三振', '98球', '完封', 'HQS', '本'];
    var previousRight = tester.getTopRight(find.text('髙橋遥人')).dx;
    for (final label in labels) {
      expect(tester.getTopLeft(find.text(label)).dx, greaterThan(previousRight - 0.5));
      previousRight = tester.getTopRight(find.text(label)).dx;
    }
  });

  testWidgets('inning scores sit below player lines with nine columns', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            height: 240,
            child: GamesBoardYahooStyle(
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

    final board = tester.getRect(find.byType(GamesBoardYahooStyle));
    final batterRect = tester.getRect(find.text('打者'));
    final scoreRect = tester.getRect(find.text('計'));
    expect(scoreRect.top, greaterThan(batterRect.bottom - 1));
    expect(tester.getRect(find.text('失')).right, greaterThan(board.right - 48));
    expect(find.text('8'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    // 4回までしかデータがなくても、5回以降は 0。両チーム分と相手の失策。
    expect(find.text('0'), findsNWidgets(17));

    Color cellColor(Finder text) {
      final box = tester.widget<Container>(find.ancestor(of: text, matching: find.byType(Container)).first);
      return (box.decoration! as BoxDecoration).color!;
    }

    expect(cellColor(find.text('計')), const Color(0xFF555555));
    expect(tester.widget<Text>(find.text('計')).style?.color, Colors.white);
    expect(cellColor(find.text('ヤクルト').at(1)), const Color(0xFF1D4E89));
    expect(cellColor(find.text('巨人').at(1)), const Color(0xFFF15A22));

    double cellW(String label) {
      return tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(Container)).first).width;
    }

    expect(cellW('計'), closeTo(cellW('1'), 0.6));
    expect(cellW('安'), closeTo(cellW('1'), 0.6));
    expect(cellW('失'), closeTo(cellW('1'), 0.6));

    bool logo(String asset) {
      return find.byWidgetPredicate((widget) {
        if (widget is! Image) return false;
        final provider = widget.image;
        return provider is AssetImage && provider.assetName == asset;
      }).evaluate().isNotEmpty;
    }

    expect(logo('backend/assets/images/team_s.png'), isTrue);
    expect(logo('backend/assets/images/team_g.png'), isTrue);
    final homeLogo = tester.getRect(find.byWidgetPredicate((widget) {
      if (widget is! Image) return false;
      final provider = widget.image;
      return provider is AssetImage && provider.assetName == 'backend/assets/images/team_s.png';
    }));
    final awayLogo = tester.getRect(find.byWidgetPredicate((widget) {
      if (widget is! Image) return false;
      final provider = widget.image;
      return provider is AssetImage && provider.assetName == 'backend/assets/images/team_g.png';
    }));
    final scoreText = tester.getRect(find.text('1 - 1'));
    final homeName = tester.getRect(find.text('ヤクルト').first);
    final awayName = tester.getRect(find.text('巨人').first);
    expect(homeLogo.center.dx, greaterThan(homeName.right));
    expect(homeLogo.center.dx, lessThan(scoreText.left));
    expect(awayLogo.center.dx, greaterThan(scoreText.right));
    expect(awayLogo.center.dx, lessThan(awayName.left));
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
            child: GamesBoardYahooStyle(
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
    expect(tester.getTopLeft(find.text('投手').first).dx, lessThan(home.dx));
  });
}
