import 'package:postgres/postgres.dart';
import 'AppSql.dart';
import 'JapaneseMlbContracts.dart';

Future<Map<String, dynamic>> readJapaneseMlbStats(
    Connection conn, int year) async {
  final careers = await conn.execute('''
    SELECT DISTINCT ON(c.id_player,c.id_team) c.*, p.name_full AS name_player,
      t.name_short AS name_team, t.color_back, t.color_font, t.id_league,
      p.name_last, p.name_first, p.date_birth::text, p.url, p.txt_position, st.int_game
    FROM m_player_career c JOIN m_player p ON p.id=c.id_player
    JOIN m_country country ON country.id=p.id_country
    JOIN m_team t ON t.id=c.id_team
    LEFT JOIN t_stats_team st ON st.id_team=t.id AND st.year=c.int_year
    WHERE c.int_year=\$1 AND t.id_league IN (3,4) AND (country.name='日本' OR p.url LIKE '%/mlb/player/2102188/%')
      AND NOT COALESCE(c.flg_delete,false) AND NOT COALESCE(p.flg_delete,false)
    ORDER BY c.id_player,c.id_team,c.updat DESC NULLS LAST,c.id DESC
  ''', parameters: [year]);
  final inactive = await conn.execute('''
    SELECT p.id AS id_player,p.name_full AS name_player,p.date_birth::text,
      p.url,p.txt_position,p.id_team,t.name_short AS name_team,t.color_back,t.color_font
    FROM m_player p JOIN m_team t ON t.id=p.id_team
    WHERE p.url LIKE '%/mlb/player/2100954/%' AND t.id_league IN (3,4)
      AND NOT COALESCE(p.flg_delete,false)
      AND \$1 = EXTRACT(YEAR FROM CURRENT_DATE)::int
  ''', parameters: [year]);
  final stats =
      await conn.execute(AppSql.selectStatsPlayer(), parameters: [year]);
  final ids = {
    ...careers.map((r) => r.toColumnMap()['id_player']),
    ...stats.map((r) => r.toColumnMap()['id_player'])
  }.whereType<int>().toList();
  final identities = await conn.execute(
      "SELECT id AS id_player,name_full,name_last,name_first,date_birth::text,url,id_team,txt_position FROM m_player WHERE id=ANY(\$1::int[])",
      parameters: [ids]);
  final byId = {
    for (final r in identities)
      '${r.toColumnMap()['id_player']}': r.toColumnMap()
  };
  final teamRows = await conn.execute('''
    SELECT DISTINCT ON(t.id) t.id AS id_team,
      COALESCE(st.id_league,t.id_league) AS id_league,
      COALESCE(NULLIF(st.code_area,''),t.code_area,'') AS code_area
    FROM m_team t LEFT JOIN t_stats_team st ON st.id_team=t.id AND st.year=\$1
    WHERE t.id_league IN (3,4)
    ORDER BY t.id,st.crtat DESC NULLS LAST
  ''', parameters: [year]);
  final teamsById = {for (final r in teamRows) '${r.toColumnMap()['id_team']}': r.toColumnMap()};
  Map<String, dynamic> withTeam(Map<String, dynamic> row) => {
    ...row, ...?teamsById['${row['id_team']}'],
  };
  final result = buildJapaneseMlbStats(
      [...careers.map((r) => withTeam(r.toColumnMap())), ...inactive.map((r) => withTeam(r.toColumnMap()))],
      stats.map((r) {
        final row = withTeam(r.toColumnMap());
        return {...?byId['${row['id_player']}'], ...row,
          'name_player': byId['${row['id_player']}']?['name_full'] ?? row['name_player']};
      }).toList(),
      year);
  await attachJapaneseMlbContracts(conn, (result['players'] as List).cast<Map<String, dynamic>>(), year);
  return result;
}

Map<String, dynamic> buildJapaneseMlbStats(List<Map<String, dynamic>> careers,
    List<Map<String, dynamic>> stats, int year) {
  final normalized = canonicalJapaneseRows(careers, stats);
  careers = normalized.$1;
  stats = normalized.$2;
  bool yes(Object? v) => v == true || v == 1 || v == 'true';
  num number(Object? v) => num.tryParse('$v') ?? 0;
  final result = <String, Map<String, dynamic>>{};
  void put(
      Map<String, dynamic> row, bool pitching, String title, Object? value) {
    final key = '${row['id_player']}:$pitching';
    final player = result.putIfAbsent(
        key,
        () => {
              'id_player': row['id_player'],
              'name_player': row['name_player'],
              'date_birth': row['date_birth'],
              'name_team': row['name_team'],
              'id_team': row['id_team'],
              'team_ids': row['team_ids'] ?? [row['id_team']],
              'id_league': row['id_league'],
              'code_area': row['code_area'],
              'name_league': row['name_league'] ?? japaneseMlbLeagueName(row['id_league']),
              'name_area': row['name_area'] ?? japaneseMlbAreaName(row['code_area']),
              'color_back': row['color_back'],
              'color_font': row['color_font'],
              'pitching': pitching,
              'stats': <String, dynamic>{},
            });
    player['date_birth'] ??= row['date_birth'];
    (player['stats'] as Map<String, dynamic>)[title] = value;
  }

  // These fields are populated by the existing Japanese-player career importer.
  // Do not treat unimported career columns (default zero) as measured results.
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final row in careers) {
    grouped.putIfAbsent('${row['id_player']}', () => []).add(row);
  }
  for (final teams in grouped.values) {
    teams.sort(compareJapaneseMlbTeams);
    final arizona = teams.where((r) =>
        '${r['url']}'.contains('/mlb/player/2102188/') &&
        '${r['name_team']}'.contains('ダイヤモンドバックス')).firstOrNull;
    // Keep season totals across clubs; show Nootbaar's Arizona affiliation only.
    final displayTeams = arizona == null ? teams : [arizona];
    final row = {
      ...displayTeams.first,
      'team_ids': teams.map((r) => r['id_team']).toSet().toList(),
      'name_team': displayTeams.map((r) => r['name_team']).toSet().join(' / '),
      'name_league': displayTeams.map((r) => japaneseMlbLeagueName(r['id_league'])).toSet().join(' / '),
      'name_area': displayTeams.map((r) => japaneseMlbAreaName(r['code_area'])).toSet().join(' / ')
    };
    num sum(String field) => teams.fold<num>(0, (n, r) => n + number(r[field]));
    if ('${row['url']}'.contains('/mlb/player/2100954/') && sum('int_pitching') == 0) {
      put(row, true, '登板', null);
    }
    if (sum('int_appearance') > 0 || sum('int_batting') > 0) {
      put(row, false, '打席', sum('int_appearance'));
      put(row, false, '打数', sum('int_batting'));
      // A multi-team average cannot be obtained by averaging rounded averages.
      if (teams.length == 1) {
        put(row, false, '打率',
            number(row['double_average_batting']).toStringAsFixed(3));
      }
    }
    if (sum('int_pitching') > 0) {
      for (final entry in {
        '登板': 'int_pitching',
        '勝利': 'int_win',
        '敗戦': 'int_lose',
        '奪三振': 'int_strike_out_pitcher'
      }.entries) {
        put(row, true, entry.key, sum(entry.value));
      }
      final outs = teams.fold<int>(0, (n, r) {
        final innings = number(r['double_inning']);
        return n +
            innings.floor() * 3 +
            ((innings - innings.floor()) * 10).round();
      });
      put(row, true, '投球回', '${outs ~/ 3}.${outs % 3}');
      if (teams.length == 1) {
        put(row, true, '防御率',
            number(row['double_average_earned_runs']).toStringAsFixed(2));
      }
    }
  }
  const aliases = {
    '最多勝': '勝利',
    '最多安打': '安打',
    '打席数': '打席',
    '登板回数': '登板',
    '投球回数': '投球回'
  };
  for (final row in stats) {
    if ((!yes(row['flg_japan']) && !'${row['url']}'.contains('/mlb/player/2102188/')) || ![3, 4].contains(number(row['id_league']))) {
      continue;
    }
    final title = '${row['title']}';
    if (title == '打率' && (number(row['stats']) < 0 || number(row['stats']) > 1)) continue;
    put(row, yes(row['flg_pitcher']), aliases[title] ?? title, row['stats']);
    if (!yes(row['flg_pitcher']) && {'打率', '本塁打', '打点', '最多安打', '出塁率', 'OPS'}.contains(title) && number(row['cnt_play']) > 0) {
      put(row, false, '打席', number(row['cnt_play']));
    }
  }
  // Keep genuine two-way hitters; suppress occasional pitcher batting lines.
  final battingOnly = <String>{
    for (final entry in grouped.entries)
      if (entry.value.any((r) => number(r['int_batting']) > 0) && !entry.value.any((r) => number(r['int_pitching']) > 0)) entry.key,
  };
  final pitchers = <String>{
    for (final row in [...careers, ...stats])
      if (!battingOnly.contains('${row['id_player']}') && ('${row['txt_position']}'.contains('投手') || number(row['int_pitching']) > 0)) '${row['id_player']}',
  };
  result.removeWhere((key, player) {
    if (player['pitching'] == true) {
      // Some rankings include zero-valued pitching records for batters.
      // A batting-only season must not create a pitcher row from those records.
      return battingOnly.contains('${player['id_player']}');
    }
    if (!pitchers.contains('${player['id_player']}')) return false;
    final fields = player['stats'] as Map;
    var appearances = number(fields['打席']);
    final atBats = number(fields['打数']);
    if (atBats > appearances) appearances = atBats;
    for (final row in stats.where((r) => '${r['id_player']}' == '${player['id_player']}' && !yes(r['flg_pitcher']))) {
      if (number(row['cnt_play']) > appearances) appearances = number(row['cnt_play']);
    }
    return appearances < 100;
  });
  for (final player in result.values) {
    final rows = [...careers, ...stats].where((r) => '${r['id_player']}' == '${player['id_player']}');
    final games = rows.fold<num>(0, (n, r) => number(r['int_game']) > n ? number(r['int_game']) : n);
    final fields = player['stats'] as Map<String, dynamic>;
    final pitching = player['pitching'] == true;
    final raw = num.tryParse('${fields[pitching ? '投球回' : '打席']}');
    if (games > 0 && raw != null) {
      final amount = pitching ? raw.floor() + ((raw - raw.floor()) * 10).round() / 3 : raw;
      final rate = amount / (games * (pitching ? 1 : 3.1)) * 100;
      fields['規定到達率'] = (rate < 0 ? 0 : rate).toStringAsFixed(1);
    }
  }
  final players = result.values.toList()
    ..sort((a, b) {
      final teamOrder = compareJapaneseMlbTeams(a, b);
      if (teamOrder != 0) return teamOrder;
      final ad = DateTime.tryParse('${a['date_birth']}');
      final bd = DateTime.tryParse('${b['date_birth']}');
      if (ad == null && bd != null) return 1;
      if (ad != null && bd == null) return -1;
      final ageOrder = ad != null && bd != null ? ad.compareTo(bd) : 0;
      return ageOrder != 0 ? ageOrder : '${a['name_player']}'.compareTo('${b['name_player']}');
    });
  return {'year': year, 'players': players};
}

String japaneseMlbLeagueName(Object? id) =>
    const {3: 'ア・リーグ', 4: 'ナ・リーグ'}[int.tryParse('$id')] ?? 'ー';

String japaneseMlbAreaName(Object? code) =>
    const {'EAST': '東地区', 'CENTER': '中地区', 'WEST': '西地区'}['$code'.trim().toUpperCase()] ?? 'ー';

int compareJapaneseMlbTeams(Map<String, dynamic> a, Map<String, dynamic> b) {
  final league = (int.tryParse('${a['id_league']}') ?? 99)
      .compareTo(int.tryParse('${b['id_league']}') ?? 99);
  if (league != 0) return league;
  int area(Map<String, dynamic> r) => const {'EAST': 0, 'CENTER': 1, 'WEST': 2}['${r['code_area']}'.trim().toUpperCase()] ?? 3;
  final division = area(a).compareTo(area(b));
  if (division != 0) return division;
  return '${a['name_team'] ?? ''}'.compareTo('${b['name_team'] ?? ''}');
}

/// Merge abbreviated duplicate master records only when identity is unambiguous.
(List<Map<String, dynamic>>, List<Map<String, dynamic>>) canonicalJapaneseRows(
    List<Map<String, dynamic>> careers, List<Map<String, dynamic>> stats) {
  String clean(dynamic v) =>
      '${v ?? ''}'.replaceAll(RegExp(r'\([^)]*\)|[\s　]'), '');
  String full(Map<String, dynamic> r) =>
      clean(r['name_full'] ?? r['name_player']);
  String family(Map<String, dynamic> r) => clean(r['name_last']).isNotEmpty
      ? clean(r['name_last'])
      : '${r['name_player'] ?? ''}'.trim().split(RegExp(r'[\s　]+')).first;
  bool sameTeam(Map<String, dynamic> a, Map<String, dynamic> b) =>
      a['id_team'] != null && b['id_team'] != null
          ? '${a['id_team']}' == '${b['id_team']}'
          : clean(a['name_team']).isNotEmpty &&
              clean(a['name_team']) == clean(b['name_team']);
  final people = <String, Map<String, dynamic>>{};
  for (final r in [...careers, ...stats]) {
    final key = '${r['id_player']}';
    if (!people.containsKey(key) || full(r).length > full(people[key]!).length) {
      people[key] = r;
    }
  }
  final aliases = <String, Map<String, dynamic>>{};
  for (final entry in people.entries) {
    final r = entry.value, name = full(entry.value);
    final matches = people.values.where((other) {
      if (other['id_player'] == r['id_player'] || !sameTeam(r, other)) {
        return false;
      }
      final birth = clean(r['date_birth']),
          otherBirth = clean(other['date_birth']);
      if (birth.isNotEmpty && otherBirth.isNotEmpty && birth != otherBirth) {
        return false;
      }
      final otherName = full(other);
      if (clean(r['url']).isNotEmpty && r['url'] == other['url'] && otherName.length > name.length) return true;
      final malformedFamily = clean(other['name_first']).isEmpty &&
          clean(other['name_last']) == otherName;
      final compactName = RegExp(r'^[一-龯々]{2,3}$').hasMatch(name);
      return otherName.length > name.length &&
          (name == family(other) ||
              (malformedFamily && compactName && otherName.startsWith(name)));
    }).toList();
    if (matches.length == 1) aliases[entry.key] = matches.single;
  }
  Map<String, dynamic> canonical(Map<String, dynamic> r) {
    final match = aliases['${r['id_player']}'];
    return match == null
        ? r
        : {
            ...r,
            'id_player': match['id_player'],
            'date_birth': match['date_birth'] ?? r['date_birth'],
            'name_player': match['name_full'] ?? match['name_player']
          };
  }

  final uniqueCareers = <String, Map<String, dynamic>>{};
  // Prefer the full-name record when both imports contain the same club totals.
  final sorted = [...careers]..sort((a, b) =>
      (aliases.containsKey('${a['id_player']}') ? 1 : 0)
          .compareTo(aliases.containsKey('${b['id_player']}') ? 1 : 0));
  for (final r in sorted) {
    final row = canonical(r);
    uniqueCareers.putIfAbsent(
        '${row['id_player']}:${row['id_team'] ?? row['name_team']}', () => row);
  }
  final uniqueStats = <String, Map<String, dynamic>>{};
  int rank(Map<String, dynamic> r) => int.tryParse('${r['int_rank']}') ?? 1000;
  num appearances(Map<String, dynamic> r) => num.tryParse('${r['cnt_play']}') ?? 0;
  bool ranked(Map<String, dynamic> r) => rank(r) > 0 && rank(r) < 1000;
  for (final source in stats) {
    final row = canonical(source);
    final key = '${row['id_player']}:${row['id_team']}:${row['id_league']}:'
        '${row['id_stats'] ?? row['title']}:${row['flg_pitcher']}';
    final previous = uniqueStats[key];
    // A supplemental profile for an abbreviated identity must not overwrite
    // the official ranking (e.g. Ohtani's stale 0 HR / 14 PA vs 30 HR / 618 PA).
    if (previous == null ||
        ranked(row) && !ranked(previous) ||
        ranked(row) == ranked(previous) && appearances(row) > appearances(previous)) {
      uniqueStats[key] = row;
    }
  }
  return (uniqueCareers.values.toList(), uniqueStats.values.toList());
}
