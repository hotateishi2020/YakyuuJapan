import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/pages/admin_billing_panel.dart';
void main() {
  testWidgets('未登録とゼロを区別し保存失敗時も入力を保持する', (t) async {
    t.view.physicalSize = const Size(390,1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    Map? sent;
    var fail = true;
    await http.runWithClient(() async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: AdminBillingPanel())));
      await t.pumpAndSettle();
      expect(find.text('USD 0.00'),findsOneWidget);
      expect(find.text('未登録'),findsNWidgets(3));
      await t.tap(find.byKey(const ValueKey('billing-edit-neon-invoiced')));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextFormField,'金額'),'12.34');
      await t.enterText(find.widgetWithText(TextFormField,'利用対象期間'),'2026年9月');
      await t.tap(find.text('確認した金額を保存'));
      await t.pumpAndSettle();
      expect(find.text('12.34'),findsOneWidget);
      expect(find.textContaining('保存できませんでした'),findsOneWidget);
      expect(sent!['kind'],'invoiced');
      expect(sent!['amount'],'12.34');
      fail = false;
      await t.tap(find.text('確認した金額を保存'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog),findsNothing);
      expect(t.takeException(),isNull);
    }, () => MockClient((r) async {
      if (r.method == 'POST') { sent=jsonDecode(r.body) as Map; return http.Response('{}',fail ? 500 : 200); }
      return http.Response(jsonEncode({'entries':[{'provider':'neon','kind':'accrued','currency':'USD','amount_minor':0,'period':'2026年10月','checked_at':'2026-10-22T00:00:00Z'}]}),200,headers:{'content-type':'application/json'});
    }));
  });
}
