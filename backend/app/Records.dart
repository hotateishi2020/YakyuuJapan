import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'OrgLeague.dart';
import 'RecordCatalog.dart';
import 'RecordStreaks.dart';
import 'StrengthUsage.dart';

/// Read-only records endpoint. Official historical baselines are refreshed offline.
class Records {
  static final _cache = <String, ({DateTime at, Map<String, dynamic> data})>{};
  static Future<Map<String, dynamic>> read(Connection conn, {required OrgKind org, required int year}) async {
    final key = '${org.code}:$year';
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.at).inMinutes < 10) {
      return cached.data;
    }
    final leagues = org.leagueIds.join(',');
    final standingRows = await conn.execute('''
      SELECT DISTINCT ON (s.year,s.id_team) s.year, s.id_team, s.id_league, s.int_rank, s.int_win, s.int_lose, s.int_draw,
        COALESCE(NULLIF(s.name_team,''),t.name_short) AS name, s.code_area
      FROM t_stats_team s JOIN m_team t ON t.id=s.id_team
      WHERE s.id_league IN ($leagues) AND s.year <= \$1 AND NOT COALESCE(s.flg_delete,false)
      ORDER BY s.year DESC,s.id_team,s.crtat DESC,s.id DESC
    ''', parameters: [year]);
    final playoffs = await conn.execute('''
      SELECT EXTRACT(YEAR FROM g.datetime_start)::int AS year,g.id_team_home,g.id_team_away,
        g.score_home,g.score_away,g.state,g.code_game
      FROM t_game g JOIN m_team t ON t.id=g.id_team_home
      WHERE t.id_league IN ($leagues) AND g.datetime_start < make_date(\$1+1,1,1)
        AND g.code_game IN ('CS1','CSF','JS','WC','DS','LCS','ALCS','NLCS','WS')
        AND NOT COALESCE(g.flg_delete,false)
      ORDER BY g.datetime_start,g.id
    ''', parameters: [year]);
    final titleRows = await conn.execute('''
      SELECT s.int_year AS year,s.id_league,s.id_stats,s.id_player,s.stats AS value,
        p.name_full AS name,COALESCE(NULLIF(st.name_team,''),t.name_short) AS team,
        CASE WHEN p.year_retire > 0 THEN 'retired' ELSE 'unknown' END AS status
      FROM (
        SELECT int_year,id_league,id_stats,id_player,id_team,int_rank,stats FROM t_stats_player
          WHERE int_year <> EXTRACT(YEAR FROM CURRENT_DATE)::int AND NOT COALESCE(flg_delete,false)
        UNION ALL
        SELECT EXTRACT(YEAR FROM CURRENT_DATE)::int,id_league,id_stats,id_player,id_team,int_rank,stats FROM t_stats_player_latest
      ) s JOIN m_player p ON p.id=s.id_player
      LEFT JOIN m_team t ON t.id=s.id_team
      LEFT JOIN LATERAL (SELECT name_team FROM t_stats_team WHERE year=s.int_year AND id_team=s.id_team AND NOT COALESCE(flg_delete,false) ORDER BY crtat DESC,id DESC LIMIT 1) st ON true
      WHERE s.id_league IN ($leagues) AND s.int_year <= \$1 AND s.int_rank=1
        
      ORDER BY s.int_year DESC,s.id_league,s.id_stats,s.id_player
    ''', parameters: [year]);
    final titles = titleRows.map((r) => r.toColumnMap()).toList();
    final baselineFile = [File('data/records.json'), File('backend/data/records.json')].firstWhere((f) => f.existsSync());
    final baseline = usageMap(usageMap(jsonDecode(baselineFile.readAsStringSync()))[org.code]);
    final season = usageMaps(baseline['season']);
    for (final record in season) {
      final metric = recordMetrics.firstWhere((m) => m.key == record['key']);
      record['current'] = currentLeaders(titles, metric, year);
      record['current_note'] = '規定条件を満たす登録済み首位成績がありません。';
    }
    final games = await conn.execute('''
      SELECT g.id,g.id_team_home,g.id_team_away,g.flg_stats_loaded,
        g.datetime_start::text AS date
      FROM t_game g JOIN m_team t ON t.id=g.id_team_home
      WHERE t.id_league IN ($leagues) AND g.datetime_start >= make_date(\$1,1,1)
        AND g.datetime_start < make_date(\$1+1,1,1) AND (g.code_game IN ('NM','EX') OR g.code_game IS NULL)
        AND (g.state LIKE '%終了%' OR g.state LIKE '%コールド%') AND NOT COALESCE(g.flg_delete,false)
      ORDER BY g.datetime_start,g.id
    ''', parameters: [year]);
    final gameIds = games.map((r) => r[0]).whereType<int>().toList();
    final summaries = gameIds.isEmpty ? <Map<String, dynamic>>[] : (await conn.execute('''
      SELECT s.*, p.name_full AS name FROM t_game_summary s JOIN m_player p ON p.id=s.id_player
      WHERE s.id_game=ANY(\$1::int[]) AND NOT COALESCE(s.flg_delete,false)
      ORDER BY s.id_game,s.id_player
    ''', parameters: [gameIds])).map((r) => r.toColumnMap()).toList();
    final streaks = buildSummaryStreaks(games.map((r) => r.toColumnMap()).toList(), summaries, year);
    final events = gameIds.isEmpty ? <Map<String, dynamic>>[] : (await conn.execute('''
      SELECT d.id_game,d.id_batter,d.id_pitcher,d.id_player_enter,d.flg_bottom,d.code_result FROM t_game_details d WHERE d.id_game=ANY(\$1::int[]) AND NOT COALESCE(d.flg_delete,false) ORDER BY d.id_game,d.id
    ''', parameters: [gameIds])).map((r) => r.toColumnMap()).toList();
    streaks.addAll(buildEventStreaks(games.map((r) => r.toColumnMap()).toList(), summaries, events, year));
    final currentSnapshot = usageMap(usageMap(baseline['current_streaks'])['$year']);
    final officialStreaks = usageMap(currentSnapshot['records']);
    for (final entry in officialStreaks.entries) {
      streaks[entry.key] = usageMaps(entry.value);
    }
    final data = <String, dynamic>{
      'org': org.code,
      'year': year,
      'standings': buildRecordStandings(standingRows.map((r) => r.toColumnMap()).toList(), playoffs.map((r) => r.toColumnMap()).toList(), org),
      'titles': mergeRecordAwards(buildRecordTitles(titles, org), usageMaps(baseline['awards']), year),
      'season': season,
      'career': usageMaps(baseline['career']),
      'streaks': [
        for (final d in streakDefinitions)
          {
            ...{
              for (final r in usageMaps(baseline['streaks']))
                if (r['key'] == d.$1) ...r
            },
            'key': d.$1,
            'label': d.$2,
            'unit': d.$3,
            'note': '${d.$4} 歴代は複数シーズンをまたぐ記録を含み、比較欄は選択年度内。${usageMaps(baseline['streaks']).where((r) => r['key'] == d.$1).map((r) => ' ${r['scope_note'] ?? ''}').join()}',
            'current': streaks[d.$1] ?? [],
            'current_note': officialStreaks.containsKey(d.$1)
                ? '${currentSnapshot['note']} 確認日：${currentSnapshot['checked_at']}'
                : streaks.containsKey(d.$1)
                    ? '終了済み・成績取得済み試合の連続区間内の最長。未取得試合で区切ります。'
                    : 'この記録の判定に必要な公式記録・打席別データを確認できていません。',
          }
      ],
    };
    _cache[key] = (at: DateTime.now(), data: data);
    return data;
  }
}

double _number(dynamic v) => double.tryParse('$v') ?? 0;
List<Map<String, dynamic>> currentLeaders(List<Map<String, dynamic>> rows, RecordMetric metric, int year) {
  final candidates = rows.where((r) => usageInt(r['year']) == year && usageInt(r['id_stats']) == metric.statId).toList();
  candidates.sort((a, b) => metric.lower ? _number(a['value']).compareTo(_number(b['value'])) : _number(b['value']).compareTo(_number(a['value'])));
  if (candidates.isEmpty) return [];
  final best = _number(candidates.first['value']);
  final seen = <int>{};
  return [
    for (final p in candidates)
      if (_number(p['value']) == best && seen.add(usageInt(p['id_player']))) {...p, 'value': formatRecordValue(p['value'], metric), 'unit': metric.unit}
  ];
}

String formatRecordValue(dynamic value, RecordMetric metric) => metric.unit.isEmpty ? _number(value).toStringAsFixed(metric.key == 'era' ? 2 : 3) : _number(value).toStringAsFixed(0);
String _league(OrgKind org, int id, int year) => org == OrgKind.npb && year < 1950 ? '日本野球連盟' : org.leagues.where((l) => l.id == id).first.nameShort;
List<Map<String, dynamic>> buildRecordTitles(List<Map<String, dynamic>> rows, OrgKind org) {
  const labels = {1: '首位打者', 2: '最多安打', 3: '本塁打王', 4: '打点王', 5: '盗塁王', 6: '最高出塁率', 9: '最優秀防御率', 10: '最多勝利', 11: '最多奪三振', 18: '最優秀中継ぎ', 19: '最多セーブ'};
  final seasons = <String, Map<String, dynamic>>{};
  final seen = <String>{};
  for (final row in rows) {
    final id = usageInt(row['id_stats']), year = usageInt(row['year']), league = usageInt(row['id_league']);
    if (!labels.containsKey(id) || org == OrgKind.mlb && [6, 18].contains(id)) {
      continue;
    }
    if (!seen.add('$year:$league:$id:${row['id_player']}')) continue;
    final s = seasons.putIfAbsent('$year:$league', () => {'year': year, 'league': _league(org, league, year), 'provisional': year >= DateTime.now().year, 'categories': <Map<String, dynamic>>[]});
    final categories = s['categories'] as List<Map<String, dynamic>>;
    final category = categories.where((c) => c['label'] == labels[id]).firstOrNull;
    final c = category ?? {'label': labels[id], 'players': <Map<String, dynamic>>[]};
    if (category == null) categories.add(c);
    final metric = recordMetrics.firstWhere((m) => m.statId == id);
    (c['players'] as List).add({...row, 'value': formatRecordValue(row['value'], metric), 'unit': metric.unit});
  }
  return seasons.values.toList()..sort((a, b) => usageInt(b['year']).compareTo(usageInt(a['year'])));
}

List<Map<String, dynamic>> buildRecordStandings(List<Map<String, dynamic>> rows, List<Map<String, dynamic>> games, OrgKind org) {
  final entrants = <int, Set<int>>{}, wins = <int, Map<int, int>>{};
  for (final g in games) {
    final year = usageInt(g['year']), home = usageInt(g['id_team_home']), away = usageInt(g['id_team_away']);
    if ('${g['state']}'.contains('中止')) continue;
    entrants.putIfAbsent(year, () => {}).addAll([home, away]);
    if (!['JS', 'WS'].contains(g['code_game']) || !'${g['state']}'.contains('終了')) {
      continue;
    }
    final h = usageInt(g['score_home']), a = usageInt(g['score_away']);
    if (h == a) continue;
    final tally = wins.putIfAbsent(year, () => {}), winner = h > a ? home : away;
    tally[winner] = (tally[winner] ?? 0) + 1;
  }
  final seasons = <int, Map<String, dynamic>>{};
  for (final r in rows) {
    final year = usageInt(r['year']), team = usageInt(r['id_team']);
    final required = org == OrgKind.mlb && [1903, 1919, 1920, 1921].contains(year) ? 5 : 4;
    final champion = (wins[year]?[team] ?? 0) >= required;
    final s = seasons.putIfAbsent(year, () => {'year': year, 'champion': null, 'leagues': <Map<String, dynamic>>[]});
    if (champion) s['champion'] = r['name'];
    final leagueName = _league(org, usageInt(r['id_league']), year);

    final label = leagueName;
    final leagues = s['leagues'] as List<Map<String, dynamic>>;
    var league = leagues.where((l) => l['name'] == label).firstOrNull;
    if (league == null) {
      league = {'name': label, 'teams': <Map<String, dynamic>>[]};
      leagues.add(league);
    }
    (league['teams'] as List).add({'rank': r['int_rank'], 'name': r['name'], 'wins': r['int_win'], 'losses': r['int_lose'], 'draws': r['int_draw'], 'postseason': entrants[year]?.contains(team) ?? false, 'champion': champion});
  }
  for (final s in seasons.values) {
    for (final l in s['leagues']) {
      (l['teams'] as List).sort((a, b) => usageInt(a['rank']).compareTo(usageInt(b['rank'])));
    }
  }
  return seasons.values.toList()..sort((a, b) => usageInt(b['year']).compareTo(usageInt(a['year'])));
}

List<Map<String, dynamic>> mergeRecordAwards(List<Map<String, dynamic>> statistical, List<Map<String, dynamic>> awards, int throughYear) {
  final bySeason = {for (final s in statistical) '${s['year']}:${s['league']}': s};
  for (final award in awards) {
    if (usageInt(award['year']) > throughYear) continue;
    final key = '${award['year']}:${award['league']}';
    final season = bySeason.putIfAbsent(key, () => {...award, 'categories': <Map<String, dynamic>>[]});
    final categories = usageMaps(season['categories']);
    for (final c in usageMaps(award['categories'])) {
      categories.removeWhere((old) => old['label'] == c['label']);
      categories.add(c);
    }
    season['categories'] = categories;
    season['provisional'] = false;
  }
  return bySeason.values.toList()..sort((a, b) => usageInt(b['year']).compareTo(usageInt(a['year'])));
}
