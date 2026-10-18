import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/pages/prediction_page.dart';

void main() {
  testWidgets('API応答前にヘッダー配下の団体・情報タブを描画する', (tester) async {
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PredictionPage())));
      await tester.pump(const Duration(milliseconds: 1));
      for (final label in ['予想対決', 'NPB', 'MLB', '日程', '試合情報', 'チーム順位', '個人成績', '戦力', '記録', '動画']) {
        expect(find.text(label), findsWidgets);
      }
      expect(pending.isCompleted, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(http.Response('{}', 200));
      await tester.pump(const Duration(seconds: 21));
    }, () => MockClient((_) => pending.future));
  });
}
