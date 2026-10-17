import 'dart:convert';
import 'PlayerAchievements.dart';
import 'StrengthUsage.dart';

Future<Map<String, List<Map<String, dynamic>>>> achievementSupplement(int year, Future<String> Function(String) get, List<Map<String, dynamic>> roster) async {
  final result = <String, List<Map<String, dynamic>>>{};
  void add(String key, Map<String, dynamic> badge) => result.putIfAbsent(key, () => []).add(badge);
  // Published MLB qualified pools account for shortened seasons and exemptions.
  Future<void> season(int y) async {
    for (final group in ['hitting', 'pitching']) {
      final url = 'https://statsapi.mlb.com/api/v1/stats?stats=season&group=$group&season=$y&sportIds=1&playerPool=QUALIFIED&limit=5000';
      final data = usageMap(jsonDecode(await get(url)));
      for (final g in usageMaps(data['stats'])) {
        for (final p in usageMaps(g['splits'])) {
          add('mlb:${usageMap(p['player'])['id']}', achievement(group == 'hitting' ? 'MLB 規定打席到達' : 'MLB 規定投球回到達', y, url, kind: 'qualification'));
        }
      }
    }
  }

  for (var y = 2002; y <= year; y += 4) {
    await Future.wait([for (var n = y; n < y + 4 && n <= year; n++) season(n)]);
  }
  if (year >= 2023) {
    const schedule = 'https://statsapi.mlb.com/api/v1/schedule?sportId=51&teamId=843&season=2023';
    final games = [for (final d in usageMaps(usageMap(jsonDecode(await get(schedule)))['dates'])) ...usageMaps(d['games'])];
    final starts = <String, int>{}, pitchStarts = <String, int>{};
    for (final g in games) {
      final box = usageMap(jsonDecode(await get('https://statsapi.mlb.com/api/v1/game/${g['gamePk']}/boxscore')));
      for (final side in usageMap(box['teams']).values) {
        final team = usageMap(side);
        if (usageInt(usageMap(team['team'])['id']) != 843) continue;
        for (final p in usageMap(team['players']).values) {
          final v = usageMap(p), id = '${usageMap(v['person'])['id']}';
          if (v['battingOrder'] != null && '${v['battingOrder']}'.endsWith('00')) {
            starts[id] = (starts[id] ?? 0) + 1;
          }
          if (usageInt(usageMap(usageMap(v['stats'])['pitching'])['gamesStarted']) > 0) {
            pitchStarts[id] = (pitchStarts[id] ?? 0) + 1;
          }
        }
      }
    }
    final ids = {...starts.keys, ...pitchStarts.keys}.where((id) => (starts[id] ?? 0) >= 4 || (pitchStarts[id] ?? 0) >= 2).toList();
    final people = usageMaps(usageMap(jsonDecode(await get('https://statsapi.mlb.com/api/v1/people?personIds=${ids.join(',')}')))['people']);
    for (final p in people) {
      final badge = achievement('WBC優勝レギュラー', 2023, schedule, kind: 'championship', detail: '優勝した日本代表で4試合以上のスタメン、または2試合以上の先発登板。');
      add('mlb:${p['id']}', badge);
      final matching = roster.where((r) => '${r['player_key']}'.startsWith('npb:') && r['date_birth'] == p['birthDate']).toList();
      if (matching.length == 1) add('${matching.single['player_key']}', badge);
    }
  }
  // Individually verified records which cannot be inferred from current leaderboards.
  final verified = [
    ('mlb:660271', 2024, '日本出身選手MLB通算最多本塁打更新', 'https://www.mlb.com/player/shohei-ohtani-660271'),
    ('mlb:660271', 2024, 'MLB史上初 50-50', 'https://www.mlb.com/press-release/press-release-shohei-ohtani-becomes-first-50-50-player-in-mlb-history'),
    ('mlb:592450', 2022, 'ア・リーグ年間最多62本塁打', 'https://www.mlb.com/news/aaron-judge-breaks-roger-maris-home-run-record-with-62'),
  ];
  for (final r in verified) {
    if (r.$2 <= year) add(r.$1, achievement(r.$3, r.$2, r.$4, kind: 'record'));
  }
  final tob = roster.where((r) => usageName('${r['name']}') == '戸柱恭孝').toList();
  if (year >= 2024 && tob.length == 1) {
    add('${tob.single['player_key']}', achievement('CS MVP', 2024, 'https://sp.baystars.co.jp/news/2024/10/1021_12.php', kind: 'title'));
  }
  final miyanishi = roster.where((r) => usageName('${r['name']}') == '宮西尚生').toList();
  if (year >= 2018 && miyanishi.length == 1) {
    add('${miyanishi.single['player_key']}', achievement('NPB通算ホールド新記録（274）', 2018, 'https://npb.jp/news/detail/20180715_01.html', kind: 'record'));
  }
  return result;
}
