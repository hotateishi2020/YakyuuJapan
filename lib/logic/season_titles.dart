import '../tools/json_utils.dart';
import 'record_awards.dart';

const seasonTitleSections = <String, String>{
  'series_mvp': '日本シリーズMVP',
  'series_fighting': '日本シリーズ敢闘選手賞',
  'series_outstanding': '日本シリーズ優秀選手賞',
  'series_champion': '日本シリーズ優勝チーム',
  'cs_mvp': 'CS MVP',
  'series_entrants': '日本シリーズ進出チーム',
  'league_champion': 'リーグ優勝チーム',
  'sawamura': '沢村賞',
  'nagashima': '長嶋茂雄賞',
  'shoriki': '正力松太郎賞',
  'manager': '最優秀監督賞',
  'shoriki_special': '正力松太郎賞 特別賞',
  'league_merit': '連盟特別表彰（功労賞）',
  'league_special': '連盟特別表彰（特別賞）',
  'commissioner_special': 'コミッショナー特別表彰',
  'speedup': 'スピードアップ賞',
  'hikeshi': 'HIKESHI賞',
  'league_mvp': 'リーグMVP',
  'rookie': '新人王',
  'best9': 'ベストナイン',
  'glove': 'ゴールデングラブ',
  'records': 'シーズン記録更新',
  'major': '個人タイトル（メジャー指標）',
  'minor': '個人タイトル（マイナー指標）',
  'allstar_mvp': 'オールスターMVP',
  'derby': 'ホームランダービー優勝',
  'allstar_roster': 'オールスター選出',
  'fresh_mvp': 'フレッシュオールスターMVP',
  'fresh_roster': 'フレッシュオールスター選出',
  'interleague_champion': '交流戦優勝チーム',
  'interleague_mvp': '交流戦MVP',
  'monthly': '月間MVP',
  'weekly': 'SportsNavi 週間MVP',
};

Map<String, List<Map<String, dynamic>>> buildSeasonTitles(
    Map<String, dynamic> data, int year) {
  final result = {
    for (final key in seasonTitleSections.keys) key: <Map<String, dynamic>>[]
  };
  void add(String key, Map<String, dynamic> row) {
    final rows = result.putIfAbsent(key, () => []);
    // CS winners can arrive from both the series page and supplemental data.
    // Their identity is the team, not the source's detail or redundant team field.
    if (key == 'series_entrants') {
      String teamIdentity(Map<String, dynamic> value) => recordShortestTeam(
          {'team': value['name'] ?? value['team'] ?? ''}, preferCanonical: true)
          .replaceAll(RegExp(r'[\s　]'), '').toLowerCase();
      final team = teamIdentity(row);
      if (team.isNotEmpty && rows.any((p) => teamIdentity(p) == team)) return;
    }
    final identity =
        '${row['detail'] ?? ''}:${row['name']}:${row['team'] ?? ''}'
            .replaceAll(RegExp(r'[\s　]'), '');
    if (!rows.any((p) =>
        '${p['detail'] ?? ''}:${p['name']}:${p['team'] ?? ''}'
            .replaceAll(RegExp(r'[\s　]'), '') ==
        identity)) {
      rows.add(row);
    }
  }

  final source = Map<String, dynamic>.from(data['season_awards'] as Map? ?? {});
  for (final page in (source['pages'] as Map? ?? {}).values) {
    for (final row in listMapFromJson(page)) {
      add('${row['key']}', row);
    }
  }
  final supplement = listMapFromJson(data['season_award_supplement']);
  for (final key in supplement.where((r) => r['override'] == true).map((r) => '${r['key']}').toSet()) {
    result[key] = [];
  }
  for (final row in supplement) {
    add('${row['key']}', row);
  }
  final officialRows = {
    for (final e in result.entries) e.key: [...e.value]
  };
  final officialKeys =
      result.entries.where((e) => e.value.isNotEmpty).map((e) => e.key).toSet();
  for (final season in listMapFromJson(data['titles'])
      .where((s) => '${s['year']}' == '$year')) {
    for (final category
        in normalizeRecordAwards(listMapFromJson(season['categories']))) {
      final label = '${category['label']}';
      final key = label == 'リーグMVP'
          ? 'league_mvp'
          : label == '新人王'
              ? 'rookie'
              : label.startsWith('ベスト')
                  ? 'best9'
                  : 'major';
      // The official year's pages override statistical leaders (which are not awards).
      if (key == 'major' &&
          !const [
            '首位打者',
            '最多安打',
            '本塁打王',
            '打点王',
            '盗塁王',
            '最高出塁率',
            '最優秀防御率',
            '最多勝利',
            '最多奪三振',
            '最優秀中継ぎ',
            '最多セーブ',
            '最高勝率',
            'サイ・ヤング賞'
          ].contains(label)) { continue; }
      if (officialRows[key]!
          .any((row) => '${row['detail']}'.startsWith('${season['league']} '))) {
        continue;
      }
      for (final player in listMapFromJson(category['players'])) {
        add(key, {
          ...player,
          'detail': '${season['league']} $label',
          'confirmed': season['provisional'] != true
        });
      }
    }
  }
  for (final row in listMapFromJson(data['minor_title_leaders'])) {
    add('minor', {
      ...row,
      'detail': '${row['league']} ${row['title']}',
      'confirmed': false,
      'statistical': true
    });
  }
  final standings = listMapFromJson(data['standings'])
      .where((s) => '${s['year']}' == '$year')
      .firstOrNull;
  if (standings != null) {
    final inter = Map<String, dynamic>.from(
        standings['interleague_champion'] as Map? ?? {});
    if (inter.isNotEmpty && !officialKeys.contains('interleague_champion')) {
      add('interleague_champion', {...inter, 'confirmed': true});
    }
    for (final league in listMapFromJson(standings['leagues'])) {
      for (final team in listMapFromJson(league['teams'])) {
        if (team['champion'] == true &&
            !officialKeys.contains('series_champion')) {
          add('series_champion', {...team, 'confirmed': true});
        }
        // A live first-place team is not necessarily the pennant winner.
        if (team['league_champion'] == true &&
            year < DateTime.now().year &&
            !officialKeys.contains('league_champion')) {
          add('league_champion',
              {...team, 'detail': league['name'], 'confirmed': true});
        }
      }
    }
  }
  for (final record in listMapFromJson(data['season'])) {
    for (final player in listMapFromJson(record['leaders'])
        .where((p) => '${p['year']}' == '$year')) {
      add('records', {
        ...player,
        'detail': record['label'],
        'unit': record['unit'],
        'confirmed': true
      });
    }
    final leaders = listMapFromJson(record['leaders']);
    final historical =
        leaders.isEmpty ? null : num.tryParse('${leaders.first['value']}');
    if (historical == null) continue;
    for (final player in listMapFromJson(record['current'])) {
      final value = num.tryParse('${player['value']}');
      if (value != null &&
          (record['key'] == 'era' ? value < historical : value > historical)) {
        // Rate records require an officially completed season, not mid-season pace.
        if (['avg', 'era', 'obp', 'slg'].contains(record['key']) &&
            year >= DateTime.now().year) {
          continue;
        }
        add('records', {
          ...player,
          'detail': '${record['label']}（歴代最高を更新）',
          'confirmed': true
        });
      }
    }
  }
  // Award source pages often omit styling; use the team's identity for that
  // season rather than today's team (players may since have transferred).
  final teams = [
    for (final season in listMapFromJson(data['standings']))
      if ('${season['year']}' == '$year')
        for (final league in listMapFromJson(season['leagues']))
          ...listMapFromJson(league['teams']),
  ];
  for (final rows in result.values) {
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if ('${row['team'] ?? ''}'.isEmpty) continue;
      final matches = teams.where((team) =>
          row['id_team'] != null && team['id_team'] != null
              ? '${row['id_team']}' == '${team['id_team']}'
              : recordShortestTeam(row) ==
                  recordShortestTeam({'team': team['name'] ?? team['short_name']}));
      if (matches.length != 1) continue;
      final team = matches.single;
      rows[i] = {
        ...row,
        for (final field in ['color_back', 'color_font', 'name_shortest'])
          if ('${row[field] ?? ''}'.trim().isEmpty && team[field] != null) field: team[field],
      };
    }
  }
  return result;
}
