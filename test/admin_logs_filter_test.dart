import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/pages/admin_logs_page.dart';

void main() {
  testWidgets('操作ログのチェックを外すとエラーログだけ残る', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AdminLogsPage()));
      await tester.pumpAndSettle();
      expect(find.text('操作'), findsOneWidget);
      expect(find.text('サーバー処理'), findsOneWidget);
      expect(find.text('ブラウザ処理'), findsOneWidget);
      expect(find.text('エラー'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.text('操作'), findsNothing);
      expect(find.text('サーバー処理'), findsNothing);
      expect(find.text('ブラウザ処理'), findsNothing);
      expect(find.text('エラー'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.text('操作'), findsOneWidget);
      expect(find.text('サーバー処理'), findsOneWidget);
      expect(find.text('ブラウザ処理'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response(jsonEncode({'logs': [
      {'log_type': '操作', 'timestamp': '2026-10-20T00:00:00Z'},
      {'log_type': 'サーバー処理', 'timestamp': '2026-10-20T00:10:00Z'},
      {'log_type': 'ブラウザ処理', 'timestamp': '2026-10-20T00:20:00Z'},
      {'log_type': 'エラー', 'timestamp': '2026-10-20T01:00:00Z'},
    ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
  });
}
