import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/PostseasonBracket.dart';
import 'package:Yakyuu_Japan/View/MlbPostseasonBracket.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

Map<String, dynamic> club(int id, int league, int rank, String name) => {
  'id_team': id, 'id_league': league, 'int_rank': rank, 'name_team': name,
  'name_team_full': name, 'int_win': 100 - rank, 'int_lose': 60 + rank,
  'int_game_left': 0, 'game_behind': '0', 'color_back': 'navy', 'color_font': 'white',
  'code_area': ['EAST', 'CENTER', 'WEST'][(rank - 1) % 3],
};
List<Map<String, dynamic>> wins(String code, int home, int away, int count) => [
  for (var i = 0; i < count; i++) {
    'id_game': '$code-$home-$i', 'code_game': code, 'id_team_home': home,
    'id_team_away': away, 'score_home': 4, 'score_away': 1,
    'state': '試合終了', 'date_game': '2026-10-${10 + i}',
  }
];

void main() {
  setUp(() { AuthSession.instance.user = AuthUser.fromJson({'id': 1, 'admin': true}); AuthSession.instance.token = 'test'; });
  tearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
  for (final mlb in [false, true]) {
    for (final width in [390.0, 1100.0]) {
      testWidgets('${mlb ? 'MLB' : 'NPB'} champion rises above final with fireworks; undecided hides it width=$width', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final standings = mlb ? [
          club(16, 3, 1, 'レイズ'), club(17, 3, 2, 'ガーディアンズ'), club(18, 3, 3, 'マリナーズ'),
          club(19, 3, 4, 'ヤンキース'), club(20, 3, 5, 'アストロズ'), club(21, 3, 6, 'タイガース'),
          club(35, 4, 1, 'ブルワーズ'), club(40, 4, 2, 'ドジャース'), club(28, 4, 3, 'ブレーブス'),
          club(41, 4, 4, 'パドレス'), club(33, 4, 5, 'カブス'), club(31, 4, 6, 'フィリーズ'),
        ] : [
          club(1, 1, 1, '横浜DeNAベイスターズ'), club(2, 1, 2, '阪神タイガース'), club(3, 1, 3, '読売ジャイアンツ'),
          club(7, 2, 1, '福岡ソフトバンクホークス'), club(8, 2, 2, '北海道日本ハムファイターズ'), club(9, 2, 3, 'オリックス・バファローズ'),
        ];
        final rounds = mlb ? [
          ...wins('ALDS',16,19,3), ...wins('ALDS',17,18,3), ...wins('ALCS',16,17,4),
          ...wins('NLDS',35,41,3), ...wins('NLDS',40,28,3), ...wins('NLCS',35,40,4),
        ] : [
          ...wins('CS1',2,3,2), ...wins('CS1',8,9,2), ...wins('CSF',1,2,3), ...wins('CSF',7,8,3),
        ];
        Widget build(int count, {bool reduceMotion = false}) => MaterialApp(home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion, size: const Size(1100,780)),
          child: Scaffold(body: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(key: Key('fold-header'), height: 26),
              RepaintBoundary(key: const Key('preview'),
                child: mlb ? MlbPostseasonBracket(standings: standings, games: [...rounds, ...wins('WS',35,16,count)])
                  : PostseasonBracket(standings: standings, games: [...rounds, ...wins('JS',7,1,count)])),
            ])))));
        await tester.pumpWidget(build(3));
        await tester.pump();
        expect(find.byKey(const Key('champion-fireworks')), findsNothing);
        final backgroundKey = Key(mlb ? 'mlb-postseason-background' : 'postseason-background');
        expect(tester.getRect(find.byKey(backgroundKey)).width, closeTo(width, .1));
        await tester.pumpWidget(build(4));
        await tester.pump(const Duration(milliseconds: 1400));
        final logo = find.byKey(ValueKey('champion-logo-${mlb ? 35 : 7}'));
        expect(logo, findsOneWidget);
        expect(find.text(mlb ? 'WORLD CHAMPIONS' : '日本一'), findsOneWidget);
        expect(find.byKey(const Key('champion-fireworks')), findsOneWidget);
        final header = tester.getRect(find.byKey(const Key('fold-header')));
        final background = tester.getRect(find.byKey(backgroundKey));
        expect(background.left, closeTo(header.left, .1));
        expect(background.right, closeTo(header.right, .1));
        final celebration = tester.widget<DecoratedBox>(find.byKey(const Key('champion-background')));
        final bracket = tester.widget<DecoratedBox>(find.byKey(backgroundKey));
        expect((celebration.decoration as BoxDecoration).gradient, (bracket.decoration as BoxDecoration).gradient);
        final series = find.byKey(Key(mlb ? 'postseason-ws-content' : 'postseason-js-content'));
        expect(tester.getBottomRight(logo).dy, lessThan(tester.getTopLeft(series).dy));
        expect(tester.getSize(find.byKey(const Key('champion-advance-line'))).height, greaterThan(20));
        expect(tester.takeException(), isNull);
        // Reduced-motion preference leaves the champion and a static celebration.
        await tester.pumpWidget(build(4, reduceMotion: true));
        await tester.pumpAndSettle();
        expect(logo, findsOneWidget);
        if (const bool.fromEnvironment('BRACKET_PREVIEW') && width == 1100) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('preview')));
            final image = await boundary.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('output/championship_${mlb ? 'mlb' : 'npb'}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
