import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_vertical_label.dart';

Widget label(String text,
        {double width = 40,
        double height = 200,
        TextScaler textScaler = TextScaler.noScaling}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: StrengthVerticalLabel(
              text,
              style: const TextStyle(fontFamily: 'Ahem', height: 1),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('結合文字と絵文字は分割せず上から順に表示する', (tester) async {
    await tester.pumpWidget(label('ガe\u0301👨‍👩‍👧‍👦'));
    expect(find.text('ガ'), findsOneWidget);
    expect(find.text('e\u0301'), findsOneWidget);
    expect(find.text('👨‍👩‍👧‍👦'), findsOneWidget);
    expect(tester.getTopLeft(find.text('ガ')).dy,
        lessThan(tester.getTopLeft(find.text('e\u0301')).dy));
    expect(tester.getTopLeft(find.text('e\u0301')).dy,
        lessThan(tester.getTopLeft(find.text('👨‍👩‍👧‍👦')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('長音・半角長音・括弧・ダッシュを90度回転する', (tester) async {
    await tester.pumpWidget(label('パー（A）ｰ—'));
    for (final glyph in ['ー', '（', '）', 'ｰ', '—']) {
      final rotation = tester.widget<RotatedBox>(find.ancestor(
          of: find.text(glyph), matching: find.byType(RotatedBox)));
      expect(rotation.quarterTurns, 1, reason: glyph);
    }
    final upright = tester.widget<RotatedBox>(
        find.ancestor(of: find.text('パ'), matching: find.byType(RotatedBox)));
    expect(upright.quarterTurns, 0);
  });

  testWidgets('文字送り幅が狭くても漢字を欠けさせない文字領域を確保する', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SizedBox(
          width: 40,
          height: 100,
          child: StrengthVerticalLabel(
            '温郷ー',
            style: TextStyle(fontFamily: 'Ahem', height: 1, letterSpacing: -8),
          ),
        ),
      ),
    ));
    for (final glyph in ['温', '郷', 'ー']) {
      final text = find.text(glyph);
      final cell = find.ancestor(of: text, matching: find.byType(RotatedBox));
      expect(tester.getSize(cell), const Size(12, 12));
      expect(tester.widget<Text>(text).overflow, TextOverflow.visible);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('高さに合わせ12pxから縮小し10px未満にはしない', (tester) async {
    await tester.pumpWidget(label('投手', height: 22));
    expect(tester.widget<Text>(find.text('投')).style?.fontSize, 11);
    expect(tester.widget<Text>(find.text('手')).style?.fontSize, 11);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(label('投手', height: 19));
    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横幅に収まらない場合も非表示にする', (tester) async {
    await tester.pumpWidget(label('投手', width: 9));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('文字拡大を計測・描画に反映する', (tester) async {
    await tester.pumpWidget(label('投手',
        width: 30, height: 44, textScaler: const TextScaler.linear(2)));
    final text = tester.widget<Text>(find.text('投'));
    expect(text.style?.fontSize, 11);
    expect(text.textScaler?.scale(11), 22);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(label('投手',
        width: 30, height: 39, textScaler: const TextScaler.linear(2)));
    expect(find.byType(Text), findsNothing);
  });
}
