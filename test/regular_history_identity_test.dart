import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/strength_usage.dart';
import 'package:Yakyuu_Japan/logic/strength_analytics.dart';
import 'package:Yakyuu_Japan/tools/json_utils.dart';

void main() {
  final rows = listMapFromJson(
      jsonDecode(File('backend/data/regular-history.json').readAsStringSync())['rows']);

  test('全540球団年度の投手を補完し実際に左先発がいない3年度だけ除外する', () {
    expect(rows.length, 540);
    const noLeftStarter = {'1996:日本ハム', '1981:ソフトバンク', '1981:広島'};
    for (final row in rows) {
      final key = '${row['year']}:${row['club_name']}';
      expect(row['archive_stat_sources'], isNotEmpty, reason: key);
      final selected = selectPitcherAces(row);
      for (final slot in pitcherAceSlots.keys) {
        if (slot == 'SP_L' && noLeftStarter.contains(key)) {
          expect(selected[slot], isNull, reason: key);
          continue;
        }
        expect(selected[slot], isNotEmpty, reason: '$key $slot');
      }
    }
  });

  test('兼任投手の内訳未確認でも確認済み先発登板数でエースを表示する', () {
    final row = rows.singleWhere((r) => r['year'] == 2021 && r['club_name'] == 'ソフトバンク');
    final pitcher = selectPitcherAces(row)['SP_R']!.single;
    expect(pitcher['name'], '石川柊太');
    expect(pitcher['ace_basis'], 'starts');
    expect(pitcher['starts'], 25);
    expect(pitcher['starter_outs'], isNull);
  });

  test('全年度の守備レギュラーは現年度と同じ選出処理で選手を重複させない', () {
    for (final row in rows) {
      final selected = selectRegularGroups(listMapFromJson(row['positions']));
      final keys = selected.values.expand((p) => p).map(usagePlayerKey).toList();
      expect(keys.toSet(), hasLength(keys.length),
          reason: '${row['year']} ${row['club_name']}');
    }
  });

  test('松田宣・内川の略称を統合し、過去年にも公式成績とエースが表示できる', () {
    final hawks = rows.singleWhere(
        (r) => r['year'] == 2019 && r['club_name'] == 'ソフトバンク');
    final selected = selectRegularGroups(listMapFromJson(hawks['positions']));
    expect(selected['3B']!.single['name'], '松田宣浩');
    expect(selected['3B']!.single['count'], 143);
    expect(selected['1B']!.first['name'], '内川聖一');
    expect(strengthPlayerMetrics(hawks, selected['1B']!.first)['ops'], isNotNull);
    final recent = rows.singleWhere(
        (r) => r['year'] == 2025 && r['club_name'] == 'ソフトバンク');
    final aces = selectPitcherAces(recent);
    expect(aces['SP_L']!.single['name'], 'モイネロ');
    expect(aces['SP_R']!.single['name'], '有原航平');
    expect(aces['CL'], isNotEmpty);
  });
}
