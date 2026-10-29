import 'PlayerCountry.dart';
import 'GameSeasonStats.dart';
import 'GoldenGloveStats.dart';
import 'package:koko_shared/postseason_homers.dart';
import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'StrengthUsage.dart';
import 'PlayerDetail.dart' show detailMap, attachOfficialIdentity, officialPlayerId;

const postseasonCodes = {'CS1', 'CS2', 'CSF', 'CS', 'FS', 'NS', 'JS', 'SM', 'S1', 'S2', 'WC', 'DS', 'LCS', 'WS', 'ALWC', 'NLWC', 'ALWC36', 'ALWC45', 'NLWC36', 'NLWC45', 'ALDS', 'NLDS', 'ALDS1', 'ALDS2', 'NLDS1', 'NLDS2', 'ALCS', 'NLCS'};
Map<String, dynamic> comparePostseasonForm({required num? season, required num? recent, required int sample, required bool pitcher}) {
  final enough = sample > 0;
  if (!enough || season == null || recent == null) {
    return {'label': '判定保留', 'level': null, 'note': 'シーズン成績または比較期間の打数・投球回が未取得です。'};
  }
  final delta = pitcher ? season - recent : recent - season;
  final high = pitcher ? 2.0 : .10, low = pitcher ? 0.75 : 0.04;
  final level = delta >= high - 1e-9
      ? 2
      : delta >= low - 1e-9
          ? 1
          : delta <= -high + 1e-9
              ? -2
              : delta <= -low + 1e-9
                  ? -1
                  : 0;
  return {
    'label': const {-2: '絶不調', -1: '不調', 0: '普通', 1: '好調', 2: '絶好調'}[level],
    'level': level,
    'season': season,
    'postseason': recent,
    'sample': sample,
    'small_sample': sample < (pitcher ? 9 : 10),
    'pitcher': pitcher,
    'note': (sample < (pitcher ? 9 : 10) ? '少数サンプルの参考判定。' : '') + (pitcher ? '当該試合開始前の取得済みPS防御率とシーズン防御率を比較（±0.75／±2.00）。' : '当該試合開始前の取得済みPS打率とシーズン打率を比較（±.040／±.100）。')
  };
}

Future<void> attachPostseasonForm(Connection conn, List<Map<String, dynamic>> games, int year) async {
  final targets = games;
  if (targets.isEmpty) return;
  final teamIds = {
    for (final g in games)
      for (final k in ['id_team_home', 'id_team_away'])
        if (int.tryParse('${g[k]}') != null) int.parse('${g[k]}')
  }.toList();
  final rows = (await conn.execute('''SELECT s.*,p.name_full,p.id_team AS current_team,g.datetime_start::text AS start,g.code_game FROM t_game_summary s JOIN t_game g ON g.id=s.id_game JOIN m_player p ON p.id=s.id_player WHERE g.datetime_start>=make_date(\$1,1,1) AND g.datetime_start<make_date(\$1+1,1,1) AND (g.state LIKE '%終了%' OR g.state LIKE '%コールド%') AND NOT COALESCE(g.flg_delete,false) AND NOT COALESCE(s.flg_delete,false) AND (cardinality(\$2::int[])=0 OR p.id_team=ANY(\$2::int[]))''', parameters: [year, teamIds])).map((r) => r.toColumnMap()).toList();
  final stats = (await conn.execute("SELECT payload FROM v_stats_player WHERE int_year=\$1 AND payload->>'title' IN ('打率','防御率','本塁打','最多勝','勝利','ホールド','セーブ')", parameters: [year])).map((r) => detailMap(r[0])).toList();
  final gameIds = games.map((g) => usageInt(g['id_game'] ?? g['id'])).where((id) => id > 0).toList();
  final participants = (await conn.execute('SELECT DISTINCT id_game,id_player FROM t_game_summary WHERE id_game=ANY(\$1::int[]) AND NOT COALESCE(flg_delete,false)', parameters: [gameIds])).map((r) => r.toColumnMap()).toList();
  final participantIds = participants.map((p) => usageInt(p['id_player'])).toSet().toList();
  final people = (await conn.execute('SELECT p.id AS id_player,p.id_team,t.id_league,p.url,p.identity_sources,p.name_patterns,p.name_last,p.name_first_initial,p.date_birth::text,p.name_full AS name_full_summary,p.pitching AS pitching_hand,p.batting AS batting_hand FROM m_player p JOIN m_team t ON t.id=p.id_team WHERE (p.id_team=ANY(\$1::int[]) AND NOT COALESCE(p.flg_delete,false)) OR p.id=ANY(\$2::int[])', parameters: [teamIds, participantIds])).map((r) => r.toColumnMap()).toList();
  await attachPlayerCountries(conn, year, people);
  if (people.any((p) => [3, 4].contains(p['id_league']) && officialPlayerId(p) == null)) {
    for (final p in people) {
      p['id'] = p['id_player'];
      p['name_full'] = p['name_full_summary'];
    }
    await attachOfficialIdentity(conn, year, people);
  }
  if (games.any((g) => [1, 2].contains(g['id_league_home']) || [1, 2].contains(g['id_league_away']))) {
    final awardPlayers = await goldenGloveSeasonPlayers(conn, year, [1, 2]);
    stats.addAll(goldenGloveRows(year, awardPlayers));
    stats.addAll(goldenGloveRows(year, awardPlayers, pitching: true));
  }

  final careers = (await conn.execute('SELECT c.*,p.url AS identity_url,p.id_team AS identity_team FROM m_player_career c JOIN m_player p ON p.id=c.id_player WHERE c.int_year=\$1 AND (p.id_team=ANY(\$2::int[]) OR p.id=ANY(\$3::int[])) AND NOT COALESCE(c.flg_delete,false) ORDER BY c.id DESC', parameters: [year, teamIds, participantIds])).map((r) => r.toColumnMap()).toList();
  addCareerFormBaselines(stats, careers, people: people);
  addOfficialGameSeasonStats(stats, people, GameSeasonStats.cached(year));
  for (final game in games) {
    game['golden_glove_stats_version'] = 1;
    game['season_stats_version'] = gameSeasonStatsVersion;
    final appeared = participants.where((p) => usageInt(p['id_game']) == usageInt(game['id_game'] ?? game['id'])).map((p) => '${p['id_player']}').toSet();
    game['player_hands'] = people.where((p) => p['id_team'] == game['id_team_home'] || p['id_team'] == game['id_team_away'] || appeared.contains('${p['id_player']}')).toList();
    final ids = (game['player_hands'] as List).map((p) => '${p['id_player']}').toSet();
    game['season_player_stats'] = [
      for (final row in stats)
        if (ids.contains('${row['id_player']}'))
          {
            for (final key in ['id_player', 'name_player', 'id_team', 'id_league', 'title', 'stats']) key: row[key]
          },
    ];
  }
  // Official game logs are prepared by the detail snapshot job, not fetched here.
  if ((await conn.execute("SELECT to_regclass('public.t_player_detail_snapshot') IS NOT NULL")).first[0] == true) {
    final cached = await conn.execute("SELECT id_player,payload->'profile',payload->'recent_games' FROM t_player_detail_snapshot WHERE int_year=\$1 AND (cardinality(\$2::int[])=0 OR id_team=ANY(\$2::int[]))", parameters: [year, teamIds]);
    final knownDates = {for (final r in rows) "${r['id_player']}:${'${r['start']}'.split(RegExp('[ T]')).first}"};
    for (final r in cached) {
      final profile = detailMap(r[1]);
      final recent = r[2] is String ? (jsonDecode(r[2] as String) as List) : r[2];
      for (final g in usageMaps(recent)) {
        final date = '${g['datetime_start']}'.split(RegExp('[ T]')).first;
        final known = knownDates.contains('${r[0]}:$date');
        if (known) continue;
        for (final line in usageMaps(g['lines'])) {
          rows.add({...line, 'id_player': r[0], 'name_full': profile['name_full'], 'current_team': profile['id_team'], 'start': g['datetime_start'], 'date_only': true, 'code_game': g['code_game'], 'hits_total': g['source'] != null ? usageInt(line['int_hit1']) : databaseBattingHits(line)});
        }
      }
    }
  }
  for (final row in rows) {
    row['hits_total'] ??= databaseBattingHits(row);
  }
  attachFormsFromRecords(targets, rows, stats);
}

int databaseBattingHits(Map<String, dynamic> row) => ['int_hit1', 'int_hit2', 'int_hit3', 'int_homerun'].fold(0, (sum, k) => sum + usageInt(row[k]));

DateTime? formGameStart(Map<String, dynamic> game) {
  final date = '${game['date_game'] ?? game['datetime_start'] ?? ''}'.trim();
  if (date.contains('T') || date.contains(' ')) {
    return DateTime.tryParse(date.replaceFirst(' ', 'T'));
  }
  final time = RegExp(r'\d{1,2}:\d{2}').firstMatch('${game['time_game'] ?? ''}')?.group(0) ?? '00:00';
  return DateTime.tryParse('${date}T${time.padLeft(5, '0')}');
}

void attachFormsFromRecords(List<Map<String, dynamic>> targets, List<Map<String, dynamic>> rows, List<Map<String, dynamic>> stats) {
  for (final game in targets) {
    final start = formGameStart(game);
    if (start == null) continue;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final team = '${r['current_team']}';
      if (game['id_team_home'] != null && game['id_team_away'] != null && team != '${game['id_team_home']}' && team != '${game['id_team_away']}') {
        continue;
      }
      final when = DateTime.tryParse('${r['start']}'.replaceFirst(' ', 'T'));
      if (when == null || !when.isBefore(start) || r['date_only'] == true && when.year == start.year && when.month == start.month && when.day == start.day) {
        continue;
      }
      groups.putIfAbsent('${r['id_player']}', () => []).add(r);
    }
    if (npbPostseasonCodes.contains('${game['code_game']}'.toUpperCase())) {
      game['postseason_homers_before'] = [
        for (final entry in groups.entries)
          {
            'id_player': int.parse(entry.key),
            'name': entry.value.first['name_full'],
            'homers': entry.value.where((r) => npbPostseasonCodes.contains('${r['code_game']}'.toUpperCase()) && DateTime.tryParse('${r['start']}'.replaceFirst(' ', 'T'))?.year == start.year).fold<int>(0, (sum, r) => sum + usageInt(r['int_homerun'])),
          },
      ];
    }
    game['postseason_form'] = [
      for (final entry in groups.entries)
        for (final pitcher in [false, true])
          (() {
            final all = entry.value..sort((a, b) => '${b['start']}'.compareTo('${a['start']}'));
            final ps = all.where((r) => postseasonCodes.contains('${r['code_game']}'.toUpperCase())).toList();
            int sampleOf(List<Map<String, dynamic>> values) => values.fold<int>(0, (n, r) => n + (pitcher ? inningsToOuts('${r['double_inning_pitch'] ?? 0}') : usageInt(r['int_batting'])));
            final usePs = postseasonCodes.contains('${game['code_game']}'.toUpperCase()) && sampleOf(ps) > 0;
            final dates = all.map((r) => '${r['start']}').toSet().take(25).toSet();
            final list = usePs ? ps : all.where((r) => dates.contains('${r['start']}')).toList();
            int sum(String k) => list.fold(0, (v, r) => v + usageInt(r[k]));
            final sample = pitcher ? list.fold<int>(0, (v, r) => v + inningsToOuts('${r['double_inning_pitch'] ?? 0}')) : sum('int_batting');
            final baseline = stats.where((s) => '${s['id_player']}' == entry.key && s['title'] == (pitcher ? '防御率' : '打率')).firstOrNull;
            final value = sample == 0
                ? null
                : pitcher
                    ? sum('int_runs_earned') * 27 / sample
                    : list.fold<int>(0, (n, r) => n + usageInt(r['hits_total'] ?? databaseBattingHits(r))) / sample;
            final result = comparePostseasonForm(season: num.tryParse(RegExp(r'[0-9]*\.?[0-9]+').firstMatch('${baseline?['stats']}')?.group(0) ?? ''), recent: value, sample: sample, pitcher: pitcher);
            return {'id_player': int.parse(entry.key), 'name': list.first['name_full'], 'pitcher': pitcher, ...result, 'note': '${result['note']}'.replaceAll('PS', usePs ? 'PS' : '直近25試合（PSを含む）')};
          })()
    ];
  }
}

/// Ranking snapshots omit unqualified players; career records include relievers.
void addCareerFormBaselines(List<Map<String, dynamic>> stats, List<Map<String, dynamic>> careers, {List<Map<String, dynamic>> people = const []}) {
  final resolved = [...careers];
  String urlKey(dynamic value) => value == null ? '' : '$value'.trim().replaceFirst(RegExp(r'/+$'), '');
  for (final c in careers) {
    final url = urlKey(c['identity_url']);
    if (url.isEmpty) continue;
    for (final p in people) {
      if (p['id_player'] != c['id_player'] && p['id_team'] == c['identity_team'] && urlKey(p['url']) == url) {
        resolved.add({...c, 'id_player': p['id_player']});
      }
    }
  }
  final groups = <String, Map<String, Map<String, dynamic>>>{};
  for (final c in resolved) {
    groups.putIfAbsent('${c['id_player']}', () => {}).putIfAbsent('${c['id_team'] ?? 0}', () => c);
  }
  for (final teams in groups.values) {
    final records = teams.containsKey('0') ? [teams['0']!] : teams.values.toList();
    final c = records.first;
    void add(String title, dynamic value) {
      if (value == null || stats.any((s) => '${s['id_player']}' == '${c['id_player']}' && (s['title'] == title || title == '勝利' && s['title'] == '最多勝'))) {
        return;
      }
      final person = people.where((p) => '${p['id_player']}' == '${c['id_player']}').firstOrNull;
      stats.add({'id_player': c['id_player'], 'title': title, 'stats': value, 'name_player': person?['name_full_summary'], 'id_team': person?['id_team']});
    }

    for (final pitcher in [false, true]) {
      final title = pitcher ? '防御率' : '打率';
      final sampleKey = pitcher ? 'double_inning' : 'int_batting';
      final applicable = records.where((r) => (num.tryParse('${r[sampleKey]}') ?? 0) > 0).toList();
      if (applicable.isNotEmpty) {
        if (applicable.length == 1) {
          add(title, applicable.single[pitcher ? 'double_average_earned_runs' : 'double_average_batting']);
        } else if (pitcher) {
          int outs(dynamic value) {
            final parts = '$value'.split('.');
            return (int.tryParse(parts.first) ?? 0) * 3 + (parts.length > 1 ? int.tryParse(parts.last.substring(0, 1)) ?? 0 : 0);
          }

          final innings = applicable.fold<int>(0, (n, r) => n + outs(r['double_inning']));
          final earned = applicable.fold<int>(0, (n, r) => n + usageInt(r['int_earned_runds']));
          if (innings > 0) add(title, earned * 27 / innings);
        } else {
          final atBats = applicable.fold<int>(0, (n, r) => n + usageInt(r['int_batting']));
          final hits = applicable.fold<int>(0, (n, r) => n + usageInt(r['int_hit1']));
          if (atBats > 0) add(title, hits / atBats);
        }
      }
      final played = records.any((r) => usageInt(r[pitcher ? 'int_pitching' : 'int_appearance']) > 0 || (num.tryParse('${r[sampleKey]}') ?? 0) > 0);
      if (!played) continue;
      final fields = pitcher ? {'勝利': 'int_win', 'ホールド': 'int_hold', 'セーブ': 'int_save'} : {'本塁打': 'int_homerun'};
      for (final field in fields.entries) {
        if (records.every((r) => r[field.value] != null)) {
          add(field.key, records.fold<int>(0, (n, r) => n + usageInt(r[field.value])));
        }
      }
    }
  }
}
