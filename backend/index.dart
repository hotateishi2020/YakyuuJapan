import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:postgres/postgres.dart';
import 'tools/DateTimeTool.dart';
import 'tools/Postgres.dart';
import 'app/DB/t_system_log.dart';
import 'app/DB/t_system_log_error.dart';
import 'app/DB/m_user.dart';
import 'app/AppSql.dart';
import 'app/Achieve.dart';
import 'app/AceEvaluator.dart';
import 'app/FetchURL.dart';
import 'app/FetchMLB.dart';
import 'app/Lineup.dart';
import 'app/OrgLeague.dart';
import 'app/PlayLabel.dart';
import 'app/Postseason.dart';
import 'app/Value.dart';
import 'app/Auth.dart';
import 'app/EventReadReset.dart';
import 'app/PlayerStatsSchedule.dart';

/// /predictions 用の短TTLキャッシュ（同一プロセス内・団体別）
final Map<String, String> _predictionsCacheBody = {};
final Map<String, DateTime> _predictionsCacheAt = {};
/// /predictions/part 用（org|part）
final Map<String, String> _predictionsPartCacheBody = {};
final Map<String, DateTime> _predictionsPartCacheAt = {};
const Duration _predictionsCacheTtl = Duration(seconds: 45);

void _clearPredictionsCache() {
  _predictionsCacheBody.clear();
  _predictionsCacheAt.clear();
  _predictionsPartCacheBody.clear();
  _predictionsPartCacheAt.clear();
}

Future<Map<String, dynamic>> _buildPredictionsPartInfo(OrgKind org) async {
  final currentYear = DateTimeTool.getThisYear();
  final results = await Postgres.mapParallel([
    (conn) => Postgres.execute(conn, AppSql.selectEventsDetails()),
    (conn) => Postgres.execute(conn, AppSql.selectNotification()),
    (conn) => Postgres.execute(conn, AppSql.selectPredictNPBTeams(), data: [currentYear]),
  ]);
  final leagueIds = org.leagueIds;
  return {
    'org': org.code,
    'part': 'info',
    'events': org.code == 'npb' ? Postgres.toJson(results[0]) : const <Map<String, dynamic>>[],
    'notification': org.code == 'npb' ? Postgres.toJson(results[1]) : const <Map<String, dynamic>>[],
    'predict_team': _filterByLeagues(Postgres.toJson(results[2]), leagueIds),
  };
}

Future<Map<String, dynamic>> _buildPredictionsPartStandings(OrgKind org, int year) async {
  final results = await Postgres.mapParallel([
    (conn) => Postgres.execute(conn, AppSql.selectPredictNPBTeams(), data: [year]),
    (conn) => Postgres.execute(conn, AppSql.selectStatsTeam(), data: [year]),
  ]);
  final leagueIds = org.leagueIds;
  return {
    'org': org.code,
    'year': year,
    'part': 'standings',
    'predict_team': _filterByLeagues(Postgres.toJson(results[0]), leagueIds),
    'stats_team': _filterByLeagues(Postgres.toJson(results[1]), leagueIds),
  };
}

Future<Map<String, dynamic>> _buildPredictionsPartPlayers(OrgKind org, int year) async {
  final results = await Postgres.mapParallel([
    (conn) => Postgres.execute(conn, AppSql.selectPredictPlayer(), data: [year]),
    (conn) => Postgres.execute(conn, AppSql.selectStatsPlayer(), data: [year]),
  ]);
  final leagueIds = org.leagueIds;
  return {
    'org': org.code,
    'year': year,
    'part': 'players',
    'predict_player': _filterByLeagues(Postgres.toJson(results[0]), leagueIds),
    'stats_player': _filterByLeagues(Postgres.toJson(results[1]), leagueIds),
  };
}

String? _queryYmd(String? raw) {
  final text = (raw ?? '').trim();
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ? text : null;
}

({String? from, String? to}) _gamesQueryWindow(Request request, int year) {
  final date = _queryYmd(request.url.queryParameters['date']);
  final from = _queryYmd(request.url.queryParameters['from']) ?? date;
  final to = _queryYmd(request.url.queryParameters['to']) ?? date;
  if (from != null && to != null) {
    return from.compareTo(to) <= 0 ? (from: from, to: to) : (from: to, to: from);
  }
  return _currentYearGamesWindow(year) ?? (from: null, to: null);
}

({String from, String to})? _currentYearGamesWindow(int year) {
  final now = DateTime.now();
  if (year != now.year) return null;
  final today = DateTime(now.year, now.month, now.day);
  return (
    from: _ymdOf(today.subtract(Duration(days: AppSql.gamesPastDays))),
    to: _ymdOf(today.add(Duration(days: AppSql.gamesFutureDays))),
  );
}

String _ymdOf(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

({String from, String to}) _defaultGamesWindow(int year, List<Map<String, dynamic>> games) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (year == today.year) {
    return (
      from: _ymdOf(today.subtract(Duration(days: AppSql.gamesPastDays))),
      to: _ymdOf(today.add(Duration(days: AppSql.gamesFutureDays))),
    );
  }
  DateTime? min;
  DateTime? max;
  for (final game in games) {
    final parsed = DateTime.tryParse('${game['date_game'] ?? ''}');
    if (parsed == null) continue;
    final day = DateTime(parsed.year, parsed.month, parsed.day);
    if (min == null || day.isBefore(min)) min = day;
    if (max == null || day.isAfter(max)) max = day;
  }
  return (from: min == null ? '' : _ymdOf(min), to: max == null ? '' : _ymdOf(max));
}

Future<Map<String, dynamic>> _buildPredictionsPartGames(
  OrgKind org,
  int year, {
  String? from,
  String? to,
}) async {
  var windowFrom = from;
  var windowTo = to;
  if (windowFrom == null || windowTo == null) {
    final fallback = _currentYearGamesWindow(year);
    if (fallback != null) {
      windowFrom = fallback.from;
      windowTo = fallback.to;
    }
  }
  final ranged = windowFrom != null && windowTo != null;
  final data = ranged ? <Object>[year, windowFrom, windowTo] : <Object>[year];
  final results = await Postgres.mapParallel([
    (conn) => Postgres.execute(conn, AppSql.selectGames(ranged: ranged), data: data),
    (conn) => Postgres.execute(conn, AppSql.selectGamePlayRows(ranged: ranged), data: data),
    (conn) => Postgres.execute(conn, AppSql.selectBattingLines(ranged: ranged), data: data),
    (conn) => Postgres.execute(conn, AppSql.selectPostseasonGames(), data: [year]),
    (conn) => Postgres.execute(conn, AppSql.selectPostseasonBoard(), data: [
      Value.SystemCode.Code.ADMIN,
      Value.SystemCode.Key.DATE_FINAL_GAME,
      Value.SystemCode.Key.DATE_OPEN_GAME,
    ]),
  ]);
  final leagueIds = org.leagueIds;
  final gameRows = _filterByLeagues(
    Postgres.toJson(results[0]),
    leagueIds,
    keys: const ['id_league_home', 'id_league_away'],
  );
  final gameIds = <int>{
    for (final game in gameRows) _asInt(game['id_game'] ?? game['id']),
  };
  final playRows = [
    for (final row in Postgres.toJson(results[1]))
      if (gameIds.contains(_asInt(row['id_game']))) row,
  ];
  final battingLines = _battingLinesOf([
    for (final row in Postgres.toJson(results[2]))
      if (gameIds.contains(_asInt(row['id_game']))) row,
  ]);
  final playLabels = playLabelsByPlayer(playRows);
  for (final entry in battingLines.entries) {
    final filled = playsFilledFromLine(
      playLabels[entry.key] ?? '',
      homers: _asInt(entry.value['int_homerun']),
    );
    final numbered = playsWithHomerNumbers(filled, '${entry.value['txt_homerun_total'] ?? ''}');
    if (numbered.isNotEmpty) playLabels[entry.key] = numbered;
  }
  final plateFeats = <String, String>{};
  for (final entry in plateFeatMarksByPlayer(playRows).entries) {
    final text = _plateFeatConfirmed(entry.value, battingLines[entry.key]);
    if (text.isNotEmpty) plateFeats[entry.key] = text;
  }
  final games = _dedupeSameDayMatchups(_collapseGames(
    gameRows,
    playLabels,
    cycleMarksByPlayer(playRows),
    hitCountsByPlayer(playRows),
    plateFeats,
    maxInningByGame(playRows),
  ));
  _fillMissingLineScores(games, playRows);
  final lineups = battingLineupsOf(
    playRows,
    plays: playLabels,
    pitchers: pitcherKeysOf(gameRows),
    rbi: {for (final entry in battingLines.entries) entry.key: _asInt(entry.value['int_rbi'])},
    errors: {for (final entry in battingLines.entries) entry.key: _asInt(entry.value['int_error'])},
    starters: _lineupStartersOf(battingLines),
  );
  for (final game in games) {
    game['lineup'] = lineups[_asInt(game['id_game'])] ?? const <Map<String, dynamic>>[];
  }
  _attachLiveBatters(games, playRows);
  final window = windowFrom != null && windowTo != null
      ? (from: windowFrom, to: windowTo)
      : _defaultGamesWindow(year, games);
  final postseason = Postgres.toJson(results[3]);
  return {
    'org': org.code,
    'year': year,
    'part': 'games',
    'from': window.from,
    'to': window.to,
    'games': games,
    'postseason_games': _dedupeSameDayMatchups(postseason),
    'show_postseason_board':
        postseason.isNotEmpty || _showPostseasonBoard(Postgres.toJson(results[4])),
  };
}

Future<Map<String, dynamic>> _buildPredictionsPart(
  String part,
  OrgKind org,
  int year, {
  String? from,
  String? to,
}) {
  switch (part) {
    case 'info':
      return _buildPredictionsPartInfo(org);
    case 'standings':
      return _buildPredictionsPartStandings(org, year);
    case 'players':
      return _buildPredictionsPartPlayers(org, year);
    case 'games':
      return _buildPredictionsPartGames(org, year, from: from, to: to);
    default:
      throw ArgumentError('unknown part: $part');
  }
}

int _seasonYear(Request request, OrgKind org) {
  final current = DateTimeTool.getThisYear();
  final year = int.tryParse(request.url.queryParameters['year'] ?? '') ?? current;
  final first = org == OrgKind.mlb ? 1876 : 1936;
  if (year < first || year > current) {
    throw FormatException('${org.code} の年度は $first〜$current を指定してください');
  }
  return year;
}

bool _rowInLeagues(Map<String, dynamic> row, List<int> leagueIds, {List<String> keys = const ['id_league']}) {
  for (final key in keys) {
    final id = int.tryParse('${row[key] ?? ''}') ?? 0;
    if (leagueIds.contains(id)) return true;
  }
  return false;
}

List<Map<String, dynamic>> _filterByLeagues(List<Map<String, dynamic>> rows, List<int> leagueIds, {List<String> keys = const ['id_league']}) {
  return [for (final row in rows) if (_rowInLeagues(row, leagueIds, keys: keys)) row];
}

bool _showPostseasonBoard(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return false;
  final value = rows.first['flg_break'];
  if (value == true) return true;
  final text = '$value'.trim().toLowerCase();
  return text == 'true' || text == 't';
}

String _gameMatchupKey(Map<String, dynamic> game) {
  final id = '${game['id_game'] ?? ''}'.trim();
  if (id.isNotEmpty && id != 'null' && id != '0') return 'id:$id';
  return [
    '${game['date_game'] ?? ''}'.trim(),
    '${game['name_team_home'] ?? ''}'.trim(),
    '${game['name_team_away'] ?? ''}'.trim(),
    '${game['id_team_home'] ?? ''}'.trim(),
    '${game['id_team_away'] ?? ''}'.trim(),
  ].join('|');
}

String _dateOnly(dynamic value) {
  final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch('$value');
  return match?.group(0) ?? '$value'.trim();
}

String _gameNightDate(Map<String, dynamic> game) {
  final date = _dateOnly(game['date_game']);
  final time = '${game['time_game'] ?? game['datetime_start'] ?? ''}';
  final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(time);
  if (match == null) return date;
  final hour = int.tryParse(match.group(1) ?? '') ?? 12;
  if (hour <= 0 || hour >= 8) return date;
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  final prev = parsed.subtract(const Duration(days: 1));
  final month = prev.month.toString().padLeft(2, '0');
  final day = prev.day.toString().padLeft(2, '0');
  return '${prev.year}-$month-$day';
}

String _dayMatchupKey(Map<String, dynamic> game) {
  final home = _asInt(game['id_team_home']);
  final away = _asInt(game['id_team_away']);
  final a = home <= away ? home : away;
  final b = home <= away ? away : home;
  final code = '${game['code_game'] ?? ''}'.trim().toUpperCase();
  return '${_gameNightDate(game)}|$a|$b|$code';
}

bool _rowFinished(Map<String, dynamic> game) => '${game['state'] ?? ''}'.contains('試合終了');

bool _rowInProgress(Map<String, dynamic> game) {
  final state = '${game['state'] ?? ''}';
  return state.contains('試合中') || RegExp(r'\d+\s*回').hasMatch(state);
}

int _gameRowQuality(Map<String, dynamic> game) {
  var score = 0;
  final state = '${game['state'] ?? ''}';
  if (state.contains('試合終了')) score += 50;
  if (_rowInProgress(game)) score += 40;
  if ('${game['time_game'] ?? ''}'.trim().isNotEmpty) score += 20;
  final summaries = game['summaries'];
  if (summaries is List) score += summaries.length * 5;
  final idGame = _asInt(game['id_game'] ?? game['id']);
  if (idGame > 0 && idGame < 2000) score += 25;
  if ('${game['name_pitcher_home'] ?? ''}'.trim().isNotEmpty) score += 4;
  if ('${game['name_pitcher_away'] ?? ''}'.trim().isNotEmpty) score += 4;
  return score;
}

List<Map<String, dynamic>> _dedupeSameDayMatchups(List<Map<String, dynamic>> games) {
  if (games.length <= 1) return games;
  final buckets = <String, List<Map<String, dynamic>>>{};
  final order = <String>[];
  for (final game in games) {
    final key = _dayMatchupKey(game);
    if (!buckets.containsKey(key)) {
      order.add(key);
      buckets[key] = [];
    }
    buckets[key]!.add(game);
  }
  final out = <Map<String, dynamic>>[];
  for (final key in order) {
    final group = buckets[key]!;
    if (group.length == 1) {
      out.add(group.first);
      continue;
    }
    group.sort((a, b) => _gameRowQuality(b).compareTo(_gameRowQuality(a)));
    final finished = group.where(_rowFinished).toList();
    final distinctScores = finished.map((g) => '${g['score_home']}|${g['score_away']}').toSet();
    if (distinctScores.length > 1) {
      final best = <String, Map<String, dynamic>>{};
      for (final game in finished) {
        final scoreKey = '${game['score_home']}|${game['score_away']}';
        final prev = best[scoreKey];
        if (prev == null || _gameRowQuality(game) > _gameRowQuality(prev)) best[scoreKey] = game;
      }
      out.addAll(best.values);
      continue;
    }
    final hasYahoo = group.any(_yahooGameSource);
    final hasHistorical = group.any((game) => !_yahooGameSource(game) && _asInt(game['id_game'] ?? game['id']) >= 2000);
    if (hasYahoo && hasHistorical) {
      out.add(group.first);
      continue;
    }
    out.add(group.first);
  }
  return _mergeAdjacentScoreDupes(out);
}

bool _yahooGameSource(Map<String, dynamic> game) {
  final id = _asInt(game['id_game'] ?? game['id']);
  return id > 0 && id < 2000;
}

String _matchupCodeKey(Map<String, dynamic> game) {
  final home = _asInt(game['id_team_home']);
  final away = _asInt(game['id_team_away']);
  final a = home <= away ? home : away;
  final b = home <= away ? away : home;
  final code = '${game['code_game'] ?? ''}'.trim().toUpperCase();
  return '$a|$b|$code';
}

bool _yahooHistoricalMix(Map<String, dynamic> a, Map<String, dynamic> b) {
  return _yahooGameSource(a) != _yahooGameSource(b);
}

bool _rowUnstarted(Map<String, dynamic> game) => !_rowFinished(game) && !_rowInProgress(game);

bool _nearSameGameDay(Map<String, dynamic> a, Map<String, dynamic> b) {
  String dateOnly(dynamic value) {
    final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch('$value');
    return match?.group(0) ?? '$value'.trim();
  }

  if (dateOnly(a['date_game']) == dateOnly(b['date_game'])) return true;
  final left = DateTime.tryParse(_gameNightDate(a));
  final right = DateTime.tryParse(_gameNightDate(b));
  if (left == null || right == null) return false;
  return left.difference(right).inDays.abs() <= 1;
}

bool _importDuplicateOf(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (!_yahooHistoricalMix(a, b) || !_nearSameGameDay(a, b)) return false;
  if (_rowFinished(a) &&
      _rowFinished(b) &&
      '${a['score_home']}|${a['score_away']}' != '${b['score_home']}|${b['score_away']}') {
    return false;
  }
  return true;
}

List<Map<String, dynamic>> _mergeAdjacentScoreDupes(List<Map<String, dynamic>> games) {
  if (games.length <= 1) return games;
  final used = List<bool>.filled(games.length, false);
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < games.length; i++) {
    if (used[i]) continue;
    var best = games[i];
    final key = _matchupCodeKey(best);
    for (var j = i + 1; j < games.length; j++) {
      if (used[j] || _matchupCodeKey(games[j]) != key) continue;
      final other = games[j];
      if (!_nearSameGameDay(best, other)) continue;
      final finishedPair = _rowFinished(best) &&
          _rowFinished(other) &&
          '${best['score_home']}|${best['score_away']}' == '${other['score_home']}|${other['score_away']}';
      if (!finishedPair && !_importDuplicateOf(best, other)) continue;
      used[j] = true;
      if (_gameRowQuality(other) > _gameRowQuality(best)) best = other;
    }
    out.add(best);
  }
  return out;
}

bool _summaryIsPitcher(dynamic value) {
  if (value is bool) return value;
  final text = '$value'.trim().toLowerCase();
  return text == 'true' || text == 't' || text == '1';
}

int _asInt(dynamic value) => int.tryParse('$value') ?? (value is int ? value : 0);

bool _asBool(dynamic value) {
  if (value == true) return true;
  final text = '$value'.trim().toLowerCase();
  return text == 'true' || text == 't' || text == '1';
}

double _asDouble(dynamic value) => double.tryParse('$value') ?? (value is num ? value.toDouble() : 0);

bool _gameFinished(dynamic state) => '$state'.contains('試合終了');

bool _isStarter(Map<String, dynamic> row) {
  final name = '${row['name_full_summary'] ?? ''}'.trim();
  if (name.isEmpty) return false;
  return name == '${row['name_pitcher_home'] ?? ''}'.trim() || name == '${row['name_pitcher_away'] ?? ''}'.trim();
}

List<Map<String, dynamic>> _lineupStartersOf(Map<String, Map<String, dynamic>> lines) {
  return [
    for (final row in lines.values)
      if (_asInt(row['int_batting_order']) >= 1 && _asInt(row['int_batting_order']) <= 9)
        {
          'id_game': row['id_game'],
          'id_team': row['id_team'],
          'name_full': row['name_full'],
          'int_batting_order': row['int_batting_order'],
          'code_position_from': row['code_position_from'] ?? '',
        },
  ];
}

Map<String, Map<String, dynamic>> _battingLinesOf(List<Map<String, dynamic>> rows) {
  final lines = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    final name = '${row['name_full'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    lines[playPlayerKey(row['id_game'], row['id_team'], name)] = row;
  }
  return lines;
}

/// 公式成績に凡退がある選手は、速報の打席だけでは全打席安打・全打席出塁にしない。
String _plateFeatConfirmed(String playFeat, Map<String, dynamic>? line) {
  if (line == null) return playFeat;
  final hits = _asInt(line['int_hit1']) + _asInt(line['int_hit2']) + _asInt(line['int_hit3']) + _asInt(line['int_homerun']);
  final atBats = _asInt(line['int_batting']);
  final walks = _asInt(line['int_fourball']);
  final hbp = _asInt(line['int_dead_batting']);
  final sacrifices = _asInt(line['int_sacrifice']);
  final errors = _asInt(line['int_error']);
  if (atBats + hits + walks + hbp + sacrifices + errors == 0) return playFeat;
  return plateFeatsFromLine(
    atBats: atBats,
    hits: hits,
    walks: walks,
    hbp: hbp,
    sacrifices: sacrifices,
    errors: errors,
  );
}

String _summaryAchieve(Map<String, dynamic> row, Map<String, String> cycles, Map<String, int> hits, Map<String, String> plateFeats, Map<int, int> maxInning) {
  final key = playPlayerKey(row['id_game'], row['id_team_summary'], row['name_full_summary']);
  final marks = <String>[];
  final cycle = cycles[key] ?? '';
  if (cycle.isNotEmpty) marks.add(cycle);
  if (!_summaryIsPitcher(row['flg_pitcher'])) {
    final hitCount = (hits[key] ?? 0) > _asInt(row['int_hit_batting']) ? (hits[key] ?? 0) : _asInt(row['int_hit_batting']);
    final multi = multiHitMark(hitCount);
    if (multi.isNotEmpty) marks.add(multi);
    final plateFeat = plateFeats[key] ?? '';
    if (plateFeat.isNotEmpty) marks.add(plateFeat);
  }
  if (_summaryIsPitcher(row['flg_pitcher'])) {
    final gameId = _asInt(row['id_game']);
    final pitching = pitcherMarks(
      finished: _gameFinished(row['state']),
      starter: _isStarter(row),
      innings: _asDouble(row['double_inning_pitch']),
      pitches: _asInt(row['int_pitch']),
      hits: _asInt(row['int_hit_allowed']),
      walks: _asInt(row['int_walk_pitch']),
      hbp: _asInt(row['int_hbp_pitch']),
      runs: _asInt(row['int_runs_pitch']),
      earned: _asInt(row['int_runs_earned']),
      balks: _asInt(row['int_balk']),
      gameInnings: maxInning[gameId] ?? 0,
    );
    if (pitching.isNotEmpty) marks.add(pitching);
    final digits = doubleDigitStrikeouts(_asInt(row['int_strike_out']));
    if (digits.isNotEmpty) marks.add(digits);
  }
  return marks.join(' ');
}

String _summaryPitchTone(Map<String, dynamic> row) {
  if (!_summaryIsPitcher(row['flg_pitcher'])) return '';
  if (_asDouble(row['double_inning_pitch']) <= 0) return '';
  final points = pitcherPoints(
    innings: _asDouble(row['double_inning_pitch']),
    strikeouts: _asInt(row['int_strike_out']),
    runs: _asInt(row['int_runs_pitch']),
    hits: _asInt(row['int_hit_allowed']),
    walks: _asInt(row['int_walk_pitch']),
    hbp: _asInt(row['int_hbp_pitch']),
    starter: _isStarter(row),
  );
  return pitcherTone(points);
}

String _summaryPitchChips(Map<String, dynamic> row) {
  if (!_summaryIsPitcher(row['flg_pitcher'])) return '';
  return pitcherStatChips(
    innings: _asDouble(row['double_inning_pitch']),
    runs: _asInt(row['int_runs_pitch']),
    hits: _asInt(row['int_hit_allowed']),
    walks: _asInt(row['int_walk_pitch']),
    hbp: _asInt(row['int_hbp_pitch']),
    strikeouts: _asInt(row['int_strike_out']),
    pitches: _asInt(row['int_pitch']),
    starter: _isStarter(row),
  );
}

/// イニング得点が未保存の試合は、打席の得点から表を作る。
void _fillMissingLineScores(List<Map<String, dynamic>> games, List<Map<String, dynamic>> playRows) {
  final byGame = <int, List<Map<String, dynamic>>>{};
  for (final row in playRows) {
    byGame.putIfAbsent(_asInt(row['id_game']), () => []).add(row);
  }
  const hits = {'HIT1', 'HIT2', 'HIT3', 'HOMERUN'};
  for (final game in games) {
    final homeBlank = '${game['txt_scores_home'] ?? ''}'.trim().isEmpty;
    final awayBlank = '${game['txt_scores_away'] ?? ''}'.trim().isEmpty;
    if (!homeBlank && !awayBlank) continue;
    final rows = byGame[_asInt(game['id_game'])] ?? const <Map<String, dynamic>>[];
    if (rows.isEmpty) continue;
    final homeRuns = <int, int>{};
    final awayRuns = <int, int>{};
    final seenHits = <String>{};
    var homeHits = 0;
    var awayHits = 0;
    var maxInning = 0;
    for (final row in rows) {
      final inning = _asInt(row['int_inning']);
      if (inning <= 0) continue;
      if (inning > maxInning) maxInning = inning;
      final bottom = row['flg_bottom'] == true || '${row['flg_bottom']}'.trim() == 'true' || '${row['flg_bottom']}'.trim() == 't';
      final runs = _asInt(row['int_runs']);
      if (runs > 0) {
        final bucket = bottom ? homeRuns : awayRuns;
        bucket[inning] = (bucket[inning] ?? 0) + runs;
      }
      final result = '${row['code_result'] ?? ''}'.trim();
      if (!hits.contains(result)) continue;
      final key = '$inning|$bottom|${row['int_batting_order']}|${row['cnt_out']}|${row['name_full']}|$result';
      if (!seenHits.add(key)) continue;
      if (bottom) {
        homeHits++;
      } else {
        awayHits++;
      }
    }
    if (maxInning <= 0) continue;
    String line(Map<int, int> bucket) => [for (var i = 1; i <= maxInning; i++) '${bucket[i] ?? 0}'].join(',');
    int total(Map<int, int> bucket) => bucket.values.fold(0, (sum, n) => sum + n);
    if (homeBlank) {
      game['txt_scores_home'] = line(homeRuns);
      if (_asInt(game['int_runs_home']) <= 0) game['int_runs_home'] = total(homeRuns);
      if (_asInt(game['int_hit_home']) <= 0 && homeHits > 0) game['int_hit_home'] = homeHits;
    }
    if (awayBlank) {
      game['txt_scores_away'] = line(awayRuns);
      if (_asInt(game['int_runs_away']) <= 0) game['int_runs_away'] = total(awayRuns);
      if (_asInt(game['int_hit_away']) <= 0 && awayHits > 0) game['int_hit_away'] = awayHits;
    }
  }
}

({int inning, bool bottom})? _liveHalf(String state) {
  final match = RegExp(r'(\d+)\s*回\s*(表|裏)').firstMatch(state);
  if (match == null) return null;
  var inning = int.parse(match.group(1)!);
  var bottom = match.group(2) == '裏';
  final outs = RegExp(r'(\d+)\s*アウト').firstMatch(state);
  if (outs != null && int.parse(outs.group(1)!) >= 3) {
    if (!bottom) {
      bottom = true;
    } else {
      inning += 1;
      bottom = false;
    }
  }
  return (inning: inning, bottom: bottom);
}

bool _isLiveBattingResult(String result) {
  return const {
    'HIT1', 'HIT2', 'HIT3', 'HOMERUN',
    'OUT_FLY', 'OUT_GROUND', 'OUT_POP_UP', 'OUT_DOUBLE_PLAY', 'OUT_LINE_DRIVE',
    'SACRIFICE_BUNT', 'SACRIFICE_FLY', 'SQUEEZE',
    'STRIKE_OUT', 'DROPPED_THIRD', 'ERROR', 'WALK', 'WALK_DEAD',
    'ERROR_FIELDING', 'INTERFERENCE_BATTING', 'FIELDERS_CHOICE',
  }.contains(result);
}

void _attachLiveBatters(List<Map<String, dynamic>> games, List<Map<String, dynamic>> playRows) {
  final byGame = <int, List<Map<String, dynamic>>>{};
  for (final row in playRows) {
    byGame.putIfAbsent(_asInt(row['id_game']), () => []).add(row);
  }
  for (final game in games) {
    final half = _liveHalf('${game['state'] ?? ''}');
    if (half == null) continue;
    final teamId = half.bottom ? _asInt(game['id_team_home']) : _asInt(game['id_team_away']);
    if (teamId <= 0) continue;
    final rows = [
      for (final row in byGame[_asInt(game['id_game'] ?? game['id'])] ?? const <Map<String, dynamic>>[])
        if (_asInt(row['int_inning']) == half.inning &&
            (_asBool(row['flg_bottom']) == half.bottom) &&
            _isLiveBattingResult('${row['code_result'] ?? ''}'))
          row,
    ]..sort((a, b) => _asInt(a['id']).compareTo(_asInt(b['id'])));
    var nextOrder = 1;
    if (rows.isNotEmpty) {
      final last = _asInt(rows.last['int_batting_order']);
      nextOrder = last >= 9 ? 1 : last + 1;
    } else {
      final prevInning = half.bottom ? half.inning : half.inning - 1;
      final prevBottom = !half.bottom;
      if (prevInning > 0) {
        final prev = [
          for (final row in byGame[_asInt(game['id_game'] ?? game['id'])] ?? const <Map<String, dynamic>>[])
            if (_asInt(row['int_inning']) == prevInning &&
                _asBool(row['flg_bottom']) == prevBottom &&
                _isLiveBattingResult('${row['code_result'] ?? ''}'))
              row,
        ]..sort((a, b) => _asInt(a['id']).compareTo(_asInt(b['id'])));
        if (prev.isNotEmpty) {
          final last = _asInt(prev.last['int_batting_order']);
          nextOrder = last >= 9 ? 1 : last + 1;
        }
      }
    }
    var name = '';
    final lineup = game['lineup'];
    if (lineup is List) {
      for (final item in lineup) {
        if (item is! Map) continue;
        if (_asInt(item['id_team']) != teamId) continue;
        if (_asInt(item['order']) != nextOrder) continue;
        final players = item['players'];
        if (players is! List || players.isEmpty) continue;
        final last = players.last;
        if (last is Map) name = '${last['name'] ?? ''}'.trim();
      }
    }
    if (name.isEmpty) continue;
    game['name_batter'] = name;
    game['id_team_batter'] = teamId;
  }
}

List<Map<String, dynamic>> _collapseGames(
  List<Map<String, dynamic>> rows,
  Map<String, String> plays,
  Map<String, String> cycles,
  Map<String, int> hits,
  Map<String, String> plateFeats,
  Map<int, int> maxInning,
) {
  final order = <String>[];
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final key = _gameMatchupKey(row);
    if (!groups.containsKey(key)) {
      order.add(key);
      groups[key] = [];
    }
    groups[key]!.add(row);
  }
  return [
    for (final key in order)
      {
        ...groups[key]!.first,
        'summaries': _summariesOf(groups[key]!, plays, cycles, hits, plateFeats, maxInning),
      },
  ];
}

List<Map<String, dynamic>> _summariesOf(
  List<Map<String, dynamic>> rows,
  Map<String, String> plays,
  Map<String, String> cycles,
  Map<String, int> hits,
  Map<String, String> plateFeats,
  Map<int, int> maxInning,
) {
  final summaries = <Map<String, dynamic>>[
    for (final row in rows)
      if (row['id_game_summary'] != null || '${row['name_full_summary'] ?? ''}'.trim().isNotEmpty)
        {
          'id_game_summary': row['id_game_summary'],
          'id_team_summary': row['id_team_summary'],
          'name_full_summary': row['name_full_summary'],
          'txt_batting': row['txt_batting'],
          'txt_pitching': row['txt_pitching'],
          'txt_homerun_total': row['txt_homerun_total'],
          'flg_pitcher': row['flg_pitcher'],
          'flg_japan': row['flg_japan'],
          'code_result_pitcher': row['code_result_pitcher'],
          'colors_summary': row['colors_summary'],
          'titles_predict': row['titles_predict'],
          'txt_plays': _summaryIsPitcher(row['flg_pitcher'])
              ? ''
              : playsWithHomerNumbers(
                  plays[playPlayerKey(row['id_game'], row['id_team_summary'], row['name_full_summary'])] ?? '',
                  '${row['txt_homerun_total'] ?? ''}',
                ),
          'txt_achieve': _summaryAchieve(row, cycles, hits, plateFeats, maxInning),
          'txt_pitch_tone': _summaryPitchTone(row),
          'txt_pitch_chips': _summaryPitchChips(row),
          'int_velo_max': row['int_velo_max'],
        },
  ];
  final gameId = rows.isEmpty ? 0 : _asInt(rows.first['id_game']);
  final seen = <String>{
    for (final row in summaries) playPlayerKey(gameId, row['id_team_summary'], row['name_full_summary']),
  };
  final extra = <String>{
    ...cycles.keys,
    ...plateFeats.keys,
    for (final entry in hits.entries)
      if (entry.value >= 3) entry.key,
  };
  for (final key in extra) {
    if (!key.startsWith('$gameId|') || seen.contains(key)) continue;
    final parts = key.split('|');
    if (parts.length < 3) continue;
    final marks = <String>[];
    final cycle = cycles[key] ?? '';
    if (cycle.isNotEmpty) marks.add(cycle);
    final multi = multiHitMark(hits[key] ?? 0);
    if (multi.isNotEmpty) marks.add(multi);
    final plateFeat = plateFeats[key] ?? '';
    if (plateFeat.isNotEmpty) marks.add(plateFeat);
    if (marks.isEmpty) continue;
    summaries.add({
      'id_team_summary': parts[1],
      'name_full_summary': parts.sublist(2).join('|'),
      'flg_pitcher': false,
      'txt_plays': plays[key] ?? '',
      'txt_achieve': marks.join(' '),
    });
  }
  return summaries;
}

Future<void> _warmSchemaInBackground() async {
  try {
    await FetchURL.ensureGameDetailsVelo();
    await FetchURL.ensureAppColumns();
    unawaited(FetchURL.seedStadiumImagesAndTeamColors());
  } catch (e, st) {
    print('schema warm failed: $e\n$st');
  }
}

void main() async {
  try {
    final app = Router();
    final log = Value.SystemCode.Log;

    // ====== API ======

    app.get('/healthz', (Request _) => Response.ok('ok'));

    app.get('/fetchStatsTeamNPB', (Request request) async {
      final response = await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.STATS_TEAM, (conn) async {
        if (await FetchURL.isOfficialSeasonBreak(conn)) {
          print('シーズンオフのためチーム成績のスクレイピングを行いません');
          return Response.ok('offseason', headers: {'x-offseason': '1'});
        }
        return await FetchURL.fetchStatsTeamNPB(conn);
      });
      if (response.statusCode == 200 && response.headers['x-offseason'] != '1') _clearPredictionsCache();
      return response;
    });

    app.get('/fetchStatsPlayerNPB', (Request request) async {
      final response = await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.STATS_PLAYER, (conn) async {
        if (await FetchURL.isOfficialSeasonBreak(conn)) {
          print('シーズンオフのため個人成績のスクレイピングを行いません');
          return Response.ok('offseason', headers: {'x-offseason': '1'});
        }
        await FetchURL.fetchStatsPlayerNPB(conn);
        final scraped = await FetchURL.fetchStatsPlayerNPB(conn);
        await AceEvaluator.refresh(conn, OrgKind.npb.leagueIds);
        return scraped;
      });
      if (response.statusCode == 200 && response.headers['x-offseason'] != '1') _clearPredictionsCache();
      return response;
    });

    app.get('/fetchGamesNPB', (Request request) async {
      print('fetchGamesNPB');
      final response = await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.GAMES, (conn) async {
        if (await FetchURL.isOfficialSeasonBreak(conn)) {
          if (await Postseason.shouldKeepUpdating(conn)) {
            await Postseason.sync(conn);
            await FetchURL.refreshRecentPostseasonDetails(conn);
            return Response.ok('postseason');
          }
          print('シーズンオフのため試合情報のスクレイピングを行いません');
          return Response.ok('offseason', headers: {'x-offseason': '1'});
        }
        final scraped = await FetchURL.fetchGamesNPB(conn);
        if (await Postseason.isRegistrationOpen(conn)) {
          await Postseason.sync(conn);
        }
        return scraped;
      });
      if (response.statusCode == 200 && response.headers['x-offseason'] != '1') _clearPredictionsCache();
      return response;
    });

    app.get('/insertNewPlayersNPB', (Request request) async {
      print('insertNewPlayersNPB');
      return await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.GAMES, (conn) async {
        return await FetchURL.fetchNPBPlayers(conn);
      });
    });

    app.get('/fetchStatsTeamMLB', (Request request) async {
      final response = await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.STATS_TEAM, (conn) async {
        return await FetchMLB.fetchStatsTeam(conn);
      });
      if (response.statusCode == 200) _clearPredictionsCache();
      return response;
    });

    app.get('/fetchStatsPlayerMLB', (Request request) async {
      final response = await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.STATS_PLAYER, (conn) async {
        final scraped = await FetchMLB.fetchStatsPlayer(conn);
        await AceEvaluator.refresh(conn, OrgKind.mlb.leagueIds);
        return scraped;
      });
      if (response.statusCode == 200) _clearPredictionsCache();
      return response;
    });

    app.get('/refreshAceFlags', (Request request) async {
      return await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.STATS_PLAYER, (conn) async {
        await AceEvaluator.refreshAll(conn);
        return Response.ok('ok');
      });
    });

    app.get('/fetchGamesMLB', (Request request) async {
      print('fetchGamesMLB');
      final response = await tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.GAMES, (conn) async {
        return await FetchMLB.fetchGames(conn);
      });
      if (response.statusCode == 200) _clearPredictionsCache();
      return response;
    });

    app.post('/auth/register', (Request request) async {
      try {
        return await Auth.register(request);
      } catch (e, st) {
        print('auth/register ERROR: $e\n$st');
        return _authBusyOrError(e, '登録に失敗しました');
      }
    });

    app.post('/auth/login', (Request request) async {
      try {
        return await Auth.login(request);
      } catch (e, st) {
        print('auth/login ERROR: $e\n$st');
        return _authBusyOrError(e, 'ログインに失敗しました');
      }
    });

    app.get('/auth/me', (Request request) async {
      try {
        return await Auth.me(request);
      } catch (e, st) {
        print('auth/me ERROR: $e\n$st');
        return _authBusyOrError(e, '認証確認に失敗しました');
      }
    });

    app.post('/auth/logout', (Request request) async {
      try {
        return await Auth.logout(request);
      } catch (e, st) {
        print('auth/logout ERROR: $e\n$st');
        return Response.ok(
          jsonEncode({'ok': true}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.post('/auth/change-password', (Request request) async {
      try {
        return await Auth.changePassword(request);
      } catch (e, st) {
        print('auth/change-password ERROR: $e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': 'パスワード変更に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.post('/auth/profile', (Request request) async {
      try {
        return await Auth.updateProfile(request);
      } catch (e, st) {
        print('auth/profile ERROR: $e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '基本設定の保存に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.post('/auth/notifications', (Request request) async {
      try {
        return await Auth.updateNotifications(request);
      } catch (e, st) {
        print('auth/notifications ERROR: $e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '通知設定の保存に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.post('/auth/mark-read', (Request request) async {
      try {
        return await Auth.markRead(request);
      } catch (e, st) {
        print('auth/mark-read ERROR: $e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '既読更新に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.get('/auth/teams', (Request request) async {
      try {
        return await Auth.listTeams(request);
      } catch (e, st) {
        print('auth/teams ERROR: $e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': 'チーム一覧の取得に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.get('/auth/players', (Request request) async {
      try {
        return await Auth.listPlayers(request);
      } catch (e, st) {
        print('auth/players ERROR: $e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '選手一覧の取得に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    // 画面セクション単位の軽量取得（info / standings / players / games）
    // 初回表示を段階的に進めるため、重い games を待たずに他を返せる
    app.get('/predictions/part', (Request request) async {
      return await tryCatchAPIReadonly(request, log.Prediction.NAME, log.Prediction.Codes.ENTER_NPB, () async {
        final org = OrgKind.parse(request.url.queryParameters['org']);
        final year = _seasonYear(request, org);
        final part = (request.url.queryParameters['part'] ?? '').trim().toLowerCase();
        const allowed = {'info', 'standings', 'players', 'games'};
        if (!allowed.contains(part)) {
          return Response(
            400,
            body: jsonEncode({'ok': false, 'error': 'part は info|standings|players|games のいずれか'}),
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final window = part == 'games' ? _gamesQueryWindow(request, year) : (from: null, to: null);
        final cacheKey = window.from != null
            ? '${org.code}|$part|$year|${window.from}|${window.to}'
            : '${org.code}|$part|$year';
        final now = DateTime.now();
        if (request.url.queryParameters['fresh'] != '1') {
          final cachedBody = _predictionsPartCacheBody[cacheKey];
          final cachedAt = _predictionsPartCacheAt[cacheKey];
          if (cachedBody != null && cachedAt != null && now.difference(cachedAt) < _predictionsCacheTtl) {
            return Response.ok(
              cachedBody,
              headers: {
                'content-type': 'application/json; charset=utf-8',
                'x-cache': 'HIT',
                'x-org': org.code,
                'x-part': part,
              },
            );
          }
        }
        final payload = await _buildPredictionsPart(part, org, year, from: window.from, to: window.to);
        final body = jsonEncode(payload);
        _predictionsPartCacheBody[cacheKey] = body;
        _predictionsPartCacheAt[cacheKey] = DateTime.now();
        return Response.ok(
          body,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'x-cache': 'MISS',
            'x-org': org.code,
            'x-part': part,
          },
        );
      });
    });

    //タイトル予想画面の表示（並列取得・短TTLキャッシュ・読み取り専用で高速化）
    // ?org=npb|mlb で団体を切り替える（省略時は npb）
    app.get('/predictions', (Request request) async {
      return await tryCatchAPIReadonly(request, log.Prediction.NAME, log.Prediction.Codes.ENTER_NPB, () async {
        final org = OrgKind.parse(request.url.queryParameters['org']);
        final selectedYear = _seasonYear(request, org);
        final cacheKey = '${org.code}|$selectedYear';
        final now = DateTime.now();
        final cachedBody = _predictionsCacheBody[cacheKey];
        final cachedAt = _predictionsCacheAt[cacheKey];
        if (cachedBody != null && cachedAt != null && now.difference(cachedAt) < _predictionsCacheTtl) {
          return Response.ok(
            cachedBody,
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'x-cache': 'HIT',
              'x-org': org.code,
            },
          );
        }

        final current_year = selectedYear;
        final results = await Postgres.mapParallel([
          (conn) => Postgres.execute(conn, AppSql.selectPredictNPBTeams(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectPredictPlayer(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectStatsTeam(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectStatsPlayer(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectGames(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectGamePlayRows(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectEventsDetails()),
          (conn) => Postgres.execute(conn, AppSql.selectNotification()),
          (conn) => Postgres.execute(conn, AppSql.selectPostseasonGames(), data: [current_year]),
          (conn) => Postgres.execute(conn, AppSql.selectPostseasonBoard(), data: [
            Value.SystemCode.Code.ADMIN,
            Value.SystemCode.Key.DATE_FINAL_GAME,
            Value.SystemCode.Key.DATE_OPEN_GAME,
          ]),
          (conn) => Postgres.execute(conn, AppSql.selectBattingLines(), data: [current_year]),
        ]);
        final playRows = Postgres.toJson(results[5]);
        final gameRows = Postgres.toJson(results[4]);
        final battingLines = _battingLinesOf(Postgres.toJson(results[10]));
        final playLabels = playLabelsByPlayer(playRows);
        for (final entry in battingLines.entries) {
          final filled = playsFilledFromLine(
            playLabels[entry.key] ?? '',
            homers: _asInt(entry.value['int_homerun']),
          );
          final numbered = playsWithHomerNumbers(filled, '${entry.value['txt_homerun_total'] ?? ''}');
          if (numbered.isNotEmpty) playLabels[entry.key] = numbered;
        }
        final plateFeats = <String, String>{};
        for (final entry in plateFeatMarksByPlayer(playRows).entries) {
          final text = _plateFeatConfirmed(entry.value, battingLines[entry.key]);
          if (text.isNotEmpty) plateFeats[entry.key] = text;
        }
        final games = _dedupeSameDayMatchups(_collapseGames(
          gameRows,
          playLabels,
          cycleMarksByPlayer(playRows),
          hitCountsByPlayer(playRows),
          plateFeats,
          maxInningByGame(playRows),
        ));
        _fillMissingLineScores(games, playRows);
        final lineups = battingLineupsOf(
          playRows,
          plays: playLabels,
          pitchers: pitcherKeysOf(gameRows),
          rbi: {for (final entry in battingLines.entries) entry.key: _asInt(entry.value['int_rbi'])},
          errors: {for (final entry in battingLines.entries) entry.key: _asInt(entry.value['int_error'])},
          starters: _lineupStartersOf(battingLines),
        );
        for (final game in games) {
          game['lineup'] = lineups[_asInt(game['id_game'])] ?? const <Map<String, dynamic>>[];
        }
        _attachLiveBatters(games, playRows);
        // print(games);
        final leagueIds = org.leagueIds;
        final filteredGames = _filterByLeagues(games, leagueIds, keys: const ['id_league_home', 'id_league_away']);
        final payload = <String, dynamic>{
          'org': org.code,
          'year': current_year,
          'predict_team': _filterByLeagues(Postgres.toJson(results[0]), leagueIds),
          'predict_player': _filterByLeagues(Postgres.toJson(results[1]), leagueIds),
          'stats_team': _filterByLeagues(Postgres.toJson(results[2]), leagueIds),
          'stats_player': _filterByLeagues(Postgres.toJson(results[3]), leagueIds),
          'games': filteredGames,
          'events': org.code == 'npb' ? Postgres.toJson(results[6]) : const <Map<String, dynamic>>[],
          'notification': org.code == 'npb' ? Postgres.toJson(results[7]) : const <Map<String, dynamic>>[],
          'postseason_games': _dedupeSameDayMatchups(Postgres.toJson(results[8])),
          'show_postseason_board':
              Postgres.toJson(results[8]).isNotEmpty || _showPostseasonBoard(Postgres.toJson(results[9])),
        };
        final body = jsonEncode(payload);
        _predictionsCacheBody[cacheKey] = body;
        _predictionsCacheAt[cacheKey] = DateTime.now();
        return Response.ok(
          body,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'x-cache': 'MISS',
            'x-org': org.code,
          },
        );
      });
    });

    // 2) 静的ディレクトリの検出
    final candidates = [Directory('public'), Directory('backend/public')];
    Directory? publicDir;
    for (final d in candidates) {
      if (await d.exists() && File('${d.path}/index.html').existsSync()) {
        publicDir = d;
        break;
      }
    }

    // 3) ハンドラ作成（API → 静的の順で Cascade）
    Handler handler;
    if (publicDir != null) {
      final staticHandler = createStaticHandler(
        publicDir.path,
        defaultDocument: 'index.html',
      );

      // SPA fallback: 静的で 404 のときだけ index.html を返すラッパー
      Future<Response> staticWithSpa(Request req) async {
        final res = await staticHandler(req);
        if (res.statusCode == 404 && req.method == 'GET') {
          final index = File('${publicDir!.path}/index.html');
          if (await index.exists()) {
            return Response.ok(
              index.openRead(),
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
        }
        return res;
      }

      handler = Cascade()
          .add(app.call) // ← まず API
          .add(staticWithSpa) // ← 次に静的（+ SPA fallback）
          .handler;

      handler = Pipeline().addMiddleware(logRequests()).addMiddleware(corsHeaders()).addHandler(handler);

      stdout.writeln('🗂 Serving static from: ${publicDir.path}');
    } else {
      // 静的なし（dev表示）
      handler = Pipeline().addMiddleware(logRequests()).addMiddleware(corsHeaders()).addHandler((req) {
        if (req.url.path.isEmpty) {
          return Response.ok('Backend API (dev). Try /predictions', headers: {'content-type': 'text/plain; charset=utf-8'});
        }
        return app.call(req);
      });
    }

    final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
    final server = await io.serve(handler, InternetAddress.anyIPv4, port);
    print('✅ Server running on http://${server.address.host}:${server.port}'
        ' (serveStatic=${publicDir != null})');
    stdout.flush();

    unawaited(_warmSchemaInBackground());
    // イベント開始日・最終日に flg_read_event をリセット（15分ごと）
    unawaited(EventReadReset.tick());
    Timer.periodic(const Duration(minutes: 15), (_) {
      unawaited(EventReadReset.tick());
    });
    // 個人成績は初期表示では取らず、起動の数分後から定期登録する。
    PlayerStatsSchedule.start(onUpdated: _clearPredictionsCache);
  } catch (e, st) {
    print('🔥 void main ERROR: $e\n$st');
    stderr.writeln('🔥 /void main ERROR: $e\n$st');
  }
} // void main

Response _authBusyOrError(Object e, String fallback) {
  final busy = e is TimeoutException || Postgres.isBrokenConnection(e);
  return Response(
    busy ? 503 : 500,
    body: jsonEncode({
      'ok': false,
      'error': busy ? 'ログインが混み合っています。少し待って再度お試しください' : fallback,
    }),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

String _clipDb(String value, int max) {
  if (value.length <= max) return value;
  return value.substring(0, max);
}

void _printRequestError(Request request, Object e, StackTrace st) {
  print("⚠️⚠️⚠️⚠️⚠️⚠️ ERROR ⚠️⚠️⚠️⚠️⚠️⚠️");
  print('🔥 ${request.requestedUri.path} ERROR: $e\n$st');
  stderr.writeln('🔥 ${request.requestedUri.path} ERROR: $e\n$st');
}

void _notifyProgramError(Object e) {
  try {
    final username = 'hotateishi2012@yahoo.co.jp';
    final password = '199424';
    sendMail(username, password, 'プログラム上でエラーが発生しました', e.toString());
  } catch (_) {}
}

Future<int> _saveErrorLog(Object e, String stacktrace, m_user user) async {
  try {
    final id = await Postgres.withConnection((conn) async {
      return insertLogError(conn, e, stacktrace, user);
    });
    print("エラーログのDBに登録しました。");
    return id;
  } catch (e2, st2) {
    print("エラーログのDB登録に失敗しました。");
    print('🔥 error-log ERROR: $e2\n$st2');
    try {
      File('error_log.txt').writeAsStringSync(
        '${DateTimeTool.getNow("")}\n$e\n$stacktrace\n---\n$e2\n$st2\n\n',
        mode: FileMode.append,
      );
      print("エラーログをローカルディレクトリに書き込みました。");
    } catch (_) {}
    return 0;
  }
}

Future<void> _saveAccessLog(Request request, m_user user, int idError) async {
  try {
    await Postgres.withConnection((conn) async {
      final log = t_system_log();
      log.method = _clipDb(request.method, 20);
      log.category = _clipDb(user.category_system, 20);
      log.code = _clipDb(user.code_system, 20);
      log.memo = '';
      log.flg_user = user.flg_user;
      log.url = request.requestedUri.toString();
      log.url_pre = "";
      log.id_log_error = idError;
      log.flg_check = false;
      log.crtby = user.id;
      log.crtpgm = _clipDb(user.code_system, 30);
      log.updby = user.id;
      log.updpgm = _clipDb(user.code_system, 30);
      await Postgres.insert(conn, log);
    });
    print("操作ログを登録しました。【${user.code_system}】");
  } catch (e, st) {
    print('操作ログ登録失敗: $e\n$st');
  }
}

/// 読み取り専用API: トランザクションなし。ログINSERTのみ別接続で行う。
Future<Response> tryCatchAPIReadonly(
  Request request,
  String category_system,
  String code_system,
  Future<Response> Function() callback,
) async {
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  var id_error = 0;
  final user = m_user();
  var response = Response.ok('ok');
  user.category_system = category_system;
  user.code_system = code_system;
  user.flg_user = false;
  try {
    print("🌐Routing...【" + request.requestedUri.toString() + "】");
    // DDL は待たない。列確認・seed は裏で進め、試合 SELECT を先に返す。
    FetchURL.kickSchemaEnsures();
    response = await callback();
  } catch (e, st) {
    _printRequestError(request, e, st);
    id_error = await _saveErrorLog(e, st.toString(), user);
    _notifyProgramError(e);
    response = Response.internalServerError(body: 'データベースエラー: $e');
  } finally {
    if (request.requestedUri.path != '/predictions/part') {
      unawaited(_saveAccessLog(request, user, id_error));
    }
    print("🌐Responsed Successfully‼️【" + request.requestedUri.toString() + "】");
  }
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  return response;
}

Future<Response> tryCatchAPI(Request request, String category_system, String code_system, Future<Response> callback(Connection conn)) async {
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  var id_error = 0;
  final user = m_user();
  var response = Response.ok('ok');
  user.category_system = category_system;
  user.code_system = code_system;
  user.flg_user = false;
  try {
    await FetchURL.ensureGameDetailsVelo();
    await FetchURL.ensureAppColumns();
    await Postgres.openConnection((conn) async {
      await Postgres.transactionCommit(conn, () async {
        print("🌐Routing...【" + request.requestedUri.toString() + "】");
        print("");
        await user.loadProperty(conn, 0);
        user.category_system = category_system;
        user.code_system = code_system;
        user.flg_user = false;
        response = await callback(conn);
      });
    });
  } catch (e, st) {
    _printRequestError(request, e, st);
    id_error = await _saveErrorLog(e, st.toString(), user);
    _notifyProgramError(e);
    response = Response.internalServerError(body: 'データベースエラー: $e');
  } finally {
    unawaited(_saveAccessLog(request, user, id_error));
    print("🌐Responsed Successfully‼️【" + request.requestedUri.toString() + "】");
  }
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  return response;
}

void sendMail(String mailaddress, String password, String title, String text) async {
  // Yahoo SMTP
  final smtpServer = SmtpServer(
    'smtp.mail.yahoo.co.jp',
    port: 465,
    ssl: true,
    username: mailaddress,
    password: password,
  );

  final message = Message()
    ..from = Address(mailaddress, 'YakyuuJapan')
    ..recipients.add('hotateishi2018@gmail.com')
    ..subject = title
    ..text = text;

  final sendReport = await send(message, smtpServer);
  print('送信成功: ${sendReport.toString()}');
}

Future<int> insertLogError(Connection conn, Object e, String stacktrace, m_user user) async {
  final log_error = t_system_log_error();
  log_error.message_error = e.toString();
  log_error.stacktrace = stacktrace;
  log_error.flg_check = false;
  log_error.code_log_system = _clipDb(user.code_system, 20);
  log_error.crtby = user.id;
  log_error.crtpgm = _clipDb(user.code_system, 30);
  log_error.updby = user.id;
  log_error.updpgm = _clipDb(user.code_system, 30);
  return await Postgres.insert(conn, log_error);
}
