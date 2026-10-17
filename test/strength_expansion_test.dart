import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/SeasonTable.dart';
import 'package:Yakyuu_Japan/View/achievement_badge.dart';
import 'package:Yakyuu_Japan/View/achievement_layout.dart';
import 'package:Yakyuu_Japan/logic/achievement_priority.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';
import 'package:Yakyuu_Japan/View/strength_research.dart';
import 'package:Yakyuu_Japan/View/strength_contracts.dart';
import 'package:Yakyuu_Japan/logic/strength_usage.dart';

void main() {
  test('ドラフト経歴は新しい年度と季節から順に並べ年度不明は末尾に表示する', () {
    expect(draftCareerText({
      'achievement': '2026年日本代表',
      'career_facts': [
        {'year': 2026, 'season': '夏', 'label': '2026年夏ベスト4'},
        {'label': '高校通算30本'},
        {'year': 2025, 'season': '夏', 'label': '2025年夏ベスト8'},
        {'year': 2025, 'season': '春', 'label': '2025年春優勝'},
      ],
    }).split('\n'), ['2026年夏ベスト4', '2026年日本代表', '2025年夏ベスト8', '2025年春優勝', '高校通算30本']);
  });
  test('退団区分は確認済みの情報だけを使用する', () {
    expect(rosterDepartureLabel({'departure_type': 'retired'}), isNull);
    expect(rosterDepartureLabel({'fa_confirmed': true}), isNull);
    for (final entry in {'retired': '引退', 'transfer': '移籍', 'non-tender': '戦力外', 'released': '自由契約'}.entries) {
      expect(rosterDepartureLabel({'departure_confirmed': true, 'departure_type': entry.key}), entry.value);
    }
  });

  test('変動契約の将来セルには契約内容を表示し、既知の年俸を優先する', () {
    final periods = <Map<String, dynamic>>[
      {'start_year': 2026, 'end_year': 2028, 'team': '阪神', 'detail': '年俸変動制'}
    ];
    final notes = contractFutureNotes([], periods, 2026);
    expect(notes.keys.toSet(), {2027, 2028});
    expect(notes[2027], contains('年俸変動制'));
    expect(notes[2027], contains('年俸額未公表'));
    expect(
        contractFutureNotes([
          {'year': 2027, 'projected': true}
        ], periods, 2026)
            .containsKey(2027),
        isFalse);
    final ending = <Map<String, dynamic>>[
      {'start_year': 2026, 'end_year': 2026}
    ];
    expect(contractFutureNotes([], ending, 2026)[2027], contains('契約満了'));
    expect(
        contractFutureNotes([
          {'year': 2027, 'amount': 100}
        ], ending, 2026),
        isEmpty);
  });

  test('功績の面積は独自評価の価値比率に比例する', () {
    final mvp = {'kind': 'title', 'label': 'MVP'};
    final qualification = {'kind': 'qualification', 'label': '規定打席'};
    final title = {'kind': 'title', 'label': '首位打者'};
    double area(Map<String, dynamic> a) => achievementBadgeSize(a) * achievementBadgeSize(a);
    expect(area(mvp) / area(qualification), closeTo(25, .001));
    expect(area(title) / area(mvp), closeTo(.5625, .001));
    expect(draftAttentionRank({'attention_grade': 'S'}), lessThan(draftAttentionRank({'attention_grade': 'A'})));
    expect(draftAttentionRank({}), greaterThan(draftAttentionRank({'attention_grade': 'E'})));
  });

  test('年齢は表示年度の3月31日時点で算出する', () {
    expect(draftAgeOnMarch31('2004-03-31', 2026), 22);
    expect(draftAgeOnMarch31('2004-04-01', 2026), 21);
    expect(draftAgeOnMarch31('2004-08-20', 2026), 21);
    expect(draftAgeOnMarch31(null, 2026), isNull);
  });

  test('同額の複数年契約は将来セルだけ補い、金額変更や契約終了を尊重する', () {
    final salaries = <Map<String, dynamic>>[
      {'year': 2026, 'amount': 100000000, 'currency': 'JPY', 'team': '阪神'},
      {'year': 2028, 'amount': 100000000, 'currency': 'JPY', 'team': '阪神'},
    ];
    final periods = <Map<String, dynamic>>[
      {'start_year': 2026, 'end_year': 2029, 'team': '阪神'},
    ];
    final displayed = contractDisplaySalaries(salaries, periods, 2026);
    expect(displayed.map((s) => s['year']).toSet(), {2026, 2027, 2028, 2029});
    expect(displayed.where((s) => s['projected'] == true).length, 2);
    expect(displayed.firstWhere((s) => s['year'] == 2028)['projected'], isNull);
    expect(salaries.length, 2);
    expect(careerSalaryLabel(displayed, 2026), careerSalaryLabel(salaries, 2026));
    expect(contractDisplaySalaries(salaries, [], 2026).length, 2);
    expect(
        contractDisplaySalaries(
                salaries,
                [
                  {...periods.single, 'detail': '年俸変動制'}
                ],
                2026)
            .length,
        2);
    expect(
        contractDisplaySalaries([
          salaries.first,
          {...salaries.last, 'amount': 200000000}
        ], periods, 2026)
            .length,
        2);
    expect(
        contractDisplaySalaries(
                salaries,
                [
                  {...periods.single, 'team': '巨人'}
                ],
                2026)
            .length,
        2);
  });

  testWidgets('予想ロゴは根拠を開き出典URLを表示しない', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.runAsync(() => rootBundle.loadString('backend/assets/data/draft_2026.json'));
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: StrengthDraft(year: 2026))));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    final logo = find.byKey(const ValueKey('draft-prediction-菰田陽生-巨人'));
    await t.tap(logo);
    await t.pumpAndSettle();
    expect(find.text('https://www.hb-nippon.com/articles/18340'), findsNothing);
    expect(find.text('https://www.youtube.com/watch?v=oOYEfvW9xOk'), findsNothing);
    expect(find.textContaining('予想者：AIデータ二刀流'), findsNothing);
    await t.tap(find.text('閉じる'));
    await t.pumpAndSettle();
    expect(t.getBottomRight(find.byKey(const ValueKey('draft-cell-菰田陽生-11'))).dx, closeTo(1200, .1));
    final age = find.byKey(const ValueKey('draft-cell-菰田陽生-4'));
    expect(find.descendant(of: age, matching: find.text('18')), findsOneWidget);
    expect(find.byTooltip('2027年3月31日時点'), findsOneWidget);
    expect(find.byTooltip('予想の自動表示を停止'), findsNothing);
    await t.pump(const Duration(minutes: 2));
    expect(find.byKey(const ValueKey('draft-auto-preview')), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  test('功績は重ならず画面幅に収まり段の空きを再利用する', () {
    for (final width in [152.0, 192.0, 247.0, 680.0, 1200.0]) {
      final sizes = [160.0, 160.0, 72.0, 72.0, 68.0, 60.0, 60.0, 52.0, 48.0, for (var i = 0; i < 30; i++) 40.0];
      final rects = packAchievementBadges(sizes, width);
      expect(rects.length, sizes.length);
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].left, greaterThanOrEqualTo(0));
        expect(rects[i].right, lessThanOrEqualTo(width));
        for (var j = 0; j < i; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    }
  });
  test('大きいトロフィー横の空きを埋めて縦長にしない', () {
    final rects = packAchievementBadges([160, 40, 40, 40, 40, 40, 40], 247);
    expect(rects[0].left, 0);
    expect(rects.skip(1).map((r) => r.left).toSet().length, 2);
    expect(rects.every((r) => r.bottom <= 160), isTrue);
    final large = packAchievementBadges([160, 160, 160], 325);
    expect(large[1].top, 0);
    expect(large[2].left, 0);
    expect(large[2].top, 162);
  });

  test('功績の格は年間と月間MVPを区別し、通算の到達数も考慮する', () {
    final awards = [
      {'label': '規定打席到達', 'kind': 'qualification', 'year': 2026},
      {'label': '月間MVP', 'kind': 'title', 'year': 2026},
      {'label': 'NPB 通算100本塁打', 'kind': 'milestone', 'year': 2026},
      {'label': 'NPB 通算500本塁打', 'kind': 'milestone', 'year': 2020},
      {'label': 'AL MVP', 'kind': 'title', 'year': 2024},
      {'label': '三冠王', 'kind': 'record', 'year': 2022},
      {'label': 'MLB史上初 50-50', 'kind': 'record', 'year': 2024},
    ]..sort(compareAchievementPriority);
    expect(awards.map((a) => a['label']), ['MLB史上初 50-50', '三冠王', 'NPB 通算500本塁打', 'AL MVP', 'NPB 通算100本塁打', '月間MVP', '規定打席到達']);
    final standard = awards.where((a) => !isLeagueMvp(a)).toList();
    for (var i = 1; i < standard.length; i++) {
      expect(achievementBadgeSize(standard[i - 1]), greaterThanOrEqualTo(achievementBadgeSize(standard[i])));
    }
    expect(achievementBadgeSize({'label': 'AL MVP'}), 96);
    for (final label in ['首位打者', '最多本塁打', '最多打点', '最多勝', '最優秀防御率']) {
      expect(achievementBadgeSize({'label': label, 'kind': 'title'}), 72);
    }
    expect(achievementBadgeSize({'label': 'トリプルスリー', 'kind': 'record'}), 192);
    expect(isLeagueMvp({'label': '最優秀選手賞'}), isTrue);
    expect(isLeagueMvp({'label': 'NL Most Valuable Player'}), isTrue);
    expect(isLeagueMvp({'label': '月間MVP'}), isFalse);
    expect(isLeagueMvp({'label': 'World Series MVP'}), isFalse);
    expect(compareAchievementPriority({'label': '最多本塁打', 'year': 2025}, {'label': '最多本塁打', 'year': 2024}), lessThan(0));
    expect(achievementPriority({'label': 'AL Player of the Month', 'kind': 'title'}), 45);
  });

  testWidgets('功績を格の高い順に左から並べ、大きな功績ほどアイコンも大きくする', (t) async {
    await t.binding.setSurfaceSize(const Size(375, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: StrengthAchievements(year: 2026, team: {
      'roster': [
        {
          'name': '選手',
          'achievements': [
            {'label': '規定打席到達', 'year': 2026, 'kind': 'qualification'},
            {'label': '三冠王', 'year': 2022, 'kind': 'record'},
            {'label': '月間MVP', 'year': 2025, 'kind': 'title'},
          ]
        }
      ]
    }))));
    final badges = find.byType(AchievementBadge);
    final widgets = t.widgetList<AchievementBadge>(badges).toList();
    expect(widgets.map((w) => w.achievement['label']), ['三冠王', '月間MVP', '規定打席到達']);
    final rects = [for (var i = 0; i < 3; i++) t.getRect(badges.at(i))];
    expect(rects[0].width, greaterThan(rects[1].width));
    expect(rects[1].width, greaterThan(rects[2].width));
    expect(rects[0].right, lessThanOrEqualTo(rects[1].left));
    expect(rects[1].right, lessThanOrEqualTo(rects[2].left));
    await t.tap(find.byTooltip('2022年 三冠王'));
    await t.pumpAndSettle();
    expect(find.text('選手：三冠王'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('小さい功績をスマホ幅で折り返しリーグMVPは大きく表示する', (t) async {
    await t.binding.setSurfaceSize(const Size(375, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthAchievements(year: 2026, team: {
      'roster': [
        {
          'name': '選手',
          'achievements': [
            const {'label': 'AL MVP', 'kind': 'title', 'year': 2025},
            for (var year = 2000; year <= 2025; year++) {'label': '規定打席到達', 'kind': 'qualification', 'year': year},
          ]
        }
      ]
    }))));
    expect(find.text('2000'), findsOneWidget);
    expect(find.text('2025'), findsNWidgets(2));
    final badges = find.byType(AchievementBadge);
    final rects = [for (var i = 0; i < 27; i++) t.getRect(badges.at(i))];
    expect(rects.first.width, 96);
    expect(rects.last.top, greaterThan(rects[1].top));
    for (final rect in rects) {
      expect(rect.left, greaterThanOrEqualTo(120));
      expect(rect.right, lessThanOrEqualTo(375));
    }
    expect(find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal), findsNothing);
    await t.tap(find.byTooltip('2025年 AL MVP'));
    await t.pumpAndSettle();
    expect(find.text('選手：AL MVP'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('リーグMVPは枠と背景を持ち左上にリーグ、黒いトロフィーに白いMVPを表示', (t) async {
    for (final league in [('cl', 'セMVP'), ('pl', 'パMVP')]) {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: AchievementBadge(achievement: {
        'label': '最優秀選手',
        'kind': 'title',
        'year': 2023,
        'source': 'https://npb.jp/award/2023/${league.$1}.html',
      })))));
      expect(t.getSize(find.byType(AchievementBadge)), const Size(96, 96));
      expect(t.widget<Text>(find.text('MVP')).style!.color, Colors.white);
      expect(find.text('2023'), findsOneWidget);
      expect(find.text(league.$2.replaceFirst('MVP', '')), findsOneWidget);
      final frame = t.widget<Container>(find.byKey(const ValueKey('league-mvp-frame')));
      final decoration = frame.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.gradient, isNotNull);
      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LeagueMvpTrophyPainter), findsOneWidget);
      expect(t.takeException(), isNull);
    }
    expect(leagueMvpCaption({'label': '最優秀選手'}), 'MVP');
    expect(leagueMvpCaption({'label': 'AL MVP'}), 'アMVP');
    expect(leagueMvpCaption({'label': 'NL MVP'}), 'ナMVP');
  });

  testWidgets('小さい功績はホバーとクリックで正式名と詳細を表示', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StrengthAchievements(year: 2026, team: {
      'roster': [{'name': '選手', 'achievements': [
        {'label': '規定打席到達', 'kind': 'qualification', 'year': 2025, 'detail': '規定443打席に到達'}
      ]}]
    }))));
    final badge = find.byType(AchievementBadge);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(t.getCenter(badge));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('2025年 規定打席到達\n規定443打席に到達'), findsOneWidget);
    await mouse.removePointer();
    await t.tap(badge);
    await t.pumpAndSettle();
    expect(find.text('選手：規定打席到達'), findsOneWidget);
    expect(find.textContaining('規定443打席に到達'), findsWidgets);
    expect(t.takeException(), isNull);
    expect(achievementBadgeCaption({'label': '最多盗塁者'}), '盗塁王');
    expect(achievementBadgeCaption({'label': '最多勝利投手'}), '最多勝');
  });

  testWidgets('功績には識別文字と右下の年度、全面の四角い背景を表示', (t) async {
    for (final label in ['最多本塁打', '最優秀防御率', '月間MVP', '優秀選手賞', '特別功労選手表彰']) {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(
        child: AchievementBadge(achievement: {'label':label,'kind':'title','year':2025})))));
      expect(find.byWidgetPredicate((w) => w is Text && w.data?.replaceAll('\n', '') == achievementBadgeCaption({'label': label})), findsOneWidget);
      expect(t.widget<Container>(find.byKey(const ValueKey('achievement-year-label'))).color, Colors.white);
      if (label == '優秀選手賞') expect(find.text('MVP'), findsOneWidget);
      if (label == '特別功労選手表彰') {
        expect(t.widget<Text>(find.byKey(const ValueKey('achievement-engraving'))).data, contains('\n'));
      }
      final badge = t.getRect(find.byType(AchievementBadge));
      final year = t.getRect(find.text('2025'));
      expect(year.center.dx, greaterThan(badge.center.dx));
      expect(year.center.dy, greaterThan(badge.center.dy));
      final frame = find.byKey(const ValueKey('achievement-frame'));
      expect(t.getSize(frame).width, closeTo(badge.width, .001));
      expect(t.getSize(frame).height, closeTo(badge.height, .001));
      expect((t.widget<Container>(frame).decoration as BoxDecoration).borderRadius, BorderRadius.zero);
      expect(t.takeException(),isNull);
    }
  });
  test('功績の種類で色と図柄を変え、年度には依存しない', () {
    final hr = achievementBadgeStyle({'label': '最多本塁打', 'kind': 'title'});
    final era = achievementBadgeStyle({'label': '最優秀防御率', 'kind': 'title'});
    final milestone = achievementBadgeStyle({'label': '通算100本塁打', 'kind': 'milestone'});
    final pa = achievementBadgeStyle({'label': '規定打席到達', 'kind': 'qualification'});
    final ip = achievementBadgeStyle({'label': '規定投球回到達', 'kind': 'qualification'});
    expect(hr.color, isNot(era.color));
    expect(hr.symbol, isNot(era.symbol));
    expect(hr.trophy, isTrue);
    expect(milestone.trophy, isFalse);
    expect(pa.color, isNot(ip.color));
    expect(achievementBadgeStyle({'label': '最多本塁打', 'kind': 'title', 'year': 2020}), hr);
  });

  test('複数位置は登録位置を先にし同系統を重複させない', () {
    for (final pair in [
      ['内野手', '外野手'],
      ['外野手', '内野手'],
      ['投手', '指名打者'],
      ['捕手', '内野手']
    ]) {
      final colors = personalStatPositionColors({
        'txt_position': pair[0],
        'season_position_groups': [pair[1], pair[0], pair[1]]
      });
      expect(colors, [personalStatPositionColor(pair[0]), personalStatPositionColor(pair[1])]);
      expect(
          personalStatPositionGradient({
            'txt_position': pair[0],
            'season_position_groups': [pair[1]]
          })!
              .stops,
          [0, .5, .5, 1]);
    }
    expect(personalStatPositionGradient({'txt_position': '投手'}), isNull);
  });
  test('起用軍と投球回は小数でなくアウト数で比較し未取得を区別', () {
    final p = {
      'position_group': '投手',
      'level_appearances': {'1': 3, '2': 10},
      'level_usage_metrics': {
        '2': {'outs': 32}
      }
    };
    expect(rosterMainLevel(p), 2);
    expect(rosterWorkload(p, {}, 2), 32);
    expect(rosterWorkloadLabel(p, {}, 2), '10.2回');
    expect(rosterWorkload(p, {}, 3), isNull);
    expect(
        rosterWorkload({
          'position_group': '投手',
          'level_usage_metrics': {
            '2': {'outs': 0}
          }
        }, {}, 2),
        0);
  });
  testWidgets('初期表示は起用順で軍ごとに打席数降順、年齢順に切り替えられる', (t) async {
    final roster = [
      for (final v in [('少ない', 20, 20), ('多い', 19, 100)])
        {
          'name': v.$1,
          'player_key': v.$1,
          'age': v.$2,
          'date_birth': '2000-01-01',
          'position_group': '捕手',
          'bats': '右',
          'level_appearances': {'1': 5},
          'level_usage_metrics': {
            '1': {'pa': v.$3}
          }
        }
    ];
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StrengthRosterGrid(year: 2026, team: {'roster': roster}))));
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '起用順')).selected, isTrue);
    expect(find.text('1軍'), findsOneWidget);
    expect(find.text('4軍'), findsOneWidget);
    expect(t.getTopLeft(find.text('多い')).dy, lessThan(t.getTopLeft(find.text('少ない')).dy));
    expect(find.text('100打席'), findsOneWidget);
    await t.tap(find.text('年齢順'));
    await t.pumpAndSettle();
    expect(find.text('1軍'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('経歴が多い選手も拡大文字ですべてセル内に収める', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.runAsync(() => rootBundle.loadString('backend/assets/data/draft_2026.json'));
    await t.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: const Scaffold(body: StrengthDraft(year: 2026)))));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    final cell = find.byKey(const ValueKey('draft-cell-織田翔希-9'));
    final text = find.descendant(of: cell, matching: find.byType(Text));
    expect(t.widget<Text>(text).data, contains('2025年春'));
    expect(t.widget<Text>(text).data, contains('2026年夏'));
    expect(t.getSize(cell).height, greaterThan(150));
    expect(t.getRect(text).bottom, lessThanOrEqualTo(t.getRect(cell).bottom - 5));
    expect(t.getRect(text).top, greaterThanOrEqualTo(t.getRect(cell).top + 5));
    expect(t.getSize(cell).height, t.getSize(find.byKey(const ValueKey('draft-cell-織田翔希-1'))).height);
    expect(t.takeException(), isNull);
  });
  testWidgets('ドラフトは固定4列と横スクロール表で詳細を開き出典URLを表示しない', (t) async {
    await t.binding.setSurfaceSize(const Size(375, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.runAsync(() => rootBundle.loadString('backend/assets/data/draft_2026.json'));
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: StrengthDraft(year: 2026))));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    expect(find.text('織田翔希'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
    for (final header in ['注目度', '選手名', '所属', 'チーム', '年齢', '身長', '体重', '投打', 'ポジション', '経歴', '特徴', '獲得予想']) {
      expect(find.text(header), findsOneWidget);
    }
    expect(find.text('高校生'), findsWidgets);
    expect(find.text('大学生'), findsWidgets);
    expect(find.text('社会人'), findsWidgets);
    expect(find.text('独立'), findsWidgets);
    expect(find.text('鎌田州真'), findsOneWidget);
    final fixed = find.byKey(const ValueKey('draft-cell-菰田陽生-1'));
    final age = find.byKey(const ValueKey('draft-cell-菰田陽生-4'));
    final initialFixed = t.getTopLeft(fixed);
    final initialAge = t.getTopLeft(age);
    await t.dragFrom(const Offset(330, 180), const Offset(-220, 0));
    await t.pumpAndSettle();
    expect(t.getTopLeft(fixed), initialFixed);
    expect(t.getTopLeft(age).dx, lessThan(initialAge.dx));
    await t.tap(find.text('菰田陽生'));
    await t.pumpAndSettle();
    expect(find.text('閉じる'), findsOneWidget);
    await t.tap(find.text('閉じる'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: StrengthAchievements(year: 2026, team: {
      'roster': [
        {
          'name': '選手',
          'achievements': [
            {'year': 2023, 'label': 'WBC優勝', 'kind': 'championship', 'source': 'https://example.com', 'detail': '確認済み'}
          ]
        }
      ]
    }))));
    await t.tap(find.byTooltip('2023年 WBC優勝\n確認済み'));
    await t.pumpAndSettle();
    expect(find.text('https://example.com'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('功績は表示年度内の件数順でアイコンのみ表示しホバーで内容を確認', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: StrengthAchievements(year: 2026, team: {
      'roster': [
        {
          'name': '少ない選手',
          'achievements': [
            {'year': 2025, 'label': '一つの功績', 'kind': 'title'},
            {'year': 2027, 'label': '将来の功績', 'kind': 'title'},
            {'year': 2028, 'label': '将来の功績2', 'kind': 'title'},
          ]
        },
        {
          'name': '多い選手',
          'achievements': [
            {'year': 2024, 'label': '優勝の功績', 'kind': 'championship'},
            {'year': 2025, 'label': '記録の功績', 'kind': 'record'},
          ]
        },
      ]
    }))));
    expect(t.getTopLeft(find.text('多い選手')).dy, lessThan(t.getTopLeft(find.text('少ない選手')).dy));
    expect(find.byType(IconButton), findsNWidgets(3));
    expect(find.text('2024年 優勝の功績'), findsNothing);
    final tooltip = t.state<TooltipState>(find.byTooltip('2024年 優勝の功績'));
    tooltip.ensureTooltipVisible();
    await t.pumpAndSettle();
    expect(find.text('2024年 優勝の功績'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('狭い契約画面は生涯年俸が横に移動し注意書きは表の中', (t) async {
    t.view.physicalSize = const Size(375, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StrengthContracts(year: 2026, team: {
      'id_team': 1,
      'name_team': '球団',
      'contracts': [
        {
          'player_key': 'a',
          'name': '選手A',
          'salary_history': [
            for (var y = 2020; y <= 2027; y++) {'year': y, 'amount': 10000000, 'currency': 'JPY'}
          ]
        }
      ]
    }))));
    await t.pumpAndSettle();
    final salary = find.byKey(const ValueKey('career-salary-1-a'));
    final name = find.byKey(const ValueKey('contract-name-1-a'));
    final oldSalary = t.getTopLeft(salary).dx, oldName = t.getTopLeft(name).dx;
    final scroll = find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
    await t.drag(scroll, const Offset(200, 0));
    await t.pumpAndSettle();
    expect(t.getTopLeft(salary).dx, greaterThan(oldSalary));
    expect(t.getTopLeft(name).dx, closeTo(oldName, .01));
    final note = find.textContaining('札束は1段につき');
    expect(find.ancestor(of: note, matching: find.byType(ListView)), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
