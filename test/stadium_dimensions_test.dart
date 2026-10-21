import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/baseball_catalog_boards.dart';

void main() {
  for (final width in [375.0, 1400.0]) {
    testWidgets('球場寸法の2列と未収録を幅$widthで表示', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StadiumsBoard(org: 'npb'))));
        await tester.pumpAndSettle();
        expect(find.text('スタンドまでの距離'), findsOneWidget);
        expect(find.text('外野フェンスの高さ'), findsOneWidget);
        expect(find.text('左翼 98m\n中堅 122m\n右翼 100m'), findsOneWidget);
        expect(find.text('2m（一部1.8m）\n2026年改修後'), findsOneWidget);
        await tester.ensureVisible(find.text('外野フェンスの高さ'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('https://example.org/fence'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('2軍球場'));
        await tester.pumpAndSettle();
        expect(find.text('スタンドまでの距離'), findsNothing);
        expect(find.text('外野フェンスの高さ'), findsNothing);
        expect(tester.takeException(), isNull);
      }, () => MockClient((_) async => http.Response(jsonEncode({'stadiums': [
        {'name': '球場A', 'team': '球団A', 'stadium_level': 'first', 'outfield_distance': '左翼 98m\n中堅 122m\n右翼 100m', 'outfield_distance_source': 'https://example.org/distance', 'fence_height': '2m（一部1.8m）\n2026年改修後', 'fence_height_source': 'https://example.org/fence'},
        {'name': '未確認球場', 'team': '球団B', 'stadium_level': 'first'},
        {'name': '2軍球場名', 'team': '球団A', 'stadium_level': 'farm'},
      ]}), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
    });
  }
}
