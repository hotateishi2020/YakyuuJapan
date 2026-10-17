import 'ScheduledLog.dart';
import 'RosterBirthplaces.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import '../tools/Postgres.dart';
import 'StrengthUsage.dart';
import 'StrengthMetrics.dart';
import 'LowerLevelUsage.dart';
import 'SeasonUsageEvidence.dart';

/// 戦力タブは登録済みJSONを読むだけ。外部サイト取得・集計はrefreshで行う。
class TeamStrength {
  static Timer? _timer;
  static bool _busy = false;
  static bool _ensured = false;

  static Future<void> ensure(Connection conn) async {
    if (_ensured) return;
    final existing = await conn.execute("SELECT to_regclass('public.t_team_strength') IS NOT NULL");
    if (existing.isNotEmpty && existing.first[0] == true) {
      _ensured = true;
      return;
    }
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS t_team_strength (
        int_year integer NOT NULL,
        code_org text NOT NULL,
        id_team integer NOT NULL,
        payload jsonb NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT NOW(),
        PRIMARY KEY (int_year, code_org, id_team)
      )
    ''');
    _ensured = true;
  }

  /// リクエスト経路。DDL・再集計・外部HTTPは呼び出さない。
  static Future<Map<String, dynamic>> read(Connection conn, {required String org, required int year}) async {
    final rows = await conn.execute('''
      SELECT payload || jsonb_build_object('updated_at', updated_at)
      FROM t_team_strength
      WHERE int_year = \$1 AND code_org = \$2
      ORDER BY id_team
    ''', parameters: [year, org]);
    return {
      'org': org,
      'year': year,
      'teams': [for (final row in rows) _map(row[0])],
    };
  }

  /// 起動直後の取得は行わない。初回登録は管理CLI、以後6時間ごとに更新。
  static void start({void Function()? onUpdated}) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 6), (_) async {
      try {
        await ScheduledLog.run('team_strength', () async {
          final result = await refresh(year: DateTime.now().year);
          if (_int(result['registered']) > 0) onUpdated?.call();
          final errors = result['errors'];
          if (errors is List && errors.isNotEmpty) {
            throw StateError(errors.join(' / '));
          }
          return result;
        });
      } catch (error) {
        print('戦力データ定期登録に失敗: $error');
      }
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 外部取得中はDB接続を保持しない。成功した球団だけを置き換える。
  static Future<Map<String, dynamic>> refresh({required int year, String? org}) async {
    if (_busy) return {'registered': 0, 'busy': true, 'errors': <String>[]};
    if (year < 2005 || year > DateTime.now().year) {
      throw ArgumentError.value(year, 'year', '2005年以降の表示年を指定してください');
    }
    _busy = true;
    final client = http.Client();
    final errors = <String>[];
    var registered = 0;
    try {
      final teams = await Postgres.withConnection((conn) async {
        await ensure(conn);
        return Postgres.toJson(await conn.execute('''
          SELECT id AS id_team, id_league, name_short AS name_team,
            name_shortest, color_back, color_font
          FROM m_team WHERE id_league IN (1,2,3,4)
            AND COALESCE(flg_delete, FALSE) = FALSE
          ORDER BY id
        '''));
      });
      if (org == null || org == 'npb') {
        final usageGames = await StrengthUsage.npbGames(client, year);
        List<Map<String, dynamic>>? lowerGames;
        try {
          lowerGames = await LowerLevelUsage.fetch(client, year);
        } catch (error) {
          errors.add('2軍起用記録: $error');
        }
        final announcements = await fetchNpbStatusAnnouncements(client, year);
        final npb = teams.where((team) => _int(team['id_league']) <= 2 && npbStrengthSources.containsKey(team['name_team'])).toList();
        for (var offset = 0; offset < npb.length; offset += 3) {
          final batch = npb.skip(offset).take(3);
          final payloads = await Future.wait(batch.map((team) async {
            final name = '${team['name_team']}';
            final source = npbStrengthSources[name]!;
            final lineupUrl = 'https://sta-men.jp/$year${source.$1}.html';
            final pitchingUrl = 'https://npb.jp/bis/$year/stats/idp1_${source.$2}.html';
            try {
              final pages = await Future.wait([
                _fetchHtml(client, lineupUrl),
                _fetchHtml(client, pitchingUrl),
              ]);
              final payload = buildNpbTeamStrength(
                team: team,
                year: year,
                lineupHtml: pages[0],
                pitchingHtml: pages[1],
                lineupUrl: lineupUrl,
                pitchingUrl: pitchingUrl,
              );
              return await enrichNpbUsage(client, payload, year, source.$2, usageGames, announcements: announcements);
            } catch (error) {
              errors.add('$name: $error');
              return null;
            }
          }));
          final valid = payloads.whereType<Map<String, dynamic>>().toList();
          if (lowerGames != null) {
            await LowerLevelUsage.save(year, valid, lowerGames, {for (final e in npbStrengthSources.entries) e.key: e.value.$2});
          }
          registered += await _save('npb', year, valid);
        }
      }
      if (org == null || org == 'mlb') {
        try {
          final payloads = await _fetchMlb(client, teams, year);
          registered += await _save('mlb', year, payloads);
        } catch (error) {
          errors.add('MLB: $error');
        }
      }
      return {'year': year, 'org': org ?? 'all', 'registered': registered, 'errors': errors};
    } finally {
      client.close();
      _busy = false;
    }
  }

  static Future<int> _save(String org, int year, List<Map<String, dynamic>> teams) async {
    if (teams.isEmpty) return 0;
    final metricsClient = http.Client();
    try {
      for (final team in teams) {
        team['defense_substitutions'] = defenseSubstitutionBands(_maps(team['substitutions']));
        team.addAll(await fetchStrengthMetrics(metricsClient, team, year, org, npbCode: npbStrengthSources['${team['name_team']}']?.$2));
      }
      await enrichSeasonEvidence(metricsClient, year, org, teams, {for (final e in npbStrengthSources.entries) e.key: e.value.$2});
    } finally {
      metricsClient.close();
    }
    await StrengthUsage.attachStatuses(org, year, teams);
    await Postgres.withConnection((conn) => attachRosterBirthplaces(conn, teams));
    if (org == 'npb') await fillNpbBirthplaces(teams);
    await Postgres.withConnection((conn) => conn.runTx((tx) async {
          await StrengthUsage.saveTotals(tx, org, year, teams);
          await tx.execute('''
        INSERT INTO t_team_strength (int_year, code_org, id_team, payload)
        SELECT \$1::integer, \$2::text, (payload->>'id_team')::integer, payload
        FROM jsonb_array_elements(\$3::jsonb) AS rows(payload)
        ON CONFLICT (int_year, code_org, id_team) DO UPDATE
        SET payload = t_team_strength.payload || EXCLUDED.payload, updated_at = NOW()
      ''', parameters: [year, org, jsonEncode(teams)]);
        }));
    for (final team in teams) {
      print('戦力登録 $org/$year ${team['name_team']}: '
          'スタメン${team['lineup_game_count']}試合');
    }
    return teams.length;
  }

  static Future<List<Map<String, dynamic>>> _fetchMlb(http.Client client, List<Map<String, dynamic>> dbTeams, int year) async {
    const api = 'https://statsapi.mlb.com/api/v1';
    final lineupsUrl = '$api/schedule?sportId=1&season=$year&gameTypes=R&hydrate=lineups'
        '&fields=dates,date,games,gamePk,status,abstractGameState,detailedState,reason,officialDate,teams,'
        'away,home,team,id,lineups,homePlayers,awayPlayers,fullName,primaryPosition,code,abbreviation';
    final pages = await Future.wait([
      _fetchJson(client, '$api/teams?sportId=1&season=$year'),
      _fetchJson(client, '$api/teams/stats?stats=season&group=hitting&season=$year&sportIds=1'),
      _fetchJson(client, lineupsUrl),
      _fetchJson(
          client,
          '$api/sports/1/players?season=$year'
          '&fields=people,id,primaryPosition,code,abbreviation'),
    ]);
    final usageGames = await StrengthUsage.mlbGames(client, year, pages[2]);
    final pitcherIds = {
      for (final player in _maps(pages[3]['people']))
        if (const {'P', 'TWP'}.contains(_map(player['primaryPosition'])['abbreviation'])) _int(player['id']),
    };
    if (pitcherIds.isEmpty) throw StateError('MLB公式の投手・二刀流区分を取得できません');
    final byCode = {
      for (final team in dbTeams)
        if (_int(team['id_league']) >= 3 && '${team['name_shortest']}'.length <= 3) '${team['name_shortest']}': team,
    };
    final result = <Map<String, dynamic>>[];
    final sourceTeams = _maps(pages[0]['teams']);
    for (var offset = 0; offset < sourceTeams.length; offset += 5) {
      final batch = await Future.wait(sourceTeams.skip(offset).take(5).map((source) async {
        final code = '${source['abbreviation']}';
        final team = byCode[code];
        if (team == null) return null;
        final teamId = _int(source['id']);
        // 全選手seasonは移籍前後を合算するため、必ず球団ごとに取得する。
        final stats = await _fetchJson(
            client,
            '$api/stats?stats=season&group=pitching,fielding,hitting&season=$year'
            '&sportIds=1&teamId=$teamId&playerPool=ALL&limit=5000'
            '&fields=stats,group,displayName,splits,stat,gamesPlayed,gamesStarted,'
            'gamesPitched,saves,holds,inningsPitched,team,id,player,fullName,position,abbreviation');
        List<Map<String, dynamic>> group(String name) => [
              for (final group in _maps(stats['stats']))
                if (_map(group['group'])['displayName'] == name) ..._maps(group['splits']),
            ];
        final payload = buildMlbTeamStrength(
          team: team,
          year: year,
          sourceTeamId: teamId,
          pitching: group('pitching'),
          fielding: group('fielding'),
          teamStats: _splits(pages[1]),
          schedule: pages[2],
          sourceUrl: lineupsUrl,
          pitcherIds: pitcherIds,
        );
        final workload = aggregateUsageGames(usageGames, '$teamId');
        for (final player in workload) {
          player['player_key'] = 'mlb:${player['source_player_id']}';
          final season = group('pitching').where((p) => '${_map(p['player'])['id']}' == '${player['source_player_id']}').firstOrNull;
          if (season != null) {
            final stat = _map(season['stat']);
            if (stat['inningsPitched'] != null && inningsToOuts('${stat['inningsPitched']}') != player['total_outs']) {
              throw StateError('MLB公式投球回と試合別合計が一致しません: ${player['name']}');
            }
            player['saves'] = _int(stat['saves']);
            player['holds'] = _int(stat['holds']);
          }
        }
        final rosterData = await _fetchJson(client, '$api/teams/$teamId/roster?rosterType=fullSeason&season=$year&hydrate=person');
        payload['roster'] = [
          for (final row in _maps(rosterData['roster']))
            {
              'player_key': 'mlb:${_map(row['person'])['id']}',
              'source_player_id': '${_map(row['person'])['id']}',
              'name': _map(row['person'])['fullName'],
              'date_birth': _map(row['person'])['birthDate'],
              'birth_country': _map(row['person'])['birthCountry'],
              'birth_state': _map(row['person'])['birthStateProvince'],
              'birth_place': _map(row['person'])['birthStateProvince'] ?? _map(row['person'])['birthCity'],
              'throws': {'R': '右', 'L': '左', 'S': '両'}[_map(_map(row['person'])['pitchHand'])['code']] ?? '不明',
              'bats': {'R': '右', 'L': '左', 'S': '両'}[_map(_map(row['person'])['batSide'])['code']] ?? '不明',
              'position_group': {'P': '投手', 'TWP': '投手', 'C': '捕手', '1B': '内野手', '2B': '内野手', '3B': '内野手', 'SS': '内野手', 'LF': '外野手', 'CF': '外野手', 'RF': '外野手', 'OF': '外野手', 'DH': '指名打者'}[_map(row['position'])['abbreviation']] ?? '不明',
              'registration': '制度対象外',
              'level_appearances': <String, int>{
                '1': [
                  for (final stat in [...group('pitching'), ...group('hitting')])
                    if ('${_map(stat['player'])['id']}' == '${_map(row['person'])['id']}') _int(_map(stat['stat'])['gamesPlayed'])
                ].fold<int>(0, (a, b) => a > b ? a : b)
              },
              'level_coverage': <int>[1],
            }
        ];
        payload['substitutions'] = substitutionBands(usageGames, '$teamId', org: 'mlb');
        payload['pitching_workload'] = workload;
        payload['pitching_game_count'] = usageGames.where((g) => usageMaps(g['players']).any((p) => p['team_code'] == '$teamId')).length;
        payload['substitution_game_count'] = payload['pitching_game_count'];
        if (payload['pitching_game_count'] != payload['game_count']) {
          throw StateError('MLB球団の公式試合数と投球回取得試合数が一致しません: $teamId');
        }
        return payload;
      }));
      result.addAll(batch.whereType<Map<String, dynamic>>());
    }
    if (result.length != 30) {
      throw StateError('MLB球団対応が30球団に満たないため保存を中止: ${result.length}');
    }
    return result;
  }
}

const npbStrengthSources = <String, (String, String)>{
  '巨人': ('giants', 'g'),
  '阪神': ('tigers', 't'),
  '中日': ('dragons', 'd'),
  'ヤクルト': ('swallows', 's'),
  'DeNA': ('baystars', 'db'),
  '広島': ('carp', 'c'),
  'ソフトバンク': ('hawks', 'h'),
  '西武': ('lions', 'l'),
  '日本ハム': ('fighters', 'f'),
  'オリックス': ('buffaloes', 'b'),
  '楽天': ('eagles', 'e'),
  'ロッテ': ('marines', 'm'),
};

const strengthPositionLabels = <String, String>{
  'P': '投手',
  'C': '捕手',
  '1B': '一塁',
  '2B': '二塁',
  '3B': '三塁',
  'SS': '遊撃',
  'LF': '左翼',
  'CF': '中堅',
  'RF': '右翼',
  'DH': '指名打者',
};

const _positions = <String, String>{
  '1': 'P',
  'P': 'P',
  '2': 'C',
  '3': '1B',
  '4': '2B',
  '5': '3B',
  '6': 'SS',
  '7': 'LF',
  '8': 'CF',
  '9': 'RF',
  'D': 'DH',
  '10': 'DH',
};

/// 指定サイトの試合別スタメンを集計。日付・9打者・先発投手を確認する。
Map<String, dynamic> buildNpbTeamStrength({
  required Map<String, dynamic> team,
  required int year,
  required String lineupHtml,
  required String pitchingHtml,
  required String lineupUrl,
  required String pitchingUrl,
}) {
  final order = <String, Map<String, int>>{};
  final positions = <String, Map<String, int>>{};
  final starts = <String, int>{};
  final seen = <String>{};
  var games = 0;
  for (final row in html.parse(lineupHtml).querySelectorAll('tr')) {
    final cells = row.children.where((cell) => cell.localName == 'td' || cell.localName == 'th').map((cell) => cell.text.replaceAll(RegExp(r'\s+'), '').trim()).toList();
    if (cells.length < 10 || !RegExp('^$year/[0-9]{1,2}/[0-9]{1,2}').hasMatch(cells.first)) {
      continue;
    }
    final lineup = <(String, String)>[];
    for (final cell in cells.skip(1).take(9)) {
      final match = RegExp(r'^([1-9DP])(.+)$').firstMatch(cell);
      if (match == null) break;
      lineup.add((_positions[match.group(1)]!, match.group(2)!));
    }
    if (lineup.length != 9) continue;
    if (!seen.add(cells.take(11).join('|'))) continue;
    var starter = lineup.where((player) => player.$1 == 'P').map((player) => player.$2).firstOrNull;
    if (cells.length > 10 && cells[10].startsWith('P') && cells[10].length > 1) {
      starter = cells[10].substring(1);
    }
    if (starter == null || starter.isEmpty) {
      throw StateError('スタメンの先発投手を確認できません: ${cells.first}');
    }
    games++;
    for (var index = 0; index < lineup.length; index++) {
      _add(order, '${index + 1}', lineup[index].$2);
      _add(positions, lineup[index].$1, lineup[index].$2);
    }
    starts[starter] = (starts[starter] ?? 0) + 1;
    if (!lineup.any((player) => player.$1 == 'P')) {
      _add(positions, 'P', starter);
    }
  }
  if (games == 0) throw StateError('有効なスタメン9人の試合がありません');

  final pitchers = parseNpbPitchers(pitchingHtml);
  if (pitchers.isEmpty) throw StateError('NPB公式の投手成績がありません');
  final unresolved = <String>[];
  final playerAliases = <String, String>{};
  for (final entry in starts.entries) {
    final candidates = _npbPitcherCandidates(pitchers, entry.key);
    if (candidates.length == 1) {
      playerAliases[entry.key] = '${candidates.single['name']}';
      candidates.single['starts'] = _int(candidates.single['starts']) + entry.value;
    } else {
      unresolved.add('${entry.key} ${entry.value}試合');
    }
  }
  if (unresolved.isNotEmpty) {
    throw StateError('先発投手の氏名を一意に照合できません: ${unresolved.join('、')}');
  }
  if (pitchers.fold<int>(0, (total, pitcher) => total + _int(pitcher['starts'])) != games) {
    throw StateError('先発回数と採用試合数が一致しないため更新を保留します');
  }
  if (pitchers.any((pitcher) => _int(pitcher['starts']) > _int(pitcher['appearances']))) {
    throw StateError('先発回数が公式登板数を超えるため更新を保留します');
  }
  return withStrengthPlayerKeys({
    ...team,
    'org': 'npb',
    'year': year,
    'game_count': games,
    'lineup_game_count': games,
    'source_url': lineupUrl,
    'source_label': 'スタメンデータベース / NPB公式',
    'sources': [
      {'label': 'スタメンデータベース', 'url': lineupUrl},
      {'label': 'NPB公式投手成績', 'url': pitchingUrl},
    ],
    'notes': [
      '打順・守備位置の比率は、スタメン9人を確認できた公式戦$games試合を分母に算出。途中出場は含みません。',
      '先発回数は試合別スタメン、登板・セーブ・ホールドはNPB公式成績。指名打者を使わない試合も分母に含みます。',
      ...pitcherRoleNotes,
    ],
    'pitchers': classifyStrengthPitchers(pitchers),
    'batting_order': _groups(order, games, batting: true),
    'positions': _groups(positions, games, batting: false),
  }, playerAliases: playerAliases);
}

List<Map<String, dynamic>> parseNpbPitchers(String source) {
  final result = <Map<String, dynamic>>[];
  for (final table in html.parse(source).querySelectorAll('table')) {
    List<String>? headers;
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.children.where((cell) => cell.localName == 'td' || cell.localName == 'th').toList();
      final texts = cells.map((cell) => cell.text.trim()).toList();
      if (texts.contains('選手') && texts.contains('登板') && texts.contains('セーブ')) {
        headers = texts;
        continue;
      }
      if (headers == null || texts.length != headers.length || cells.first.localName != 'td') {
        continue;
      }
      int value(String name) => _int(texts[headers!.indexOf(name)]);
      final name = texts.first.replaceAll(RegExp(r'^[*＊\s]+'), '').replaceAll(RegExp(r'[\s　]+'), '');
      if (name.isEmpty || value('登板') == 0) continue;
      result.add({
        'name': name,
        'source_surname': texts.first.replaceAll(RegExp(r'^[*＊\s]+'), '').split(RegExp(r'[\s　]+')).first,
        'starts': 0,
        'appearances': value('登板'),
        'saves': value('セーブ'),
        'holds': value('ホールド'),
        if (headers.contains('投球回')) 'official_outs': inningsToOuts(texts[headers.indexOf('投球回')]),
      });
    }
  }
  return result;
}

const pitcherRoleNotes = <String>[
  '先発は先発登板あり、中継ぎは救援登板（登板－先発）ありの投手。両方で登板した投手は重複します。',
  '抑えは球団内の最多セーブ投手（1セーブ以上・同数含む）として分類し、中継ぎから分離。現在の起用予定ではなくシーズン実績です。',
];

Map<String, dynamic> classifyStrengthPitchers(List<Map<String, dynamic>> rows) {
  var mostSaves = 0;
  for (final row in rows) {
    if (_int(row['saves']) > mostSaves) mostSaves = _int(row['saves']);
  }
  final starters = <Map<String, dynamic>>[];
  final relievers = <Map<String, dynamic>>[];
  final closers = <Map<String, dynamic>>[];
  for (final source in rows) {
    final row = {...source, 'relief_appearances': (_int(source['appearances']) - _int(source['starts'])).clamp(0, 1000)};
    row.remove('source_surname');
    if (_int(row['starts']) > 0) starters.add(row);
    final closer = mostSaves > 0 && _int(row['saves']) == mostSaves;
    if (closer) closers.add(row);
    if (!closer && _int(row['relief_appearances']) > 0) relievers.add(row);
  }
  void sort(List<Map<String, dynamic>> list, String key) {
    list.sort((a, b) {
      final result = _int(b[key]).compareTo(_int(a[key]));
      return result != 0 ? result : '${a['name']}'.compareTo('${b['name']}');
    });
  }

  sort(starters, 'starts');
  sort(relievers, 'relief_appearances');
  sort(closers, 'saves');
  return {'starters': starters, 'relievers': relievers, 'closers': closers};
}

Map<String, dynamic> buildMlbTeamStrength({
  required Map<String, dynamic> team,
  required int year,
  required int sourceTeamId,
  required List<Map<String, dynamic>> pitching,
  required List<Map<String, dynamic>> fielding,
  required List<Map<String, dynamic>> teamStats,
  required Map<String, dynamic> schedule,
  required String sourceUrl,
  Set<int>? pitcherIds,
}) {
  bool belongs(Map<String, dynamic> row) => _int(_map(row['team'])['id']) == sourceTeamId;
  final totals = teamStats.where(belongs).toList();
  if (totals.length != 1) {
    throw StateError('MLB球団の試合数が一意ではありません: $sourceTeamId');
  }
  final games = _int(_map(totals.single['stat'])['gamesPlayed']);
  if (games <= 0) throw StateError('MLB公式戦の消化試合がありません: $sourceTeamId');
  final pitchers = <Map<String, dynamic>>[];
  final playerIds = <String, int>{};
  void rememberPlayer(Map<String, dynamic> player) {
    final name = '${player['fullName'] ?? ''}'.trim();
    final id = _int(player['id']);
    if (name.isEmpty || id <= 0) return;
    if (playerIds.containsKey(name) && playerIds[name] != id) {
      throw StateError('同じ氏名に複数のMLB選手IDがあります: $name');
    }
    playerIds[name] = id;
  }

  for (final row in pitching.where(belongs)) {
    final player = _map(row['player']);
    if (pitcherIds != null && !pitcherIds.contains(_int(player['id']))) {
      continue;
    }
    final stat = _map(row['stat']);
    final name = '${player['fullName'] ?? ''}'.trim();
    final appearances = _int(stat['gamesPitched'] ?? stat['gamesPlayed']);
    if (name.isEmpty || appearances <= 0) continue;
    rememberPlayer(player);
    pitchers.add({
      'name': name,
      'source_player_id': player['id'],
      'starts': _int(stat['gamesStarted']),
      'appearances': appearances,
      'saves': _int(stat['saves']),
      'holds': _int(stat['holds']),
    });
  }
  if (pitchers.isEmpty) {
    throw StateError('MLBの有効な投手成績を取得できません: $sourceTeamId');
  }
  final positions = <String, Map<String, int>>{};
  for (final row in fielding.where(belongs)) {
    final position = '${_map(row['position'])['abbreviation'] ?? ''}';
    final starts = _int(_map(row['stat'])['gamesStarted']);
    final name = '${_map(row['player'])['fullName'] ?? ''}'.trim();
    if (starts > 0 && name.isNotEmpty && strengthPositionLabels.containsKey(position)) {
      rememberPlayer(_map(row['player']));
      _add(positions, position, name, starts);
    }
  }
  if (positions.isEmpty) {
    throw StateError('MLBの有効な守備成績を取得できません: $sourceTeamId');
  }
  final order = <String, Map<String, int>>{};
  final seen = <int>{};
  final cancelled = <int>{};
  var lineupGames = 0;
  for (final date in _maps(schedule['dates'])) {
    for (final game in _maps(date['games'])) {
      if (_map(game['status'])['abstractGameState'] != 'Final') continue;
      final teams = _map(game['teams']);
      for (final side in ['home', 'away']) {
        if (_int(_map(_map(teams[side])['team'])['id']) != sourceTeamId) {
          continue;
        }
        if (_map(game['status'])['detailedState'] == 'Cancelled') {
          cancelled.add(_int(game['gamePk']));
          continue;
        }
        final lineup = _maps(_map(game['lineups'])['${side}Players']);
        if (lineup.length != 9 || lineup.any((player) => '${player['fullName'] ?? ''}'.isEmpty)) {
          continue;
        }
        if (!seen.add(_int(game['gamePk']))) continue;
        lineupGames++;
        for (var index = 0; index < 9; index++) {
          rememberPlayer(lineup[index]);
          _add(order, '${index + 1}', '${lineup[index]['fullName']}');
        }
      }
    }
  }
  if (lineupGames == 0) throw StateError('MLBの実スタメンを取得できません: $sourceTeamId');
  return withStrengthPlayerKeys({
    ...team,
    'org': 'mlb',
    'year': year,
    'game_count': games,
    'lineup_game_count': lineupGames,
    'source_team_id': sourceTeamId,
    'source_url': 'https://www.mlb.com/stats/$year',
    'source_label': 'MLB公式 Stats API',
    'sources': [
      {'label': 'MLB公式・試合別スタメン', 'url': sourceUrl},
      {'label': 'MLB公式・投手と守備成績', 'url': 'https://www.mlb.com/stats/$year'},
    ],
    'notes': [
      '打順比率はMLB公式日程でスタメン9人を確認できた$lineupGames試合が分母（球団公式戦$games試合）。途中出場を含む打順別出場数は使用しません。',
      '守備位置比率はMLB公式の守備位置別先発数を球団公式戦$games試合で割って算出。',
      '投球回には野手登板も含みます。移籍選手の投球回は球団別に集計。選手一覧の投手役割は登録投手・二刀流選手に表示。',
      if (cancelled.isNotEmpty) 'MLB公式で中止（Cancelled）となった${cancelled.length}試合は対象外です。',
      ...pitcherRoleNotes,
    ],
    'pitchers': classifyStrengthPitchers(pitchers),
    'batting_order': _groups(order, lineupGames, batting: true),
    'positions': _groups(positions, games, batting: false),
  }, sourcePlayerIds: playerIds);
}

/// 先発の略称だけを公式投手の一意な照合結果に結び付ける。
/// 姓だけが一致する複数選手は推測でまとめない。
Map<String, String> npbStrengthPlayerAliases(List<Map<String, dynamic>> pitchers, Iterable<String> starterNames) {
  final aliases = <String, String>{};
  for (final name in starterNames) {
    final candidates = _npbPitcherCandidates(pitchers, name);
    if (candidates.length != 1) {
      throw StateError('先発投手の氏名を一意に照合できません: $name');
    }
    aliases[name] = '${candidates.single['name']}';
  }
  return aliases;
}

List<Map<String, dynamic>> _npbPitcherCandidates(List<Map<String, dynamic>> pitchers, String name) {
  final short = _nameKey(name);
  var candidates = pitchers.where((pitcher) => _nameKey('${pitcher['name']}') == short).toList();
  if (candidates.isEmpty) {
    candidates = pitchers.where((pitcher) => _nameKey('${pitcher['source_surname']}') == short).toList();
  }
  if (candidates.isEmpty) {
    candidates = pitchers.where((pitcher) => _nameKey('${pitcher['name']}').startsWith(short)).toList();
  }
  return candidates;
}

/// 登録時に投手・打順・守備をまたぐ色分け用の選手キーを保存する。
/// 読取APIでは処理せず、既存データへの付与でも成績・表示名は変更しない。
Map<String, dynamic> withStrengthPlayerKeys(Map<String, dynamic> payload, {Map<String, String> playerAliases = const {}, Map<String, int> sourcePlayerIds = const {}}) {
  final org = '${payload['org']}';
  final aliases = {
    for (final entry in playerAliases.entries) _nameKey(entry.key): _nameKey(entry.value),
  };
  final ids = <String, int>{};
  void rememberId(String name, int id) {
    if (id <= 0) return;
    final key = _nameKey(name);
    if (ids.containsKey(key) && ids[key] != id) {
      throw StateError('同じ氏名に複数の選手IDがあります: $name');
    }
    ids[key] = id;
  }

  for (final entry in sourcePlayerIds.entries) {
    rememberId(entry.key, entry.value);
  }
  final pitchers = _map(payload['pitchers']);
  for (final group in pitchers.values) {
    for (final row in _maps(group)) {
      rememberId('${row['name']}', _int(row['source_player_id']));
    }
  }
  Map<String, dynamic> player(Map<String, dynamic> row) {
    final name = _nameKey('${row['name']}');
    final canonical = aliases[name] ?? name;
    final id = ids[canonical];
    return {
      ...row,
      'player_key': org == 'mlb' && id != null ? 'mlb:$id' : '$org:name:$canonical',
    };
  }

  return {
    ...payload,
    'pitchers': {
      for (final entry in pitchers.entries) entry.key: [for (final row in _maps(entry.value)) player(row)],
    },
    for (final field in ['batting_order', 'positions'])
      field: [
        for (final group in _maps(payload[field]))
          {
            ...group,
            'players': [for (final row in _maps(group['players'])) player(row)],
          },
      ],
  };
}

List<Map<String, dynamic>> _groups(Map<String, Map<String, int>> counts, int games, {required bool batting}) {
  final keys = batting ? [for (var i = 1; i <= 9; i++) '$i'] : strengthPositionLabels.keys.toList();
  return [
    for (final key in keys)
      {
        'slot': batting ? int.parse(key) : key,
        'label': batting ? '$key番' : strengthPositionLabels[key],
        'total': games,
        'players': _rates(counts[key] ?? {}, games),
      }
  ];
}

List<Map<String, dynamic>> _rates(Map<String, int> counts, int games) {
  final rows = [
    for (final entry in counts.entries)
      {
        'name': entry.key,
        'count': entry.value,
        'rate': games == 0 ? 0.0 : (entry.value * 1000 / games).round() / 10,
      }
  ];
  rows.sort((a, b) {
    final result = _int(b['count']).compareTo(_int(a['count']));
    return result != 0 ? result : '${a['name']}'.compareTo('${b['name']}');
  });
  return rows;
}

void _add(Map<String, Map<String, int>> groups, String slot, String name, [int count = 1]) {
  final values = groups.putIfAbsent(slot, () => {});
  values[name] = (values[name] ?? 0) + count;
}

String _nameKey(String value) => value.replaceAllMapped(RegExp(r'[！-～]'), (match) => String.fromCharCode(match.group(0)!.codeUnitAt(0) - 0xfee0)).toLowerCase().replaceAll('髙', '高').replaceAll('﨑', '崎').replaceAll('ジュニア', 'jr').replaceAll(RegExp(r'[\s　・.．]+'), '');

Future<http.Response> _get(http.Client client, String url) async {
  final response = await client.get(Uri.parse(url), headers: {
    'User-Agent': 'Koko-Baseball-Statistics/1.0',
  }).timeout(const Duration(seconds: 90));
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
  }
  return response;
}

Future<String> _fetchHtml(http.Client client, String url) async {
  final response = await _get(client, url);
  final head = latin1.decode(response.bodyBytes.take(500).toList()).toLowerCase();
  if (!head.contains('shift_jis') && !head.contains('shift-jis')) {
    return utf8.decode(response.bodyBytes);
  }
  // スタメンDBはCP932。macOS/Linuxのiconvで文字化けさせず取り込む。
  final process = await Process.start('iconv', ['-f', 'CP932', '-t', 'UTF-8']);
  final output = utf8.decoder.bind(process.stdout).join();
  final error = utf8.decoder.bind(process.stderr).join();
  process.stdin.add(response.bodyBytes);
  await process.stdin.close();
  final code = await process.exitCode.timeout(const Duration(seconds: 10));
  if (code != 0) throw FormatException('Shift_JIS変換に失敗: ${await error}');
  return output;
}

Future<Map<String, dynamic>> _fetchJson(http.Client client, String url) async => _map(jsonDecode(utf8.decode((await _get(client, url)).bodyBytes)));

List<Map<String, dynamic>> _splits(Map<String, dynamic> value) => [
      for (final group in _maps(value['stats'])) ..._maps(group['splits']),
    ];

Map<String, dynamic> _map(dynamic value) {
  if (value is String) return _map(jsonDecode(value));
  return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? [
        for (final row in value)
          if (row is Map) Map<String, dynamic>.from(row)
      ]
    : [];

int _int(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
