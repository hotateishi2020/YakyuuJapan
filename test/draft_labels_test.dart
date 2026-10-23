import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/widgets/draft_labels.dart';
void main() {
  testWidgets('ハズレ3回のラベルも狭いセルで1行に縮小する', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 88, child: DraftLabels(player: {
        'rank': 1, 'note': '候補A×・候補B×・候補C×',
      })),
    ))));
    final label = find.text('ハズレハズレハズレ1位');
    expect(label, findsOneWidget);
    final text = tester.widget<Text>(label);
    expect(text.maxLines, 1);
    expect(text.softWrap, false);
    final box = find.ancestor(of: label, matching: find.byType(FittedBox));
    expect(tester.widget<FittedBox>(box).fit, BoxFit.scaleDown);
    expect(tester.getSize(box).width, lessThanOrEqualTo(78));
    expect(tester.getSize(box).height, lessThan(20));
    expect(tester.takeException(), isNull);
  });
  test('所属カテゴリは資料を優先し学校種別を識別する', () {
    expect(draftSchoolCategory({'category':'中学生','from':'硬式クラブ'}), '中学生');
    expect(draftSchoolCategory({'from':'横浜高'}), '高校生');
    expect(draftSchoolCategory({'from':'明治大学'}), '大学生');
    expect(draftSchoolCategory({'from':'ENEOS'}), '社会人');
    expect(draftSchoolCategory({'from':'徳島インディゴソックス'}), '独立リーグ');
  });
  testWidgets('カテゴリと再指名・競合のラベルを狭いセルで折り返す', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width:88, child: DraftLabels(player: {'category':'高校生', 'rank':'1', 'competition':2, 'note':'前候補×・次候補×'}))))));
    expect(find.text('高校生'), findsOneWidget);
    expect(find.text('2球団競合'), findsOneWidget);
    expect(find.text('ハズレハズレ1位'), findsOneWidget);
    expect(draftLabelColor('単独指名'), Colors.black);
    expect(draftLabelColor('高校生'), Colors.red.shade700);
    expect(draftLabelColor('中学生'), Colors.purple.shade700);
    expect(draftLabelColor('大学生'), Colors.blue.shade700);
    expect(draftLabelColor('社会人'), Colors.green.shade700);
    expect(draftLabelColor('独立リーグ'), Colors.orange.shade800);
    expect(tester.takeException(), isNull);
  });
}
