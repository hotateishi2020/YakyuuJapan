import 'ChampionshipSummary.dart';
import 'TimelineCs.dart';
import 'ClubData.dart' show readClubFile, clubKey;
import 'RecordInterleague.dart';
import 'SeasonAwards.dart';
import 'BaseballTimeline.dart';
import 'AdditionalRecords.dart';
import 'ClubRecords.dart';
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
  static Future<Map<String, dynamic>> read(Connection conn, {required OrgKind org, required int year, bool force = false}) async {
    final key = '${org.code}:$year';
    final cached = _cache[key];
    if (!force && cached != null && DateTime.now().difference(cached.at).inMinutes < 10) {
      return cached.data;
    }
    final leagues = org.leagueIds.join(',');
    final standingRows = await conn.execute('''
      SELECT DISTINCT ON (s.year,s.id_team) s.year, s.id_team, s.id_league, s.int_rank, s.int_win, s.int_lose, s.int_draw,
        COALESCE(h.name_full,NULLIF(s.name_team,''),t.name_short) AS name,
        COALESCE(h.name_short,NULLIF(s.name_team,''),t.name_short) AS short_name,
        COALESCE(h.name_shortest,s.name_shortest) AS name_shortest,
        t.url_npb_players AS manager_team_url, t.name_short AS manager_team_name,
        CASE WHEN h.name_full='近畿グレートリング' THEN COALESCE(h.color_back,t.color_back) ELSE t.color_back END AS color_back,
        CASE WHEN h.name_full='近畿グレートリング' THEN COALESCE(h.color_font,t.color_font) ELSE t.color_font END AS color_font,h.logo_url,
        COALESCE(h.name_full,s.name_team) IS DISTINCT FROM t.name_short
          AND COALESCE(h.name_full,s.name_team) IS DISTINCT FROM t.name_full AS historical_identity, s.code_area
      FROM t_stats_team s JOIN m_team t ON t.id=s.id_team
      LEFT JOIN m_team_season_identity h ON h.id_franchise=s.id_team AND h.int_year=s.year
      WHERE s.id_league IN ($leagues) AND s.year <= \$1 AND NOT COALESCE(s.flg_delete,false)
      ORDER BY s.year DESC,s.id_team,s.crtat DESC,s.id DESC
    ''', parameters: [year]);
    final playoffs = await conn.execute('''
      SELECT DISTINCT ON (g.datetime_start::date,g.id_team_home,g.id_team_away,g.code_game)
        EXTRACT(YEAR FROM g.datetime_start)::int AS year,g.id_team_home,g.id_team_away,
        g.score_home,g.score_away,g.state,g.code_game
      FROM t_game g JOIN m_team t ON t.id=g.id_team_home
      WHERE t.id_league IN ($leagues) AND g.datetime_start < make_date(\$1+1,1,1)
        AND g.code_game IN ('CS1','CSF','CS2','CS','JS','WC','DS','LCS','ALCS','NLCS','WS')
        AND NOT COALESCE(g.flg_delete,false)
      ORDER BY g.datetime_start::date,g.id_team_home,g.id_team_away,g.code_game,g.updat DESC NULLS LAST,g.id DESC
    ''', parameters: [year]);
    final titleRows = await conn.execute('''
      SELECT s.int_year AS year,s.id_league,s.id_stats,s.id_player,s.stats AS value,
        s.id_team, ms.title AS stat_title, p.name_full AS name,COALESCE(h.name_short,NULLIF(st.name_team,''),t.name_short) AS team,
        t.color_back AS color_back,
        t.color_font AS color_font,
        CASE WHEN p.year_retire > 0 THEN 'retired' ELSE 'unknown' END AS status
      FROM (
        SELECT int_year,id_league,id_stats,id_player,id_team,int_rank,stats FROM t_stats_player
          WHERE int_year <> EXTRACT(YEAR FROM CURRENT_DATE)::int AND NOT COALESCE(flg_delete,false)
        UNION ALL
        SELECT EXTRACT(YEAR FROM CURRENT_DATE)::int,id_league,id_stats,id_player,id_team,int_rank,stats FROM t_stats_player_latest
      ) s JOIN m_player p ON p.id=s.id_player
      LEFT JOIN m_stats ms ON ms.id=s.id_stats
      LEFT JOIN m_team t ON t.id=s.id_team
      LEFT JOIN m_team_season_identity h ON h.id_franchise=s.id_team AND h.int_year=s.int_year
      LEFT JOIN LATERAL (SELECT name_team FROM t_stats_team WHERE year=s.int_year AND id_team=s.id_team AND NOT COALESCE(flg_delete,false) ORDER BY crtat DESC,id DESC LIMIT 1) st ON true
      WHERE s.id_league IN ($leagues) AND s.int_year <= \$1 AND s.int_rank=1
        
      ORDER BY s.int_year DESC,s.id_league,s.id_stats,s.id_player
    ''', parameters: [year]);
    final titles = titleRows.map((r) => r.toColumnMap()).toList();
    final baselineFile = [File('data/records.json'), File('backend/data/records.json')].firstWhere((f) => f.existsSync());
    final baseline = usageMap(usageMap(jsonDecode(baselineFile.readAsStringSync()))[org.code]);
    final season = usageMaps(baseline['season']);
    final combinedFile = [File('data/combined_career_records.json'), File('backend/data/combined_career_records.json')].where((f) => f.existsSync()).firstOrNull;
    final combined = combinedFile == null ? <Map<String,dynamic>>[] : usageMaps(usageMap(usageMap(jsonDecode(combinedFile.readAsStringSync()))['career'])[org.code]);
    // Holds are not a title ranking in t_stats_player_latest. Reuse the
    // official regular-season pitching snapshots refreshed by TeamStrength.
    final pitchingSnapshots = await conn.execute('''
      SELECT s.id_team,s.payload,t.name_short AS team,t.color_back,t.color_font
      FROM t_team_strength s JOIN m_team t ON t.id=s.id_team
      WHERE s.int_year = \$1 AND s.code_org = \$2
    ''', parameters: [year, org.code]);
    final holdLeaders = seasonHoldLeaders(pitchingSnapshots.map((r) => r.toColumnMap()).toList(), year);
    for (final record in season) {
      final metric = recordMetrics.firstWhere((m) => m.key == record['key']);
      record['current'] = currentLeaders(titles, metric, year);
      if (metric.key == 'holds' && (record['current'] as List).isEmpty) {
        record['current'] = holdLeaders;
      }
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
      SELECT s.id_game,s.id_player,s.code_result_pitcher,s.int_pitch,
        s.double_inning_pitch,s.int_runs,s.int_hit1,s.int_hit2,s.int_hit3,
        s.int_homerun,s.int_batting,s.int_fourball,s.int_dead_batting,
        s.int_sacrifice,p.name_full AS name
      FROM t_game_summary s JOIN m_player p ON p.id=s.id_player
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
    final splitFile = [File('data/npb_split_standings.json'), File('backend/data/npb_split_standings.json')]
        .where((f) => f.existsSync()).firstOrNull;
    final managerCatalog = org == OrgKind.npb
        ? usageMap(readClubFile('timeline-managers-npb.json')['clubs']) : <String, dynamic>{};
    final standings = buildRecordStandings(standingRows.map((r) {
      final row = r.toColumnMap();
      final code = clubKey({'url_npb_players': row['manager_team_url'], 'name_team': row['manager_team_name']});
      final entry = usageMap(managerCatalog[code]);
      final manager = usageMap(entry['years'])['${row['year']}'];
      return {...row, if (manager != null) 'manager': manager};
    }).toList(),
        playoffs.map((r) => r.toColumnMap()).toList(), org);
    final splitStandings = org == OrgKind.npb && splitFile != null
        ? applySplitRecordStandings(standings, usageMaps(jsonDecode(splitFile.readAsStringSync()))) : standings;
    if (org == OrgKind.npb) {
      final file = [File('data/interleague_champions.json'), File('backend/data/interleague_champions.json')]
          .where((f) => f.existsSync()).firstOrNull;
      final champions = file == null ? <String,dynamic>{} : usageMap(jsonDecode(file.readAsStringSync()));
      for (final season in splitStandings) {
        final winner = usageMap(champions['${season['year']}']);
        attachInterleagueRanks(season, winner);
        if (winner.isEmpty) continue;
        final teams = usageMaps(season['leagues']).expand((l) => usageMaps(l['teams']));
        final team = teams.where((t) => t['name'] == winner['name'] ||
          '${winner['name']}'.contains('${t['short_name'] ?? t['name']}')).firstOrNull;
        season['interleague_champion'] = {...?team, ...winner};
      }
    }
    final clubTeams = <String, Map<String, dynamic>>{};
    if (org == OrgKind.npb) {
      // The selected season's participants exclude defunct franchises from the 12-team grid.
      final latestYear = standingRows.isEmpty ? year : standingRows.first.toColumnMap()['year'];
      for (final row in standingRows.map((r) => r.toColumnMap())) {
        if (row['year'] == latestYear) clubTeams['${row['id_team']}'] = row;
      }
    }
    final clubRecords = org == OrgKind.npb
        ? buildClubRecords(clubTeams.values.toList(), await readClubRecordRows(conn, year), year,
            streakRows: await readClubStreakRows(conn, baseline, clubTeams.values.toList(), year)) : null;
    final additional = await readAdditionalRecords(conn, org, year);
    final completeTitles = colorRecordTitles(mergeRecordAwards(buildRecordTitles(titles, org), usageMaps(baseline['awards']), year), standingRows.map((r) => r.toColumnMap()).toList(), titles);
    season.add(usageMap(additional['hr_sb']));
    final data = <String, dynamic>{
      'org': org.code,
      'year': year,
      'standings': splitStandings,
      'championship_summary': championshipSummary(splitStandings, year, mlb: org == OrgKind.mlb, officialLeagueWinners: usageMap(readClubFile('npb_league_champions.json')['years'])),
      'timeline': readBaseballTimeline(org.code, year),
      'titles': completeTitles,
      'season_awards': org == OrgKind.npb ? SeasonAwards.read(year) : {},
      'season_award_supplement': readSeasonAwardSupplement(org.code, year),
      'minor_title_leaders': [for (final row in titles)
        if (usageInt(row['year']) == year && ![1,2,3,4,5,6,9,10,11,18,19].contains(usageInt(row['id_stats'])))
          {...row, 'title':row['stat_title'], 'league':_league(org,usageInt(row['id_league']),year)}],
      'age_records': additional['age_records'],
      'regular_history': additional['regular_history'],
      'count_records': buildCountRecords(usageMaps(additional['count_seasons']), completeTitles, npb: org == OrgKind.npb),
      'season': season,
      if (clubRecords != null) 'club_records': clubRecords,
      'career': combined.isEmpty ? usageMaps(baseline['career']) : combined,
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
            ...seasonStreakPresentation(
              observed: streaks[d.$1] ?? [],
              official: officialStreaks.containsKey(d.$1),
              completedGames: games.length,
              loadedGames: games.where((g) => g.toColumnMap()['flg_stats_loaded'] == true).length,
            ),
            'current_note': officialStreaks.containsKey(d.$1)
                ? '${currentSnapshot['note']} 確認日：${currentSnapshot['checked_at']}'
                : streaks.containsKey(d.$1)
                    ? '終了済み・成績取得済み試合の連続区間内の最長。未取得試合で区切ります。'
                    : 'この記録の判定に必要な公式記録・打席別データを確認できていません。',
          }
      ],
    };
    _cache.clear(); // Background historical builds must not retain every full season in memory.
    if (!force) _cache[key] = (at: DateTime.now(), data: data);
    return data;
  }
}

/// Combine team-specific regular-season totals, including traded pitchers.
List<Map<String, dynamic>> seasonHoldLeaders(List<Map<String, dynamic>> teams, int year) {
  final players = <String, Map<String, dynamic>>{};
  final seen = <String>{};
  for (final team in teams) {
    final pitchers = usageMap(usageMap(team['payload'])['pitchers']);
    for (final role in ['starters', 'relievers', 'closers']) {
      for (final pitcher in usageMaps(pitchers[role])) {
        final name = '${pitcher['name'] ?? ''}';
        final key = '${pitcher['player_key'] ?? name}';
        final holds = usageInt(pitcher['holds']);
        if (key.isEmpty || holds <= 0 || !seen.add('${team['id_team']}:$key')) continue;
        final entry = players.putIfAbsent(key, () => {
          'name': name, 'player_key': key, 'year': year, 'value': 0,
          'unit': 'ホールド', 'team': team['team'],
          'color_back': team['color_back'], 'color_font': team['color_font'],
          'status': 'active',
        });
        entry['value'] = usageInt(entry['value']) + holds;
      }
    }
  }
  final rows = players.values.toList()..sort((a,b) => usageInt(b['value']).compareTo(usageInt(a['value'])));
  if (rows.isEmpty) return [];
  final best = rows.first['value'];
  return [for (final row in rows) if (row['value'] == best) {...row, 'value': '$best'}];
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
  final leagueWinners = <int, Map<int,int>>{};
  for(final g in games) {
    if (!['LCS','ALCS','NLCS'].contains(g['code_game']) || !'${g['state']}'.contains('終了')) continue;
    final h = usageInt(g['score_home']), a = usageInt(g['score_away']);
    if(h == a) continue;
    final tally = leagueWinners.putIfAbsent(usageInt(g['year']), () => {});
    final winner = usageInt(g[h > a ? 'id_team_home' : 'id_team_away']);
    tally[winner] = (tally[winner] ?? 0) + 1;
  }
  final seasons = <int, Map<String, dynamic>>{};
  for (final r in rows) {
    final year = usageInt(r['year']), team = usageInt(r['id_team']);
    final required = org == OrgKind.mlb && [1903, 1919, 1920, 1921].contains(year) ? 5 : 4;
    final singleLeague = org == OrgKind.npb && year >= 1936 && year <= 1949;
    final champion = singleLeague ? usageInt(r['int_rank']) == 1 : (wins[year]?[team] ?? 0) >= required;
    final s = seasons.putIfAbsent(year, () => {'year': year, 'champion': null, 'leagues': <Map<String, dynamic>>[]});
    if (champion) s['champion'] = r['name'];
    final leagueName = _league(org, usageInt(r['id_league']), year);

    final label = leagueName;
    final leagues = s['leagues'] as List<Map<String, dynamic>>;
    var league = leagues.where((l) => l['name'] == label).firstOrNull;
    if (league == null) {
      league = {'id_league': r['id_league'], 'name': label, 'teams': <Map<String, dynamic>>[]};
      leagues.add(league);
    }
    (league['teams'] as List).add({'id_team': team, 'manager': r['manager'], 'historical_identity': r['historical_identity'], 'logo_url': r['logo_url'], 'color_back': r['color_back'], 'color_font': r['color_font'], 'name_shortest': r['name_shortest'], 'league_champion': org == OrgKind.npb || year < 1969 ? usageInt(r['int_rank']) == 1 : (leagueWinners[year]?[team] ?? 0) >= (year < 1985 ? 3 : 4), 'rank': r['int_rank'], 'name': r['name'], 'short_name': r['short_name'] ?? r['name'], 'wins': r['int_win'], 'losses': r['int_lose'], 'draws': r['int_draw'], 'postseason': entrants[year]?.contains(team) ?? false, 'champion': champion});
  }
  for (final s in seasons.values) {
    for (final l in s['leagues']) {
      (l['teams'] as List).sort((a, b) => usageInt(a['rank']).compareTo(usageInt(b['rank'])));
    }
  }
  if (org == OrgKind.npb) addTimelineCs(seasons.values.toList(), games);
  return seasons.values.toList()..sort((a, b) => usageInt(b['year']).compareTo(usageInt(a['year'])));
}

/// Replace annual aggregates only when official phase standings are available.
List<Map<String, dynamic>> applySplitRecordStandings(
    List<Map<String, dynamic>> annual, List<Map<String, dynamic>> phases) {
  String identity(dynamic name) {
    final normalized = '$name'.replaceAll(RegExp(r'[\s・･]'), '');
    return ['大東京', 'ライオン'].contains(normalized) ? '大東京/ライオン' : normalized;
  }
  return [for (final season in annual) ...(() {
    final parts = phases.where((p) => p['year'] == season['year']).toList()
      ..sort((a, b) => (a['phase'] == 'spring' ? 0 : 1).compareTo(b['phase'] == 'spring' ? 0 : 1));
    if (parts.isEmpty) return [season];
    final previous = usageMaps(season['leagues']).expand((l) => usageMaps(l['teams'])).toList();
    return parts.map((part) {
      final teams = usageMaps(part['teams']).map((team) {
        final old = previous.where((t) => identity(t['name']) == identity(team['name'])).firstOrNull;
        return <String, dynamic>{
          if (old != null) ...old,
          ...team, 'short_name': team['name'], 'historical_identity': true,
          if (old != null && old['name'] != team['name'] && team['logo_url'] == null) 'logo_url': null,
          'champion': team['rank'] == 1, 'league_champion': team['rank'] == 1,
        };
      }).toList()..sort((a, b) => usageInt(a['rank']).compareTo(usageInt(b['rank'])));
      return <String, dynamic>{
        ...season, 'phase': part['phase'],
        'phase_label': part['phase'] == 'spring' ? '春季' : '秋季',
        'source': part['source'], 'champion': teams.where((t) => t['champion'] == true).firstOrNull?['name'],
        'leagues': [{'id_league': 1, 'name': '日本野球連盟', 'teams': teams}],
      };
    }).toList();
  })()];
}

List<Map<String, dynamic>> mergeRecordAwards(List<Map<String, dynamic>> statistical, List<Map<String, dynamic>> awards, int throughYear) {
  String name(Object? value) => '${value ?? ''}'.replaceAll(RegExp(r'[\s　・.]'), '').toLowerCase();
  bool hasValue(Map<String, dynamic> p) => double.tryParse('${p['value'] ?? ''}') != null;
  String label(Object? value) {
    final text = '$value'.replaceAll('賞', '');
    return const {
      '最多安打者': '最多安打', '最多本塁打者': '本塁打王', '最多本塁打': '本塁打王',
      '最多打点者': '打点王', '最多打点': '打点王', '最多盗塁者': '盗塁王', '最多盗塁': '盗塁王',
      '最高出塁率者': '最高出塁率', '最優秀防御率投手': '最優秀防御率',
      '最多勝利投手': '最多勝利', '最多セーブ投手': '最多セーブ',
      '最優秀中継ぎ投手': '最優秀中継ぎ', '最多三振奪取投手': '最多奪三振', '最多奪三振投手': '最多奪三振',
    }[text] ?? '$value';
  }
  final bySeason = {for (final s in statistical) '${s['year']}:${s['league']}': s};
  for (final award in awards) {
    if (usageInt(award['year']) > throughYear) continue;
    final key = '${award['year']}:${award['league']}';
    final season = bySeason.putIfAbsent(key, () => {...award, 'categories': <Map<String, dynamic>>[]});
    final categories = usageMaps(season['categories']);
    for (final c in usageMaps(award['categories'])) {
      final title = label(c['label']);
      final stats = categories.where((old) => label(old['label']) == title)
          .expand((old) => usageMaps(old['players'])).toList();
      final players = usageMaps(c['players']).map((p) {
        final matches = stats.where((s) =>
            p['id_player'] != null && s['id_player'] != null
                ? '${p['id_player']}' == '${s['id_player']}'
                : name(p['name']).isNotEmpty && name(p['name']) == name(s['name']));
        final stat = matches.where(hasValue).firstOrNull;
        return {...p, if (!hasValue(p) && stat != null) ...{
          'value': stat['value'], 'unit': stat['unit'], 'id_player': stat['id_player'],
        }};
      }).toList();
      categories.removeWhere((old) => label(old['label']) == title);
      categories.add({...c, 'label': title, 'players': players});
    }
    season['categories'] = categories;
    season['provisional'] = false;
  }
  return bySeason.values.toList()..sort((a, b) => usageInt(b['year']).compareTo(usageInt(a['year'])));
}

/// Match historical awards to the team in that season, never the player's current team.
List<Map<String, dynamic>> colorRecordTitles(List<Map<String, dynamic>> seasons,
    List<Map<String, dynamic>> teams, List<Map<String, dynamic>> stats) {
  String normalized(Object? value) => '${value ?? ''}'
      .replaceAll(RegExp(r'[\s　()（）・.]'), '').toLowerCase();
  String alias(Object? value) {
    final name = normalized(value);
    return const {'読売': '巨人', 'イーグルス': '楽天', '東北楽天': '楽天'}[name] ?? name;
  }
  for (final season in seasons) {
    final year = '${season['year']}';
    final seasonTeams = teams.where((t) => '${t['year']}' == year).toList();
    final categories = usageMaps(season['categories']);
    season['categories'] = categories;
    for (final category in categories) {
      final players = usageMaps(category['players']);
      category['players'] = players;
      for (final player in players) {
        final teamName = alias(player['team']);
        final candidates = seasonTeams.where((t) {
          if (player['id_team'] != null) return t['id_team'] == player['id_team'];
          if (teamName.isEmpty) return false;
          return ['name', 'short_name', 'name_shortest'].any((key) {
            final name = alias(t[key]);
            return name.isNotEmpty && (name == teamName || name.startsWith(teamName));
          });
        }).toList();
        Map<String, dynamic>? source = candidates.length == 1 ? candidates.single : null;
        if (source == null) {
          final matches = stats.where((s) => '${s['year']}' == year &&
              normalized(s['name']) == normalized(player['name'])).toList();
          if (matches.isNotEmpty && matches.map((s) => s['id_team']).toSet().length == 1) {
            source = matches.first;
          }
        }
        if (source != null) {
          for (final field in ['id_team', 'color_back', 'color_font']) {
            if (source[field] != null) player[field] = source[field];
          }
          // 資料ごとの表記ではなく、受賞年度の球団マスターの略称に統一する。
          final identity = seasonTeams.where((t) => t['id_team'] == source!['id_team']).firstOrNull;
          final displayName = [identity?['short_name'], identity?['name'], source['short_name'], source['team']]
              .map((value) => '${value ?? ''}'.trim()).where((value) => value.isNotEmpty).firstOrNull;
          if (displayName != null) player['team'] = displayName;
        }
      }
    }
  }
  return seasons;
}
