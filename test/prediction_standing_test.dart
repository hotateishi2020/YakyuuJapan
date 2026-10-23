import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/PredictGroupBoard.dart';
void main() {
  test('順位・規定未到達と順位圏外を区別し当たりや不明は表示しない', () {
    expect(predictionStandingLabel({'actual_rank': 3}), '（リーグ3位）');
    expect(predictionStandingLabel({'actual_rank': 1000, 'stats_title':'打率'}), '（規定未到達）');
    expect(predictionStandingLabel({'actual_rank': 1000, 'stats_title':'本塁打'}), '（順位圏外）');
    expect(predictionStandingLabel({'actual_rank': 1, 'hit':true}), '');
    expect(predictionStandingLabel({}), '');
  });
  testWidgets('外れの選手名の下だけに小さな灰色の補足を表示', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width:150, child: predictPlayerLabels([
      {'name':'外れ選手', 'actual_rank':3},
      {'name':'当たり選手', 'actual_rank':1, 'hit':true},
    ], const TextStyle(fontSize:13), showStanding:true)))));
    final label = find.text('（リーグ3位）');
    expect(label, findsOneWidget);
    expect(find.text('（リーグ1位）'), findsNothing);
    expect(tester.getTopLeft(label).dy, greaterThan(tester.getTopLeft(find.text('外れ選手')).dy));
    expect(tester.widget<Text>(label).style!.color, Colors.grey);
    expect(tester.widget<Text>(label).style!.fontSize, 10);
    expect(tester.takeException(), isNull);
  });
}
