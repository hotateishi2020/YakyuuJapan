import 'postseason_bracket.dart';

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

/// 規定勝数に達したあとの、行われない試合を除く。
/// [seriesGames] は表示期間の外にある同シリーズの試合。勝数の判定にだけ使う。
List<Map<String, dynamic>> dropUnplayedClinchedGames(
  List<Map<String, dynamic>> games, {
  List<Map<String, dynamic>> standings = const [],
  List<Map<String, dynamic>> seriesGames = const [],
}) {
  final pool = seriesGames.isEmpty ? games : _seriesPool(seriesGames, games);
  final groups = <String, List<int>>{};
  for (var i = 0; i < pool.length; i++) {
    final code = _code(pool[i]);
    if (seriesWinsNeeded(code, advantage: 0) <= 0) continue;
    final home = _asInt(pool[i]['id_team_home']);
    final away = _asInt(pool[i]['id_team_away']);
    if (home <= 0 || away <= 0) continue;
    final low = home < away ? home : away;
    final high = home < away ? away : home;
    groups.putIfAbsent('$code|$low|$high', () => []).add(i);
  }
  final drop = <int>{};
  for (final indexes in groups.values) {
    final ordered = [...indexes]..sort((a, b) => _byStart(pool[a], pool[b]));
    final sample = pool[ordered.first];
    final code = _code(sample);
    final home = _asInt(sample['id_team_home']);
    final away = _asInt(sample['id_team_away']);
    final advHome = _csfAdvantage(code, home, away, standings);
    final advAway = _csfAdvantage(code, away, home, standings);
    final needed = seriesWinsNeeded(code, advantage: advHome > advAway ? advHome : advAway);
    if (needed <= 0) continue;
    final wins = <int, int>{home: advHome, away: advAway};
    var decided = (wins[home] ?? 0) >= needed || (wins[away] ?? 0) >= needed;
    for (final index in ordered) {
      final game = pool[index];
      if (decided && _unplayed(game)) {
        drop.add(index);
        continue;
      }
      if (_finished(game)) {
        final winner = _winner(game);
        if (winner != null && (winner == home || winner == away)) {
          wins[winner] = (wins[winner] ?? 0) + 1;
        }
        decided = (wins[home] ?? 0) >= needed || (wins[away] ?? 0) >= needed;
      }
    }
  }
  if (drop.isEmpty) return games;
  if (identical(pool, games)) {
    return [
      for (var i = 0; i < games.length; i++)
        if (!drop.contains(i)) games[i],
    ];
  }
  final droppedIds = <int>{
    for (final index in drop) _asInt(pool[index]['id_game'] ?? pool[index]['id']),
  }..remove(0);
  final droppedRows = <Map<String, dynamic>>{
    for (final index in drop) pool[index],
  };
  return [
    for (final game in games)
      if (!droppedIds.contains(_asInt(game['id_game'] ?? game['id'])) && !droppedRows.contains(game)) game,
  ];
}

/// 表示中の試合を優先し、同じ id の履歴は勝数判定に一度だけ入れる。
List<Map<String, dynamic>> _seriesPool(
  List<Map<String, dynamic>> history,
  List<Map<String, dynamic>> visible,
) {
  final byId = <int, Map<String, dynamic>>{};
  final extras = <Map<String, dynamic>>[];
  void put(Map<String, dynamic> row, {required bool prefer}) {
    final id = _asInt(row['id_game'] ?? row['id']);
    if (id <= 0) {
      extras.add(row);
      return;
    }
    if (!byId.containsKey(id) || prefer) byId[id] = row;
  }

  for (final row in history) {
    put(row, prefer: false);
  }
  for (final row in visible) {
    put(row, prefer: true);
  }
  return [...byId.values, ...extras];
}

int _csfAdvantage(String code, int teamId, int otherId, List<Map<String, dynamic>> standings) {
  if (code != 'CSF' && code != 'CS' && code != 'CS2') return 0;
  final self = _standing(standings, teamId);
  if (self == null || _asInt(self['int_rank']) != 1) return 0;
  final rival = _standing(standings, otherId);
  final extra = rival != null && finalistTakesExtraAdvantage(_team(rival), leader: _team(self));
  return extra ? 2 : 1;
}

Map<String, dynamic>? _standing(List<Map<String, dynamic>> standings, int teamId) {
  for (final row in standings) {
    if (_asInt(row['id_team']) == teamId) return row;
  }
  return null;
}

BracketTeam _team(Map<String, dynamic> row) {
  return BracketTeam(
    id: _asInt(row['id_team']),
    leagueId: _asInt(row['id_league']),
    rank: _asInt(row['int_rank']),
    name: '${row['name_team'] ?? ''}',
    colorBack: '',
    colorFont: '',
    wins: _asInt(row['int_win']),
    losses: _asInt(row['int_lose']),
    gamesBehind: gamesBehindOf(row['game_behind']),
  );
}

String _code(Map<String, dynamic> game) => '${game['code_game'] ?? ''}'.trim().toUpperCase();

bool _finished(Map<String, dynamic> game) => '${game['state'] ?? ''}'.contains('試合終了');

bool _unplayed(Map<String, dynamic> game) {
  final state = '${game['state'] ?? ''}'.trim();
  if (state.contains('試合終了') || state.contains('試合中')) return false;
  if (RegExp(r'\d+\s*回').hasMatch(state)) return false;
  return true;
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
