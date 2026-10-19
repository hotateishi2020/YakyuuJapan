import 'package:postgres/postgres.dart';
import 'RecordCatalog.dart';
import 'StrengthUsage.dart';

const clubRecordMetrics = [
  ('hits', '安打', '安打', 'int_hit1', 2),
  ('hr', '本塁打', '本', 'int_homerun', 3),
  ('rbi', '打点', '打点', 'int_rbi', 4),
  ('sb', '盗塁', '盗塁', 'int_steal_base', 5),
  ('wins', '勝利', '勝', 'int_win', 10),
  ('so', '奪三振', '奪三振', 'int_strike_out_pitcher', 11),
  ('holds', 'ホールド', 'ホールド', 'int_hold', 17),
  ('hp', 'ホールドポイント', 'HP', 'int_hold_point', 18),
  ('saves', 'セーブ', 'セーブ', 'int_save', 19),
  ('shutouts', '完封', '完封', 'int_shutout', 0),
];

Future<List<Map<String, dynamic>>> readClubRecordRows(
    Connection conn, int year) async {
  final values =
      clubRecordMetrics.map((m) => "('${m.$1}',c.${m.$4})").join(',');
  final metricCase = clubRecordMetrics
      .where((m) => m.$5 > 0)
      .map((m) => "WHEN ${m.$5} THEN '${m.$1}'")
      .join(' ');
  final rows = await conn.execute('''
    WITH career AS (
      SELECT DISTINCT ON (c.int_year,c.id_team,c.id_player)
        c.* FROM m_player_career c JOIN m_team t ON t.id=c.id_team
      WHERE c.int_year <= \$1 AND t.id_league IN (1,2)
        AND NOT COALESCE(c.flg_delete,false)
      ORDER BY c.int_year,c.id_team,c.id_player,c.updat DESC NULLS LAST,c.id DESC
    ), candidates AS (
      SELECT c.int_year AS year,c.id_team,c.id_player,p.name_full AS name,
        v.key,v.value,0 AS priority
      FROM career c JOIN m_player p ON p.id=c.id_player
      CROSS JOIN LATERAL (VALUES $values) v(key,value)
      WHERE v.value IS NOT NULL AND v.value > 0
      UNION ALL
      SELECT \$1,s.id_team,s.id_player,p.name_full,
        CASE s.id_stats $metricCase END,s.stats,1
      FROM t_stats_player_latest s JOIN m_player p ON p.id=s.id_player
      WHERE \$1 = EXTRACT(YEAR FROM CURRENT_DATE)::int AND s.id_league IN (1,2)
        AND s.id_stats IN (${clubRecordMetrics.where((m) => m.$5 > 0).map((m) => m.$5).join(',')})
        AND s.stats IS NOT NULL
    ), unique_rows AS (
      SELECT DISTINCT ON (year,id_team,id_player,key) * FROM candidates
      ORDER BY year,id_team,id_player,key,priority DESC,value DESC
    ), totals AS (
      SELECT \$1-1 AS year,id_team,id_player,MAX(name) AS name,
        'career_' || key AS key,SUM(value) AS value,0 AS priority
      FROM unique_rows WHERE year < \$1 GROUP BY id_team,id_player,key
      UNION ALL
      SELECT \$1,u.id_team,u.id_player,MAX(u.name),
        'career_' || u.key,SUM(u.value),1
      FROM unique_rows u
      WHERE EXISTS (SELECT 1 FROM unique_rows now
        WHERE now.year=\$1 AND now.id_team=u.id_team AND now.id_player=u.id_player)
      GROUP BY u.id_team,u.id_player,u.key
    ), all_rows AS (
      SELECT * FROM unique_rows UNION ALL SELECT * FROM totals
    ), ranked AS (
      SELECT *,DENSE_RANK() OVER(PARTITION BY id_team,key,(year=\$1) ORDER BY value DESC) AS position
      FROM all_rows
    ) SELECT year,id_team,id_player,name,key,value FROM ranked WHERE position=1
  ''', parameters: [year]);
  return rows.map((row) => row.toColumnMap()).toList();
}

Map<String, dynamic> buildClubRecords(
    List<Map<String, dynamic>> teams, List<Map<String, dynamic>> rows, int year,
    {List<Map<String, dynamic>> streakRows = const []}) {
  List<Map<String, dynamic>> leaders(dynamic team, String key, bool current) {
    final matching = rows
        .where((r) =>
            r['id_team'] == team &&
            r['key'] == key &&
            (current ? r['year'] == year : (r['year'] as num) < year))
        .toList();
    if (matching.isEmpty) return [];
    final best = matching
        .map((r) => num.parse('${r['value']}'))
        .reduce((a, b) => a > b ? a : b);
    return matching.where((r) => num.parse('${r['value']}') == best).toList();
  }

  return {
    'year': year,
    'note':
        '登録済みの球団別成績。通算は当該球団での成績のみを合算し、今季出場者の通算値と比較。連続記録は出典を確認できた記録のみ（年度をまたぐ記録を含む）。未収録の記録は未取得と表示します。',
    'teams': teams,
    'metrics': [
      for (final group in ['season', 'career'])
        for (final m in clubRecordMetrics)
          {
            'key': group == 'career' ? 'career_${m.$1}' : m.$1,
            'label': m.$2,
            'unit': m.$3,
            'group': group,
            'cells': [
              for (final team in teams)
                {
                  'id_team': team['id_team'],
                  'record': leaders(team['id_team'],
                      group == 'career' ? 'career_${m.$1}' : m.$1, false),
                  'current': leaders(team['id_team'],
                      group == 'career' ? 'career_${m.$1}' : m.$1, true),
                }
            ],
          },
      for (final d in streakDefinitions)
        {
          'key': 'streak_${d.$1}',
          'label': d.$2,
          'unit': d.$3,
          'group': 'streak',
          'cells': [
            for (final team in teams)
              {
                'id_team': team['id_team'],
                'record': bestClubStreaks(
                    streakRows, team['id_team'], d.$1, year, false),
                'current': bestClubStreaks(
                    streakRows, team['id_team'], d.$1, year, true),
              }
          ],
        }
    ],
  };
}

num? clubRecordValue(dynamic raw) {
  final direct = num.tryParse('$raw');
  if (direct != null) return direct;
  final fraction = RegExp(r'^(\d+) (\d+)/(\d+)$').firstMatch('$raw');
  if (fraction == null || int.parse(fraction[3]!) == 0) return null;
  return int.parse(fraction[1]!) +
      int.parse(fraction[2]!) / int.parse(fraction[3]!);
}

List<Map<String, dynamic>> bestClubStreaks(List<Map<String, dynamic>> rows,
    dynamic team, String key, int year, bool current) {
  final eligible = rows
      .where((r) =>
          r['id_team'] == team &&
          r['key'] == key &&
          (current
              ? r['current'] == true && r['year'] == year
              : r['current'] != true && usageInt(r['year']) <= year) &&
          clubRecordValue(r['value']) != null)
      .toList();
  if (eligible.isEmpty) return [];
  final best = eligible
      .map((r) => clubRecordValue(r['value'])!)
      .reduce((a, b) => a > b ? a : b);
  return eligible
      .where((r) => clubRecordValue(r['value']) == best)
      .map((r) => {...r, 'numeric_value': best})
      .toList();
}

/// Use the club at the time of the record, never the player's current club.
Future<List<Map<String, dynamic>>> readClubStreakRows(
    Connection conn,
    Map<String, dynamic> baseline,
    List<Map<String, dynamic>> teams,
    int year) async {
  final candidates = <Map<String, dynamic>>[
    for (final metric in usageMaps(baseline['streaks']))
      for (final row in usageMaps(metric['leaders']))
        if (usageInt(row['year']) <= year)
          {
            ...row,
            'key': metric['key'],
            'sources': metric['sources'],
            'current': false
          },
    for (final entry in usageMap(
            usageMap(usageMap(baseline['current_streaks'])['$year'])['records'])
        .entries)
      for (final row in usageMaps(entry.value))
        {...row, 'key': entry.key, 'current': true},
  ];
  if (candidates.isEmpty) return [];
  final affiliations = (await conn.execute(r'''
    SELECT DISTINCT c.int_year AS year,c.id_team,p.name_full AS name
    FROM m_player_career c JOIN m_player p ON p.id=c.id_player
    WHERE c.int_year=ANY($1::int[]) AND NOT COALESCE(c.flg_delete,false)
      AND regexp_replace(p.name_full,'[[:space:]　]','','g')=ANY($2::text[])
  ''', parameters: [
    candidates.map((r) => usageInt(r['year'])).toSet().toList(),
    candidates
        .map((r) => '${r['name']}'.replaceAll(RegExp(r'[\s　]'), ''))
        .toSet()
        .toList()
  ]))
      .map((r) => r.toColumnMap())
      .toList();
  return assignClubStreaks(candidates, affiliations, teams);
}

List<Map<String, dynamic>> assignClubStreaks(
    List<Map<String, dynamic>> candidates,
    List<Map<String, dynamic>> affiliations,
    List<Map<String, dynamic>> teams) {
  String name(dynamic s) => '$s'.replaceAll(RegExp(r'[\s　]'), '');
  final result = <Map<String, dynamic>>[];
  for (final row in candidates) {
    final ids = row['team'] != null
        ? teams
            .where((t) => [t['name'], t['short_name'], t['name_shortest']]
                .contains(row['team']))
            .map((t) => t['id_team'])
            .toSet()
        : affiliations
            .where((a) =>
                a['year'] == row['year'] &&
                name(a['name']) == name(row['name']))
            .map((a) => a['id_team'])
            .toSet();
    if (ids.length == 1 && teams.any((t) => t['id_team'] == ids.single)) {
      result.add({...row, 'id_team': ids.single});
    }
  }
  return result;
}
