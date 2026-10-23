import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/pages/admin_logs_page.dart';

void main() {
  testWidgets('チェック時は操作とエラーのみ、未チェック時はエラーのみ表示する', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AdminLogsPage()));
      await tester.pumpAndSettle();
      expect(find.text('操作'), findsOneWidget);
      expect(find.text('1日（24時間）：3人'), findsOneWidget);
      expect(find.text('125ms'), findsOneWidget);
      expect(find.text('2.0 KiB'), findsOneWidget);
      expect(find.text('32.0 MiB'), findsOneWidget);
      expect(find.text('-1.0 MiB'), findsOneWidget);
      expect(find.text('サーバー処理'), findsNothing);
      expect(find.text('ブラウザ処理'), findsNothing);
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
      expect(find.text('サーバー処理'), findsNothing);
      expect(find.text('ブラウザ処理'), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response(jsonEncode({'visitors': {'1':3, '7':5, '30':8}, 'logs': [
      {'log_type': '操作', 'timestamp': '2026-10-20T00:00:00Z', 'duration_ms': 125, 'transfer_bytes': 2048, 'memory_rss_bytes': 33554432, 'memory_delta_bytes': -1048576},
      {'log_type': 'サーバー処理', 'timestamp': '2026-10-20T00:10:00Z'},
      {'log_type': 'ブラウザ処理', 'timestamp': '2026-10-20T00:20:00Z'},
      {'log_type': 'エラー', 'timestamp': '2026-10-20T01:00:00Z'},
    ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
  });
}
