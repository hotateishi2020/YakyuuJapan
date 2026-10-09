import 'package:postgres/postgres.dart';

import '../tools/Postgres.dart';

/// ポストシーズンで勝ち上がりか敗退が決まったあとの、行われない試合。
const postseasonGameCodes = [
  'CS1',
  'CSF',
  'CS',
  'CS2',
  'JS',
  'WC',
  'ALWC',
  'NLWC',
  'ALWC36',
  'ALWC45',
  'NLWC36',
  'NLWC45',
  'DS',
  'ALDS',
  'NLDS',
  'ALDS1',
  'ALDS2',
  'NLDS1',
  'NLDS2',
  'LCS',
  'ALCS',
  'NLCS',
  'WS',
];

/// シリーズの規定勝数。ポストシーズン以外は 0。
int seriesWinsNeeded(String code, {required int advantage}) {
  switch (code.trim().toUpperCase()) {
    case 'CS1':
      return 2;
    case 'CSF':
    case 'CS':
    case 'CS2':
      return advantage >= 2 ? 5 : 4;
    case 'JS':
      return 4;
    case 'WC':
    case 'ALWC':
    case 'NLWC':
    case 'ALWC36':
    case 'ALWC45':
    case 'NLWC36':
    case 'NLWC45':
      return 2;
    case 'DS':
    case 'ALDS':
    case 'NLDS':
    case 'ALDS1':
    case 'ALDS2':
    case 'NLDS1':
    case 'NLDS2':
      return 3;
    case 'LCS':
    case 'ALCS':
    case 'NLCS':
    case 'WS':
      return 4;
    default:
      return 0;
  }
}

/// 規定勝数に達したあとの未実施試合の id。終了試合の同スコア重複は1勝に数える。
List<int> unplayedClinchedGameIds(
  List<Map<String, dynamic>> games, {
  List<Map<String, dynamic>> standings = const [],
}) {
  final groups = <String, List<int>>{};
  for (var i = 0; i < games.length; i++) {
    final code = _code(games[i]);
    if (seriesWinsNeeded(code, advantage: 0) <= 0) continue;
    final home = _asInt(games[i]['id_team_home']);
    final away = _asInt(games[i]['id_team_away']);
    if (home <= 0 || away <= 0) continue;
    final low = home < away ? home : away;
    final high = home < away ? away : home;
    groups.putIfAbsent('$code|$low|$high', () => []).add(i);
  }
  final drop = <int>[];
  for (final indexes in groups.values) {
    final ordered = [...indexes]..sort((a, b) => _byStart(games[a], games[b]));
    final sample = games[ordered.first];
    final code = _code(sample);
    final home = _asInt(sample['id_team_home']);
    final away = _asInt(sample['id_team_away']);
    final advHome = _csfAdvantage(code, home, away, standings);
    final advAway = _csfAdvantage(code, away, home, standings);
    final needed = seriesWinsNeeded(code, advantage: advHome > advAway ? advHome : advAway);
    if (needed <= 0) continue;
    final wins = <int, int>{home: advHome, away: advAway};
    final counted = <Map<String, dynamic>>[];
    var decided = (wins[home] ?? 0) >= needed || (wins[away] ?? 0) >= needed;
    for (final index in ordered) {
      final game = games[index];
      if (decided && _unplayed(game)) {
        final id = _asInt(game['id_game'] ?? game['id']);
        if (id > 0) drop.add(id);
        continue;
      }
      if (!_finished(game) || counted.any((prior) => _importDuplicate(prior, game))) continue;
      counted.add(game);
      final winner = _winner(game);
      if (winner != null && (winner == home || winner == away)) {
        wins[winner] = (wins[winner] ?? 0) + 1;
      }
      decided = (wins[home] ?? 0) >= needed || (wins[away] ?? 0) >= needed;
    }
  }
  return drop;
}

/// 当年のポストシーズンで、もう行われない試合を削除する。
Future<int> dropUnplayedClinchedGames(Connection conn, {int? year}) async {
  final season = year ?? DateTime.now().year;
  final codes = postseasonGameCodes.map((code) => "'$code'").join(', ');
  final games = Postgres.toJson(await conn.execute('''
    SELECT
      g.id AS id_game,
      g.code_game,
      to_char(g.datetime_start, 'YYYY-MM-DD') AS date_game,
      to_char(g.datetime_start, 'HH24:MI') AS time_game,
      g.score_home,
      g.score_away,
      g.state,
      g.id_team_home,
      g.id_team_away,
      COALESCE(h.name_short, '') AS name_home,
      COALESCE(a.name_short, '') AS name_away
    FROM t_game g
    LEFT JOIN m_team h ON h.id = g.id_team_home
    LEFT JOIN m_team a ON a.id = g.id_team_away
    WHERE g.code_game IN ($codes)
      AND COALESCE(g.flg_delete, FALSE) = FALSE
      AND EXTRACT(YEAR FROM g.datetime_start) = \$1
  ''', parameters: [season]));
  final standings = Postgres.toJson(await conn.execute('''
    SELECT DISTINCT ON (id_team)
      id_team, id_league, int_rank, int_win, int_lose, game_behind
    FROM t_stats_team
    WHERE year = \$1
    ORDER BY id_team, crtat DESC
  ''', parameters: [season]));
  final ids = unplayedClinchedGameIds(games, standings: standings);
  if (ids.isEmpty) return 0;
  final byId = {for (final row in games) _asInt(row['id_game']): row};
  final placeholders = List.generate(ids.length, (i) => '\$${i + 1}').join(', ');
  await conn.execute(
    'UPDATE t_game SET flg_delete = TRUE, updat = NOW() WHERE id IN ($placeholders)',
    parameters: ids,
  );
  for (final id in ids) {
    final row = byId[id];
    if (row == null) continue;
    print('ポストシーズン未実施を削除: ${row['code_game']} ${row['date_game']} ${row['name_away']} @ ${row['name_home']} id=$id');
  }
  return ids.length;
}

int _csfAdvantage(String code, int teamId, int otherId, List<Map<String, dynamic>> standings) {
  if (code != 'CSF' && code != 'CS' && code != 'CS2') return 0;
  final self = _standing(standings, teamId);
  if (self == null || _asInt(self['int_rank']) != 1) return 0;
  final rival = _standing(standings, otherId);
  if (rival == null) return 1;
  final selfWins = _asInt(self['int_win']);
  final selfLosses = _asInt(self['int_lose']);
  final rivalWins = _asInt(rival['int_win']);
  final rivalLosses = _asInt(rival['int_lose']);
  final behind = ((selfWins - rivalWins) + (rivalLosses - selfLosses)) / 2;
  final games = rivalWins + rivalLosses;
  final rate = games == 0 ? null : rivalWins / games;
  final extra = behind >= 10 || (rate != null && rate < 0.5);
  return extra ? 2 : 1;
}

Map<String, dynamic>? _standing(List<Map<String, dynamic>> standings, int teamId) {
  for (final row in standings) {
    if (_asInt(row['id_team']) == teamId) return row;
  }
  return null;
}

String _code(Map<String, dynamic> game) => '${game['code_game'] ?? ''}'.trim().toUpperCase();

bool _finished(Map<String, dynamic> game) => '${game['state'] ?? ''}'.contains('試合終了');

bool _unplayed(Map<String, dynamic> game) {
  final state = '${game['state'] ?? ''}'.trim();
  if (state.contains('試合終了') || state.contains('試合中')) return false;
  if (RegExp(r'\d+\s*回').hasMatch(state)) return false;
  return true;
}

/// Yahoo 行（id 2000 未満）と歴史インポート行が、近い日に同じスコアで入ったもの。
bool _importDuplicate(Map<String, dynamic> a, Map<String, dynamic> b) {
  final leftId = _asInt(a['id_game'] ?? a['id']);
  final rightId = _asInt(b['id_game'] ?? b['id']);
  final leftYahoo = leftId > 0 && leftId < 2000;
  final rightYahoo = rightId > 0 && rightId < 2000;
  if (leftYahoo == rightYahoo) return false;
  if (_asInt(a['score_home']) != _asInt(b['score_home'])) return false;
  if (_asInt(a['score_away']) != _asInt(b['score_away'])) return false;
  final left = DateTime.tryParse(_date(a));
  final right = DateTime.tryParse(_date(b));
  if (left == null || right == null) return false;
  return left.difference(right).inDays.abs() <= 1;
}

int? _winner(Map<String, dynamic> game) {
  final home = _asInt(game['score_home']);
  final away = _asInt(game['score_away']);
  if (home < 0 || away < 0 || home == away) return null;
  return home > away ? _asInt(game['id_team_home']) : _asInt(game['id_team_away']);
}

int _byStart(Map<String, dynamic> a, Map<String, dynamic> b) {
  final date = _date(a).compareTo(_date(b));
  if (date != 0) return date;
  return _asInt(a['id_game'] ?? a['id']).compareTo(_asInt(b['id_game'] ?? b['id']));
}

String _date(Map<String, dynamic> game) {
  final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch('${game['date_game'] ?? ''}');
  return match?.group(0) ?? '';
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value'.trim()) ?? 0;
}
