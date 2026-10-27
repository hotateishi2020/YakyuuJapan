import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/GamesBoard.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

void main() {
  for (final viewportWidth in [2000.0, 480.0]) {
  for (final runnerBats in [false, true]) {
  testWidgets('同一回の2巡目を折り返し、回の区間を囲み、特殊成績は枠外に置く runnerBats=$runnerBats width=$viewportWidth', (tester) async {
    tester.view.physicalSize = Size(viewportWidth, 1600);
    tester.view.devicePixelRatio = 1;
    AuthSession.instance.user = AuthUser.fromJson({'id': 1});
    AuthSession.instance.token = 'test';
    addTearDown(() {
      AuthSession.instance.user = null;
      AuthSession.instance.token = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GamesBoardYahooStyle(
      horizontal: true,
      games: [{
        'id_game': 1, 'date_game': '2026-10-25', 'state': '8回表',
        'id_team_home': 1, 'id_team_away': 2,
        'name_team_home': 'ソフトバンク', 'name_team_away': 'DeNA',
        'name_pitcher_home': '自軍　先発', 'name_pitcher_away': '相手　先発',
        'score_home': 3, 'score_away': 0,
        'lineup': [for (var order = 1; order <= 9; order++) {
          'id_team': 1, 'order': order, 'players': [
            {'name': '先発$order', 'plays': order == 1
              ? '左安|single/inning1/bases5/event${Uri.encodeComponent('投手:新投手')}/event${Uri.encodeComponent('暴投')}/event${Uri.encodeComponent('盗塁:三森 大貴')}/event${Uri.encodeComponent('代走:川村')}/event${Uri.encodeComponent('代守:守備(中→左)')}/event${Uri.encodeComponent('守備位置転換:守備(左→中)')}/event${Uri.encodeComponent('守備位置転換:近藤(右→左)')}/event${Uri.encodeComponent('代打:代打選手')} 中安|single/inning1/bases2 右安|single/inning3/bases0'
              : order == 2
                ? '遊飛|out/inning1 遊飛|out/inning1 遊飛|out/inning3 遊飛|out/inning4 遊飛|out/inning5'
                : '三振|out/inning1'},
            if (order == 3) {'name': '代打　選手', 'role': '代打', 'plays': '左本|hr/pinch/inning2'},
            if (order == 4) {'name': '代走　選手', 'role': '代走', 'plays': runnerBats ? '中本|hr/inning2 右安|single/inning3' : ''},
            if (order == 5) {'name': '守備　選手', 'role': '代守', 'plays': '右飛|out/inning2'},
          ],
        }, {'id_team': 2, 'order': 1, 'players': [{'name': '横浜打者', 'plays': '中飛|out/inning1 三振|out/inning8/event${Uri.encodeComponent('投手:松本裕樹')}'}]}],
      }],
    ))));
    await tester.pump(const Duration(milliseconds: 300));
    Finder keyed(String key) => find.byKey(ValueKey(key));
    final first = tester.getRect(keyed('batting-inning-1-home-0-1'));
    final repeat = tester.getRect(keyed('batting-inning-1-home-1-1'));
    final second = tester.getRect(keyed('batting-inning-2-home-1-3'));
    expect(repeat.left, greaterThanOrEqualTo(first.right));
    expect(repeat.top, first.top);
    expect(first.height, greaterThan(repeat.height));
    expect(second.top, closeTo(repeat.bottom, 0.1));
    expect(find.descendant(of: keyed('batting-turn-home-0-1'), matching: find.text('左安')), findsOneWidget);
    expect(find.descendant(of: keyed('batting-turn-home-1-1'), matching: find.text('中安')), findsOneWidget);
    for (final name in ['代打選手', '代走選手', '守備選手']) {
      expect(keyed('substitution-frame-$name'), name == '代走選手' ? (runnerBats ? findsNWidgets(2) : findsNothing) : findsOneWidget);
      expect(keyed('substitution-title-$name'), name == '代走選手' ? (runnerBats ? findsNWidgets(2) : findsNothing) : findsOneWidget);
      expect(keyed('substitution-badge-$name'), name == '代走選手' ? (runnerBats ? findsNWidgets(2) : findsNothing) : findsOneWidget);
    }
    expect(keyed('batting-runner-代走選手'), findsNothing);
    if (runnerBats) {
      expect(find.descendant(of: keyed('batting-turn-home-1-4'), matching: find.text('中本')), findsOneWidget);
      expect(keyed('batting-runner-代走選手'), findsNothing);
    }
    expect(tester.getSize(keyed('batting-name-home-1')).height,
      greaterThan(tester.getSize(keyed('batting-name-home-2')).height));
    expect(tester.getSize(keyed('batting-name-home-2')).height, lessThanOrEqualTo(29));
    for (final pair in [('先発1', '左安'), ('先発2', '遊飛')]) {
      final result = find.descendant(of: keyed('batting-turn-home-0-${pair.$1 == '先発1' ? 1 : 2}'), matching: find.text(pair.$2));
      expect(tester.getCenter(find.text(pair.$1)).dy, closeTo(tester.getCenter(result).dy, 0.5));
    }
    final awayOpening = keyed('batting-turn-away-0-1');
    expect(find.descendant(of: awayOpening, matching: find.text('自軍先')), findsOneWidget);
    expect(find.descendant(of: keyed('batting-turn-away-1-1'), matching: find.text('松本裕')), findsOneWidget);
    final opening = keyed('batting-turn-home-0-1');
    final starterLabel = find.descendant(of: opening, matching: keyed('plate-event-label-先発投手'));
    expect(starterLabel, findsOneWidget);
    expect(find.descendant(of: starterLabel, matching: find.text('相手先')), findsOneWidget);
    expect((tester.widget<Container>(starterLabel).decoration as BoxDecoration).color, const Color(0xFFFF4B7D));
    expect(find.descendant(of: keyed('batting-turn-home-1-1'), matching: keyed('plate-event-label-先発投手')), findsNothing);
    expect(find.text('→相手先発'), findsNothing);
    expect(find.text('→新投手'), findsNothing);
    expect(find.text('→松本裕樹'), findsNothing);

    final chip = find.descendant(of: opening, matching: find.text('左安'));
    final header = find.descendant(of: opening, matching: keyed('plate-event-header'));
    final runnerFooter = find.descendant(of: opening, matching: keyed('plate-event-footer'));
    expect(tester.getTopLeft(runnerFooter).dy, greaterThanOrEqualTo(tester.getBottomLeft(chip).dy));
    for (final expected in [
      ('投手', '新投手', const Color(0xFFFF4B7D)),
      ('盗塁', '盗：三森', const Color(0xFFC6FF00)),
      ('代走', '走：川村', const Color(0xFF5C6BC0)),
      ('代守', '守備(左)', const Color(0xFF5C6BC0)),
      ('守備位置転換', '近藤(右→左)', const Color(0xFF5C6BC0)),
    ]) {
      final label = find.descendant(of: opening, matching: keyed('plate-event-label-${expected.$1}'));
      expect(find.descendant(of: label, matching: find.text(expected.$2)), findsOneWidget);
      expect((tester.widget<Container>(label).decoration as BoxDecoration).color, expected.$3);
    }
    expect(find.text('守備(左→中)'), findsNothing);
    final pitcherLabel = find.descendant(of: opening, matching: keyed('plate-event-label-投手'));
    final stealLabel = find.descendant(of: opening, matching: keyed('plate-event-label-盗塁'));
    expect(tester.getTopLeft(stealLabel).dy, greaterThan(tester.getBottomLeft(pitcherLabel).dy));
    expect(tester.getTopLeft(stealLabel).dx, tester.getTopLeft(pitcherLabel).dx);
    expect(find.descendant(of: opening, matching: keyed('plate-event-label-代打')), findsNothing);
    expect(tester.getBottomLeft(header).dy, lessThan(tester.getTopLeft(chip).dy));
    expect(find.descendant(of: opening, matching: keyed('base-occupied-1')), findsOneWidget);
    expect(find.descendant(of: opening, matching: keyed('base-occupied-2')), findsNothing);
    expect(find.descendant(of: opening, matching: keyed('base-occupied-3')), findsOneWidget);
    expect(find.descendant(of: keyed('batting-turn-home-1-1'), matching: keyed('base-occupied-2')), findsOneWidget);
    expect(find.descendant(of: keyed('batting-turn-home-2-1'), matching: keyed('base-occupied-1')), findsNothing);
    final specials = keyed('batting-specials-home');
    for (final label in ['猛打賞', '5タコ']) {
      expect(find.descendant(of: specials, matching: find.text(label)), findsOneWidget);
    }
    final frames = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('batting-inning-') && (w.key as ValueKey<String>).value.contains('-home-'));
    for (final element in frames.evaluate()) {
      expect(tester.getRect(find.byWidget(element.widget)).right,
        lessThanOrEqualTo(tester.getTopLeft(specials).dx));
    }
    expect(tester.takeException(), isNull);
  });
  }
  }
}
