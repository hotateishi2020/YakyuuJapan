import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/PostseasonBracket.dart';
import 'package:Yakyuu_Japan/logic/postseason_bracket.dart';

String _verticalName(WidgetTester tester, String key) {
  final texts = tester.widgetList<Text>(find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(Text),
  ));
  return texts.map((text) => text.data ?? '').where((data) => !data.endsWith('位')).join();
}

BracketTeam team({
  required int id,
  required int league,
  required int rank,
  int wins = 80,
  int losses = 60,
  double? behind = 0,
}) {
  return BracketTeam(
    id: id,
    leagueId: league,
    rank: rank,
    name: 'T$id',
    colorBack: 'yellow',
    colorFont: 'black',
    wins: wins,
    losses: losses,
    gamesBehind: behind,
  );
}

Map<String, dynamic> standing({
  required int id,
  required int league,
  required int rank,
  required String name,
  int wins = 80,
  int losses = 60,
  String behind = '0',
  String color = 'yellow',
  int gamesLeft = 0,
}) {
  return {
    'id_team': id,
    'id_league': league,
    'int_rank': rank,
    'name_team_full': name,
    'color_back': color,
    'color_font': 'black',
    'int_win': wins,
    'int_lose': losses,
    'game_behind': behind,
    'int_game_left': gamesLeft,
  };
}

Map<String, dynamic> game({
  required String code,
  required int home,
  required int away,
  required int scoreHome,
  required int scoreAway,
  String state = '試合終了',
}) {
  return {
    'code_game': code,
    'id_team_home': home,
    'id_team_away': away,
    'score_home': scoreHome,
    'score_away': scoreAway,
    'state': state,
  };
}

void main() {
  test('勝率5割未満またはゲーム差10以上でアドバンテージが2勝になる', () {
    expect(finalistTakesExtraAdvantage(team(id: 3, league: 1, rank: 3, wins: 60, losses: 70, behind: 8)), isTrue);
    expect(finalistTakesExtraAdvantage(team(id: 3, league: 1, rank: 3, wins: 70, losses: 70, behind: 4)), isFalse);
    expect(finalistTakesExtraAdvantage(team(id: 3, league: 1, rank: 3, wins: 71, losses: 70, behind: 9.5)), isFalse);
    expect(finalistTakesExtraAdvantage(team(id: 2, league: 1, rank: 2, wins: 75, losses: 65, behind: 10)), isTrue);
    expect(gamesBehindOf('優勝'), 0);
    expect(gamesBehindOf('M2'), isNull);
  });

  test('ファーストは先に2勝、負けたチームは敗退', () {
    final board = buildPostseasonBoard(
      standings: [
        standing(id: 1, league: 1, rank: 1, name: '阪神タイガース'),
        standing(id: 2, league: 1, rank: 2, name: '読売ジャイアンツ', behind: '3.0'),
        standing(id: 3, league: 1, rank: 3, name: '横浜DeNAベイスターズ', behind: '5.0', wins: 70, losses: 70),
        standing(id: 7, league: 2, rank: 1, name: '福岡ソフトバンクホークス'),
        standing(id: 8, league: 2, rank: 2, name: '埼玉西武ライオンズ', behind: '2.0'),
        standing(id: 9, league: 2, rank: 3, name: '北海道日本ハムファイターズ', behind: '4.0'),
      ],
      games: [
        game(code: 'CS1', home: 2, away: 3, scoreHome: 4, scoreAway: 1),
        game(code: 'CS1', home: 2, away: 3, scoreHome: 2, scoreAway: 0),
        game(code: 'CS1', home: 2, away: 3, scoreHome: 0, scoreAway: 0, state: '試合前'),
      ],
    );
    expect(board.cs1Central.winnerId, 2);
    expect(board.cs1Central.loserId, 3);
    expect(board.cs1Central.winsHigh, 2);
    expect(board.cs1Central.slots, 2);
    expect(board.eliminated(3), isTrue);
    expect(board.eliminated(2), isFalse);
    expect(board.finalCentral.advantage, 1);
    expect(board.finalCentral.slots, 4);
    expect(board.finalCentral.winsHigh, 1);
    expect(board.finalCentral.decided, isFalse);
  });

  test('今のゲーム差のまま終わると両方とも新規定なら星は5個で1位は2つ塗りつぶす', () {
    final board = buildPostseasonBoard(
      standings: [
        standing(id: 1, league: 1, rank: 1, name: '阪神', wins: 88, losses: 52),
        standing(id: 2, league: 1, rank: 2, name: '巨人', behind: '12.0', wins: 70, losses: 68),
        standing(id: 3, league: 1, rank: 3, name: 'DeNA', behind: '15.0', wins: 65, losses: 73),
        standing(id: 7, league: 2, rank: 1, name: 'ソフトバンク', wins: 90, losses: 48),
        standing(id: 8, league: 2, rank: 2, name: '西武', behind: '3.0', wins: 87, losses: 51),
        standing(id: 9, league: 2, rank: 3, name: '日本ハム', behind: '6.0', wins: 84, losses: 54),
      ],
      games: const [],
    );
    expect(board.finalCentral.slots, 5);
    expect(board.finalCentral.advantage, 2);
    expect(board.finalCentral.winsHigh, 2);
    expect(board.finalPacific.slots, 4);
    expect(board.finalPacific.winsHigh, 1);
  });

  test('3位のゲーム差が直上との差でも1位との差が10以上なら星は5個', () {
    final board = buildPostseasonBoard(
      standings: [
        standing(id: 7, league: 2, rank: 1, name: 'ソフトバンク', wins: 91, losses: 48),
        standing(id: 8, league: 2, rank: 2, name: '西武', behind: '13', wins: 77, losses: 60),
        standing(id: 9, league: 2, rank: 3, name: '日本ハム', behind: '0.5', wins: 78, losses: 62),
        standing(id: 1, league: 1, rank: 1, name: '阪神', wins: 77, losses: 60),
        standing(id: 2, league: 1, rank: 2, name: '巨人', behind: '2.5', wins: 76, losses: 64),
        standing(id: 5, league: 1, rank: 3, name: 'DeNA', behind: '5.5', wins: 70, losses: 69),
      ],
      games: const [],
    );
    expect(board.finalPacific.slots, 5);
    expect(board.finalPacific.advantage, 2);
    expect(board.finalPacific.winsHigh, 2);
    expect(board.finalCentral.slots, 4);
    expect(board.finalCentral.winsHigh, 1);
  });

  test('進出チームのゲーム差が10以上ならファイナルは2勝アドバンテージの5勝先取', () {
    final board = buildPostseasonBoard(
      standings: [
        standing(id: 1, league: 1, rank: 1, name: '阪神'),
        standing(id: 2, league: 1, rank: 2, name: '巨人', behind: '12.0', wins: 65, losses: 75),
        standing(id: 3, league: 1, rank: 3, name: 'DeNA', behind: '14.0', wins: 60, losses: 78),
        standing(id: 7, league: 2, rank: 1, name: 'ソフトバンク'),
        standing(id: 8, league: 2, rank: 2, name: '西武', behind: '1.0'),
        standing(id: 9, league: 2, rank: 3, name: '日本ハム', behind: '2.0'),
      ],
      games: [
        game(code: 'CS1', home: 2, away: 3, scoreHome: 1, scoreAway: 3),
        game(code: 'CS1', home: 2, away: 3, scoreHome: 0, scoreAway: 2),
      ],
    );
    expect(board.cs1Central.winnerId, 3);
    expect(board.finalCentral.advantage, 2);
    expect(board.finalCentral.slots, 5);
    expect(board.finalCentral.winsHigh, 2);
    expect(board.eliminated(2), isTrue);
  });

  test('引き分けと中止は星にならない', () {
    final board = buildPostseasonBoard(
      standings: [
        standing(id: 1, league: 1, rank: 1, name: '阪神'),
        standing(id: 2, league: 1, rank: 2, name: '巨人', behind: '1.0'),
        standing(id: 3, league: 1, rank: 3, name: 'DeNA', behind: '2.0', wins: 75, losses: 60),
        standing(id: 7, league: 2, rank: 1, name: 'ソフトバンク'),
        standing(id: 8, league: 2, rank: 2, name: '西武', behind: '1.0'),
        standing(id: 9, league: 2, rank: 3, name: '日本ハム', behind: '2.0'),
      ],
      games: [
        game(code: 'CS1', home: 2, away: 3, scoreHome: 2, scoreAway: 2),
        game(code: 'CS1', home: 2, away: 3, scoreHome: 0, scoreAway: 0, state: '試合中止'),
        game(code: 'CS1', home: 2, away: 3, scoreHome: 3, scoreAway: 1),
        game(code: 'CS1', home: 2, away: 3, scoreHome: 4, scoreAway: 2),
        game(code: 'CSF', home: 1, away: 2, scoreHome: 5, scoreAway: 1),
        game(code: 'CSF', home: 1, away: 2, scoreHome: 4, scoreAway: 2),
        game(code: 'CSF', home: 1, away: 2, scoreHome: 6, scoreAway: 0),
      ],
    );
    expect(board.cs1Central.winsHigh, 2);
    expect(board.cs1Central.winnerId, 2);
    expect(board.finalCentral.winsHigh, 4);
    expect(board.finalCentral.winnerId, 1);
    expect(board.eliminated(2), isTrue);
  });

  testWidgets('トーナメント表に星と敗退の灰色を描く', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 420,
          child: PostseasonBracket(
            standings: [
              standing(id: 1, league: 1, rank: 1, name: '阪神タイガース', color: 'yellow'),
              standing(id: 2, league: 1, rank: 2, name: '読売ジャイアンツ', color: 'orange', behind: '3'),
              standing(id: 3, league: 1, rank: 3, name: '横浜DeNAベイスターズ', color: 'blue', behind: '6', wins: 72, losses: 68),
              standing(id: 9, league: 2, rank: 3, name: '北海道日本ハムファイターズ', color: 'blue', behind: '8'),
              standing(id: 8, league: 2, rank: 2, name: '埼玉西武ライオンズ', color: 'lightblue', behind: '4'),
              standing(id: 7, league: 2, rank: 1, name: '福岡ソフトバンクホークス', color: 'gold'),
            ],
            games: [
              game(code: 'CS1', home: 2, away: 3, scoreHome: 3, scoreAway: 1),
              game(code: 'CS1', home: 2, away: 3, scoreHome: 2, scoreAway: 1),
            ],
          ),
        ),
      ),
    ));
    expect(find.text('日本シリーズ'), findsOneWidget);
    final stage = tester.widget<DecoratedBox>(find.ancestor(of: find.text('日本シリーズ'), matching: find.byType(DecoratedBox)).first);
    final stageBorder = (stage.decoration as BoxDecoration).border! as Border;
    expect(stageBorder.top.color, Colors.black);
    expect(stageBorder.top.width, 2);
    expect(find.text('CS FINAL STAGE'), findsNWidgets(2));
    expect(find.text('CS 1st STAGE'), findsNWidgets(2));
    expect(_verticalName(tester, 'postseason-team-1-セ1位'), '阪神タイガース');
    expect(find.text('セ・リーグ1位'), findsOneWidget);
    expect(find.text('パ・リーグ1位'), findsOneWidget);
    expect(find.text('★'), findsWidgets);
    expect(tester.widget<Text>(find.text('★').first).style?.color, const Color(0xFFFFD600));
    final frame = tester.widget<DecoratedBox>(find.byKey(const Key('postseason-team-1-セ1位')));
    final border = (frame.decoration as BoxDecoration).border! as Border;
    expect(border.top.color, Colors.black);
    expect(border.top.width, 2);
    final gray = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const Key('postseason-team-3-セ3位')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(gray.color, const Color(0xFFBDBDBD));
  });

  test('残り試合で追い抜ける順位は空欄、確定した順位だけ球団名を出す', () {
    final board = buildPostseasonBoard(
      standings: [
        standing(id: 2, league: 1, rank: 1, name: '阪神タイガース', wins: 77, losses: 59, gamesLeft: 5, behind: 'M2'),
        standing(id: 1, league: 1, rank: 2, name: '読売ジャイアンツ', wins: 76, losses: 62, gamesLeft: 2, behind: '2'),
        standing(id: 5, league: 1, rank: 3, name: '横浜DeNAベイスターズ', wins: 69, losses: 69, gamesLeft: 2, behind: '7'),
        standing(id: 6, league: 1, rank: 4, name: '広島東洋カープ', wins: 59, losses: 76, gamesLeft: 4, behind: '8.5'),
        standing(id: 4, league: 1, rank: 5, name: '東京ヤクルトスワローズ', wins: 59, losses: 78, gamesLeft: 4, behind: '1'),
        standing(id: 3, league: 1, rank: 6, name: '中日ドラゴンズ', wins: 59, losses: 81, gamesLeft: 1, behind: '1.5'),
        standing(id: 7, league: 2, rank: 1, name: '福岡ソフトバンクホークス', wins: 90, losses: 47, gamesLeft: 3, behind: '優勝'),
        standing(id: 8, league: 2, rank: 2, name: '埼玉西武ライオンズ', wins: 77, losses: 60, gamesLeft: 2, behind: '13'),
        standing(id: 9, league: 2, rank: 3, name: '北海道日本ハムファイターズ', wins: 78, losses: 62, gamesLeft: 0, behind: '0.5'),
        standing(id: 10, league: 2, rank: 4, name: 'オリックス・バファローズ', wins: 65, losses: 75, gamesLeft: 1, behind: '13'),
        standing(id: 12, league: 2, rank: 5, name: '千葉ロッテマリーンズ', wins: 61, losses: 74, gamesLeft: 5, behind: '1.5'),
        standing(id: 11, league: 2, rank: 6, name: '東北楽天ゴールデンイーグルス', wins: 56, losses: 83, gamesLeft: 3, behind: '7'),
      ],
      games: const [],
    );
    expect(board.central1.name, '');
    expect(board.central1.id, 0);
    expect(board.central2.name, '');
    expect(board.central3.name, '横浜DeNAベイスターズ');
    expect(board.central3.id, 5);
    expect(board.pacific1.name, '福岡ソフトバンクホークス');
    expect(board.pacific2.name, '');
    expect(board.pacific3.name, '');
    expect(board.finalCentral.advantage, 1);
    expect(board.finalCentral.slots, 4);
  });

  test('残りが0の順位は確定し、143試合に足りない分は残り試合になる', () {
    expect(remainingGamesOf({'int_game': 138, 'int_win': 77, 'int_lose': 59, 'int_draw': 2}), 5);
    expect(remainingGamesOf({'int_game_left': 4, 'int_game': 138}), 4);
    expect(remainingGamesOf({'int_win': 80, 'int_lose': 60}), 3);
    final board = buildPostseasonBoard(
      standings: [
        standing(id: 1, league: 1, rank: 1, name: '阪神', wins: 10, losses: 0, gamesLeft: 1),
        standing(id: 2, league: 1, rank: 2, name: '巨人', wins: 9, losses: 0, gamesLeft: 1),
      ],
      games: const [],
    );
    expect(board.central1.name, '');
    expect(board.central2.name, '');
    final settled = buildPostseasonBoard(
      standings: [
        standing(id: 1, league: 1, rank: 1, name: '阪神', wins: 10, losses: 0),
        standing(id: 2, league: 1, rank: 2, name: '巨人', wins: 9, losses: 0),
      ],
      games: const [],
    );
    expect(settled.central1.name, '阪神');
    expect(settled.central2.name, '巨人');
    final shortName = standing(id: 5, league: 1, rank: 3, name: '横浜DeNAベイスターズ', wins: 1, losses: 10);
    shortName['name_team'] = 'DeNA';
    final named = buildPostseasonBoard(standings: [shortName], games: const []);
    expect(named.central3.name, 'DeNA');
  });

  test('トーナメント表は9月15日から開幕前日まで出す', () {
    expect(postseasonBoardVisible(serverFlag: false, today: DateTime(2026, 9, 14)), isFalse);
    expect(postseasonBoardVisible(serverFlag: false, today: DateTime(2026, 9, 15)), isTrue);
    expect(postseasonBoardVisible(serverFlag: false, today: DateTime(2026, 10, 2)), isTrue);
    expect(postseasonBoardVisible(serverFlag: false, today: DateTime(2027, 3, 25)), isTrue);
    expect(postseasonBoardVisible(serverFlag: false, today: DateTime(2027, 3, 26)), isFalse);
    expect(postseasonBoardVisible(serverFlag: false, today: DateTime(2026, 8, 1)), isFalse);
    expect(postseasonBoardVisible(serverFlag: true, today: DateTime(2026, 8, 1)), isTrue);
  });

  testWidgets('未確定の順位は枠内に未確定と出す', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 420,
          child: PostseasonBracket(
            standings: [
              standing(id: 1, league: 1, rank: 1, name: '阪神タイガース', wins: 10, losses: 0, gamesLeft: 1, color: 'yellow'),
              standing(id: 2, league: 1, rank: 2, name: '読売ジャイアンツ', wins: 9, losses: 0, gamesLeft: 1, color: 'orange'),
              standing(id: 3, league: 1, rank: 3, name: '横浜DeNAベイスターズ', wins: 1, losses: 10, color: 'blue'),
            ],
            games: const [],
          ),
        ),
      ),
    ));
    expect(_verticalName(tester, 'postseason-team-0-セ1位'), '未確定');
    expect(_verticalName(tester, 'postseason-team-0-セ2位'), '未確定');
    expect(_verticalName(tester, 'postseason-team-3-セ3位'), '横浜DeNAベイスターズ');
    expect(find.text('セ・リーグ1位'), findsOneWidget);
    final blank = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const Key('postseason-team-0-セ1位')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(blank.color, Colors.white);
  });
}
