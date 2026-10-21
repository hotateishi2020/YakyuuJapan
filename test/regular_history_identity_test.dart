import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/strength_usage.dart';
import 'package:Yakyuu_Japan/logic/strength_analytics.dart';
import 'package:Yakyuu_Japan/tools/json_utils.dart';

void main() {
  final rows = listMapFromJson(
      jsonDecode(File('backend/data/regular-history.json').readAsStringSync())['rows']);

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
