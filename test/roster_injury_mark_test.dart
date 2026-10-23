import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/display_settings.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';
void main() {
  testWidgets('負傷者カードだけに設定に連動したマークを表示する', (tester) async {
    final settings = DisplaySettings.instance;
    final old = settings.shows('flg_injury');
    addTearDown(() => settings.setShown('flg_injury', old));
    settings.setShown('flg_injury', true);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StrengthRosterGrid(year:2026, team:{
      'id_team':1, 'roster':[
        {'name':'負傷選手','player_key':'injured','position':'捕手','bats':'右','flg_injury':true},
        {'name':'健康選手','player_key':'healthy','position':'捕手','bats':'右','flg_injury':false},
      ],
    }))));
    expect(find.textContaining('🤕'), findsOneWidget);
    expect(find.descendant(of:find.byKey(const ValueKey('roster-card-injured')), matching:find.textContaining('🤕')),findsOneWidget);
    expect(find.descendant(of:find.byKey(const ValueKey('roster-card-healthy')), matching:find.textContaining('🤕')),findsNothing);
    settings.setShown('flg_injury', false);
    await tester.pump();
    expect(find.textContaining('🤕'), findsNothing);
    expect(find.byKey(const ValueKey('roster-card-injured')),findsOneWidget);
    settings.setShown('flg_injury', true);
    await tester.pump();
    expect(find.textContaining('🤕'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
