import 'app/GameVisibility.dart';
import 'app/GameStatsLoad.dart';
import 'app/AdminLogQuery.dart';
import 'app/InjuryList.dart';
import 'app/HomeDashboard.dart';
import 'app/VisitorSummary.dart';
import 'app/RequestMetrics.dart';
import 'app/SnapshotWork.dart';
import 'app/HomeRunVideoSearch.dart';
import 'app/AdminNews.dart';
import 'app/AdminBilling.dart';
import 'app/PlayerArt.dart';
import 'app/PlayerArtSchedule.dart';
import 'app/NpbResearch.dart';
import 'app/NpbResearchEvents.dart';
import 'app/AllStarHistory.dart';
import 'app/JapaneseMlbStats.dart';
import 'app/BaseballCatalog.dart';
import 'app/ErrorSnapshot.dart';
import 'app/GameScheduleWatch.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:postgres/postgres.dart';
import 'tools/DateTimeTool.dart';
import 'tools/Postgres.dart';
import 'app/DB/t_system_log.dart';
import 'app/DB/t_system_log_error.dart';
import 'app/DB/m_user.dart';
import 'app/AppSql.dart';
import 'app/Achieve.dart';
import 'app/AceEvaluator.dart';
import 'app/DisplaySnapshot.dart';
import 'app/PageSnapshot.dart';
import 'app/PlayerDisplay.dart';
import 'app/FieldingErrors.dart';
import 'app/TeamStrength.dart';
import 'app/RosterMoves.dart';
import 'app/AdditionalRecords.dart';
import 'app/VideoFeed.dart';
import 'app/HomeBirthdays.dart';
import 'app/VideoChannels.dart';
import 'app/ClubData.dart';
import 'app/PlayerDetailSnapshot.dart';
import 'app/PostseasonForm.dart';
import '../lib/logic/postseason_homers.dart';
import 'app/PlayerMetricSchedule.dart';
import 'app/GamesReadGate.dart';
import 'app/FetchURL.dart';
import 'app/LogDetail.dart';
import 'app/ScheduledLog.dart';
import 'app/GamesFetch.dart';
import 'app/FetchMLB.dart';
import 'app/Lineup.dart';
import 'app/OutboundMail.dart';
import 'app/OrgLeague.dart';
import 'app/PlayLabel.dart';
import 'app/Value.dart';
import 'app/Auth.dart';
import 'app/EventReadReset.dart';
import 'app/PlayerStatsSchedule.dart';
import 'app/PredictGroup.dart';
import 'app/PredictionSnapshot.dart';
import 'app/GameFetchSchedule.dart';

/// HOME reads existing snapshots and completed box scores; it never starts a fetch.
Future<Map<String, dynamic>> readHomeDashboard() async {
  final now = DateTime.now().toUtc().add(const Duration(hours: 9));
  final today = _ymdOf(now);
  final until = _ymdOf(now.add(const Duration(days: 6)));
  final results = await Future.wait([
    _buildPredictionsPartInfo(OrgKind.npb),
    _buildPredictionsPartGames(OrgKind.npb, now.year, from: today, to: until),
    _buildPredictionsPartGames(OrgKind.mlb, now.year, from: today, to: until),
    Postgres.withConnection((conn) async => <String, dynamic>{'stats_player': await DisplaySnapshot.players(conn, now.year)}),
    Postgres.withConnection((conn) async => <String, dynamic>{'birthdays': await homeBirthdays(conn, today)}),
  ]);
  final games = <Map<String, dynamic>>[
    for (final index in [1, 2])
      for (final game in results[index]['games'] as List)
        {...Map<String, dynamic>.from(game as Map), 'org': index == 1 ? 'NPB' : 'MLB'},
  ];
  final heroes = await Postgres.withConnection((conn) async {
    final lines = await homeHeroLines(conn, today);
    final result = <Map<String, dynamic>>[];
    for (final game in games.where((g) => g['date_game'] == today)) {
      final hero = homeHero(game, lines);
      if (hero == null) continue;
      final id = int.tryParse('${hero['id_player']}');
      final art = id == null ? null : await PlayerArt.read(conn, id);
      result.add({...hero, 'id_game': game['id_game'], 'org': game['org'],
        if (art != null) 'character_image': art});
    }
    return result;
  });
  return {
    'today': today,
    'birthdays': results[4]['birthdays'],
    'notification': results[0]['notification'],
    'events': results[0]['events'],
    'games': [for (final game in games) {
      for (final key in ['id_game', 'org', 'date_game', 'time_game', 'state', 'name_team_home', 'name_team_away', 'score_home', 'score_away']) key: game[key],
    }],
    'heroes': heroes,
    'leaders': homeLeaders([for (final row in results[3]['stats_player'] as List) Map<String, dynamic>.from(row as Map)]),
  };
}

/// /predictions 用の短TTLキャッシュ（同一プロセス内・団体別）
final Map<String, String> _predictionsCacheBody = {};
final Map<String, DateTime> _predictionsCacheAt = {};

/// /predictions/part 用（org|part）
final Map<String, String> _predictionsPartCacheBody = {};
final Map<String, Future<String>> _partBuildInflight = {};
final Map<String, DateTime> _predictionsPartCacheAt = {};

/// 試合パートで前回読んだ t_game の更新日時。同じなら集計SQLを出さない。
final Map<String, String> _predictionsGamesRevision = {};
final Map<String, String> _pendingGamesRevision = {};
const Duration _predictionsCacheTtl = Duration(seconds: 45);
int _predictionsCacheGeneration = 0;

void _clearPredictionsCache() {
  _predictionsCacheGeneration++;
  _partBuildInflight.clear();
  _predictionsCacheBody.clear();
  _predictionsCacheAt.clear();
  _predictionsPartCacheBody.clear();
  _predictionsPartCacheAt.clear();
  _predictionsGamesRevision.clear();
  _pendingGamesRevision.clear();
}

/// 該当 t_game の更新日時が前回と同じなら、試合集計のSQLを出さずに前回分を使う。
Future<Response?> _unchangedGamesResponse(
  OrgKind org,
  int year,
  String cacheKey,
  String? from,
  String? to, {
  required bool clientHasGames,
}) async {
  // 初回は再利用する本文がないため、更新確認のためだけのDB接続を省く。
  // 次回は revision 未登録として再取得し、その時点から更新判定を使う。
  if (_predictionsPartCacheBody[cacheKey] == null) return null;
  String revision;
  try {
    revision = await Postgres.withConnection(
      (conn) => GamesReadGate.revision(
        conn,
        leagueIds: org.leagueIds,
        year: year,
        from: from,
        to: to,
      ),
    );
  } catch (e, st) {
    print('t_game 更新日時の確認に失敗: $e');
    print(st);
    _pendingGamesRevision.remove(cacheKey);
    return null;
  }
  final cachedBody = _predictionsPartCacheBody[cacheKey];
  if (!GamesReadGate.reuse(
    cachedBody: cachedBody,
    previousRevision: _predictionsGamesRevision[cacheKey],
    revision: revision,
  )) {
    _pendingGamesRevision[cacheKey] = revision;
    return null;
  }
  // 画面がまだ試合を持っていないときは、集計SQLを出さずに前回の本文を返す。
  if (!clientHasGames && cachedBody != null) {
    return Response.ok(
      cachedBody,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'x-cache': 'UNCHANGED',
        'x-org': org.code,
        'x-part': 'games',
      },
    );
  }
  return Response.ok(
    jsonEncode({
      'ok': true,
      'unchanged': true,
      'part': 'games',
      'org': org.code,
      'year': year,
    }),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'x-cache': 'UNCHANGED',
      'x-org': org.code,
      'x-part': 'games',
    },
  );
}

Future<Map<String, dynamic>> _buildPredictionsPartInfo(OrgKind org) async {
  // ヘッダースコアは廃止。共通のお知らせを返すNPB以外ではDBを読まない。
  if (org.code != 'npb') {
    return {
      'org': org.code,
      'part': 'info',
      'events': const <Map<String, dynamic>>[],
      'notification': const <Map<String, dynamic>>[],
      'predict_team': const <Map<String, dynamic>>[],
    };
  }
  final results = await Postgres.mapParallel([
    (conn) => Postgres.execute(conn, AppSql.selectEventsDetails()),
    (conn) => Postgres.execute(conn, AppSql.selectNotification()),
  ]);
  return {
    'org': org.code,
    'part': 'info',
    'events': Postgres.toJson(results[0]),
    'notification': Postgres.toJson(results[1]),
    'predict_team': const <Map<String, dynamic>>[],
  };
}

Future<Map<String, dynamic>> _buildPredictionsPartStandings(OrgKind org, int year) async {
  final results = await Postgres.mapParallel([
    (conn) => PredictionSnapshot.teams(conn, year, org.leagueIds),
    (conn) => DisplaySnapshot.teams(conn, year),
  ]);
  final leagueIds = org.leagueIds;
  return {
    'org': org.code,
    'year': year,
    'part': 'standings',
    'predict_team': results[0],
    'stats_team': _filterByLeagues(results[1], leagueIds),
  };
}

Future<Map<String, dynamic>> _buildPredictionsPartPlayers(OrgKind org, int year) async {
  final watch = Stopwatch()..start();
  var acquiredMs = 0;
  final result = await Postgres.withConnection(
    (conn) {
      acquiredMs = watch.elapsedMilliseconds;
      return DisplaySnapshot.playerPart(conn, year, org.leagueIds);
    },
    urgent: true,
  );
  print('個人成績読取 ${org.code}/$year: 接続 ${acquiredMs}ms, '
      '取得 ${watch.elapsedMilliseconds - acquiredMs}ms, ${result.stats.length}件');
  return {
    'org': org.code,
    'year': year,
    'part': 'players',
    'predict_player': result.predictions,
    'stats_player': result.stats,
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
    from: _ymdOf(today.subtract(const Duration(days: AppSql.gamesPastDays))),
    to: _ymdOf(today.add(const Duration(days: AppSql.gamesFutureDays))),
  );
}

String _ymdOf(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

Future<void> _attachSavedForms(DisplayGames snap, List<Map<String, dynamic>> games, int year) async {
  final saved = {for (final row in snap.forms) _asInt(row['id_game']): row};
  final missing = <Map<String, dynamic>>[];
  for (final game in games) {
    final row = saved[_asInt(game['id_game'])];
    if (row == null || !row.containsKey('season_player_stats') || (npbPostseasonCodes.contains('${game['code_game']}'.toUpperCase()) && !row.containsKey('postseason_homers_before'))) { missing.add(game); continue; }
    game['postseason_form'] = row['postseason_form'];
    game['player_hands'] = row['player_hands'];
    game['season_player_stats'] = row['season_player_stats'];
    if (row.containsKey('postseason_homers_before')) game['postseason_homers_before'] = row['postseason_homers_before'];
  }
  // Compatibility with snapshots produced before form precomputation.
  if (missing.isNotEmpty) await Postgres.withConnection((conn) => attachPostseasonForm(conn, missing, year));
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
  final snap = await Postgres.withConnection(
    (conn) async {
      final snapshot=await DisplaySnapshot.games(conn, year, from: windowFrom, to: windowTo);
      return snapshot;
    },
  );
  windowFrom = snap.from;
  windowTo = snap.to;
  final leagueIds = org.leagueIds;
  final gameRows = _filterByLeagues(
    snap.games,
    leagueIds,
    keys: const ['id_league_home', 'id_league_away'],
  );
  final gameIds = <int>{
    for (final game in gameRows) _asInt(game['id_game'] ?? game['id']),
  };
  final playRows = [
    for (final row in snap.plays)
      if (gameIds.contains(_asInt(row['id_game']))) row,
  ];
  final battingLines = _battingLinesOf([
    for (final row in snap.batting)
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
  await _attachSavedForms(snap, games, year);
  _fillMissingLineScores(games, playRows);
  final lineups = battingLineupsOf(
    playRows,
    plays: playLabels,
    pitchers: pitcherKeysOf(gameRows),
    rbi: {for (final entry in battingLines.entries) entry.key: _asInt(entry.value['int_rbi'])},
    errors: {for (final entry in battingLines.entries) entry.key: _asInt(entry.value['int_error'])},
    starters: _lineupStartersOf(battingLines),
  );
  final fieldingErrors = fieldingErrorsByGame(snap.batting);
  for (final game in games) {
    game['lineup'] = lineups[_asInt(game['id_game'])] ?? const <Map<String, dynamic>>[];
    game['batting_summary'] = [for (final line in battingLines.values) if (_asInt(line['id_game']) == _asInt(game['id_game'])) {for (final key in ['id_team', 'name_full', 'int_batting', 'int_hit1', 'int_homerun', 'int_steal_base']) key: line[key]}];
    game['fielding_errors'] = fieldingErrors[_asInt(game['id_game'])] ?? const <Map<String, dynamic>>[];
    _useAnnouncedLineup(game);
  }
  _attachLiveBatters(games, playRows);
  final postseason = _postseasonForOrg(snap.postseason, org);
  return {
    'org': org.code,
    'year': year,
    'part': 'games',
    'from': windowFrom,
    'to': windowTo,
    'games': games,
    'postseason_games': _dedupeSameDayMatchups(postseason),
    'show_postseason_board': postseason.isNotEmpty || _showPostseasonBoard(snap.board),
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

const _npbPostseasonCodes = {'CS1', 'CSF', 'JS'};

/// ポストシーズンは団体ごとに分ける。NPB の応答に MLB のワールドシリーズを混ぜない。
List<Map<String, dynamic>> _postseasonForOrg(List<Map<String, dynamic>> rows, OrgKind org) {
  return [
    for (final row in rows)
      if (_postseasonRowForOrg(row, org)) row,
  ];
}

bool _postseasonRowForOrg(Map<String, dynamic> row, OrgKind org) {
  final code = '${row['code_game'] ?? ''}'.trim().toUpperCase();
  if (code.isEmpty) return false;
  final npb = _npbPostseasonCodes.contains(code);
  if (org == OrgKind.npb) return npb;
  return !npb;
}

List<Map<String, dynamic>> _filterByLeagues(List<Map<String, dynamic>> rows, List<int> leagueIds, {List<String> keys = const ['id_league']}) {
  return [
    for (final row in rows)
      if (_rowInLeagues(row, leagueIds, keys: keys)) row
  ];
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

/// 1〜7時台は前日夜に寄せるが、暦日が違う進行中・未開始は次のカードなので残す。
List<Map<String, dynamic>> _separateSeriesGames(
  List<Map<String, dynamic>> group,
  List<Map<String, dynamic>> kept,
) {
  final keptIds = <int>{};
  for (final game in kept) {
    final id = _asInt(game['id_game'] ?? game['id']);
    if (id > 0) keptIds.add(id);
  }
  final extras = <Map<String, dynamic>>[];
  for (final game in group) {
    final id = _asInt(game['id_game'] ?? game['id']);
    if (id > 0 && keptIds.contains(id)) continue;
    if (_rowFinished(game)) continue;
    final day = _dateOnly(game['date_game']);
    if (kept.any((other) => _dateOnly(other['date_game']) == day)) continue;
    if (kept.any((other) => _yahooHistoricalMix(game, other))) continue;
    extras.add(game);
    if (id > 0) keptIds.add(id);
  }
  if (extras.isEmpty) return kept;
  return [...kept, ...extras];
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
      out.addAll(_separateSeriesGames(group, best.values.toList()));
      continue;
    }
    out.addAll(_separateSeriesGames(group, [group.first]));
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
  if (_rowFinished(a) && _rowFinished(b) && '${a['score_home']}|${a['score_away']}' != '${b['score_home']}|${b['score_away']}') {
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
      // 同スコアの連日は、Yahoo と歴史取り込みの二重、または同じ夜の日付ずれだけを1件にする。
      // 日本シリーズのように翌日も同じ点差で終わった別試合は残す。
      final sameNight = _gameNightDate(best) == _gameNightDate(other);
      final sameScore = '${best['score_home']}|${best['score_away']}' == '${other['score_home']}|${other['score_away']}';
      final finishedPair = _rowFinished(best) && _rowFinished(other) && sameScore && (_yahooHistoricalMix(best, other) || sameNight);
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

List<Map<String, dynamic>>? _predictMaps(dynamic raw) {
  if (raw == null) return null;
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

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

/// 打席記録がまだ無い試合前は、発表済みスタメンを詳細欄に出す。
void _useAnnouncedLineup(Map<String, dynamic> game) {
  final current = game['lineup'];
  final raw = '${game['txt_lineup_announced'] ?? ''}'.trim();
  game.remove('txt_lineup_announced');
  if (raw.isEmpty) return;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List && decoded.isNotEmpty) {
      game['lineup'] = mergeAnnouncedLineup(current is List ? current : [], decoded);
    }
  } catch (_) {}
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

({int inning, bool bottom})? _statedHalf(String state) {
  final match = RegExp(r'(\d+)\s*回\s*(表|裏)').firstMatch(state);
  if (match == null) return null;
  return (inning: int.parse(match.group(1)!), bottom: match.group(2) == '裏');
}

int? _outsInState(String state) {
  final match = RegExp(r'(\d+)\s*アウト').firstMatch(state);
  if (match != null) return int.parse(match.group(1)!);
  if (state.contains('三死') || state.contains('三アウト')) return 3;
  return null;
}

({int inning, bool bottom})? _liveHalf(String state, {int? playOuts}) {
  final stated = _statedHalf(state);
  if (stated == null) return null;
  var inning = stated.inning;
  var bottom = stated.bottom;
  final outs = _outsInState(state) ?? ((playOuts != null && playOuts > 0) ? playOuts : null);
  if (outs != null && outs >= 3) {
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
    'HIT1',
    'HIT2',
    'HIT3',
    'HOMERUN',
    'OUT_FLY',
    'OUT_GROUND',
    'OUT_POP_UP',
    'OUT_DOUBLE_PLAY',
    'OUT_LINE_DRIVE',
    'SACRIFICE_BUNT',
    'SACRIFICE_FLY',
    'SQUEEZE',
    'STRIKE_OUT',
    'DROPPED_THIRD',
    'ERROR',
    'WALK',
    'WALK_DEAD',
    'ERROR_FIELDING',
    'INTERFERENCE_BATTING',
    'FIELDERS_CHOICE',
  }.contains(result);
}

void _attachLiveBatters(List<Map<String, dynamic>> games, List<Map<String, dynamic>> playRows) {
  final byGame = <int, List<Map<String, dynamic>>>{};
  for (final row in playRows) {
    byGame.putIfAbsent(_asInt(row['id_game']), () => []).add(row);
  }
  for (final game in games) {
    final state = '${game['state'] ?? ''}';
    final gameId = _asInt(game['id_game'] ?? game['id']);
    final all = byGame[gameId] ?? const <Map<String, dynamic>>[];
    final stated = _statedHalf(state);
    var playOuts = 0;
    if (stated != null) {
      for (final row in all) {
        if (_asInt(row['int_inning']) != stated.inning || _asBool(row['flg_bottom']) != stated.bottom) continue;
        final after = outsAfterPlate(_asInt(row['cnt_out']), '${row['code_result'] ?? ''}');
        if (after > playOuts) playOuts = after;
      }
    }
    if (playOuts > 0) game['int_outs'] = playOuts;
    final half = _liveHalf(state, playOuts: playOuts);
    if (half == null) continue;
    final teamId = half.bottom ? _asInt(game['id_team_home']) : _asInt(game['id_team_away']);
    if (teamId <= 0) continue;
    final rows = [
      for (final row in all)
        if (_asInt(row['int_inning']) == half.inning && (_asBool(row['flg_bottom']) == half.bottom) && _isLiveBattingResult('${row['code_result'] ?? ''}')) row,
    ]..sort((a, b) => _asInt(a['id']).compareTo(_asInt(b['id'])));
    var nextOrder = 1;
    if (rows.isNotEmpty) {
      final last = _asInt(rows.last['int_batting_order']);
      nextOrder = last >= 9 ? 1 : last + 1;
    } else {
      final prevInning = half.inning - 1;
      final prevBottom = half.bottom;
      if (prevInning > 0) {
        final prev = [
          for (final row in all)
            if (_asInt(row['int_inning']) == prevInning && _asBool(row['flg_bottom']) == prevBottom && _isLiveBattingResult('${row['code_result'] ?? ''}')) row,
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
    game['int_batter_order'] = nextOrder;
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
          'pitching_hand': row['pitching_hand'],
          'batting_hand': row['batting_hand'],
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
          'int_balk': row['int_balk'],
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

Future<Map<String, dynamic>?> _savePredictionChange(
  Connection conn,
  Future<Map<String, dynamic>?> Function() save,
) async {
  final result = await save();
  if (result != null && result['error'] == null) {
    await PredictionSnapshot.refreshAfterSave(conn, result);
    _clearPredictionsCache();
  }
  return result;
}

Future<void> _warmSchemaInBackground() async {
  try {
    await Postgres.withConnection(Auth.ensureSchema);
    await FetchURL.ensureGameDetailsVelo();
    await FetchURL.ensureAppColumns();
    unawaited(FetchURL.seedStadiumImagesAndTeamColors());
    await Postgres.withConnection((conn) async {
      // 起動時は既存スナップショットを利用する。全件再集計をキューへ
      // 積むと、scrape のトランザクションと初期表示が互いを待ってしまう。
      // 更新は各取得処理の完了時に行い、未作成の期間だけ読み出し時に補う。
      await DisplaySnapshot.ensure(conn);
      await TeamStrength.ensure(conn);
    });
  } catch (e, st) {
    print('schema warm failed: $e\n$st');
  }
}

void main() async {
  try {
    final app = Router();
    final videoFeed = VideoFeedService();
    await videoFeed.start(snapshotPath: Platform.environment['VIDEO_CACHE_PATH'] ?? '.dart_tool/video-feed-v2.json');
    final mlbVideoFeed = VideoFeedService(channels: mlbVideoChannels);
    await mlbVideoFeed.start(snapshotPath: Platform.environment['MLB_VIDEO_CACHE_PATH'] ?? '.dart_tool/mlb-video-feed-v2.json');
    final log = Value.SystemCode.Log;

    // ====== API ======

    app.get('/home', (Request request) async {
      return tryCatchAPIReadonly(request, 'HOME', 'READ', () async {
        return Response.ok(jsonEncode(await readHomeDashboard()), headers: {'content-type': 'application/json; charset=utf-8'});
      });
    });

    app.get('/healthz', (Request _) => Response.ok('ok'));

    app.get('/player-art/<filename>', (Request request, String filename) async {
      if (!RegExp(r'^(?:npb-)?\d+-[a-f0-9]{64}\.png$').hasMatch(filename)) return Response.notFound('Not found');
      final file = File('${PlayerArt.root}/$filename');
      if (!await file.exists()) return Response.notFound('Not found');
      return Response.ok(file.openRead(), headers: {'content-type': 'image/png', 'cache-control': 'public, max-age=86400', 'x-content-type-options': 'nosniff'});
    });
    app.get('/club-logos/<year>/<club>/<image>', (Request request,String year,String club,String image) async {
      if(!RegExp(r'^\d{4}$').hasMatch(year)||!npbClubNames.containsKey(club)||!RegExp(r'^[a-z0-9]+\.(png|jpg|jpeg|gif|webp)$').hasMatch(image))return Response.notFound('Not found');
      for(final root in ['public','backend/public']) {
        final file=File('$root/club-logos/$year/$club/$image');
        if(await file.exists())return Response.ok(file.openRead(),headers:{'content-type':'image/${image.endsWith('.jpg')?'jpeg':image.split('.').last}','cache-control':'public, max-age=86400'});
      }
      return Response.notFound('Not found');
    });
    app.get('/player-detail', (Request request) async {
      const headers={'content-type':'application/json; charset=utf-8'};
      try {
        final org=OrgKind.parse(request.url.queryParameters['org']);
        final year=_seasonYear(request,org);
        final query=request.url.queryParameters;
        if((query['name']??'').length>100)throw const FormatException('選手名が長すぎます');
        final identity=<String,dynamic>{'name':query['name']??'',if(query['id_player']!=null)'id_player':int.tryParse(query['id_player']!),if(query['id_team']!=null)'id_team':int.tryParse(query['id_team']!),if(query['source_player_id']!=null)'source_player_id':query['source_player_id']};
        final data=await Postgres.withConnection((conn)=>PlayerDetailSnapshot.read(conn,year:year,leagues:org.leagueIds,identity:identity),urgent:true);
        return Response.ok(jsonEncode(data),headers:headers);
      } on FormatException catch(e) {return Response.badRequest(body:jsonEncode({'error':e.message}),headers:headers);
      } catch(e,st) {_printRequestError(request,e,st);return Response.internalServerError(body:jsonEncode({'error':'選手情報を取得できませんでした'}),headers:headers);}
    });

    app.get('/club-hub', (Request request) async {
      const headers={'content-type':'application/json; charset=utf-8'};
      try {final org=OrgKind.parse(request.url.queryParameters['org']);final year=_seasonYear(request,org);
        return Response.ok(jsonEncode(readClubFile('club-hub-${org.code}-$year.json')),headers:headers);
      } on FormatException catch(e){return Response.badRequest(body:jsonEncode({'error':e.message}),headers:headers);}
    });
    app.get('/season-schedule', (Request request) async {
      const headers={'content-type':'application/json; charset=utf-8','cache-control':'no-store'};
      try {
        final org=OrgKind.parse(request.url.queryParameters['org']);
        final year=int.tryParse(request.url.queryParameters['year']??'')??DateTimeTool.getThisYear();
        if(year<(org==OrgKind.mlb?1876:1936)||year>DateTimeTool.getThisYear()+1)throw const FormatException('指定年度の日程は対象外です');
        final data=await Postgres.withConnection((conn)=>PageSnapshot.read(conn,kind:'schedule',org:org,year:year),urgent:true);
        return Response.ok(jsonEncode(data),headers:headers);
      } on FormatException catch(e){return Response.badRequest(body:jsonEncode({'error':e.message}),headers:headers);
      } catch(error,stack) {
        _printRequestError(request,error,stack);
        return Response.internalServerError(body:jsonEncode({'error':'日程を取得できませんでした'}),headers:headers);
      }
    });

    app.get('/home-run-video', (Request request) async {
      final q = request.url.queryParameters;
      final name = (q['name'] ?? '').trim(), opponent = q['opponent'] ?? '';
      final date = DateTime.tryParse(q['date'] ?? '');
      if (name.length < 2 || name.length > 80 || opponent.length > 80 || date == null ||
          date.year < 2000 || date.year > DateTime.now().year + 1) {
        return Response.badRequest(body: 'Invalid search');
      }
      final channels = await searchHomeRunVideos(name, date, opponent, q['pacific'] == '1');
      return Response.ok(jsonEncode({'channels': channels}), headers: {'content-type':'application/json; charset=utf-8'});
    });

    app.get('/videos', (Request request) async {
      final org = request.url.queryParameters['org'] ?? 'npb';
      if (org != 'npb' && org != 'mlb') return Response.badRequest(body: 'Unknown organization');
      final feed = org == 'mlb' ? mlbVideoFeed : videoFeed;
      final background = request.url.queryParameters['background'] == '1';
      if (background && request.url.queryParameters['refresh'] == '1') unawaited(feed.refresh());
      return Response.ok(jsonEncode(!background && request.url.queryParameters['refresh'] == '1'
          ? await feed.refresh() : feed.cached()), headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
      });
    });

    app.get('/baseball-catalog', (Request request) async {
      const headers = {'content-type': 'application/json; charset=utf-8'};
      final section = request.url.queryParameters['section'];
      if (!['stadiums','uniforms','hall'].contains(section)) return Response.badRequest(body: '{}', headers: headers);
      try {
        final org = OrgKind.parse(request.url.queryParameters['org']);
        final year = _seasonYear(request, org);
        final data = await Postgres.withConnection((conn) => BaseballCatalog.read(conn, org: org, year: year, section: section!));
        return Response.ok(jsonEncode(data), headers: headers);
      } catch (error, stack) {
        _printRequestError(request, error, stack);
        return Response.internalServerError(body: jsonEncode({'error': '情報を取得できませんでした'}), headers: headers);
      }
    });

    app.get('/mlb-japanese-stats', (Request request) async {
      const headers = {'content-type': 'application/json; charset=utf-8'};
      try {
        final year = _seasonYear(request, OrgKind.mlb);
        final data = await Postgres.withConnection((conn) => readJapaneseMlbStats(conn, year), urgent: true);
        return Response.ok(jsonEncode(data), headers: headers);
      } on FormatException catch (error) {
        return Response.badRequest(body: jsonEncode({'error': error.message}), headers: headers);
      } catch (error, stack) {
        _printRequestError(request, error, stack);
        return Response.internalServerError(body: jsonEncode({'error': '日本人選手の成績を取得できませんでした'}), headers: headers);
      }
    });

    app.get('/draft-research', (Request request) async {
      const headers = {'content-type': 'application/json; charset=utf-8'};
      try {
        final year = _seasonYear(request, OrgKind.npb);
        final years = await Postgres.withConnection((c) => NpbResearchEvents.drafts(c, year, request.url.queryParameters['active'] == 'true'));
        return Response.ok(jsonEncode({'years': years}), headers: headers);
      } catch (error, stack) {
        _printRequestError(request, error, stack);
        return Response.internalServerError(body: '{}', headers: headers);
      }
    });

    app.get('/allstar-history', (Request request) async {
      const headers = {'content-type': 'application/json; charset=utf-8'};
      try {
        final year = _seasonYear(request, OrgKind.npb);
        return Response.ok(jsonEncode(readAllStarHistory(year)), headers: headers);
      } on FormatException catch (error) {
        return Response.badRequest(body: jsonEncode({'error': error.message}), headers: headers);
      } catch (error, stack) {
        _printRequestError(request, error, stack);
        return Response.internalServerError(body: jsonEncode({'error': 'オールスター情報を取得できませんでした'}), headers: headers);
      }
    });

    app.get('/regular-history', (Request request) async {
      const headers = {'content-type': 'application/json; charset=utf-8'};
      try {
        final org = OrgKind.parse(request.url.queryParameters['org']);
        final year = _seasonYear(request, org);
        final rows = await Postgres.withConnection((conn) => readRegularHistory(conn, org, year), urgent: true);
        return Response.ok(jsonEncode({'regular_history': rows}), headers: headers);
      } on FormatException catch (error) {
        return Response.badRequest(body: jsonEncode({'error': error.message}), headers: headers);
      } catch (error, stack) {
        _printRequestError(request, error, stack);
        return Response.internalServerError(body: jsonEncode({'error': 'レギュラー情報を取得できませんでした'}), headers: headers);
      }
    });

    app.get('/records', (Request request) async {
      const headers = {'content-type': 'application/json; charset=utf-8'};
      try {
        final org = OrgKind.parse(request.url.queryParameters['org']);
        final year = _seasonYear(request, org);
        final data = await Postgres.withConnection((conn) => PageSnapshot.read(conn, kind: 'records', org: org, year: year, section: request.url.queryParameters['section']), urgent: true);
        return Response.ok(jsonEncode(data), headers: headers);
      } on FormatException catch (error) {
        return Response.badRequest(body: jsonEncode({'error': error.message}), headers: headers);
      } catch (error, stack) {
        _printRequestError(request, error, stack);
        return Response.internalServerError(body: jsonEncode({'error': '記録情報を取得できませんでした'}), headers: headers);
      }
    });

    app.get('/injuries', (Request request) async {
      return tryCatchAPIReadonly(request, 'INJURIES', 'READ', () async {
        final org = OrgKind.parse(request.url.queryParameters['org']);
        final rows = await Postgres.withConnection((conn) => InjuryList.read(conn, leagueIds: org.leagueIds));
        return Response.ok(jsonEncode({'players': rows}), headers: {'content-type': 'application/json; charset=utf-8'});
      });
    });

    app.get('/team-strength', (Request request) async {
      const headers = {'content-type': 'application/json; charset=utf-8'};
      try {
        final org = OrgKind.parse(request.url.queryParameters['org']);
        final year = _seasonYear(request, org);
        final data = await Postgres.withConnection(
          (conn) => TeamStrength.read(conn, org: org.code, year: year),
          urgent: true,
        );
        return Response.ok(jsonEncode(data), headers: headers);
      } on FormatException catch (error) {
        return Response.badRequest(body: jsonEncode({'error': error.message}), headers: headers);
      } catch (error, stack) {
        _printRequestError(request, error, stack);
        return Response.internalServerError(body: jsonEncode({'error': '戦力情報を取得できませんでした'}), headers: headers);
      }
    });

    app.post('/predict-group-name', (Request request) async {
      try {
        final body = jsonDecode(await request.readAsString());
        if (body is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '不正な要求です'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final saved = await Postgres.withConnection((conn) async {
          final userId = await Auth.userIdOf(conn, request);
          if (userId == null) return 'login';
          return _savePredictionChange(
              conn,
              () => PredictGroup.updateName(
                    conn,
                    id: int.tryParse('${body['id']}') ?? 0,
                    name: '${body['txt_name'] ?? ''}',
                    updby: userId,
                  ));
        });
        if (saved == 'login') {
          return Response(401, body: jsonEncode({'ok': false, 'error': 'ログインしてください'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': 'グループ名を保存できませんでした'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return Response.ok(jsonEncode({'ok': true, 'group': saved}), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('グループ名の保存に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': 'グループ名の保存に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.post('/predict-settings', (Request request) async {
      try {
        final body = jsonDecode(await request.readAsString());
        if (body is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '不正な要求です'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final saved = await Postgres.withConnection((conn) async {
          final userId = await Auth.userIdOf(conn, request);
          if (userId == null) return 'login';
          return _savePredictionChange(
              conn,
              () => PredictGroup.updateSetting(
                    conn,
                    id: int.tryParse('${body['id_setting']}') ?? 0,
                    dateLimitTeam: '${body['date_limit_team'] ?? ''}'.trim(),
                    dateLimitPlayer: '${body['date_limit_player'] ?? ''}'.trim(),
                    codeSelect: '${body['code_select'] ?? ''}'.trim(),
                    samePlayerLimit: int.tryParse('${body['int_same_player_limit']}') ?? 1,
                    codePoint: '${body['code_point'] ?? ''}'.trim(),
                    updby: userId,
                    titles: _predictMaps(body['titles']),
                    picks: _predictMaps(body['picks']),
                    ranks: _predictMaps(body['ranks']),
                    champions: _predictMaps(body['champions']),
                  ));
        });
        if (saved == 'login') {
          return Response(401, body: jsonEncode({'ok': false, 'error': 'ログインしてください'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is Map && '${saved['error'] ?? ''}'.isNotEmpty) {
          return Response(400, body: jsonEncode({'ok': false, 'error': saved['error']}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '予想設定を保存できませんでした'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        _clearPredictionsCache();
        return Response.ok(jsonEncode({'ok': true, 'setting': saved}), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('予想設定の保存に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '予想設定の保存に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.post('/predict-setting-vote', (Request request) async {
      try {
        final body = jsonDecode(await request.readAsString());
        if (body is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '不正な要求です'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final saved = await Postgres.withConnection((conn) async {
          final userId = await Auth.userIdOf(conn, request);
          if (userId == null) return 'login';
          return _savePredictionChange(
              conn,
              () => PredictGroup.approveProposal(
                    conn,
                    settingId: int.tryParse('${body['id_setting']}') ?? 0,
                    userId: userId,
                  ));
        });
        if (saved == 'login') {
          return Response(401, body: jsonEncode({'ok': false, 'error': 'ログインしてください'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is Map && '${saved['error'] ?? ''}'.isNotEmpty) {
          return Response(400, body: jsonEncode({'ok': false, 'error': saved['error']}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '賛成を保存できませんでした'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return Response.ok(jsonEncode({'ok': true, 'vote': saved}), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('予想ルールの賛成に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '賛成を保存できませんでした'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.get('/predict-names', (Request request) async {
      try {
        final params = request.url.queryParameters;
        final kind = params['kind'] ?? '';
        final leagueId = int.tryParse(params['league'] ?? '') ?? 0;
        final query = (params['q'] ?? '').trim();
        if (kind != 'player' && kind != 'team') {
          return Response(400, body: jsonEncode({'ok': false, 'error': '不正な要求です'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final names = query.isEmpty ? const <Map<String, dynamic>>[] : await Postgres.withConnection((conn) => PredictGroup.searchNames(conn, kind: kind, leagueId: leagueId, query: query));
        return Response.ok(jsonEncode({'names': names}), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('予想候補の取得に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '予想候補の取得に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.get('/predict-users', (Request request) async {
      try {
        final query = (request.url.queryParameters['q'] ?? '').trim();
        final names = await Postgres.withConnection((conn) async {
          final userId = await Auth.userIdOf(conn, request);
          if (userId == null) return 'login';
          return PredictGroup.searchUsers(conn, query: query, actorId: userId);
        });
        if (names == 'login') {
          return Response(401, body: jsonEncode({'ok': false, 'error': 'ログインしてください'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return Response.ok(jsonEncode({'users': names}), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('ユーザー検索に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': 'ユーザー検索に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.get('/predict-invites', (Request request) async {
      try {
        final invites = await Postgres.withConnection((conn) async {
          final userId = await Auth.readOnlyUserIdOf(conn, request);
          if (userId == null) return 'login';
          return PredictGroup.listInvites(conn, userId: userId);
        });
        if (invites == 'login') {
          return Response(401, body: jsonEncode({'ok': false, 'error': 'ログインしてください'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return Response.ok(jsonEncode({'invites': invites}), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('招待の取得に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '招待の取得に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.post('/predict-group', (Request request) async {
      try {
        final body = jsonDecode(await request.readAsString());
        if (body is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '不正な要求です'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final invitees = <int>[
          if (body['user_ids'] is List)
            for (final id in body['user_ids'] as List) int.tryParse('$id') ?? 0,
        ];
        final saved = await Postgres.withConnection((conn) async {
          final userId = await Auth.userIdOf(conn, request);
          if (userId == null) return 'login';
          return _savePredictionChange(conn, () => PredictGroup.createGroup(conn, name: '${body['txt_name'] ?? ''}', userId: userId, inviteeIds: invitees));
        });
        if (saved == 'login') {
          return Response(401, body: jsonEncode({'ok': false, 'error': 'ログインしてください'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is Map && '${saved['error'] ?? ''}'.isNotEmpty) {
          return Response(400, body: jsonEncode({'ok': false, 'error': saved['error']}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': 'グループを作成できませんでした'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return Response.ok(jsonEncode({'ok': true, 'group': saved}), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('グループの作成に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': 'グループの作成に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.post('/predict-invite-answer', (Request request) async {
      try {
        final body = jsonDecode(await request.readAsString());
        if (body is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '不正な要求です'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final saved = await Postgres.withConnection((conn) async {
          final userId = await Auth.userIdOf(conn, request);
          if (userId == null) return 'login';
          return _savePredictionChange(
              conn,
              () => PredictGroup.answerInvite(
                    conn,
                    inviteId: int.tryParse('${body['id']}') ?? 0,
                    userId: userId,
                    accept: body['accept'] == true || '${body['accept']}' == 'true',
                  ));
        });
        if (saved == 'login') {
          return Response(401, body: jsonEncode({'ok': false, 'error': 'ログインしてください'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is Map && '${saved['error'] ?? ''}'.isNotEmpty) {
          return Response(400, body: jsonEncode({'ok': false, 'error': saved['error']}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('招待への回答に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '招待への回答に失敗しました'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.post('/predict-group-delete', (Request request) async {
      try {
        final body = jsonDecode(await request.readAsString());
        if (body is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '不正な要求です'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final saved = await Postgres.withConnection((conn) async {
          final userId = await Auth.userIdOf(conn, request);
          if (userId == null) return 'login';
          return _savePredictionChange(conn, () => PredictGroup.requestDelete(conn, groupId: int.tryParse('${body['id']}') ?? 0, userId: userId));
        });
        if (saved == 'login') {
          return Response(401, body: jsonEncode({'ok': false, 'error': 'ログインしてください'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is Map && '${saved['error'] ?? ''}'.isNotEmpty) {
          return Response(400, body: jsonEncode({'ok': false, 'error': saved['error']}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '削除を保存できませんでした'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return Response.ok(jsonEncode({'ok': true, 'delete': saved}), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('グループ削除の保存に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '削除を保存できませんでした'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.post('/predict-year', (Request request) async {
      try {
        final body = jsonDecode(await request.readAsString());
        if (body is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '不正な要求です'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final saved = await Postgres.withConnection((conn) async {
          final userId = await Auth.userIdOf(conn, request);
          if (userId == null) return 'login';
          return _savePredictionChange(
              conn,
              () => PredictGroup.createYear(
                    conn,
                    groupId: int.tryParse('${body['id']}') ?? 0,
                    year: int.tryParse('${body['int_year']}') ?? 0,
                    userId: userId,
                  ));
        });
        if (saved == 'login') {
          return Response(401, body: jsonEncode({'ok': false, 'error': 'ログインしてください'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is Map && '${saved['error'] ?? ''}'.isNotEmpty) {
          return Response(400, body: jsonEncode({'ok': false, 'error': saved['error']}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (saved is! Map) {
          return Response(400, body: jsonEncode({'ok': false, 'error': '年度を追加できませんでした'}), headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return Response.ok(jsonEncode({'ok': true, 'year': saved}), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('年度の追加に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '年度を追加できませんでした'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

    app.get('/predict-groups', (Request request) async {
      try {
        final payload = await Postgres.withConnection((conn) async {
          final userId = await Auth.readOnlyUserIdOf(conn, request);
          return PredictionSnapshot.groupPayload(conn, userId: userId);
        });
        return Response.ok(jsonEncode(payload), headers: {'content-type': 'application/json; charset=utf-8'});
      } catch (e, st) {
        print('予想グループの取得に失敗しました: $e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'ok': false, 'error': '予想グループを読み込めませんでした'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    });

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
        final scraped = await FetchURL.fetchStatsPlayerNPB(conn);
        await AceEvaluator.refresh(conn, OrgKind.npb.leagueIds);
        return scraped;
      });
      if (response.statusCode == 200 && response.headers['x-offseason'] != '1') _clearPredictionsCache();
      return response;
    });

    app.get('/fetchGamesNPB', (Request request) async {
      print('fetchGamesNPB');
      final response = await SnapshotWork.run(() => tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.GAMES, GamesFetch.npb));
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
      final response = await SnapshotWork.run(() => tryCatchAPI(request, log.Fetch.NAME, log.Fetch.Codes.GAMES, GamesFetch.mlb));
      if (response.statusCode == 200) _clearPredictionsCache();
      return response;
    });

    app.post('/client/action', (Request request) async {
      return tryCatchAPI(request, 'CLIENT', 'ACTION', (conn) async {
        Map<String, dynamic> body = {};
        try {
          final decoded = jsonDecode(await request.readAsString());
          if (decoded is Map) body = Map<String, dynamic>.from(decoded);
        } catch (_) {}
        final action = '${body['action'] ?? ''}'.trim();
        if (!LogDetail.clientActions.contains(action)) {
          return Response(400, body: 'unknown action');
        }
        final reporter = m_user();
        await _attachRequestUser(conn, request, reporter);
        final year = int.tryParse('${body['year'] ?? ''}');
        final screen = '${body['screen_name'] ?? ''}'.trim();
        final log = t_system_log();
        log.method = 'VIEW';
        log.category = 'CLIENT';
        log.code = 'ACTION';
        log.memo = action;
        log.flg_user = reporter.id > 0;
        log.url = action == '年度を変更した' && year != null && year >= 1800 && year <= 2200 ? '$year年' : '';
        log.url_pre = '';
        log.id_log_error = 0;
        log.flg_check = false;
        log.crtby = reporter.id;
        log.crtpgm = 'CLIENT';
        log.updby = reporter.id;
        log.updpgm = 'CLIENT';
        log.crtenv = LogDetail.clip('${body['environment'] ?? 'web'}', 20);
        log.txt_detail = LogDetail.encode({
        ...LogDetail.clientInfo(request),
          'log_type': LogDetail.clientActionType(action),
          'level': 'INFO',
          'user_id': reporter.id,
          'session_id': LogDetail.clip('${body['session_id'] ?? ''}', 80),
          'request_id': LogDetail.clip('${body['request_id'] ?? _requestId(request)}', 64),
          'screen_name': screen.isEmpty ? LogDetail.screenOf(action) : LogDetail.clip(screen, 40),
          'action': action,
          'status': LogDetail.clip('${body['status'] ?? '成功'}', 20),
          'details': LogDetail.clip(year == null ? '${body['details'] ?? ''}' : '$year年', 500),
          'app_version': LogDetail.clip('${body['app_version'] ?? ''}', 20),
          'environment': log.crtenv,
          'source': 'client',
          'function_name': 'reportAction',
          'file_name': 'auth_session.dart',
          'api_path': '/client/action',
          'http_status': 200,
          'context': '',
        });
        final metrics = RequestMetrics.of(request);
        if (metrics == null) {
          await Postgres.insert(conn, log);
        } else {
          metrics.onComplete((values) async {
            log.txt_detail = LogDetail.encode({...LogDetail.decode(log.txt_detail), ...values});
            await Postgres.withConnection((c) => Postgres.insert(c, log));
          });
        }
        return Response.ok('ok');
      });
    });

    app.post('/client/error', (Request request) async {
      return tryCatchAPI(request, 'CLIENT', 'ERROR', (conn) async {
        Map<String, dynamic> body = {};
        try {
          final bytes = <int>[];
          await for (final chunk in request.read()) {
            if (bytes.length + chunk.length > 2100000) return Response(413, body: 'payload too large');
            bytes.addAll(chunk);
          }
          final decoded = jsonDecode(utf8.decode(bytes));
          if (decoded is Map) body = Map<String, dynamic>.from(decoded);
        } catch (_) {}
        final message = '${body['message'] ?? ''}'.trim();
        if (message.isEmpty) {
          return Response(400, body: 'message required');
        }
        final reporter = m_user();
        await _attachRequestUser(conn, request, reporter);
        reporter.category_system = 'CLIENT';
        reporter.code_system = message.toLowerCase().contains('timeout') ? 'TIMEOUT' : 'ERROR';
        final snapshotId = await ErrorSnapshotStore().save(body['snapshot_png']);
        final stack = LogDetail.clip('${body['stack'] ?? ''}', 4000);
        final frame = LogDetail.stackFrame(stack);
        await insertLogError(
          conn,
          message.length > 2000 ? message.substring(0, 2000) : message,
          stack,
          reporter,
          detail: {
            ...LogDetail.clientInfo(request),
            'log_type': 'エラー',
            'snapshot_id': snapshotId,
            'snapshot_status': snapshotId != null ? 'saved' : 'unavailable',
            'level': 'ERROR',
            'user_id': reporter.id,
            'session_id': LogDetail.clip('${body['session_id'] ?? ''}', 80),
            'request_id': LogDetail.clip('${body['request_id'] ?? _requestId(request)}', 64),
            'screen_name': LogDetail.clip('${body['screen_name'] ?? ''}', 40),
            'action': LogDetail.clip('${body['action'] ?? 'アプリエラー'}', 80),
            'status': '失敗',
            'details': LogDetail.clip('${body['details'] ?? ''}', 500),
            'app_version': LogDetail.clip('${body['app_version'] ?? ''}', 20),
            'environment': LogDetail.clip('${body['environment'] ?? 'web'}', 20),
            'error_type': LogDetail.clip('${body['error_type'] ?? 'Error'}', 80),
            'error_code': LogDetail.clip('${body['error_code'] ?? ''}', 40),
            'error_message': message.length > 2000 ? message.substring(0, 2000) : message,
            'source': LogDetail.clip('${body['source'] ?? 'client'}', 40),
            'function_name': LogDetail.clip('${body['function_name'] ?? frame['function_name'] ?? ''}', 80),
            'file_name': LogDetail.clip('${body['file_name'] ?? frame['file_name'] ?? ''}', 80),
            'line_number': LogDetail.clip('${body['line_number'] ?? frame['line_number'] ?? ''}', 10),
            'stack_trace': stack,
            'api_path': LogDetail.clip('${body['api_path'] ?? ''}', 120),
            'http_status': body['http_status'] ?? '',
            'duration_ms': body['duration_ms'] ?? '',
            'context': LogDetail.clip('${body['context'] ?? ''}', 1000),
          },
        );
        return Response.ok('ok');
      });
    });

    app.get('/admin/logs/snapshot/<id>', (Request request, String id) async {
      return tryCatchAPI(request, 'ADMIN', 'SNAPSHOT', (conn) async {
        if (await Auth.adminUserId(conn, request) == null) return Response(403, body: 'forbidden');
        final bytes = await ErrorSnapshotStore().read(id);
        if (bytes == null) return Response.notFound('snapshot not found');
        return Response.ok(bytes, headers: {'content-type': 'image/png', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff'});
      });
    });

    app.get('/admin/billing', (Request request) async =>
        tryCatchAPI(request, 'ADMIN', 'BILLING_READ', (conn) => AdminBilling.read(conn, request)));
    app.post('/admin/billing', (Request request) async =>
        tryCatchAPI(request, 'ADMIN', 'BILLING_SAVE', (conn) => AdminBilling.save(conn, request)));

    app.get('/admin/news', (Request request) async =>
        tryCatchAPI(request, 'ADMIN', 'NEWS_READ', (conn) => AdminNews.read(conn, request)));
    app.post('/admin/news', (Request request) async =>
        tryCatchAPI(request, 'ADMIN', 'NEWS_CREATE', (conn) async {
          final response = await AdminNews.create(conn, request);
          if (response.statusCode == 201) _clearPredictionsCache();
          return response;
        }));

    app.get('/admin/logs', (Request request) async {
      return tryCatchAPI(request, 'ADMIN', 'LOGS', (conn) async {
        final adminId = await Auth.adminUserId(conn, request);
        if (adminId == null) return Response(403, body: 'forbidden');
        final visitorNow = DateTime.now().toUtc();
        final visitorRows = await conn.execute(
          "SELECT crtby, crtat, txt_detail FROM t_system_log WHERE category = 'CLIENT' AND code = 'ACTION' AND COALESCE(crtby, 0) NOT IN (1, 2) AND crtat >= \$1",
          parameters: [visitorNow.subtract(const Duration(days: 30))],
        );
        final visitors = visitorSummary(visitorRows.map((row) => row.toColumnMap()), visitorNow);
        final q = (request.url.queryParameters['q'] ?? '').trim();
        final category = (request.url.queryParameters['category'] ?? '').trim();
        final categoryRows = await conn.execute(selectAdminLogCategories);
        final access = await conn.execute(
          selectAdminOperationLogs,
          parameters: [q, category],
        );
        final errors = await conn.execute(
          '''
            SELECT e.id, e.crtat, e.crtby, COALESCE(u.name_last, '') AS name_user,
                   e.message_error, e.stacktrace, COALESCE(l.url, '') AS url, l.category, e.txt_detail
            FROM t_system_log_error e
            LEFT JOIN t_system_log l ON l.id_log_error = e.id
            LEFT JOIN m_user u ON u.id = e.crtby
            WHERE (\$1::text = ''
               OR CAST(COALESCE(e.crtby, 0) AS text) = \$1::text
               OR COALESCE(u.name_last, '') ILIKE '%' || \$1::text || '%'
               OR COALESCE(u.name_first, '') ILIKE '%' || \$1::text || '%')
              AND (\$2::text = '' OR BTRIM(l.category) = \$2::text)
            ORDER BY e.crtat DESC
            LIMIT 200
          ''',
          parameters: [q, category],
        );
        String stamp(dynamic value) => LogDetail.formatJst(value);

        String textOf(Map<String, dynamic> detail, Map<String, dynamic> map, String key, String fallbackKey) {
          final fromDetail = '${detail[key] ?? ''}'.trim();
          if (fromDetail.isNotEmpty) return fromDetail;
          return '${map[fallbackKey] ?? ''}'.trim();
        }

        Map<String, dynamic> present(dynamic row, {required String fallbackType}) {
          final map = Map<String, dynamic>.from(row.toColumnMap());
          final detail = LogDetail.decode(map['txt_detail']);
          final isError = fallbackType == 'エラー';
          final logType = textOf(detail, map, 'log_type', '');
          final level = textOf(detail, map, 'level', '');
          final status = textOf(detail, map, 'status', '');
          var action = textOf(detail, map, 'action', isError ? 'message_error' : 'memo');
          if (action.isEmpty && !isError) {
            action = '${map['method'] ?? ''} ${map['url'] ?? ''}'.trim();
          }
          return {
            'log_id': '${map['id'] ?? ''}',
            'snapshot_id': detail['snapshot_id'],
            'snapshot_status': detail['snapshot_status'],
            for (final key in ['ip_address', 'browser', 'device_type', 'user_agent']) key: '${detail[key] ?? ''}',
            'timestamp': stamp(map['crtat']),
            'log_type': logType.isEmpty ? fallbackType : logType,
            'level': level.isEmpty ? (isError ? 'ERROR' : 'INFO') : level,
            'user_id': map['crtby'] ?? detail['user_id'] ?? 0,
            'user_name': '${map['name_user'] ?? ''}',
            'session_id': '${detail['session_id'] ?? ''}',
            'request_id': '${detail['request_id'] ?? ''}',
            'screen_name': '${detail['screen_name'] ?? ''}',
            'action': action,
            'status': status.isEmpty ? (isError ? '失敗' : '成功') : status,
            'details': '${detail['details'] ?? ''}',
            'app_version': '${detail['app_version'] ?? ''}',
            'environment': '${detail['environment'] ?? ''}',
            'error_type': '${detail['error_type'] ?? ''}',
            'error_code': '${detail['error_code'] ?? ''}',
            'error_message': textOf(detail, map, 'error_message', 'message_error'),
            'source': textOf(detail, map, 'source', 'category'),
            'function_name': '${detail['function_name'] ?? ''}',
            'file_name': '${detail['file_name'] ?? ''}',
            'line_number': '${detail['line_number'] ?? ''}',
            'stack_trace': textOf(detail, map, 'stack_trace', 'stacktrace'),
            'api_path': textOf(detail, map, 'api_path', 'url'),
            'http_status': '${detail['http_status'] ?? ''}',
            'duration_ms': '${detail['duration_ms'] ?? ''}',
            'request_bytes': '${detail['request_bytes'] ?? ''}',
            'response_bytes': '${detail['response_bytes'] ?? ''}',
            'transfer_bytes': '${detail['transfer_bytes'] ?? ''}',
            'memory_rss_bytes': '${detail['memory_rss_bytes'] ?? ''}',
            'memory_delta_bytes': '${detail['memory_delta_bytes'] ?? ''}',
            'metrics_scope': '${detail['metrics_scope'] ?? ''}',

            'context': '${detail['context'] ?? ''}',
            'crtat': stamp(map['crtat']),
            'id_user': map['crtby'] ?? 0,
            'name_user': map['name_user'] ?? '',
            'method': map['method'] ?? '',
            'category': map['category'] ?? '',
            'code': map['code'] ?? '',
            'memo': map['memo'] ?? '',
            'url': map['url'] ?? '',
            'message': map['message_error'] ?? detail['error_message'] ?? '',
          };
        }

        final logs = <Map<String, dynamic>>[
          for (final row in access) present(row, fallbackType: '操作'),
          for (final row in errors) present(row, fallbackType: 'エラー'),
        ]..sort((a, b) => '${b['timestamp']}'.compareTo('${a['timestamp']}'));

        return Response.ok(
          jsonEncode({
            'ok': true,
            'categories': [for (final row in categoryRows) row[0]],
            'logs': logs,
            'visitors': visitors,
            'visitors_as_of': visitorNow.toIso8601String(),
            'access': [
              for (final row in logs)
                if (row['log_type'] != 'エラー') row
            ],
            'errors': [
              for (final row in logs)
                if (row['log_type'] == 'エラー') row
            ],
          }),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
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

    // 初期表示が描画された後に届く通知。DB・認証処理を挟まず、一度だけ開始する。
    app.post('/predictions/live-details', (Request request) async {
      final org = request.url.queryParameters['org'] ?? 'npb';
      if (!['npb', 'mlb'].contains(org)) return Response(400);
      final userId = await Postgres.withConnection((conn) => Auth.userIdOf(conn, request), urgent: true);
      if (!GameStatsLoad.enableLiveViewer(userId)) return Response(403);
      GameFetchSchedule.resumeTodayWatch(org);
      return Response(204);
    });

    app.post('/predictions/ready', (Request request) {
      GameFetchSchedule.markInitialDisplayReady();
      return Response(204);
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
        final cacheKey = window.from != null ? '${org.code}|$part|$year|${window.from}|${window.to}' : '${org.code}|$part|$year';
        // 完成済みの試合本文も短時間再利用し、再表示のたびのDB往復を省く。
        // 取得処理による更新時は _clearPredictionsCache で破棄する。
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
        if (part == 'games' && request.url.queryParameters['fresh'] != '1') {
          final unchanged = await _unchangedGamesResponse(
            org,
            year,
            cacheKey,
            window.from,
            window.to,
            clientHasGames: request.url.queryParameters['have'] == '1',
          );
          if (unchanged != null) return unchanged;
        }
        final cacheGeneration = _predictionsCacheGeneration;
        final inflight = _partBuildInflight[cacheKey];
        final Future<String> build;
        if (inflight != null) {
          build = inflight;
        } else {
          build = _buildPredictionsPart(part, org, year, from: window.from, to: window.to).then(jsonEncode);
          _partBuildInflight[cacheKey] = build;
        }
        final String body;
        try {
          body = await build;
        } finally {
          if (identical(_partBuildInflight[cacheKey], build)) _partBuildInflight.remove(cacheKey);
        }
        if (cacheGeneration == _predictionsCacheGeneration) {
          _predictionsPartCacheBody[cacheKey] = body;
          _predictionsPartCacheAt[cacheKey] = DateTime.now();
        }
        if (part == 'games' && cacheGeneration == _predictionsCacheGeneration) {
          final revision = _pendingGamesRevision.remove(cacheKey);
          if (revision != null) _predictionsGamesRevision[cacheKey] = revision;
        }
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

        final currentYear = selectedYear;
        final cacheGeneration = _predictionsCacheGeneration;
        final results = await Postgres.mapParallel([
          (conn) => PredictionSnapshot.teams(conn, currentYear, org.leagueIds),
          (conn) => DisplaySnapshot.playerPart(conn, currentYear, org.leagueIds),
          (conn) => DisplaySnapshot.teams(conn, currentYear),
          (conn) => DisplaySnapshot.games(conn, currentYear),
          (conn) => Postgres.execute(conn, AppSql.selectEventsDetails()),
          (conn) => Postgres.execute(conn, AppSql.selectNotification()),
        ]);
        final players = results[1] as PlayerDisplay;
        final snap = results[3] as DisplayGames;
        final playRows = snap.plays;
        final gameRows = snap.games;
        final battingLines = _battingLinesOf(snap.batting);
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
        await _attachSavedForms(snap, games, currentYear);
        _fillMissingLineScores(games, playRows);
        final lineups = battingLineupsOf(
          playRows,
          plays: playLabels,
          pitchers: pitcherKeysOf(gameRows),
          rbi: {for (final entry in battingLines.entries) entry.key: _asInt(entry.value['int_rbi'])},
          errors: {for (final entry in battingLines.entries) entry.key: _asInt(entry.value['int_error'])},
          starters: _lineupStartersOf(battingLines),
        );
        final fieldingErrors = fieldingErrorsByGame(snap.batting);
        for (final game in games) {
          game['lineup'] = lineups[_asInt(game['id_game'])] ?? const <Map<String, dynamic>>[];
    game['batting_summary'] = [for (final line in battingLines.values) if (_asInt(line['id_game']) == _asInt(game['id_game'])) {for (final key in ['id_team', 'name_full', 'int_batting', 'int_hit1', 'int_homerun', 'int_steal_base']) key: line[key]}];
          game['fielding_errors'] = fieldingErrors[_asInt(game['id_game'])] ?? const <Map<String, dynamic>>[];
          _useAnnouncedLineup(game);
        }
        _attachLiveBatters(games, playRows);
        // print(games);
        final leagueIds = org.leagueIds;
        final filteredGames = _filterByLeagues(games, leagueIds, keys: const ['id_league_home', 'id_league_away']);
        final postseason = _postseasonForOrg(snap.postseason, org);
        final payload = <String, dynamic>{
          'org': org.code,
          'year': currentYear,
          'predict_team': results[0],
          'predict_player': players.predictions,
          'stats_team': _filterByLeagues(results[2] as List<Map<String, dynamic>>, leagueIds),
          'stats_player': players.stats,
          'games': filteredGames,
          'events': org.code == 'npb' ? Postgres.toJson(results[4] as Result) : const <Map<String, dynamic>>[],
          'notification': org.code == 'npb' ? Postgres.toJson(results[5] as Result) : const <Map<String, dynamic>>[],
          'postseason_games': _dedupeSameDayMatchups(postseason),
          'show_postseason_board': postseason.isNotEmpty || _showPostseasonBoard(snap.board),
        };
        final body = jsonEncode(payload);
        if (cacheGeneration == _predictionsCacheGeneration) {
          _predictionsCacheBody[cacheKey] = body;
          _predictionsCacheAt[cacheKey] = DateTime.now();
        }
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

      handler = const Pipeline().addMiddleware(logRequests()).addMiddleware(RequestMetrics.middleware()).addMiddleware(corsHeaders()).addHandler(handler);

      stdout.writeln('🗂 Serving static from: ${publicDir.path}');
    } else {
      // 静的なし（dev表示）
      handler = const Pipeline().addMiddleware(logRequests()).addMiddleware(RequestMetrics.middleware()).addMiddleware(corsHeaders()).addHandler((req) {
        if (req.url.path.isEmpty) {
          return Response.ok('Backend API (dev). Try /predictions', headers: {'content-type': 'text/plain; charset=utf-8'});
        }
        return app.call(req);
      });
    }

    handler = gameVisibility((request) async => !Auth.hasSessionToken(request) ? null : await Postgres.withConnection(
      (conn) => Auth.readOnlyUserIdOf(conn, request), urgent: true))(handler);

    final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
    await Postgres.withConnection(PageSnapshot.ensure);
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
    TeamStrength.start();
    RosterMoves.start();
    NpbResearch.start();
    PlayerArtSchedule.start();
    PlayerMetricSchedule.start(onUpdated: _clearPredictionsCache);
    PlayerDetailSnapshot.start();
    PageSnapshot.start();
    PredictionSnapshotSchedule.start(onUpdated: _clearPredictionsCache);
    // 取得処理だけ登録する。タイマーは /predictions/ready の通知後に開始する。
    GameScheduleWatch.start(onUpdated: _clearPredictionsCache);
    GameFetchSchedule.armFutureWatch('mlb', FetchMLB.refreshFutureIfChanged);
    GameFetchSchedule.armFutureWatch('npb', FetchURL.refreshFutureIfChanged);
    // 当日の試合も初期表示完了まで定期取得を始めない。
    GameFetchSchedule.scheduleTodayAgain('mlb', FetchMLB.refreshToday);
    GameFetchSchedule.scheduleTodayAgain('npb', FetchURL.refreshTodayNPB);
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
  unawaited(sendProgramErrorMail(e).catchError((_) {}));
}

Future<int> _saveErrorLog(
  Object e,
  String stacktrace,
  m_user user, {
  required Request request,
  required int durationMs,
  required String requestId,
}) async {
  try {
    final id = await Postgres.withConnection((conn) async {
      return insertLogError(
        conn,
        e,
        stacktrace,
        user,
        detail: {
          ...LogDetail.clientInfo(request),
          'api_path': request.requestedUri.path,
          'http_status': 500,
          'duration_ms': durationMs,
          'request_id': requestId,
          'source': user.category_system,
          'environment': 'server',
          'context': jsonEncode({
            'method': request.method,
            'path': request.requestedUri.path,
          }),
        },
      );
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

Future<void> _attachRequestUser(Connection conn, Request request, m_user user) async {
  final id = await Auth.userIdOf(conn, request);
  if (id == null || id <= 0) return;
  user.id = id;
  user.flg_user = true;
}

String _requestId(Request request) {
  final header = (request.headers['x-request-id'] ?? '').trim();
  if (header.isNotEmpty) return _clipDb(header, 64);
  return 'req_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
}

Future<void> _saveAccessLog(
  Request request,
  m_user user,
  int idError, {
  required int durationMs,
  required int httpStatus,
  required String requestId,
  Map<String, Object> metrics = const {},
}) async {
  try {
    await Postgres.withConnection((conn) async {
      final failed = idError > 0 || httpStatus >= 400;
      final log = t_system_log();
      log.method = _clipDb(request.method, 20);
      log.category = _clipDb(user.category_system, 20);
      log.code = _clipDb(user.code_system, 20);
      log.memo = '';
      log.flg_user = user.flg_user;
      log.url = request.requestedUri.path;
      log.url_pre = "";
      log.id_log_error = idError;
      log.flg_check = false;
      log.crtby = user.id;
      log.crtpgm = _clipDb(user.code_system, 30);
      log.updby = user.id;
      log.updpgm = _clipDb(user.code_system, 30);
      log.crtenv = 'server';
      log.txt_detail = LogDetail.encode({
        ...LogDetail.clientInfo(request),
        'log_type': LogDetail.accessType(request,
            scheduled: ScheduledLog.isScheduledRequest(request)),
        'level': httpStatus >= 500 ? 'ERROR' : (httpStatus >= 400 ? 'WARN' : 'INFO'),
        'user_id': user.id,
        'session_id': '',
        'request_id': requestId,
        'screen_name': '',
        'action': '${request.method} ${request.requestedUri.path}',
        'status': failed ? '失敗' : '成功',
        'details': user.code_system,
        'app_version': '',
        'environment': 'server',
        'source': user.category_system,
        'function_name': user.code_system,
        'api_path': request.requestedUri.path,
        'http_status': httpStatus,
        'duration_ms': durationMs,
        ...metrics,
        'context': jsonEncode({'method': request.method, 'path': request.requestedUri.path}),
      });
      await Postgres.insert(conn, log);
    });
    print("操作ログを登録しました。【${user.code_system}】");
  } catch (e, st) {
    print('操作ログ登録失敗: $e\n$st');
  }
}

bool _skipAccessLog(String path, {required bool readonly}) {
  if (readonly) return false;
  return path == '/client/action' || path == '/client/error';
}

/// 読み取り専用API: トランザクションなし。ログINSERTのみ別接続で行う。
Future<Response> tryCatchAPIReadonly(
  Request request,
  String categorySystem,
  String codeSystem,
  Future<Response> Function() callback,
) async {
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  final started = DateTime.now();
  final requestId = _requestId(request);
  var idError = 0;
  final user = m_user();
  var response = Response.ok('ok');
  user.category_system = categorySystem;
  user.code_system = codeSystem;
  user.flg_user = false;
  try {
    if (Auth.hasSessionToken(request)) {
      await Postgres.withConnection((conn) => _attachRequestUser(conn, request, user));
    }
    print("🌐Routing...【${request.requestedUri}】");
    // DDL は待たない。列確認・seed は裏で進め、試合 SELECT を先に返す。
    FetchURL.kickSchemaEnsures();
    response = await callback();
  } catch (e, st) {
    _printRequestError(request, e, st);
    idError = await _saveErrorLog(
      e,
      st.toString(),
      user,
      request: request,
      durationMs: DateTime.now().difference(started).inMilliseconds,
      requestId: requestId,
    );
    _notifyProgramError(e);
    response = Response.internalServerError(body: 'データベースエラー: $e');
  } finally {
    if (!_skipAccessLog(request.requestedUri.path, readonly: true)) {
      Future<void> save(Map<String, Object> metrics) => _saveAccessLog(
        request,
        user,
        idError,
        durationMs: DateTime.now().difference(started).inMilliseconds,
        httpStatus: response.statusCode,
        requestId: requestId,
        metrics: metrics,
      );
      final metrics = RequestMetrics.of(request);
      if (metrics != null) {
        metrics.onComplete(save);
      } else {
        unawaited(save(const {}));
      }
    }
    print("🌐Responsed Successfully‼️【${request.requestedUri}】");
  }
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  return response;
}

Future<Response> tryCatchAPI(Request request, String categorySystem, String codeSystem, Future<Response> Function(Connection conn) callback) async {
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  final started = DateTime.now();
  final requestId = _requestId(request);
  var idError = 0;
  final user = m_user();
  // Set the actor before opening the DB so connection failures retain it too.
  if (ScheduledLog.isScheduledRequest(request)) user.id = ScheduledLog.userId;
  var response = Response.ok('ok');
  user.category_system = categorySystem;
  user.code_system = codeSystem;
  user.flg_user = false;
  try {
    await Postgres.withConnection((conn) => _attachRequestUser(conn, request, user));
    await FetchURL.ensureGameDetailsVelo();
    await FetchURL.ensureAppColumns();
    await Postgres.openConnection((conn) async {
      await Postgres.transactionCommit(conn, () async {
        print("🌐Routing...【${request.requestedUri}】");
        print("");
        user.category_system = categorySystem;
        user.code_system = codeSystem;
        response = await callback(conn);
      });
    });
  } catch (e, st) {
    _printRequestError(request, e, st);
    idError = await _saveErrorLog(
      e,
      st.toString(),
      user,
      request: request,
      durationMs: DateTime.now().difference(started).inMilliseconds,
      requestId: requestId,
    );
    _notifyProgramError(e);
    response = Response.internalServerError(body: 'データベースエラー: $e');
  } finally {
    if (!_skipAccessLog(request.requestedUri.path, readonly: false)) {
      Future<void> save(Map<String, Object> metrics) => _saveAccessLog(
        request,
        user,
        idError,
        durationMs: DateTime.now().difference(started).inMilliseconds,
        httpStatus: response.statusCode,
        requestId: requestId,
        metrics: metrics,
      );
      final metrics = RequestMetrics.of(request);
      if (metrics != null) {
        metrics.onComplete(save);
      } else {
        unawaited(save(const {}));
      }
    }
    print("🌐Responsed Successfully‼️【${request.requestedUri}】");
  }
  print('🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸🔸');
  return response;
}

Future<int> insertLogError(
  Connection conn,
  Object e,
  String stacktrace,
  m_user user, {
  Map<String, dynamic>? detail,
}) async {
  final message = LogDetail.clip(e.toString(), 2000);
  final stack = LogDetail.clip(stacktrace, 4000);
  final frame = LogDetail.stackFrame(stack);
  final logError = t_system_log_error();
  logError.message_error = message;
  logError.stacktrace = stack;
  logError.flg_check = false;
  logError.code_log_system = _clipDb(user.code_system, 20);
  logError.crtby = user.id;
  logError.crtpgm = _clipDb(user.code_system, 30);
  logError.updby = user.id;
  logError.updpgm = _clipDb(user.code_system, 30);
  logError.crtenv = LogDetail.clip('${detail?['environment'] ?? 'server'}', 20);
  logError.txt_detail = LogDetail.encode({
    'log_type': 'エラー',
    'level': 'ERROR',
    'user_id': user.id,
    'error_type': e.runtimeType.toString(),
    'error_code': LogDetail.errorCode(e),
    'error_message': message,
    'source': user.category_system,
    'function_name': frame['function_name'] ?? '',
    'file_name': frame['file_name'] ?? '',
    'line_number': frame['line_number'] ?? '',
    'stack_trace': stack,
    'action': user.code_system,
    'status': '失敗',
    'environment': 'server',
    ...?detail,
  });
  return await Postgres.insert(conn, logError);
}
