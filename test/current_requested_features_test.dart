import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/adaptive_section_selector.dart';
import 'package:Yakyuu_Japan/View/player_stats_grid.dart';
import 'package:Yakyuu_Japan/logic/strength_usage.dart';

void main() {
  test('HR - 盗塁は両成績がある選手のみ、少ない方の降順', () {
    final rows = withHrStealStats([
      {'id_player': 1, 'id_league': 1, 'title': '本塁打', 'stats': '40'},
      {'id_player': 1, 'id_league': 1, 'title': '盗塁', 'stats': '10'},
      {'id_player': 2, 'id_league': 1, 'title': '本塁打', 'stats': '20'},
      {'id_player': 2, 'id_league': 1, 'title': '盗塁', 'stats': '30'},
      {'id_player': 3, 'id_league': 1, 'title': '本塁打', 'stats': '50'},
    ]).where((r) => r['title'] == 'HR - 盗塁').toList();
    sortPersonalStatRows(rows);
    expect(rows.length, 2);
    expect(rows.first['id_player'], 2);
    expect(rows.first['stats'], '20 - 30');
  });
  test('来季の確定新戦力は起用実績がなくても一軍へ', () {
    expect(
        rosterMainLevel(
            {'new_arrival': true, 'arrival_year': DateTime.now().year + 1}),
        1);
    expect(rosterMainLevel({'arrival_year': DateTime.now().year + 1}), 0);
  });
  testWidgets('表示可能な文字幅に応じてタブとpickerを切り替える', (tester) async {
    Widget app(double width) => MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                    width: width,
                    child: AdaptiveSectionSelector(
                        labels: const {0: '年齢記録', 1: '回数記録', 2: 'レギュラー'},
                        value: 0,
                        onChanged: (_) {},
                        background: Colors.black,
                        foreground: Colors.white)))));
    await tester.pumpWidget(app(600));
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    await tester.pumpWidget(app(160));
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
