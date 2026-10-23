import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/View/injuries_board.dart';
import 'package:Yakyuu_Japan/View/team_strength_board.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';

void main() {
  testWidgets('説明は表の末尾にあり行と同じスクロール領域で移動する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: InjuriesBoard(org: 'npb'))));
      await tester.pumpAndSettle();
      final notes = find.byKey(const ValueKey('injuries-grid-notes'));
      final list = find.byKey(const ValueKey('injuries-grid-scroll'));
      expect(notes, findsNothing);
      await tester.scrollUntilVisible(notes, 300, scrollable: find.descendant(of: list, matching: find.byType(Scrollable)));
      await tester.pumpAndSettle();
      expect(find.descendant(of: list, matching: notes), findsOneWidget);
      expect(tester.getTopLeft(notes).dy, greaterThan(tester.getBottomLeft(find.text('選手29')).dy));
      final state = tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)));
      state.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(notes, findsNothing);
      expect(find.text('選手0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response(jsonEncode({'players': [
      for (var i=0; i<30; i++) {'name_player':'選手$i','name_team':'阪神','injury':'肩痛'}
    ]}), 200, headers: {'content-type':'application/json; charset=utf-8'})));
  });
  testWidgets('戦力の怪我人選択で5列の表を表示し、不明な日付を推測しない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TeamStrengthBoard(org: OrgConfig.of(OrgKind.npb), year: 2026, initialView: 15, providedTeams: const []))));
      await tester.pumpAndSettle();
      expect(find.text('🤕怪我人'), findsWidgets);
      expect(find.byType(InjuriesBoard), findsOneWidget);
      for (final title in ['球団','選手名','怪我の内容','負傷時期','復帰時期']) { expect(find.text(title), findsOneWidget); }
      expect(find.text('対象選手'), findsOneWidget);
      expect(find.text('情報元を開く'), findsNothing);
      expect(find.textContaining('情報元の基準日'), findsNothing);
      expect(find.text('右肩痛'), findsOneWidget);
      expect(find.text('不明'), findsOneWidget);
      expect(find.text('全治4週間'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async {
      expect(request.url.path, '/injuries');
      expect(request.url.queryParameters['org'], 'npb');
      return http.Response(jsonEncode({'players':[{'id_player': 1,'name_player':'対象選手','name_team':'阪神','injury':'右肩痛','injured_at':'','return_at':'全治4週間','source_url':'https://example.com/article','source_as_of':'2026-10-01'}]}),200,headers:{'content-type':'application/json; charset=utf-8'});
    }));
  });
  testWidgets('取得失敗から再読み込みでき、空の一覧を表示する', (tester) async {
    var attempts = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: InjuriesBoard(org:'mlb'))));
      await tester.pumpAndSettle();
      expect(find.text('怪我人情報を取得できませんでした。'), findsOneWidget);
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('怪我人情報は登録されていません。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => ++attempts == 1 ? http.Response('',500) : http.Response('{"players":[]}',200)));
  });
}
