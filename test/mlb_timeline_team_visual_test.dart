import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:Yakyuu_Japan/config/org_config.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/records_board.dart';
import 'package:Yakyuu_Japan/logic/auth_session.dart';

void main() {
  final session = AuthSession.instance;
  tearDown(() { session.user = null; session.token = null; });
  testWidgets('MLB年表の1位から16位まで略称セルを使う', (tester) async {
    await tester.binding.setSurfaceSize(const Size(3200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payload = {'standings': [{'year': 2026, 'leagues': [
      {'id_league': 4, 'name': OrgConfig.mlb.leagues.last.name, 'teams': [
        for (var i=1; i<=16; i++) {'id_team': 100+i, 'name': 'Los Angeles Dodgers', 'short_name': 'Dodgers', 'name_shortest': 'LAD', 'rank': i},
      ]},
    ]}]};
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecordsBoard(org: OrgConfig.mlb, year: 2026))));
      await tester.pumpAndSettle();
      expect(find.byType(MlbTimelineTeamVisual), findsNWidgets(16));
      for (var i=1; i<=16; i++) {
        final cell=find.byKey(ValueKey('rank-team-2026-id:${100+i}'));
        expect(find.descendant(of:cell, matching:find.text('LAD')), findsOneWidget);
        expect(find.descendant(of:cell, matching:find.byType(Image)), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response(jsonEncode(payload), 200, headers: {'content-type':'application/json; charset=utf-8'})));
  });
  testWidgets('旧球団フラグと空のロゴURLでもID1・2は順位セルのMLBロゴを取得する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(3200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payload = {'standings': [{'year': 2026, 'leagues': [
      {'id_league': 4, 'name': OrgConfig.mlb.leagues.last.name, 'teams': [
        for (var rank = 1; rank <= 16; rank++)
        {'id_team': 118 + rank, 'name': 'Los Angeles Dodgers', 'short_name': 'Dodgers',
         'name_shortest': 'LAD', 'rank': rank, 'historical_identity': true, 'logo_url': null},
      ]},
    ]}]};
    session.token = 'test';
    session.user = AuthUser.fromJson({'id': 1, 'flg_special': false});
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecordsBoard(org: OrgConfig.mlb, year: 2026))));
      await tester.pumpAndSettle();
      for (final id in [1, 2, 3]) {
        session.user = AuthUser.fromJson({'id': id, 'flg_special': false});
        await tester.pumpAndSettle();
        final cell = find.byKey(const ValueKey('rank-team-2026-id:119'));
        final visuals = find.descendant(of: cell, matching: find.byType(MlbTimelineTeamVisual));
        expect(visuals, findsOneWidget);
        final visual = tester.widget<MlbTimelineTeamVisual>(visuals);
        expect(visual.logo, isA<Image>());
        final provider = (visual.logo! as Image).image as ResizeImage;
        expect((provider.imageProvider as NetworkImage).url, contains('/lad.png'));
        expect(find.descendant(of: cell, matching: find.byType(Image)), id <= 2 ? findsOneWidget : findsNothing);
      }
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response(jsonEncode(payload), 200,
      headers: {'content-type': 'application/json; charset=utf-8'})));
  });
  testWidgets('MLB年表はID1・2のみロゴ、それ以外とログアウト後は略称', (tester) async {
    final bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: [
      MlbTimelineTeamVisual(team: const {'name':'Los Angeles Dodgers','name_shortest':'Dodgers'},logo: Image.memory(bytes)),
      MlbTimelineTeamVisual(team: const {'name':'ヤンキース','name_shortest':'Yankees'},logo: Image.memory(bytes)),
    ]))));
    expect(find.text('LAD'), findsOneWidget);
    expect(find.text('NYY'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    session.token='test';
    for (final id in [1,2,3]) {
      session.user=AuthUser.fromJson({'id':id,'flg_special':id==3});
      await tester.pump();
      expect(find.byType(Image), id<=2 ? findsNWidgets(2) : findsNothing);
      expect(find.text('LAD'), id<=2 ? findsNothing : findsOneWidget);
    }
    session.user=AuthUser.fromJson({'id':1,'flg_special':false});
    await tester.pump();
    session.token=null;
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('LAD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
