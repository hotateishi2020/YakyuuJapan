import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/roster_leadership.dart';
import 'package:Yakyuu_Japan/View/strength_grids.dart';

void main() {
  test('役職は年度と球団を一致させ、名前の空白と異体字を吸収する', () {
    expect(rosterLeadershipRoles({'name': '坂本 誠志郎'}, {'name_team': '阪神'}, 2026).single.label, 'キャプテン');
    expect(rosterLeadershipRoles({'name': '髙橋 宏斗'}, {'name_team': '中日'}, 2026).single.detail, '投手');
    expect(rosterLeadershipRoles({'name': '坂本誠志郎'}, {'name_team': '巨人'}, 2026), isEmpty);
    expect(rosterLeadershipRoles({'name': '坂本誠志郎'}, {'name_team': '阪神'}, 2025), isEmpty);
    expect(rosterLeadershipRoles({'name': 'ソト'}, {'name_team': 'メッツ'}, 2026), isEmpty);
    expect(rosterLeadershipRoles({'name': 'ネフタリ・ソト'}, {'name_team': 'ロッテ'}, 2026).single.label, 'キャプテン');
  });

  testWidgets('狭い選手一覧にキャプテンと選手会長を表示し、年度変更で外す', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final team = {
      'name_team': '阪神',
      'id_team': 2,
      'roster': [
        for (final name in ['坂本誠志郎', '村上頌樹'])
          {'name': name, 'player_key': name, 'position_group': '捕手', 'bats': '右', 'level_appearances': {'1': 10}}
      ],
    };
    Widget grid(int year) => MaterialApp(home: Scaffold(body: StrengthRosterGrid(year: year, team: team)));
    await tester.pumpWidget(grid(2026));
    expect(find.text('キャプテン'), findsOneWidget);
    expect(find.text('選手会長'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(grid(2025));
    expect(find.text('キャプテン'), findsNothing);
    expect(find.text('選手会長'), findsNothing);
  });
}
