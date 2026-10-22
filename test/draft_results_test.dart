import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/View/strength_research.dart';

void main() {
  test('2026年の公式指名127人が両タブで一致する', () {
    final history = jsonDecode(File('backend/assets/data/draft_history.json').readAsStringSync());
    final draft = jsonDecode(File('backend/assets/data/draft_2026.json').readAsStringSync());
    final picks = history['years']['2026']['picks'] as List;
    final players = (draft['players'] as List).cast<Map<String, dynamic>>();
    expect(draft['results_complete'], true);
    expect(picks.where((p) => p['type'] != '育成'), hasLength(76));
    expect(picks.where((p) => p['type'] == '育成'), hasLength(51));
    expect(picks.map((p) => p['team']).toSet(), hasLength(12));
    expect(players.where((p) => p['draft_result'] != null), hasLength(127));
    String normalize(String name) => name.replaceAll(RegExp(r'\s'), '').replaceAll('髙', '高').replaceAll('﨑', '崎');
    for (final pick in picks) {
      final result = players.singleWhere((p) {
        final r = p['draft_result'];
        return r != null && r['team'] == pick['team'] && r['rank'] == pick['rank'] &&
            r['type'] == (pick['type'] == '育成' ? '育成' : '支配下');
      });
      expect(normalize(result['name']), normalize(pick['name']));
      expect(draftResultLabel(result), contains('${pick['rank']}位'));
    }
    expect(draftResultLabel(players.singleWhere((p) => p['name'] == '織田翔希')), '巨人 1位');
    expect(draftResultLabel({'name': '未指名選手'}), '指名なし');
    expect(draftResultLabel({'draft_result': {'team': '楽天', 'type': '育成', 'rank': '1'}}), '楽天 育成1位');
  });
}
