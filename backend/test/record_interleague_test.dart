import 'package:test/test.dart';
import '../app/RecordInterleague.dart';

void main() {
  test('公式表の同率順・球団表記の違いを保って順位を付与する', () {
    final season = <String, dynamic>{'year': 2025, 'leagues': [{'teams': <Map<String, dynamic>>[
      {'name': '巨人'}, {'name': '横浜'}, {'name': 'オリックス'}, {'name': '未知の球団'},
    ]}]};
    attachInterleagueRanks(season, {'source': 'official', 'standings': [
      {'name': '読　　売ジャイアンツ', 'rank': 11},
      {'name': '横浜DeNAベイスターズ', 'rank': 10},
      {'name': 'オリックス・バファローズ', 'rank': 3},
    ]});
    final teams = (season['leagues'] as List).first['teams'] as List;
    expect(teams.map((p) => p['interleague_rank']), [11, 10, 3, null]);
    expect(teams.first['interleague_source'], 'official');
  });
  test('開催前・中止・未取得年度の順位を補完しない', () {
    for (final year in [2004, 2020, 2026]) {
      final team = <String, dynamic>{'name': '阪神'};
      final season = <String, dynamic>{'year': year, 'leagues': [{'teams': [team]}]};
      attachInterleagueRanks(season, year == 2026 ? {} : {'standings': [{'name': '阪神', 'rank': 1}]});
      expect(team.containsKey('interleague_rank'), isFalse);
    }
  });
}
