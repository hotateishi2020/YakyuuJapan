import 'dart:convert';
import 'dart:io';
import 'QualifiedPitchingMetrics.dart';
import 'GoldenGloveStats.dart';
import 'package:postgres/postgres.dart';
import 'ClubData.dart';
import 'StrengthUsage.dart';
import 'RecentPlayerGames.dart';
import 'MlbPlayerGames.dart';

Map<String, dynamic> detailMap(dynamic v) => v is String ? usageMap(jsonDecode(v)) : usageMap(v);
String normalizedPlayerName(dynamic v) => usageName('$v').replaceAll(RegExp(r'\(.*\)$'), '');
String? officialPlayerId(Map<String, dynamic> p) => p['official_source_player_id']?.toString() ?? RegExp(r'/players/(\d+)\.html').firstMatch('${p['url']}')?[1];

String? playerWikipediaUrl(Map<String, dynamic> person) {
  final id = officialPlayerId(person);
  if (id == null || !RegExp(r'^\d+$').hasMatch(id)) return null;
  final root = Directory('data').existsSync() ? 'data' : 'backend/data';
  final file = File('$root/player-art-npb-v3/$id.json');
  if (!file.existsSync()) return null;
  try {
    final saved = detailMap(jsonDecode(file.readAsStringSync()));
    final research = detailMap(saved['research']);
    for (final source in (research['sources'] as List? ?? const [])) {
      final uri = Uri.tryParse('$source');
      if (uri != null && uri.scheme == 'https' && uri.host.endsWith('.wikipedia.org') && uri.path.startsWith('/wiki/')) {
        return uri.toString();
      }
    }
  } catch (_) {/* A missing research file must not break player details. */}
  return null;
}

/// Never resolve ambiguous names across clubs. Stable IDs take precedence.
Map<String, dynamic>? matchPlayer(Map<String, dynamic> wanted, List<Map<String, dynamic>> players) {
  final id = usageInt(wanted['id_player']);
  if (id > 0) return players.where((p) => usageInt(p['id']) == id).firstOrNull;
  final source = '${wanted['source_player_id'] ?? ''}';
  final hits = players.where((p) => source.isNotEmpty ? officialPlayerId(p) == source : normalizedPlayerName(p['name_full']) == normalizedPlayerName(wanted['name'])).where((p) => wanted['id_team'] == null || '${wanted['id_team']}' == '${p['id_team']}').toList();
  return hits.length == 1 ? hits.single : null;
}

Future<void> attachOfficialIdentity(Connection conn, int year, List<Map<String, dynamic>> people) async {
  final rows = await conn.execute("SELECT t.id_team,p->>'name' AS name,p->>'source_player_id' AS source_player_id,p->>'date_birth' AS date_birth FROM t_team_strength t CROSS JOIN LATERAL jsonb_array_elements(COALESCE(t.payload->'roster','[]'::jsonb)) p WHERE t.int_year=\$1", parameters: [year]);
  final byName = <String, List<Map<String, dynamic>>>{};
  final byBirth = <String, List<Map<String, dynamic>>>{};
  for (final p in people) {
    byName.putIfAbsent('${p['id_team']}:${normalizedPlayerName(p['name_full'])}', () => []).add(p);
    if (p['date_birth'] != null) {
      byBirth.putIfAbsent('${p['id_team']}:${'${p['date_birth']}'.split(' ').first}', () => []).add(p);
    }
  }
  for (final row in rows) {
    final p = row.toColumnMap();
    if (p['source_player_id'] == null) continue;
    final matches = <Map<String, dynamic>>{
      ...?byName['${p['id_team']}:${normalizedPlayerName(p['name'])}'],
      if (p['date_birth'] != null) ...?byBirth['${p['id_team']}:${p['date_birth']}'],
    };
    if (matches.length == 1) {
      matches.single['official_source_player_id'] = p['source_player_id'];
    }
  }
}

Future<List<Map<String, dynamic>>> extraStatRows(Connection conn, int year, List<int> leagues, {List<Map<String, dynamic>>? knownPeople}) async {
  final data = readClubFile('player-metrics-$year.json');
  final people = knownPeople ?? (await conn.execute('SELECT p.id,p.name_full,p.url,p.date_birth::date::text,p.id_team,p.txt_position,t.id_league,t.name_shortest AS name_team,t.color_back,t.color_font FROM m_player p JOIN m_team t ON t.id=p.id_team WHERE t.id_league=ANY(\$1::int[]) AND NOT COALESCE(p.flg_delete,false)', parameters: [leagues])).map((r) => r.toColumnMap()).toList();
  if (knownPeople == null) await attachOfficialIdentity(conn, year, people);
  final bySource = <String, List<Map<String, dynamic>>>{};
  final byName = <String, List<Map<String, dynamic>>>{};
  for (final p in people) {
    final source = officialPlayerId(p);
    if (source != null) bySource.putIfAbsent(source, () => []).add(p);
    byName.putIfAbsent(normalizedPlayerName(p['name_full']), () => []).add(p);
  }
  final rows = <Map<String, dynamic>>[];
  for (final p in usageMaps(data['players'])) {
    final expected = p['org'] == 'mlb' ? [3, 4] : [1, 2];
    final source = '${p['source_player_id'] ?? ''}';
    final candidates = source.isNotEmpty ? bySource[source] : byName[normalizedPlayerName(p['name'])];
    final match = matchPlayer(p, (candidates ?? []).where((r) => expected.contains(r['id_league'])).toList());
    if (match == null) continue;
    for (final s in usageMaps(p['metrics'])) {
      if (s['title'] == '盗塁阻止率') continue;
      rows.add({...match, 'id_player': match['id'], 'name_player': match['name_full'], 'int_year': year, ...s, if (s['title'] == '盗塁阻止数') 'catcher_metric': true, 'id_users': null, 'colors_user': null, 'colors': null, 'id_stats': null, 'int_rank': 1000, 'source': s['source'] ?? p['source'], 'checked_at': data['checked_at']});
    }
  }
  if (leagues.any((league) => league == 1 || league == 2)) {
    final activePlayers = await goldenGloveSeasonPlayers(conn, year, leagues);
    rows.addAll(goldenGloveRows(year, activePlayers));
    rows.addAll(goldenGloveRows(year, activePlayers, pitching: true));
  }
  final qualificationGames = await readQualificationGames(conn, year);
  retainQualifiedPitchingRates(rows, qualificationGames);
  retainCatcherCounts(rows);
  for (final title in rows.map((r) => '${r['title']}').toSet())
    for (final league in leagues)
    for (final role in title == 'GG受賞回数' ? <bool?>[false, true] : <bool?>[null]) {
      final group = rows.where((r) => r['title'] == title && r['id_league'] == league &&
        (role == null || r['flg_pitcher'] == role)).toList();
      group.sort((a, b) {
        final av = num.tryParse('${a['numeric_value']}'), bv = num.tryParse('${b['numeric_value']}');
        if (av == null) return bv == null ? 0 : 1;
        if (bv == null) return -1;
        return ['BB/9', '四球/9', '四死球/9'].contains(title) ? av.compareTo(bv) : bv.compareTo(av);
      });
      num? prev;
      var rank = 0;
      for (var i = 0; i < group.length; i++) {
        final value = num.tryParse('${group[i]['numeric_value']}');
        if (value == null) continue;
        if (value != prev) rank = i + 1;
        group[i]['int_rank'] = rank;
        prev = value;
      }
    }
  return rows;
}

Future<Map<String, dynamic>> readPlayerDetail(Connection conn, {required int year, required List<int> leagues, required Map<String, dynamic> identity, PlayerDetailBatch? batch}) async {
  final people = batch?.people ?? (await conn.execute('''SELECT p.id,p.name_full,p.url,p.id_team,p.txt_position,p.date_birth::text,p.height,p.weight,p.pitching,p.batting,p.uniform_number,c.name AS birth_country,b.name AS birth_place,t.name_short AS name_team,t.color_back,t.color_font,t.id_league FROM m_player p JOIN m_team t ON t.id=p.id_team LEFT JOIN m_country c ON c.id=p.id_country LEFT JOIN m_place_birth b ON b.id=p.id_place_birth WHERE t.id_league=ANY(\$1::int[]) AND NOT COALESCE(p.flg_delete,false)''', parameters: [leagues])).map((r) => r.toColumnMap()).toList();
  if (batch == null) await attachOfficialIdentity(conn, year, people);
  final person = matchPlayer(identity, people);
  if (person == null) {
    return {'found': false, 'message': '選手を一意に特定できませんでした。球団・選手IDが確認できる画面から開いてください。'};
  }
  if (!leagues.contains(3) && officialPlayerId(person) != null) {
    person['url'] ??= 'https://npb.jp/bis/players/${officialPlayerId(person)}.html';
  }
  final id = person['id'];
  final careers = batch?.careers.where((r) => r['id_player'] == id).toList() ?? (await conn.execute('SELECT to_jsonb(c) || jsonb_build_object(\'name_team\',t.name_short) FROM m_player_career c LEFT JOIN m_team t ON t.id=c.id_team WHERE c.id_player=\$1 AND c.int_year<=\$2 AND NOT COALESCE(c.flg_delete,false) ORDER BY c.int_year DESC,c.id', parameters: [id, year])).map((r) => detailMap(r[0])).toList();
  final stats = batch?.stats.where((r) => r['id_player'] == id).map((r) => Map<String, dynamic>.from(r)).toList() ?? (await conn.execute('SELECT payload FROM v_stats_player WHERE int_year=\$1 AND (payload->>\'id_player\')::int=\$2 ORDER BY row_no', parameters: [year, id])).map((r) => detailMap(r[0])).toList();
  final extra = batch?.extra ?? await extraStatRows(conn, year, leagues);
  stats.addAll(extra.where((r) => r['id_player'] == id));
  addMissingRequestedMetrics(stats);
  final games = batch?.games?[id]?.map((r) => Map<String, dynamic>.from(r)).toList() ?? (batch?.games != null ? <Map<String, dynamic>>[] : (await conn.execute('''
 WITH recent AS MATERIALIZED (
 SELECT g.id,g.datetime_start,g.code_game,g.state,g.score_home,g.score_away,h.name_short AS home,a.name_short AS away,jsonb_agg(to_jsonb(s) ORDER BY s.id) AS lines
 FROM t_game_summary s JOIN t_game g ON g.id=s.id_game JOIN m_team h ON h.id=g.id_team_home JOIN m_team a ON a.id=g.id_team_away
 WHERE s.id_player=\$1 AND g.datetime_start<make_date(\$2+1,1,1) AND (g.state LIKE '%終了%' OR g.state LIKE '%コールド%') AND NOT COALESCE(g.flg_delete,false) AND NOT COALESCE(s.flg_delete,false)
 GROUP BY g.id,h.name_short,a.name_short ORDER BY g.datetime_start DESC,g.id DESC LIMIT 25
 ), plays AS (
 SELECT d.id_game,jsonb_agg(jsonb_build_object('inning',d.int_inning,'bottom',d.flg_bottom,'result',d.code_result,'bases',d.double_total_bases,'rbi',d.int_runs) ORDER BY d.id) AS plays
 FROM t_game_details d WHERE d.id_batter=\$1 AND d.id_game IN (SELECT id FROM recent) AND NOT COALESCE(d.flg_delete,false) GROUP BY d.id_game
 ) SELECT r.id,r.datetime_start::text,r.code_game,r.state,r.score_home,r.score_away,r.home,r.away,r.lines,p.plays FROM recent r LEFT JOIN plays p ON p.id_game=r.id ORDER BY r.datetime_start DESC,r.id DESC
''', parameters: [id, year])).map((r) => r.toColumnMap()).toList());
  if (!leagues.contains(3) && officialPlayerId(person) != null) {
    final official = officialNpbRecentGames(officialPlayerId(person)!, year, snapshot: batch?.npbRecent);
    final dates = official.map((g) => '${g['datetime_start']}'.substring(0, 10)).toSet();
    games.removeWhere((g) => dates.contains('${g['datetime_start']}'.substring(0, 10)));
    games.addAll(official);
    games.sort((a, b) => '${b['datetime_start']}'.compareTo('${a['datetime_start']}'));
    if (games.length > 25) games.removeRange(25, games.length);
  }
  if (leagues.contains(3) && officialPlayerId(person) != null) {
    try {
      final official = await mlbRecentGames(officialPlayerId(person)!, year);
      if (official.isNotEmpty) {
        games.clear();
        games.addAll(official);
      }
    } catch (_) {
      /* Keep verified database records if the official API is unavailable. */
    }
  }
  final strength = batch?.teams.where((r) => r['id_team'] == person['id_team']).toList() ?? (await conn.execute('SELECT payload FROM t_team_strength WHERE int_year=\$1 AND code_org=\$2 AND id_team=\$3', parameters: [year, leagues.contains(3) ? 'mlb' : 'npb', person['id_team']])).map((r) => detailMap(r[0])).toList();
  Map<String, dynamic> roster = {};
  Map<String, dynamic> usage = {};
  for (final team in strength) {
    final matches = usageMaps(team['roster']).where((p) => officialPlayerId(person) != null && '${p['source_player_id']}' == officialPlayerId(person) || '${team['id_team']}' == '${person['id_team']}' && normalizedPlayerName(p['name']) == normalizedPlayerName(person['name_full'])).toList();
    if (matches.length == 1) {
      roster = matches.single;
      for (final key in ['positions', 'pitching_workload', 'batting_stats', 'pitching_stats']) {
        usage[key] = usageMaps(team[key]).where((p) => '${p['player_key']}' == '${roster['player_key']}' || normalizedPlayerName(p['name']) == normalizedPlayerName(person['name_full'])).toList();
      }
      usage['positions'] = [
        for (final group in usageMaps(team['positions']))
          for (final p in usageMaps(group['players']))
            if (p['player_key'] == roster['player_key'] || normalizedPlayerName(p['name']) == normalizedPlayerName(person['name_full'])) {...p, 'slot': group['label'] ?? group['slot'], 'total': group['total']}
      ];
      roster = {...roster, 'contract_data': usageMaps(team['contracts']).where((p) => p['player_key'] == roster['player_key']).firstOrNull ?? {}};
      break;
    }
  }
  final supplement = usageMaps((batch?.profiles ?? readClubFile('player-profiles-$year.json'))['players']).where((p) => p['org'] == (leagues.contains(3) ? 'mlb' : 'npb') && '${p['source_player_id']}' == officialPlayerId(person)).firstOrNull ?? {};
  return {'found': true, 'year': year, 'profile': person, 'wikipedia_url': playerWikipediaUrl(person), 'season_stats': stats, 'careers': careers, 'recent_games': games, 'roster': roster, 'usage': usage, 'verified': supplement, 'recent_note': '公式ボックススコア・取得済みの終了試合から直近25試合。未取得の試合は含みません。'};
}

void addMissingRequestedMetrics(List<Map<String, dynamic>> rows) {
  const pitching = {'防御率', '最多勝', '奪三振', 'HP', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'K/BB', 'QS率', 'BB/9', '四死球/9', '平均投球回', '投球回数', '登板回数'};
  final players = <String, Map<String, dynamic>>{};
  final known = <String>{};
  for (final r in rows) {
    final pitcher = r['flg_pitcher'] == true || pitching.contains(r['title']);
    final key = '${r['id_player']}:$pitcher';
    players.putIfAbsent(key, () => {...r, 'flg_pitcher': pitcher});
    known.add('$key:${r['title']}');
  }
  for (final e in players.entries) {
    final p = e.value;
    final isPitcher = p['flg_pitcher'] == true;
    for (final title in isPitcher ? ['BB/9', '四死球/9', '平均投球回', '投球回数', '登板回数'] : ['ボール球見極め率', '代打起用数', '代打打率', '盗塁阻止数', '打席数']) {
      if (qualifiedPitchingRateTitles.contains(title) || title == '盗塁阻止数') continue;
      if (!known.contains('${e.key}:$title')) {
        rows.add({...p, 'title': title, 'stats': '—', 'numeric_value': null, 'int_rank': 1000, 'id_users': null, 'colors_user': null, 'colors': null, 'note': '当年度の確認済みデータがありません。', 'id_stats': null, 'source': null});
      }
    }
  }
}

/// Shared season inputs loaded once per scheduled batch, not once per player.
class PlayerDetailBatch {
  final List<Map<String, dynamic>> people, careers, stats, extra, teams;
  Map<int, List<Map<String, dynamic>>>? games;
  Map<String, dynamic> npbRecent = {}, profiles = {};
  PlayerDetailBatch(this.people, this.careers, this.stats, this.extra, this.teams);

  /// Keep only the current processing group in memory, including past seasons.
  Future<void> loadPlayerGroup(Connection conn, int year, List<int> ids) async {
    careers.clear();
    games = {};
    if (ids.isEmpty) return;
    final rows = await conn.execute("SELECT to_jsonb(c) || jsonb_build_object('name_team',t.name_short) FROM m_player_career c LEFT JOIN m_team t ON t.id=c.id_team WHERE c.id_player=ANY(\$1::int[]) AND c.int_year<=\$2 AND NOT COALESCE(c.flg_delete,false) ORDER BY c.int_year DESC,c.id", parameters: [ids, year]);
    careers.addAll(rows.map((r) => detailMap(r[0])));
    await loadRecentGames(conn, year, ids);
  }

  Future<void> loadRecentGames(Connection conn, int year, List<int> ids) async {
    final rows = await conn.execute('''WITH grouped AS (
      SELECT s.id_player,g.id,g.datetime_start,g.code_game,g.state,g.score_home,g.score_away,
      h.name_short AS home,a.name_short AS away,jsonb_agg(to_jsonb(s) ORDER BY s.id) AS lines,
      row_number() OVER (PARTITION BY s.id_player ORDER BY g.datetime_start DESC,g.id DESC) AS rn
      FROM t_game_summary s JOIN t_game g ON g.id=s.id_game
      JOIN m_team h ON h.id=g.id_team_home JOIN m_team a ON a.id=g.id_team_away
      WHERE s.id_player=ANY(\$1::int[]) AND g.datetime_start>=make_date(\$2,1,1) AND g.datetime_start<make_date(\$2+1,1,1)
      AND (g.state LIKE '%終了%' OR g.state LIKE '%コールド%') AND NOT COALESCE(g.flg_delete,false) AND NOT COALESCE(s.flg_delete,false)
      GROUP BY s.id_player,g.id,h.name_short,a.name_short
    ), recent AS MATERIALIZED (SELECT * FROM grouped WHERE rn<=25), plays AS (
      SELECT d.id_batter,d.id_game,jsonb_agg(jsonb_build_object('inning',d.int_inning,'bottom',d.flg_bottom,'result',d.code_result,'bases',d.double_total_bases,'rbi',d.int_runs) ORDER BY d.id) AS plays
      FROM t_game_details d JOIN recent r ON r.id=d.id_game AND r.id_player=d.id_batter
      WHERE NOT COALESCE(d.flg_delete,false) GROUP BY d.id_batter,d.id_game
    ) SELECT r.id_player,r.id,r.datetime_start::text,r.code_game,r.state,r.score_home,r.score_away,r.home,r.away,r.lines,p.plays
    FROM recent r LEFT JOIN plays p ON p.id_game=r.id AND p.id_batter=r.id_player ORDER BY r.datetime_start DESC,r.id DESC''', parameters: [ids, year]);
    games = {};
    for (final row in rows) {
      final r = row.toColumnMap();
      games!.putIfAbsent(r['id_player'] as int, () => []).add(r);
    }
  }

  static Future<PlayerDetailBatch> load(Connection conn, int year, {required List<int> playerIds}) async {
    final people = (await conn.execute("SELECT p.id,p.name_full,p.url,p.id_team,p.txt_position,p.date_birth::text,p.height,p.weight,p.pitching,p.batting,p.uniform_number,c.name AS birth_country,b.name AS birth_place,t.name_short AS name_team,t.color_back,t.color_font,t.id_league FROM m_player p JOIN m_team t ON t.id=p.id_team LEFT JOIN m_country c ON c.id=p.id_country LEFT JOIN m_place_birth b ON b.id=p.id_place_birth WHERE t.id_league IN (1,2,3,4) AND NOT COALESCE(p.flg_delete,false) AND p.id=ANY(\$1::int[])", parameters: [playerIds])).map((r) => r.toColumnMap()).toList();
    await attachOfficialIdentity(conn, year, people);
    final careers = <Map<String, dynamic>>[];
    final stats = (await conn.execute('SELECT payload FROM v_stats_player WHERE int_year=\$1 AND (payload->>\'id_player\')::int=ANY(\$2::int[]) ORDER BY row_no', parameters: [year, playerIds])).map((r) => detailMap(r[0])).toList();
    final teams = (await conn.execute("SELECT jsonb_build_object('id_team',id_team,'roster',payload->'roster','positions',payload->'positions','pitching_workload',payload->'pitching_workload','batting_stats',payload->'batting_stats','pitching_stats',payload->'pitching_stats','contracts',payload->'contracts') FROM t_team_strength WHERE int_year=\$1", parameters: [year])).map((r) => detailMap(r[0])).toList();
    final extra = await extraStatRows(conn, year, [1, 2, 3, 4], knownPeople: people);
    return PlayerDetailBatch(people, careers, stats, extra, teams)
      ..npbRecent = readClubFile('npb-recent-games-$year.json')
      ..profiles = readClubFile('player-profiles-$year.json');
  }
}
