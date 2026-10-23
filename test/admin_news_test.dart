import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/pages/admin_logs_page.dart';

void main() {
  for (final status in [201, 403, 500]) {
    testWidgets('News入力保持・バリデーション・登録レスポンス$status', (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map? sent;
      var saves = 0;
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: AdminLogsPage()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('News登録').first);
        await tester.pumpAndSettle();
        expect(find.text('カテゴリ'), findsOneWidget);
        expect(find.text('サブカテゴリ'), findsOneWidget);
        expect(find.text('イベント'), findsOneWidget);
        expect(find.text('シーズン予想'), findsOneWidget);
        await tester.ensureVisible(find.text('システム'));
        await tester.tap(find.text('システム'));
        await tester.ensureVisible(find.text('アップデート'));
        await tester.tap(find.text('アップデート'));
        await tester.ensureVisible(find.text('Newsを登録'));
        await tester.tap(find.text('Newsを登録'));
        await tester.pumpAndSettle();
        expect(saves, 0);
        expect(find.text('タイトルを入力してください'), findsOneWidget);
        await tester.enterText(
            find.widgetWithText(TextFormField, 'タイトル（必須）'), '新しいNews');
        await tester.enterText(
            find.widgetWithText(TextFormField, '本文'), 'お知らせの本文');
        await tester.tap(find.text('ログ管理'));
        await tester.pumpAndSettle();
        expect(find.text('操作ログを表示'), findsOneWidget);
        await tester.tap(find.text('News登録').first);
        await tester.pumpAndSettle();
        expect(find.text('新しいNews'), findsOneWidget);
        await tester.ensureVisible(find.text('Newsを登録'));
        await tester.tap(find.text('Newsを登録'));
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(sent?['title'], '新しいNews');
        expect(sent?['text_main'], 'お知らせの本文');
        expect(sent?['code_tag_main'], 'SYS');
        expect(sent?['code_tag_sub'], 'UPD');
        if (status == 201) {
          expect(find.text('Newsを登録しました'), findsOneWidget);
          final field = tester.widget<TextFormField>(
              find.widgetWithText(TextFormField, 'タイトル（必須）'));
          expect(field.controller!.text, isEmpty);
          expect(find.text('新しいNews'), findsOneWidget);
        } else {
          expect(find.text('登録エラー'), findsOneWidget);
          expect(find.text('新しいNews'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
          () => MockClient((request) async {
                if (request.method == 'POST') {
                  saves++;
                  sent = jsonDecode(request.body) as Map;
                  return http.Response(
                      jsonEncode(status == 201
                          ? {
                              'ok': true,
                              'news': {...sent!, 'id': 1}
                            }
                          : {'error': '登録エラー'}),
                      status,
                      headers: {
                        'content-type': 'application/json; charset=utf-8'
                      });
                }
                return http.Response(
                    jsonEncode({
                      'logs': [],
                      'news': [],
                      'tags': [
                        {'code': 'NORTIFICATION', 'key': 'SYS', 'label': 'システム'},
                        {'code': 'NORTIFICATION', 'key': 'EVENT', 'label': 'イベント'},
                        {'code': 'NORTIFICATION', 'key': 'PRED', 'label': 'シーズン予想'},
                        {'code': 'NORTIFICATION_SUB', 'key': 'UPD', 'label': 'アップデート'},
                      ]
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }));
    });
  }
}
