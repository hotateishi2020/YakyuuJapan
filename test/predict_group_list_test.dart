import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/PredictGroupBoard.dart';
import 'package:Yakyuu_Japan/logic/predict_groups.dart';
import 'package:Yakyuu_Japan/tools/color_parse.dart';

void main() {
  test('予想グループは新しい年が上で同じ年の重複は1件', () {
    final sections = predictGroupsByYear([
      {'id': 1, 'txt_name': '立石組', 'int_year': 2025},
      {'id': 2, 'txt_name': '江島組', 'int_year': 2026},
      {'id': 1, 'txt_name': '立石組', 'int_year': 2026},
      {'id': 1, 'txt_name': '立石組', 'int_year': 2026},
      {'id': 3, 'txt_name': '未設定', 'int_year': null},
    ]);
    expect(sections.map((section) => section.year).toList(), [2026, 2025, null]);
    expect(sections[0].groups.map((group) => group['txt_name']).toList(), ['江島組', '立石組']);
    expect(sections[2].groups.single['txt_name'], '未設定');
    expect(sections[0].groups.first['users'], isEmpty);
  });

  test('年度ごとの参加者とタイトルを残す', () {
    final sections = predictGroupsByYear([
      {
        'id': 1,
        'txt_name': '立石・江島',
        'int_year': 2026,
        'users': [
          {'id': 1, 'name': '立石', 'hits': 4},
        ],
        'titles': ['打率', '本塁打'],
      },
    ]);
    expect(sections.single.groups.single['titles'], ['打率', '本塁打']);
    expect(sections.single.groups.single['users'], [
      {'id': 1, 'name': '立石', 'hits': 4},
    ]);
  });

  test('同じグループの年度は一つにまとまり新しい年が先', () {
    final clusters = predictGroupClusters([
      {'id': 1, 'txt_name': '立石・江島', 'int_year': 2025, 'id_setting': 2},
      {'id': 1, 'txt_name': '立石・江島', 'int_year': 2026, 'id_setting': 1, 'code_select': 'DRAW'},
      {'id': 2, 'txt_name': '別組', 'int_year': 2026},
    ]);
    expect(clusters.map((cluster) => cluster.name).toList(), ['立石・江島', '別組']);
    expect(clusters.first.years.map((year) => year['int_year']).toList(), [2026, 2025]);
    expect(clusters.first.years.first['code_select'], 'DRAW');
  });

  testWidgets('年度を押すと予想状況が切り替わり、編集で設定を開ける', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PredictGroupBoard(
          loading: false,
          selectedYear: 2026,
          onSaveSetting: (_) async => null,
          groups: [
            {
              'id': 1,
              'txt_name': '立石・江島',
              'int_year': 2026,
              'id_setting': 6,
              'code_select': 'FREE',
              'code_point': 'SINGLE',
              'int_same_player_limit': 1,
              'users': [
                {'id': 1, 'name': '立石', 'color': 'blue', 'hits': 3},
                {'id': 2, 'name': '江島', 'color': 'red', 'hits': 1},
              ],
              'titles': ['打率', 'チーム順位'],
              'players': [
                {
                  'league': 'セ・リーグ',
                  'title': '打率',
                  'pitcher': false,
                  'current': '佐藤輝明、近本光司',
                  'color_back': 'tomato',
                  'color_font': 'white',
                  'picks': [
                    {'id_user': 1, 'name': '佐藤輝明', 'hit': true},
                    {'id_user': 2, 'name': '近本光司', 'hit': false},
                  ],
                },
                {
                  'league': 'セ・リーグ',
                  'title': 'MVP',
                  'pitcher': false,
                  'current': '岡本和真',
                  'picks': [
                    {'id_user': 1, 'name': '岡本和真', 'hit': false},
                  ],
                },
                {
                  'league': '',
                  'title': '沢村賞',
                  'pitcher': true,
                  'current': '山本由伸',
                  'picks': [
                    {'id_user': 1, 'name': '山本由伸', 'hit': false},
                  ],
                },
              ],
              'teams': [
                {'league': 'セ・リーグ', 'rank': 1, 'actual': '阪神', 'color_back': 'tomato', 'color_font': 'white', 'picks': const []},
                {'league': 'パ・リーグ', 'rank': 1, 'actual': 'ソフトバンク', 'picks': const []},
              ],
              'japan': {'name': 'オリックス', 'color_back': 'navy', 'color_font': 'white'},
              'champions': [
                {'id_user': 1, 'name': 'オリックス', 'hit': true},
                {'id_user': 2, 'name': '阪神', 'hit': false},
              ],
            },
            {
              'id': 1,
              'txt_name': '立石・江島',
              'int_year': 2025,
              'id_setting': 5,
              'code_select': 'WAIVER',
              'code_point': 'GAP',
              'int_same_player_limit': 2,
              'users': [
                {'id': 1, 'name': '立石', 'color': 'blue', 'hits': 2},
              ],
              'titles': ['打点'],
              'players': const [],
              'teams': const [],
              'champions': const [],
            },
          ],
        ),
      ),
    ));

    expect(find.text('2026年　${predictSeasonHeader(2026)}'), findsOneWidget);
    expect(find.text(predictSeasonHeader(2026)), findsNWidgets(4));
    expect(tester.getTopLeft(find.text('チーム順位予想')).dy, lessThan(tester.getTopLeft(find.text('個人成績予想')).dy));
    expect(find.text('NPB'), findsOneWidget);
    expect(tester.getTopLeft(find.text('日本一').first).dy, lessThan(tester.getTopLeft(find.text('沢村賞')).dy));
    expect(tester.getTopLeft(find.text('沢村賞')).dy, lessThan(tester.getTopLeft(find.text('セ・リーグ').first).dy));
    expect(tester.getTopLeft(find.text('MVP')).dy, lessThan(tester.getTopLeft(find.text('打率')).dy));
    expect(
      find.byWidgetPredicate((widget) => widget is Container && widget.color == const Color(0xFFFF6347)),
      findsOneWidget,
    );
    final tied = find.text('佐藤輝明、近本光司');
    expect(tester.widget<Text>(tied).style?.color, Colors.black);
    expect(
      tester.widget<Container>(find.ancestor(of: tied, matching: find.byType(Container)).first).color,
      Colors.white,
    );
    expect(
      find.byWidgetPredicate((widget) => widget is Container && widget.color == const Color(0xFF001F3F)),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) => widget is Container && widget.color == const Color(0xFFFFCC00)),
      findsWidgets,
    );
    expect(
      find.byWidgetPredicate((widget) => widget is TableCell && widget.verticalAlignment == TableCellVerticalAlignment.intrinsicHeight),
      findsWidgets,
    );
    expect(find.text('セ・リーグ'), findsWidgets);
    expect(find.text('パ・リーグ'), findsWidgets);
    expect(
      find.byWidgetPredicate((widget) {
        final decoration = widget is Container ? widget.decoration : null;
        return decoration is BoxDecoration && decoration.color == const Color(0xFF0E8E2D);
      }),
      findsWidgets,
    );
    expect(
      find.byWidgetPredicate((widget) {
        final decoration = widget is Container ? widget.decoration : null;
        return decoration is BoxDecoration && decoration.color == const Color(0xFF01B1EA);
      }),
      findsWidgets,
    );
    expect(find.text('1位'), findsNWidgets(2));
    expect(find.text('打率'), findsOneWidget);
    expect(find.text('対象 打率、チーム順位'), findsNothing);
    final usersBox = tester.getTopLeft(find.text('参加 立石・江島'));
    final first2026 = tester.getTopLeft(find.byKey(const ValueKey('predict-hit-2026-0')));
    final first2025 = tester.getTopLeft(find.byKey(const ValueKey('predict-hit-2025-0')));
    final second2026 = tester.getTopLeft(find.byKey(const ValueKey('predict-hit-2026-1')));
    final second2025 = tester.getTopLeft(find.byKey(const ValueKey('predict-hit-2025-1')));
    expect(first2026.dx, greaterThan(usersBox.dx));
    expect(first2026.dx, first2025.dx);
    expect(second2026.dx, second2025.dx);
    expect(second2026.dx, greaterThan(first2026.dx));
    final editIcons = find.byIcon(Icons.edit_outlined);
    expect(tester.getTopRight(editIcons.at(0)).dx, tester.getTopRight(editIcons.at(1)).dx);
    expect(find.text('立石・江島'), findsWidgets);
    expect(find.text('佐藤輝明'), findsWidgets);
    expect(predictSeasonHeader(2026, today: DateTime(2026, 10, 13)), '現在');
    expect(predictSeasonHeader(2025, today: DateTime(2026, 10, 13)), '結果');

    await tester.tap(find.text('2025'));
    await tester.pump();
    expect(find.text('2025年　${predictSeasonHeader(2025)}'), findsOneWidget);
    expect(find.text('2026年　${predictSeasonHeader(2026)}'), findsNothing);

    await tester.tap(find.byIcon(Icons.drive_file_rename_outline));
    await tester.pump();
    expect(find.text('グループ名'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit_outlined).at(1));
    await tester.pump();
    expect(find.text('2025年の予想設定'), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('チーム順位の予想期限')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('個人成績予想の期限')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('個人成績予想')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('予想選手')), findsNothing);
    expect(find.text('対象タイトル'), findsOneWidget);
    expect(
      tester.getTopLeft(find.descendant(of: dialog, matching: find.text('立石')).first).dx,
      tester.getTopLeft(find.descendant(of: dialog, matching: find.text('未設定')).first).dx,
    );
    expect(find.text('打点'), findsWidgets);
    expect(
      find.descendant(
        of: dialog,
        matching: find.byWidgetPredicate((widget) => widget is Text && widget.data == '打点' && widget.textAlign == TextAlign.center),
      ),
      findsWidgets,
    );
    expect(find.text('ウェーバー方式'), findsOneWidget);
    expect(find.text('順位ズレポイント方式'), findsOneWidget);
    await tester.tap(find.descendant(of: dialog, matching: find.text('日付を選択')).first);
    await tester.pump();
    expect(find.text('期限を選択'), findsOneWidget);
    expect(find.text('オープン戦開幕前'), findsOneWidget);
    expect(find.text('2025-02-21'), findsOneWidget);
    await tester.tap(find.text('4月中'));
    await tester.pump();
    expect(find.text('2025-04-30'), findsOneWidget    );
  });

  test('予想期限は行事の前日と月末になる', () {
    final options = predictDeadlineOptions(2026);
    expect(options.map((option) => option.label).toList(), [
      'オープン戦開幕前',
      'オープン戦終了前',
      'シーズン開幕前',
      '4月中',
      '交流戦開幕前',
      '交流戦終了前',
      '5月中',
      '6月中',
      'オールスター開始前',
      'オールスター終了前',
      '7月中',
      '8月中',
      '9月中',
    ]);
    String dateOf(String label) => options.firstWhere((option) => option.label == label).date;
    expect(dateOf('オープン戦開幕前'), '2026-02-20');
    expect(dateOf('シーズン開幕前'), '2026-03-26');
    expect(dateOf('4月中'), '2026-04-30');
    expect(dateOf('交流戦開幕前'), '2026-05-25');
    expect(dateOf('交流戦終了前'), '2026-06-17');
    expect(dateOf('オールスター開始前'), '2026-07-27');
    expect(dateOf('オールスター終了前'), '2026-07-28');
    expect(dateOf('9月中'), '2026-09-30');
  });

  test('期限を過ぎた他人の枠は修正できない', () {
    expect(predictDeadlinePassed('2020-01-01', today: DateTime.utc(2026, 10, 13)), isTrue);
    expect(predictDeadlinePassed('2026-10-13', today: DateTime.utc(2026, 10, 13)), isFalse);
    expect(predictDeadlinePassed('', today: DateTime.utc(2026, 10, 13)), isFalse);
    expect(predictCanEditSlot(viewerId: 1, ownerId: 1, closed: false), isTrue);
    expect(predictCanEditSlot(viewerId: 1, ownerId: 2, closed: false), isFalse);
    expect(predictCanEditSlot(viewerId: 1, ownerId: 1, closed: true), isFalse);
    expect(predictCanEditSlot(viewerId: null, ownerId: 1, closed: false), isFalse);
    expect(
      predictWaiverTurnUser(userIds: const [1, 2], lastYearHits: const {1: 14, 2: 7}, pickCounts: const {1: 0, 2: 0}),
      2,
    );
    expect(
      predictWaiverTurnUser(userIds: const [1, 2], lastYearHits: const {1: 14, 2: 7}, pickCounts: const {1: 0, 2: 1}),
      1,
    );
  });

  testWidgets('ログイン者のチーム順位だけ修正でき、期限後の個人成績は閉じる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PredictGroupBoard(
          loading: false,
          selectedYear: 2026,
          viewerId: 1,
          onSaveSetting: (_) async => null,
          groups: [
            {
              'id': 1,
              'txt_name': '立石・江島',
              'int_year': 2026,
              'id_setting': 6,
              'date_limit_team': '2099-12-31',
              'date_limit_player': '2020-01-01',
              'users': [
                {'id': 1, 'name': '立石', 'color': 'blue', 'hits': 0},
                {'id': 2, 'name': '江島', 'color': 'red', 'hits': 0},
              ],
              'titles': ['打率'],
              'players': const [],
              'teams': const [],
              'champions': const [],
            },
          ],
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pump();
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('予想期限を過ぎているため変更できません')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('日本一')), findsWidgets);
    final icons = find.descendant(of: dialog, matching: find.byIcon(Icons.edit_outlined));
    expect(icons, findsNWidgets(13));
    final iconRight = tester.getTopRight(icons.first).dx;
    for (var i = 1; i < 13; i++) {
      expect(tester.getTopRight(icons.at(i)).dx, iconRight);
    }
  });

  test('黄色のチーム地色だけ星を黄みのオレンジにする', () {
    expect(seriesStarColor(const Color(0xFFFFEB3B)), const Color(0xFFFFB300));
    expect(seriesStarColor(const Color(0xFFFFD700)), const Color(0xFFFFB300));
    expect(seriesStarColor(const Color(0xFF002D72)), const Color(0xFFFFD600));
    expect(seriesStarColor(const Color(0xFFCB0115)), const Color(0xFFFFD600));
    expect(seriesStarColor(null), const Color(0xFFFFD600));
  });
}
