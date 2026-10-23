import 'package:Yakyuu_Japan/logic/auth_session.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/View/LeagueLogo.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'package:Yakyuu_Japan/widgets/navigation_picker.dart';

void main() {
  setUp(() { AuthSession.instance.user = AuthUser.fromJson({'id': 1, 'flg_special': true}); AuthSession.instance.token = 'test'; });
  tearDown(() { AuthSession.instance.user = null; AuthSession.instance.token = null; });
  for (final org in [OrgConfig.npb, OrgConfig.mlb]) {
    for (final width in [375.0, 1000.0]) {
    testWidgets('${org.label}個人タイトルのリーグpickerに色とロゴを表示（幅$width）', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: NavigationPickerScope(child: Column(children: [
          const NavigationPickerBar(), Expanded(child: RecordsBoard(org: org, year: 2026)),
        ])))));
        await tester.pumpAndSettle();
        tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>).first).onChanged!(1);
        await tester.pumpAndSettle();
        final picker = find.byKey(const ValueKey('navigation-picker-3'));
        for (final league in org.leagues) {
          Color? color;
          if (width < 500) {
            tester.widget<DropdownButton<int>>(picker).onChanged!(league.id);
            await tester.pumpAndSettle();
            final container = tester.widgetList<Container>(find.ancestor(of: picker, matching: find.byType(Container)))
                .firstWhere((c) => c.decoration is BoxDecoration);
            color = (container.decoration as BoxDecoration).color;
            await tester.ensureVisible(picker);
            await tester.tap(picker);
            await tester.pumpAndSettle();
            expect(find.text(league.name), findsWidgets);
            await tester.tap(find.text(league.name).last);
          } else {
            final option = find.byKey(ValueKey('navigation-option-3-${league.id}'));
            await tester.tap(option);
            await tester.pumpAndSettle();
            color = tester.widget<Material>(find.ancestor(of:option, matching:find.byType(Material)).first).color;
          }
          await tester.pumpAndSettle();
          expect(color, league.color);
          expect(find.byWidgetPredicate((w) => w is LeagueLogo && w.asset == league.logoAsset), findsWidgets);
          expect(find.byType(Image), findsWidgets);
          AuthSession.instance.user = AuthUser.fromJson({'id': 3, 'flg_special': false});
          await tester.pump();
          expect(find.byType(Image), findsNothing);
          expect(color, league.color);
          AuthSession.instance.user = AuthUser.fromJson({'id': 1, 'flg_special': true});
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      }, () => MockClient((_) async => http.Response(jsonEncode({'titles': []}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'})));
    });
  }
  }
}
