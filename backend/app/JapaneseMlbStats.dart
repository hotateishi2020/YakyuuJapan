import 'package:postgres/postgres.dart';
import 'AppSql.dart';

Future<Map<String, dynamic>> readJapaneseMlbStats(
    Connection conn, int year) async {
  final careers = await conn.execute('''
    SELECT DISTINCT ON(c.id_player,c.id_team) c.*, p.name_full AS name_player,
      t.name_short AS name_team, t.color_back, t.color_font, t.id_league,
      p.name_last, p.name_first, p.date_birth::text, p.url
    FROM m_player_career c JOIN m_player p ON p.id=c.id_player
    JOIN m_country country ON country.id=p.id_country
    JOIN m_team t ON t.id=c.id_team
    WHERE c.int_year=\$1 AND t.id_league IN (3,4) AND country.name='日本'
      AND NOT COALESCE(c.flg_delete,false) AND NOT COALESCE(p.flg_delete,false)
    ORDER BY c.id_player,c.id_team,c.updat DESC NULLS LAST,c.id DESC
  ''', parameters: [year]);
  final stats =
      await conn.execute(AppSql.selectStatsPlayer(), parameters: [year]);
  final ids = {
    ...careers.map((r) => r.toColumnMap()['id_player']),
    ...stats.map((r) => r.toColumnMap()['id_player'])
  }.whereType<int>().toList();
  final identities = await conn.execute(
      "SELECT id AS id_player,name_full,name_last,name_first,date_birth::text,url,id_team FROM m_player WHERE id=ANY(\$1::int[])",
      parameters: [ids]);
  final byId = {
    for (final r in identities)
      '${r.toColumnMap()['id_player']}': r.toColumnMap()
  };
  return buildJapaneseMlbStats(
      careers.map((r) => r.toColumnMap()).toList(),
      stats.map((r) {
        final row = r.toColumnMap();
        return {...?byId['${row['id_player']}'], ...row};
      }).toList(),
      year);
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
    final row = {
      ...teams.first,
      'name_team': teams.map((r) => r['name_team']).toSet().join(' / ')
    };
    num sum(String field) => teams.fold<num>(0, (n, r) => n + number(r[field]));
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
    if (!yes(row['flg_japan']) || ![3, 4].contains(number(row['id_league']))) {
      continue;
    }
    final title = '${row['title']}';
    put(row, yes(row['flg_pitcher']), aliases[title] ?? title, row['stats']);
  }
  final players = result.values.toList()
    ..sort((a, b) {
      final ad = DateTime.tryParse('${a['date_birth']}');
      final bd = DateTime.tryParse('${b['date_birth']}');
      if (ad == null && bd != null) return 1;
      if (ad != null && bd == null) return -1;
      final ageOrder = ad != null && bd != null ? ad.compareTo(bd) : 0;
      return ageOrder != 0 ? ageOrder : '${a['name_player']}'.compareTo('${b['name_player']}');
    });
  return {'year': year, 'players': players};
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
  return (uniqueCareers.values.toList(), stats.map(canonical).toList());
}
