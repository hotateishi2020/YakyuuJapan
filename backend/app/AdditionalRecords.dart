import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'OrgLeague.dart';
import 'BaseballCatalog.dart' show catalogFile;
import 'StrengthUsage.dart';

Future<Map<String, dynamic>> readAdditionalRecords(
    Connection conn, OrgKind org, int year) async {
  final leagues = org.leagueIds.join(',');
  final annual = await conn.execute('''
    WITH c AS (
      SELECT DISTINCT ON (c.int_year,c.id_team,c.id_player) c.*
      FROM m_player_career c JOIN m_team t ON t.id=c.id_team
      WHERE c.int_year <= \$1 AND t.id_league IN ($leagues) AND NOT COALESCE(c.flg_delete,false)
      ORDER BY c.int_year,c.id_team,c.id_player,c.updat DESC NULLS LAST,c.id DESC
    ) SELECT c.int_year AS year,c.id_player,p.name_full AS name,
      MAX(t.name_short) AS team, SUM(c.int_homerun) AS hr,SUM(c.int_steal_base) AS sb,
      SUM(c.int_appearance) AS pa,SUM(c.int_batting) AS ab,SUM(c.int_hit1) AS hits,
      MAX(g.games) AS team_games
    FROM c JOIN m_player p ON p.id=c.id_player JOIN m_team t ON t.id=c.id_team
    LEFT JOIN LATERAL (SELECT COALESCE(int_win,0)+COALESCE(int_lose,0)+COALESCE(int_draw,0) AS games FROM t_stats_team
      WHERE id_team=c.id_team AND year=c.int_year AND NOT COALESCE(flg_delete,false)
      ORDER BY crtat DESC,id DESC LIMIT 1) g ON true
    GROUP BY c.int_year,c.id_player,p.name_full
  ''', parameters: [year]);
  final rows = annual.map((r) => r.toColumnMap()).toList();
  // Age is calculated on the event date, never from the season number alone.
  final ages = await conn.execute('''
    WITH events AS (
      SELECT p.id AS id_player,p.name_full AS name,p.date_birth,g.datetime_start::date AS date,
        v.label, g.datetime_start::date-p.date_birth::date AS days,
        EXTRACT(YEAR FROM age(g.datetime_start::date,p.date_birth::date))::int AS age_years,
        g.datetime_start::date-(p.date_birth::date + make_interval(years => EXTRACT(YEAR FROM age(g.datetime_start::date,p.date_birth::date))::int))::date AS age_days
      FROM t_game_summary s JOIN t_game g ON g.id=s.id_game JOIN m_player p ON p.id=s.id_player
      JOIN m_team t ON t.id=g.id_team_home
      CROSS JOIN LATERAL (VALUES ('出場',true),('安打',s.int_hit1>0),('本塁打',s.int_homerun>0),('勝利',s.code_result_pitcher IN ('WIN','W','勝','勝利'))) v(label,achieved)
      WHERE t.id_league IN ($leagues) AND g.datetime_start<make_date(\$1+1,1,1)
        AND (g.code_game IN ('NM','EX') OR g.code_game IS NULL)
        AND (g.state LIKE '%終了%' OR g.state LIKE '%コールド%')
        AND p.date_birth IS NOT NULL AND g.datetime_start::date>=p.date_birth::date
        AND NOT COALESCE(s.flg_delete,false) AND NOT COALESCE(g.flg_delete,false) AND v.achieved
    ), ranked AS (SELECT *,DENSE_RANK() OVER(PARTITION BY label ORDER BY days) AS youngest,
      DENSE_RANK() OVER(PARTITION BY label ORDER BY days DESC) AS oldest FROM events)
    SELECT DISTINCT label,id_player,name,date::text,age_years,age_days,youngest,oldest FROM ranked WHERE youngest=1 OR oldest=1
  ''', parameters: [year]);
  return {
    'hr_sb': buildHrStealRecord(rows, year),
    'count_seasons': rows,
    'age_records': [
      if (org == OrgKind.npb)
        ...milestoneAgeRecords(
            usageMaps(catalogFile('age-records')['rows']), year),
      ...ages.map((r) =>
          {...r.toColumnMap(), 'label': '${r.toColumnMap()['label']}（取得済み試合）'})
    ],
    'regular_history': await readRegularHistory(conn, org, year),
  };
}

Future<List<Map<String, dynamic>>> readRegularHistory(
    Connection conn, OrgKind org, int year) async {
  final leagues = org.leagueIds.join(',');
  final snapshots = await conn.execute('''
    SELECT s.int_year AS year,s.id_team,s.payload,t.name_short AS name_team,t.color_back,t.color_font
    FROM t_team_strength s JOIN m_team t ON t.id=s.id_team
    WHERE s.code_org=\$1 AND s.int_year<=\$2 ORDER BY s.int_year DESC,s.id_team
  ''', parameters: [org.code, year]);
  final historyTeams = await conn.execute(
      'SELECT id AS id_team,name_short AS name_team,color_back,color_font FROM m_team WHERE id_league IN ($leagues)');
  return mergeRegularHistory(
      [
        for (final r in snapshots)
          (() {
            final row = r.toColumnMap();
            final payload = row['payload'] is String
                ? jsonDecode(row['payload'])
                : row['payload'];
            row.remove('payload');
            return {...usageMap(payload), ...row};
          })()
      ],
      usageMaps(catalogFile(org == OrgKind.npb
          ? 'regular-history'
          : 'regular-history-mlb')['rows']),
      historyTeams.map((r) => r.toColumnMap()).toList(),
      year);
}

List<Map<String, dynamic>> mergeRegularHistory(
    List<Map<String, dynamic>> snapshots,
    List<Map<String, dynamic>> archive,
    List<Map<String, dynamic>> teams,
    int year) {
  final result = <String, Map<String, dynamic>>{};
  for (final row in archive.where((r) => usageInt(r['year']) <= year)) {
    final team =
        teams.where((t) => t['name_team'] == row['club_name']).firstOrNull;
    final value = {
      ...row,
      if (team != null) ...team,
      if (team == null) 'id_team': 'historical-${row['club_name']}',
      if (team == null) 'name_team': row['club_name']
    };
    result['${value['year']}:${value['id_team']}'] = value;
  }
  for (final row in snapshots) {
    final key = '${row['year']}:${row['id_team']}';
    final prior = result[key];
    result[key] = {
      ...?prior,
      ...row,
      for (final field in [
        'positions', 'batting_order', 'roster', 'batting_stats',
        'pitching_stats', 'pitching_workload'
      ])
        if (usageMaps(row[field]).isEmpty && prior?[field] != null)
          field: prior![field],
    };
  }
  return result.values.toList()
    ..sort((a, b) {
      final yearOrder = usageInt(b['year']).compareTo(usageInt(a['year']));
      return yearOrder != 0
          ? yearOrder
          : '${a['name_team']}'.compareTo('${b['name_team']}');
    });
}

Map<String, dynamic> buildHrStealRecord(
    List<Map<String, dynamic>> rows, int year) {
  List<Map<String, dynamic>> ranked(Iterable<Map<String, dynamic>> source) {
    final r = [
      for (final p in source)
        if (p['hr'] != null && p['sb'] != null)
          {
            ...p,
            'value': '${usageInt(p['hr'])} - ${usageInt(p['sb'])}',
            'numeric_value': usageInt(p['hr']) < usageInt(p['sb'])
                ? usageInt(p['hr'])
                : usageInt(p['sb'])
          }
    ];
    r.sort((a, b) =>
        usageInt(b['numeric_value']).compareTo(usageInt(a['numeric_value'])));
    for (var i = 0; i < r.length; i++) {
      r[i]['rank'] = i > 0 && r[i]['numeric_value'] == r[i - 1]['numeric_value']
          ? r[i - 1]['rank']
          : i + 1;
    }
    return r.take(50).toList();
  }

  return {
    'key': 'hr_sb',
    'label': 'HR - 盗塁',
    'unit': '',
    'leaders': ranked(rows),
    'current': ranked(rows.where((r) => usageInt(r['year']) == year &&
        usageInt(r['hr']) >= 10 && usageInt(r['sb']) >= 10)),
    'note': '登録済み年度成績。本塁打・盗塁の少ない方が多い順。同値は同順位。今シーズン欄は本塁打・盗塁ともに10以上の選手を表示。'
  };
}

List<Map<String, dynamic>> buildCountRecords(
    List<Map<String, dynamic>> seasons, List<Map<String, dynamic>> titleSeasons,
    {required bool npb}) {
  final counts = <String, Map<String, Map<String, dynamic>>>{};
  String nameKey(Map<String, dynamic> p) =>
      '${p['name']}'.replaceAll(RegExp(r'[\s　・･]'), '');
  final knownIds = <String, Set<String>>{};
  for (final p in [
    ...seasons,
    ...titleSeasons
        .expand((s) => usageMaps(s['categories']))
        .expand((c) => usageMaps(c['players']))
  ]) {
    if (p['id_player'] != null) {
      knownIds.putIfAbsent(nameKey(p), () => {}).add('${p['id_player']}');
    }
  }
  void add(String category, Map<String, dynamic> p, String occurrence) {
    final ids = knownIds[nameKey(p)];
    final key = p['id_player'] != null
        ? 'id:${p['id_player']}'
        : ids?.length == 1
            ? 'id:${ids!.single}'
            : 'name:${nameKey(p)}';
    final person = counts
        .putIfAbsent(category, () => {})
        .putIfAbsent(key, () => {...p, 'events': <String>{}});
    (person['events'] as Set<String>).add(occurrence);
  }

  for (final p in seasons) {
    final year = usageInt(p['year']), games = usageInt(p['team_games']);
    // Pre-1957 NPB qualification rules varied; do not guess their thresholds.
    final qualified =
        year >= 1957 && games > 0 && usageInt(p['pa']) >= (games * 3.1).floor();
    if (qualified) {
      add('規定打席到達', p, '$year');
      if (usageInt(p['ab']) > 0 &&
          (usageInt(p['hits']) * 1000 / usageInt(p['ab'])).round() >= 300) {
        add('打率3割（規定打席）', p, '$year');
      }
    }
    if (usageInt(p['hr']) >= 30) add('30本塁打', p, '$year');
    if (usageInt(p['sb']) >= 30) add('30盗塁', p, '$year');
  }
  const official = [
    '首位打者',
    '最多安打',
    '本塁打王',
    '最多本塁打',
    '打点王',
    '最多打点',
    '盗塁王',
    '最多盗塁',
    '最高出塁率',
    '最優秀防御率',
    '最多勝利',
    '最多勝',
    '最多奪三振',
    '最多セーブ',
    '最多ホールドポイント',
    '最優秀中継ぎ',
    '最高勝率',
    'MVP',
    '最優秀選手',
    '新人王',
    '最優秀新人',
    'ベストナイン',
    'ゴールデングラブ賞'
  ];
  for (final season in titleSeasons) {
    if (season['provisional'] == true) continue;
    for (final category in usageMaps(season['categories'])) {
      final label = '${category['label'] ?? category['title']}';
      if (!official.contains(label)) continue;
      for (final p in usageMaps(category['players'])) {
        final event = '${season['year']}:${season['league']}:$label';
        add('タイトル獲得（合計）', p, event);
        add(label, p, event);
      }
    }
  }
  return [
    for (final category in counts.entries)
      (() {
        final people = [
          for (final p in category.value.values)
            {...p, 'value': (p['events'] as Set).length}..remove('events')
        ]..sort((a, b) => usageInt(b['value']).compareTo(usageInt(a['value'])));
        for (var i = 0; i < people.length; i++) {
          people[i]['rank'] =
              i > 0 && people[i]['value'] == people[i - 1]['value']
                  ? people[i - 1]['rank']
                  : i + 1;
        }
        return {
          'key': category.key,
          'label': category.key,
          'unit': '回',
          'leaders': people,
          'note': '取得済み年度成績・公式タイトルの集計。規定打席は球団試合数×3.1以上（1957年以降）。'
        };
      })()
  ];
}

List<Map<String, dynamic>> milestoneAgeRecords(
    List<Map<String, dynamic>> source, int year) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final r in source.where((r) => usageInt(r['year']) <= year)) {
    groups.putIfAbsent('${r['label']}', () => []).add(r);
  }
  return [
    for (final group in groups.values)
      ...(() {
        group.sort((a, b) =>
            usageInt(a['age_months']).compareTo(usageInt(b['age_months'])));
        final young = usageInt(group.first['age_months']),
            old = usageInt(group.last['age_months']);
        final youngest =
            group.where((r) => r['age_order'] == '【1】').firstOrNull;
        final oldest = group.where((r) => r['age_order'] == '（1）').firstOrNull;
        return [
          for (final r in group)
            if (identical(r, youngest) ||
                identical(r, oldest) ||
                youngest == null && usageInt(r['age_months']) == young ||
                oldest == null && usageInt(r['age_months']) == old)
              {
                ...r,
                'youngest': youngest != null
                    ? identical(r, youngest)
                        ? 1
                        : 0
                    : usageInt(r['age_months']) == young
                        ? 1
                        : 0,
                'oldest': oldest != null
                    ? identical(r, oldest)
                        ? 1
                        : 0
                    : usageInt(r['age_months']) == old
                        ? 1
                        : 0
              }
        ];
      })()
  ];
}
