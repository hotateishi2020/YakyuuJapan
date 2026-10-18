import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/draft_competition.dart';

void main() {
  final years = jsonDecode(File('backend/assets/data/draft_history.json').readAsStringSync())['years'] as Map;
  test('競合の当選・落選球団を同じ選手へ対応付ける', () {
    final picks = draftPicksWithCompetition((years['2025']['picks'] as List).cast<Map>());
    expect(picks.singleWhere((p) => p['name'] == '立石 正広')['competition_teams'], ['阪神', '広島', '日本ハム']);
    expect(picks.singleWhere((p) => p['name'] == '石垣 元気')['competition_teams'], ['ロッテ', 'オリックス']);
    expect(picks.singleWhere((p) => p['name'] == '平川 蓮')['competition_teams'], ['広島', '日本ハム']);
  });
  test('再抽選・異体字を照合し別の指名区分は混ぜない', () {
    final picks = draftPicksWithCompetition((years['2007']['picks'] as List).cast<Map>());
    expect(picks.singleWhere((p) => p['name'] == '髙濱 卓也')['competition_teams'], ['阪神', '横浜']);
    final split = draftPicksWithCompetition([
      {'name': '選手', 'team': 'A', 'type': '1', 'competition': 2},
      {'name': '別選手', 'team': 'B', 'type': '2', 'note': '選手×'},
    ]);
    expect(split.first['competition_teams'], isEmpty);
    expect(split.first['competition'], 2);
  });
}
