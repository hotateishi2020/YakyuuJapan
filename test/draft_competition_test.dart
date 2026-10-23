import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Yakyuu_Japan/logic/draft_competition.dart';

void main() {
  test('1位の単独・競合・再入札を区別する', () {
    Map pick(String note, {int? competition}) => {'rank': '1', 'type': '支配下', 'note': note, 'competition': competition};
    expect(draftNominationLabels(pick('')), ['単独指名']);
    expect(draftNominationLabels(pick('○3', competition: 3)), ['3球団競合']);
    expect(draftNominationLabels(pick('甲×')), ['ハズレ1位']);
    expect(draftNominationLabels(pick('甲×・○2', competition: 2)), ['2球団競合', 'ハズレ1位']);
    expect(draftNominationLabels(pick('甲×・乙×')), ['ハズレハズレ1位']);
    expect(draftNominationLabels({...pick(''), 'rank': '2'}), isEmpty);
    expect(draftNominationLabels({...pick(''), 'type': '育成'}), isEmpty);
    expect(draftNominationLabels({'rank': '1'}), isEmpty);
  });

  final years = jsonDecode(File('backend/assets/data/draft_history.json').readAsStringSync())['years'] as Map;
  test('2026年は初回と再入札の3抽選・ロッテの2回落選を保持する', () {
    final picks = draftPicksWithCompetition((years['2026']['picks'] as List).cast<Map>());
    for (final entry in {
      '渡部 海': ['楽天', '中日'],
      '鈴木 泰成': ['ソフトバンク', 'ロッテ'],
      '宮原 廉': ['中日', 'ロッテ'],
    }.entries) {
      final pick = picks.singleWhere((p) => p['name'] == entry.key);
      expect(pick['competition'], 2);
      expect(pick['competition_teams'], entry.value);
    }
    expect(picks.where((p) => p['competition'] != null), hasLength(3));
    expect(picks.singleWhere((p) => p['name'] == '宮原 廉')['note'], '渡部海×・○2');
    final yonezawa = picks.singleWhere((p) => p['name'] == '米沢 友翔');
    expect(yonezawa['note'], '鈴木泰成×・宮原廉×');
    expect(yonezawa['competition'], isNull);
    expect(yonezawa['competition_teams'], isEmpty);
    final published = jsonDecode(File('backend/public/assets/backend/assets/data/draft_history.json').readAsStringSync());
    expect(published['years']['2026'], years['2026']);
  });
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
