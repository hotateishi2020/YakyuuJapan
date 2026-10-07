import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../tools/Env.dart';
import '../tools/app_logger.dart';
import '../tools/browser_cookie.dart';
import '../tools/page_visibility.dart';
import '../tools/color_parse.dart';
import '../config/app_design.dart';
import '../config/org_config.dart';
import '../tools/json_utils.dart';
import '../tools/date_format.dart';
import '../logic/atari_counts.dart';
import '../logic/auth_session.dart';
import '../logic/show_user_predictions.dart';
import '../View/Headers.dart';
import '../View/Text.dart';
import '../View/LeagueBoardRow.dart';
import '../View/GamesBoard.dart';
import '../View/SeasonTable.dart';
import '../View/MlbPostseasonBracket.dart';
import '../View/PostseasonBracket.dart';
import '../View/BlinkNewMark.dart';
import '../logic/postseason_bracket.dart';
import '../logic/game_dedupe.dart';
import '../logic/game_date_window.dart';

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

enum _LoadPart { info, standings, players, games }

class _OrgBundle {
  List<Map<String, dynamic>> predictions;
  List<Map<String, dynamic>> standings;
  List<Map<String, dynamic>> playerStats;
  List<Map<String, dynamic>> playerStatsActual;
  List<Map<String, dynamic>> games;
  List<Map<String, dynamic>> postseasonGames;
  bool showPostseasonBoard;
  DateTime? gamesFrom;
  DateTime? gamesTo;
  final Set<String> extraGameDates;
  final Set<_LoadPart> readyParts;

  _OrgBundle({
    required this.predictions,
    required this.standings,
    required this.playerStats,
    required this.playerStatsActual,
    required this.games,
    required this.postseasonGames,
    required this.showPostseasonBoard,
    this.gamesFrom,
    this.gamesTo,
    Set<String>? extraGameDates,
    Set<_LoadPart>? readyParts,
  })  : extraGameDates = extraGameDates ?? <String>{},
        readyParts = readyParts ??
            {
              _LoadPart.info,
              _LoadPart.standings,
              _LoadPart.players,
              _LoadPart.games,
            };

  bool partReady(_LoadPart part) => readyParts.contains(part);

  /// 画面に出せるコンテンツが1つでもあるか（空のプレースホルダキャッシュを除外）
  bool get hasContent =>
      readyParts.contains(_LoadPart.standings) ||
      readyParts.contains(_LoadPart.players) ||
      readyParts.contains(_LoadPart.games);

  _OrgBundle copy() => _OrgBundle(
        predictions: List<Map<String, dynamic>>.from(predictions),
        standings: List<Map<String, dynamic>>.from(standings),
        playerStats: List<Map<String, dynamic>>.from(playerStats),
        playerStatsActual: List<Map<String, dynamic>>.from(playerStatsActual),
        games: List<Map<String, dynamic>>.from(games),
        postseasonGames: List<Map<String, dynamic>>.from(postseasonGames),
        showPostseasonBoard: showPostseasonBoard,
        gamesFrom: gamesFrom,
        gamesTo: gamesTo,
        extraGameDates: {...extraGameDates},
        readyParts: {...readyParts},
      );
}

class _PredictionPageState extends State<PredictionPage> with WidgetsBindingObserver {
  // 左カラム
  List<Map<String, dynamic>> predictions = [];
  List<Map<String, dynamic>> standings = []; // ← フラット行（id_league/name_league入り）
  List<Map<String, dynamic>> npbPlayerStats = [];
  List<Map<String, dynamic>> npbPlayerStatsActual = [];

  // 右カラム（すべて文字列で扱う）
  List<Map<String, dynamic>> games = [];
  List<Map<String, dynamic>> postseasonGames = [];
  bool showPostseasonBoard = false;
  List<Map<String, dynamic>> events = [];
  List<Map<String, dynamic>> notifications = [];
  // Info / SCORE 専用（団体タブの predictions とは独立）
  String _infoName1 = '';
  String _infoName2 = '';
  Color? _infoColor1;
  Color? _infoColor2;

  bool isLoading = true;
  /// 初回表示後はヘッダー〜団体タブを残し、タブ下だけローディングする。
  bool _shellReady = false;
  /// 初期 SQL が終わるまで Login を出さず、認証リクエストで回線を奪わない。
  bool _authEntryReady = false;
  String? error;
  /// 団体ごとのセクション準備状況（準備できたものから描画）
  final Map<OrgKind, Set<_LoadPart>> _readyParts = {};
  final Map<String, Future<void>> _partLoadFutures = {};

  bool _newsExpanded = false;
  bool _eventsExpanded = false;
  bool _infoExpanded = true;
  static const _infoCookie = 'koko_info_open';
  static const _viewCookie = 'koko_view_by_item';
  static const _orgCookie = 'koko_org';
  OrgKind _orgKind = OrgKind.npb;
  final Map<OrgKind, _OrgBundle> _orgCache = {};
  final Map<OrgKind, Future<void>> _orgLoadFutures = {};
  // 縦型: 0=第1リーグ, 1=第2リーグ
  int _portraitLeagueTab = 0;
  bool _viewByItem = false;
  int _itemTab = 0;
  int _seasonYear = DateTime.now().year;
  final Map<String, int> _loadedPartYears = {};
  PersonalStatsLayout _personalStatsLayout = PersonalStatsLayout.segment;
  Timer? _gamesRefreshTimer;
  Timer? _gamesPollTimer;
  bool _gamesRefreshRunning = false;
  bool _gamesPollRunning = false;
  final Map<OrgKind, int> _gameDayOffset = {};
  final Map<OrgKind, String?> _loadingGameDateByOrg = {};
  final Set<String> _pastDateInflight = {};
  final Set<OrgKind> _seasonStatsRefreshStarted = {};

  int get _gameDateOffset => _gameDayOffset[_orgKind] ?? 0;

  String? get _loadingGameDate => _loadingGameDateByOrg[_orgKind];

  void _setGameDateOffset(int offset) {
    if (_gameDayOffset[_orgKind] == offset) return;
    setState(() => _gameDayOffset[_orgKind] = offset);
  }

  OrgConfig get _org => OrgConfig.of(_orgKind);

  // 個人成績の id_user → 表示名
  String _usernameForId(String idUser) => lookupField(npbPlayerStats, 'id_user', idUser, 'username');

  String _userNameFromPredictions(String idUserStr) => lookupField(predictions, 'id_user', idUserStr, 'name_user_last');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bindPageVisibility(_onPageBecameVisible);
    final saved = readBrowserCookie(_infoCookie);
    if (saved == '0') _infoExpanded = false;
    if (saved == '1') _infoExpanded = true;
    if (readBrowserCookie(_viewCookie) == '1') _viewByItem = true;
    // cookie の団体をそのまま初回表示（npb / mlb）
    if (readBrowserCookie(_orgCookie) == 'mlb') {
      _orgKind = OrgKind.mlb;
    } else {
      _orgKind = OrgKind.npb;
    }
    _personalStatsLayout = readPersonalStatsLayout();
    // ヘッダー〜団体タブはデータ待ちせず先に出す
    _shellReady = true;
    _bootstrapWithAuth();
  }

  bool get _showUserPredictions => AuthSession.instance.isLoggedIn;

  bool _partReady(_LoadPart part, [OrgKind? kind]) =>
      _readyParts[kind ?? _orgKind]?.contains(part) ?? false;

  bool get _boardContentReady =>
      _partReady(_LoadPart.standings) || _partReady(_LoadPart.games) || _partReady(_LoadPart.players);

  Future<void> _bootstrapWithAuth() async {
    try {
      await _loadThenWatchGames().timeout(const Duration(seconds: 45));
    } catch (_) {}
    if (!mounted) return;
    try {
      await Future.wait([
        for (final part in _LoadPart.values)
          _fetchPart(_orgKind, part, _seasonYear, background: true),
      ]).timeout(const Duration(seconds: 20));
    } catch (_) {}
    if (!mounted) return;
    try {
      await AuthSession.instance.restore().timeout(const Duration(seconds: 15));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _authEntryReady = true);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (AuthSession.instance.isLoggedIn) {
      setState(() => _authEntryReady = true);
      return;
    }
    unawaited(_holdLoginUntilBoardReady());
  }

  Future<void> _holdLoginUntilBoardReady() async {
    if (!mounted) return;
    setState(() => _authEntryReady = false);
    try {
      await Future.wait([
        for (final part in _LoadPart.values)
          _fetchPart(_orgKind, part, _seasonYear, background: false, force: true),
      ]).timeout(const Duration(seconds: 45));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _authEntryReady = true);
  }

  Future<void> _markRead(String target) async {
    if (!AuthSession.instance.isLoggedIn) return;
    final err = await AuthSession.instance.markRead(target);
    if (!mounted) return;
    if (err == null) setState(() {});
  }

  void _toggleNewsSection() {
    final opening = !_newsExpanded;
    setState(() => _newsExpanded = opening);
    if (opening) unawaited(_markRead('news'));
  }

  void _toggleEventsSection() {
    final opening = !_eventsExpanded;
    setState(() => _eventsExpanded = opening);
    if (opening) unawaited(_markRead('event'));
  }

  void _setPersonalStatsLayout(PersonalStatsLayout layout) {
    if (layout == _personalStatsLayout) return;
    writePersonalStatsLayout(layout);
    setState(() => _personalStatsLayout = layout);
  }

  void _applyBundle(_OrgBundle bundle, {OrgKind? kind}) {
    // キャッシュと表示用リストを分離し、他団体表示中のクリアで消えないようにする
    predictions = List<Map<String, dynamic>>.from(bundle.predictions);
    standings = List<Map<String, dynamic>>.from(bundle.standings);
    npbPlayerStats = List<Map<String, dynamic>>.from(bundle.playerStats);
    npbPlayerStatsActual = List<Map<String, dynamic>>.from(bundle.playerStatsActual);
    games = List<Map<String, dynamic>>.from(bundle.games);
    postseasonGames = List<Map<String, dynamic>>.from(bundle.postseasonGames);
    showPostseasonBoard = bundle.showPostseasonBoard;
    _readyParts[kind ?? _orgKind] = {...bundle.readyParts};
    // 予想者名は取れたいずれかの団体データから Info に蓄える（空で上書きしない）
    _captureInfoUsers(predictions, npbPlayerStats);
    _scheduleTeamLogoPrecache(standings);
  }

  bool _cacheUsable(OrgKind kind) {
    final cached = _orgCache[kind];
    if (cached == null || !cached.hasContent) return false;
    return _partLoadedForYear(kind, _LoadPart.games) ||
        _partLoadedForYear(kind, _LoadPart.standings) ||
        _partLoadedForYear(kind, _LoadPart.players);
  }

  /// キャッシュへ保存（リストはコピーして参照共有を避ける）
  void _storeCache(OrgKind kind, _OrgBundle bundle) {
    _orgCache[kind] = bundle.copy();
    _readyParts[kind] = {...bundle.readyParts};
  }

  /// Info（ニュース・イベント・予想者名）は NPB/MLB 共通。空応答で消さない。
  void _applySharedInfo(Map<String, dynamic> map) {
    final evts = listMapFromJson(map['events']);
    final notifs = listMapFromJson(map['notification']);
    if (evts.isNotEmpty) events = evts;
    if (notifs.isNotEmpty) notifications = notifs;
    _captureInfoUsers(listMapFromJson(map['predict_team']));
  }

  void _captureInfoUsers(
    List<Map<String, dynamic>> preds, [
    List<Map<String, dynamic>> playerStats = const [],
  ]) {
    for (final id in const ['1', '2']) {
      final name = lookupField(preds, 'id_user', id, 'name_user_last', fallback: '').trim();
      if (name.isNotEmpty && name != '—') {
        if (id == '1') {
          _infoName1 = name;
        } else {
          _infoName2 = name;
        }
      }
      final teamColor = lookupField(preds, 'id_user', id, 'code_color', fallback: '');
      final playerColor = lookupField(playerStats, 'id_user', id, 'code_color', fallback: '');
      final parsed = parseColorNameOrNull(teamColor) ?? parseColorNameOrNull(playerColor);
      if (parsed != null) {
        if (id == '1') {
          _infoColor1 = parsed;
        } else {
          _infoColor2 = parsed;
        }
      }
    }
  }

  _OrgBundle _snapshotCurrent() => _OrgBundle(
        predictions: List<Map<String, dynamic>>.from(predictions),
        standings: List<Map<String, dynamic>>.from(standings),
        playerStats: List<Map<String, dynamic>>.from(npbPlayerStats),
        playerStatsActual: List<Map<String, dynamic>>.from(npbPlayerStatsActual),
        games: List<Map<String, dynamic>>.from(games),
        postseasonGames: List<Map<String, dynamic>>.from(postseasonGames),
        showPostseasonBoard: showPostseasonBoard,
        readyParts: {...(_readyParts[_orgKind] ?? const <_LoadPart>{})},
      );

  Future<void> _changeOrg(OrgKind kind) async {
    if (kind == _orgKind) return;
    writeBrowserCookie(_orgCookie, OrgConfig.of(kind).label.toLowerCase());
    // 離れる団体の表示内容を必ず保持
    _storeCache(_orgKind, _snapshotCurrent());
    final cached = _orgCache[kind];
    final usable = cached != null && cached.hasContent;
        setState(() {
      _orgKind = kind;
      _portraitLeagueTab = 0;
      _itemTab = 0;
      error = null;
      if (usable) {
        _applyBundle(cached, kind: kind);
          isLoading = false;
        _shellReady = true;
      } else {
        isLoading = true;
        predictions = [];
        standings = [];
        npbPlayerStats = [];
        npbPlayerStatsActual = [];
        games = [];
        postseasonGames = [];
        showPostseasonBoard = false;
        // プレースホルダだけ残っている場合は ready を捨てて取り直す
        if (cached != null && !cached.hasContent) {
          cached.readyParts.clear();
        }
        _readyParts[kind] = <_LoadPart>{};
      }
    });
    _gamesRefreshTimer?.cancel();
    _gamesPollTimer?.cancel();
    if (usable) {
      // 足りないパートだけ補完。取得済みは再取得しない
      final missing = <_LoadPart>[
        for (final part in _LoadPart.values)
          if (!cached.partReady(part)) part,
      ];
      if (missing.isNotEmpty) {
        unawaited(_fetchOrgParts(kind, background: false, only: missing));
      }
      unawaited(_ensureSeasonYearLoaded());
      await _startGamesWatch();
      unawaited(_prefetchOtherOrg());
        return;
    }
    await _loadThenWatchGames();
    unawaited(_ensureSeasonYearLoaded());
  }

  Future<void> _prefetchOtherOrg() async {
    await Future<void>.delayed(const Duration(seconds: 20));
    if (!mounted) return;
    final other = _orgKind == OrgKind.npb ? OrgKind.mlb : OrgKind.npb;
    if (_cacheUsable(other) || _orgLoadFutures.containsKey(other)) return;
    await fetchData(kind: other, background: true);
  }

  void _toggleInfo() {
    setState(() => _infoExpanded = !_infoExpanded);
    writeBrowserCookie(_infoCookie, _infoExpanded ? '1' : '0');
  }

  Widget _infoShell({required Widget child, required bool expand}) {
    final showInfoNew = !_infoExpanded && AuthSession.instance.showInfoNew;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black87, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: expand && _infoExpanded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.black,
            child: InkWell(
              onTap: _toggleInfo,
              child: SizedBox(
                height: 28,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(
                        _infoExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Info',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (showInfoNew) ...[
                        const SizedBox(width: 8),
                        const BlinkNewMark(fontSize: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_infoExpanded)
            expand
                ? Expanded(
                    child: ColoredBox(
                      color: const Color(0xFFF5F0DC),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                        child: child,
                      ),
                    ),
                  )
                : ColoredBox(
                    color: const Color(0xFFF5F0DC),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      child: child,
                    ),
                  ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gamesRefreshTimer?.cancel();
    _gamesPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onPageBecameVisible();
  }

  void _onPageBecameVisible() {
    if (!mounted) return;
    unawaited(_pollDisplayedGames());
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  String _predictionsPath([OrgKind? kind]) =>
      '/predictions?org=${OrgConfig.of(kind ?? _orgKind).label.toLowerCase()}&year=$_seasonYear';

  Future<void> _startGamesWatch() async {
    if (!mounted) return;
    // 一部パート失敗の error があっても、取れたデータがあれば監視は続ける
    if (error != null && !_boardContentReady) return;
    if (orgGamesAllFinished(games, _todayKey(), _org.leagueIds)) {
      _refreshSeasonStatsOnce();
    }
    _gamesRefreshTimer?.cancel();
    _gamesPollTimer?.cancel();
    _gamesPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_pollDisplayedGames());
    });
    // 初期表示は SQL のみ。スクレイピングは描画後に始める。
    _gamesRefreshTimer = Timer(const Duration(seconds: 5), () {
      unawaited(_refreshGames());
    });
  }

  Future<void> _pollDisplayedGames() async {
    if (!mounted || _gamesPollRunning) return;
    if (_seasonYear != DateTime.now().year) return;
    _gamesPollRunning = true;
    try {
      await _fetchPart(_orgKind, _LoadPart.games, _seasonYear, background: true, force: true);
    } finally {
      _gamesPollRunning = false;
    }
  }

  Future<void> _loadThenWatchGames() async {
    await fetchData();
    if (!mounted) return;
    if (!_shellReady || isLoading) {
      setState(() {
        _shellReady = true;
        isLoading = false;
      });
    }
    if (error != null && !_boardContentReady) return;
    await _startGamesWatch();
    unawaited(_prefetchOtherOrg());
  }

  Future<void> _refreshGames() async {
    if (!mounted || _gamesRefreshRunning || isLoading) return;
    if (_seasonYear != DateTime.now().year) return;
    final today = _todayKey();
    if (orgGamesAreSettled(games, today, _org.leagueIds)) {
      if (orgGamesAllFinished(games, today, _org.leagueIds)) {
        await _refreshSeasonStatsOnce();
      }
      return;
    }
    _gamesRefreshRunning = true;
    var refreshStats = false;
    try {
      // 初回だけ全日程。今日の続きは backend が 10 秒後に今日だけ取りに行く。
      final scrape = await http.get(Env.api(_org.gamesFetchPath)).timeout(const Duration(minutes: 10));
      if (!mounted) return;
      if (scrape.statusCode != 200) {
        logger.w('試合スクレイピング失敗: ${scrape.statusCode}');
      } else if (scrape.body.contains('offseason')) {
        _gamesRefreshTimer?.cancel();
        _gamesPollTimer?.cancel();
        return;
      }
      await _pollDisplayedGames();
      refreshStats = orgGamesAllFinished(games, today, _org.leagueIds);
    } catch (e, st) {
      logger.w('試合情報の定期更新に失敗: $e\n$st');
    } finally {
      _gamesRefreshRunning = false;
    }
    if (refreshStats) await _refreshSeasonStatsOnce();
  }

  Future<void> _refreshSeasonStatsOnce() async {
    final kind = _orgKind;
    if (!mounted || _seasonStatsRefreshStarted.contains(kind)) return;
    if (!orgGamesAllFinished(games, _todayKey(), _org.leagueIds)) return;
    _seasonStatsRefreshStarted.add(kind);
    try {
      final team = await http.get(Env.api(_org.teamStatsFetchPath)).timeout(const Duration(minutes: 5));
      if (!mounted || team.statusCode != 200) {
        logger.w('チーム成績スクレイピング失敗: ${team.statusCode}');
        _seasonStatsRefreshStarted.remove(kind);
        return;
      }
      if (team.body.contains('offseason')) {
        _gamesRefreshTimer?.cancel();
        _gamesPollTimer?.cancel();
        return;
      }
      final res = await http.get(Env.api(_predictionsPath(kind))).timeout(const Duration(seconds: 30));
      if (!mounted || res.statusCode != 200) {
        _seasonStatsRefreshStarted.remove(kind);
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final org = OrgConfig.of(kind);
      final nextStandings = listMapFromJson(map['stats_team']).where(org.rowBelongs).toList();
      final nextActual = listMapFromJson(map['stats_player']).where(org.rowBelongs).toList();
      final cached = _orgCache[kind];
      if (cached != null) {
        cached.standings = nextStandings;
        cached.playerStatsActual = nextActual;
      }
      if (kind == _orgKind) {
      setState(() {
          standings = nextStandings;
          npbPlayerStatsActual = nextActual;
        });
      }
    } catch (e, st) {
      _seasonStatsRefreshStarted.remove(kind);
      logger.w('チーム・個人成績の更新に失敗: $e\n$st');
    }
  }

  Future<void> fetchData({OrgKind? kind, bool background = false}) async {
    final target = kind ?? _orgKind;
    final inflight = _orgLoadFutures[target];
    if (inflight != null) {
      await inflight;
      if (!mounted) return;
      final cached = _orgCache[target];
      if (cached != null && cached.hasContent && target == _orgKind) {
        setState(() {
          _applyBundle(cached, kind: target);
        isLoading = false;
          _shellReady = true;
          error = null;
        });
      }
      return;
    }

    final future = _fetchOrgParts(target, background: background);
    _orgLoadFutures[target] = future;
    try {
      await future;
    } finally {
      _orgLoadFutures.remove(target);
    }
  }

  _OrgBundle _ensureCache(OrgKind target) {
    return _orgCache.putIfAbsent(
      target,
      () => _OrgBundle(
        predictions: <Map<String, dynamic>>[],
        standings: <Map<String, dynamic>>[],
        playerStats: <Map<String, dynamic>>[],
        playerStatsActual: <Map<String, dynamic>>[],
        games: <Map<String, dynamic>>[],
        postseasonGames: <Map<String, dynamic>>[],
        showPostseasonBoard: false,
        readyParts: <_LoadPart>{},
      ),
    );
  }

  String _partPath(
    OrgKind kind,
    String part,
    int year, {
    bool fresh = false,
    String? date,
    String? from,
    String? to,
  }) {
    final path = StringBuffer(
      '/predictions/part?org=${OrgConfig.of(kind).label.toLowerCase()}&part=$part&year=$year',
    );
    if (fresh) path.write('&fresh=1');
    if (date != null && date.isNotEmpty) path.write('&date=$date');
    if (from != null && from.isNotEmpty) path.write('&from=$from');
    if (to != null && to.isNotEmpty) path.write('&to=$to');
    return path.toString();
  }

  _LoadPart _partForItem(int item) {
    if (item == 0) return _LoadPart.games;
    if (item == 1) return _LoadPart.standings;
    return _LoadPart.players;
  }

  bool _partLoadedForYear(OrgKind kind, _LoadPart part) {
    return (_orgCache[kind]?.partReady(part) ?? false) &&
        _loadedPartYears['${kind.name}|${part.name}'] == _seasonYear;
  }

  void _invalidateYearParts() {
    for (final kind in OrgKind.values) {
      final bundle = _orgCache[kind];
      bundle?.readyParts.remove(_LoadPart.games);
      bundle?.readyParts.remove(_LoadPart.standings);
      bundle?.readyParts.remove(_LoadPart.players);
      bundle?.extraGameDates.clear();
      bundle?.gamesFrom = null;
      bundle?.gamesTo = null;
      _readyParts[kind]?.remove(_LoadPart.games);
      _readyParts[kind]?.remove(_LoadPart.standings);
      _readyParts[kind]?.remove(_LoadPart.players);
      _loadedPartYears.remove('${kind.name}|${_LoadPart.games.name}');
      _loadedPartYears.remove('${kind.name}|${_LoadPart.standings.name}');
      _loadedPartYears.remove('${kind.name}|${_LoadPart.players.name}');
    }
    _gameDayOffset.clear();
    _loadingGameDateByOrg.clear();
    _pastDateInflight.clear();
  }

  Future<void> _ensureItemYearLoaded(int item) async {
    await _ensureSeasonYearLoaded(only: [_partForItem(item)]);
  }

  Future<void> _ensureSeasonYearLoaded({List<_LoadPart>? only}) async {
    final parts = only ?? const [_LoadPart.games, _LoadPart.standings, _LoadPart.players];
    final missing = [
      for (final part in parts)
        if (!_partLoadedForYear(_orgKind, part)) part,
    ];
    if (missing.isEmpty) return;
    if (mounted) {
      setState(() {
        final bundle = _ensureCache(_orgKind);
        for (final part in missing) {
          bundle.readyParts.remove(part);
          _readyParts[_orgKind]?.remove(part);
        }
      });
    }
    await _fetchOrgParts(_orgKind, background: false, only: missing);
  }

  Future<void> _selectItemYear(int year) async {
    if (_seasonYear == year) return;
    setState(() {
      _seasonYear = year;
      _invalidateYearParts();
    });
    await _ensureSeasonYearLoaded();
    if (year == DateTime.now().year) {
      unawaited(_startGamesWatch());
    } else {
      _gamesRefreshTimer?.cancel();
      _gamesPollTimer?.cancel();
    }
    unawaited(_prefetchOtherOrg());
  }

  Future<void> _restoreCurrentBoardParts() async {
    await _ensureSeasonYearLoaded();
  }

  Future<void> _fetchOrgParts(
    OrgKind target, {
    required bool background,
    List<_LoadPart>? only,
  }) async {
    _ensureCache(target);
    final parts = only ?? _LoadPart.values;
    final pending = [
      for (final part in parts)
        if (!_partLoadedForYear(target, part)) part,
    ];
    if (pending.isEmpty) return;
    // 順位表→試合を先に出し、個人成績と Info は接続を奪わないよう後追いする。
    if (pending.contains(_LoadPart.standings)) {
      await _fetchPart(target, _LoadPart.standings, _seasonYear, background: background);
    }
    if (pending.contains(_LoadPart.games)) {
      await _fetchPart(target, _LoadPart.games, _seasonYear, background: background);
    }
    final rest = [
      for (final part in pending)
        if (part != _LoadPart.standings && part != _LoadPart.games) part,
    ];
    if (rest.isEmpty) return;
    final awaitRest = only != null && !pending.contains(_LoadPart.games) && !pending.contains(_LoadPart.standings);
    if (awaitRest) {
      await Future.wait([
        for (final part in rest) _fetchPart(target, part, _seasonYear, background: background),
      ]);
      return;
    }
    for (final part in rest) {
      unawaited(_fetchPart(target, part, _seasonYear, background: true));
    }
  }

  Future<void> _fetchPart(OrgKind target, _LoadPart part, int year, {required bool background, bool force = false}) async {
    final key = '${target.name}|${part.name}|$year';
    final inflight = _partLoadFutures[key];
    if (inflight != null) {
      await inflight;
      if (!force) return;
    }
    final future = _fetchPartOnce(target, part, year, background: background, fresh: force);
    _partLoadFutures[key] = future;
    try {
      await future;
    } finally {
      if (identical(_partLoadFutures[key], future)) {
        _partLoadFutures.remove(key);
      }
    }
  }

  Future<void> _fetchPartOnce(OrgKind target, _LoadPart part, int year, {required bool background, bool fresh = false}) async {
    final org = OrgConfig.of(target);
    try {
      String? from;
      String? to;
      if (part == _LoadPart.games && year == DateTime.now().year) {
        final window = defaultGamesSqlWindow(DateTime.now());
        from = ymdOf(window.from);
        to = ymdOf(window.to);
      }
      final res = await http.get(Env.api(_partPath(target, part.name, year, fresh: fresh, from: from, to: to))).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        logger.w('part ${part.name} HTTP ${res.statusCode}');
        _maybeSetPartError(target, background, 'HTTPエラー: ${res.statusCode}');
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (part != _LoadPart.info && year != _seasonYear) {
        return;
      }
      final bundle = _ensureCache(target);

      switch (part) {
        case _LoadPart.info:
          break;
        case _LoadPart.standings:
          bundle.predictions = listMapFromJson(map['predict_team']).where(org.rowBelongs).toList();
          bundle.standings = listMapFromJson(map['stats_team']).where(org.rowBelongs).toList();
          break;
        case _LoadPart.players:
          bundle.playerStats = listMapFromJson(map['predict_player']).where(org.rowBelongs).toList();
          bundle.playerStatsActual = listMapFromJson(map['stats_player']).where(org.rowBelongs).toList();
          break;
        case _LoadPart.games:
          _applyGamesPayload(bundle, map, org, year);
          break;
      }
      bundle.readyParts.add(part);
      _loadedPartYears['${target.name}|${part.name}'] = year;
      _readyParts.putIfAbsent(target, () => <_LoadPart>{}).add(part);

      if (!mounted) return;
      setState(() {
        if (part == _LoadPart.info) {
          _applySharedInfo(map);
          _captureInfoUsers(listMapFromJson(map['predict_team']));
        }
        if (target == _orgKind) {
          switch (part) {
            case _LoadPart.info:
              break;
            case _LoadPart.standings:
              predictions = List<Map<String, dynamic>>.from(bundle.predictions);
              standings = List<Map<String, dynamic>>.from(bundle.standings);
              _captureInfoUsers(predictions, npbPlayerStats);
              _scheduleTeamLogoPrecache(standings);
              break;
            case _LoadPart.players:
              npbPlayerStats = List<Map<String, dynamic>>.from(bundle.playerStats);
              npbPlayerStatsActual = List<Map<String, dynamic>>.from(bundle.playerStatsActual);
              _captureInfoUsers(predictions, npbPlayerStats);
              break;
            case _LoadPart.games:
              games = List<Map<String, dynamic>>.from(bundle.games);
              postseasonGames = List<Map<String, dynamic>>.from(bundle.postseasonGames);
              showPostseasonBoard = bundle.showPostseasonBoard;
              break;
          }
          isLoading = false;
          _shellReady = true;
          if (!background) error = null;
        }
      });
    } catch (e, st) {
      logger.e('part ${part.name} 通信/解析エラー: $e\n$st');
      _maybeSetPartError(target, background, '通信エラー: $e');
    }
  }

  void _applyGamesPayload(
    _OrgBundle bundle,
    Map<String, dynamic> map,
    OrgConfig org,
    int year,
  ) {
    final incoming = normalizeGames(listMapFromJson(map['games'])).where(org.gameBelongs).toList();
    final window = resolveGamesWindow(
      fromText: '${map['from'] ?? ''}',
      toText: '${map['to'] ?? ''}',
      year: year,
    );
    final from = window.from;
    final to = window.to;
    final dayWindow = from != null && to != null && from == to;
    if (from != null && to != null && (dayWindow || bundle.extraGameDates.isNotEmpty)) {
      bundle.games = mergeGamesForDateRange(bundle.games, incoming, from, to);
    } else {
      bundle.games = dedupeSameDayMatchupRows(incoming);
    }
    if (dayWindow) {
      bundle.extraGameDates.add(ymdOf(from));
    } else {
      bundle.gamesFrom = from;
      bundle.gamesTo = to;
    }
    bundle.postseasonGames = dedupeSameDayMatchupRows(listMapFromJson(map['postseason_games']));
    bundle.showPostseasonBoard = postseasonBoardVisible(
      serverFlag: map['show_postseason_board'] == true,
      today: DateTime.now(),
    );
  }

  bool _shouldLoadGameDate(DateTime date) {
    final bundle = _orgCache[_orgKind];
    final ymd = ymdOf(date);
    final local = bundle?.games ?? games;
    final hasGames = local.any((game) => gameDateOnly(game['date_game']) == ymd);
    return gameDateNeedsSqlLoad(
      date,
      bundle?.gamesFrom,
      bundle?.gamesTo,
      bundle?.extraGameDates ?? const {},
      hasGamesForDate: hasGames,
    );
  }

  Future<void> _loadGameDate(DateTime date) async {
    final kind = _orgKind;
    final ymd = DateFormatUtil.ymd(date);
    final inflightKey = '${kind.name}|$ymd';
    if (_pastDateInflight.contains(inflightKey) || !_shouldLoadGameDate(date)) return;
    _pastDateInflight.add(inflightKey);
    if (mounted) setState(() => _loadingGameDateByOrg[kind] = ymd);
    try {
      final org = OrgConfig.of(kind);
      final res = await http
          .get(Env.api(_partPath(kind, 'games', _seasonYear, date: ymd, fresh: true)))
          .timeout(const Duration(seconds: 60));
      if (!mounted) return;
      if (res.statusCode != 200) {
        logger.w('past games $ymd HTTP ${res.statusCode}');
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final bundle = _ensureCache(kind);
      _applyGamesPayload(bundle, map, org, _seasonYear);
      bundle.extraGameDates.add(ymd);
      setState(() {
        if (kind != _orgKind) return;
        games = List<Map<String, dynamic>>.from(bundle.games);
        postseasonGames = List<Map<String, dynamic>>.from(bundle.postseasonGames);
        showPostseasonBoard = bundle.showPostseasonBoard;
      });
    } catch (e, st) {
      logger.w('past games $ymd 失敗: $e\n$st');
    } finally {
      _pastDateInflight.remove(inflightKey);
      if (mounted) {
        setState(() {
          if (_loadingGameDateByOrg[kind] == ymd) _loadingGameDateByOrg[kind] = null;
        });
      }
    }
  }

  bool get _showPostseasonNow =>
      showPostseasonBoard || postseasonBoardVisible(serverFlag: false, today: DateTime.now());

  void _scheduleTeamLogoPrecache(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheTeamLogos(context, rows);
    });
  }

  /// コンテンツが1つも無いときだけ全面エラーにする（他パート成功時は残す）
  void _maybeSetPartError(OrgKind target, bool background, String message) {
    if (background || target != _orgKind || !mounted) return;
    final hasContent = _boardContentReady || (_orgCache[target]?.hasContent ?? false);
    if (hasContent) return;
    setState(() {
      error = message;
      isLoading = false;
      _shellReady = true;
    });
  }

  // flg_atari の合計（予想者のみ: id_user 1/2、セ+パ合算）

  Widget _portraitTabBar({
    required List<(String label, int index)> tabs,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    Color? selectedColor,
    Color? selectedForeground,
    Map<int, String>? leadingAssets,
  }) {
    final assets = leadingAssets ?? const <int, String>{};
    final Color active = selectedColor ?? ALL_COLOR_APP;
    final Color activeFg = selectedForeground ?? TAB_COLOR_FONT;
    return SizedBox(
      height: TAB_BAR_H,
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: ALL_SPACE_BLOCK),
            Expanded(
              child: Material(
                color: selectedIndex == tabs[i].$2 ? active : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(TAB_RADIUS),
                child: InkWell(
                  onTap: () => onSelected(tabs[i].$2),
                  borderRadius: BorderRadius.circular(TAB_RADIUS),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (assets[tabs[i].$2] case final asset?) ...[
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                maxWidth: 56,
                                maxHeight: 31.5,
                                child: Transform.translate(
                                  offset: const Offset(0, -2),
                                  child: ColorFiltered(
                                    colorFilter: const ColorFilter.matrix([
                                      1,
                                      0,
                                      0,
                                      0,
                                      0,
                                      0,
                                      1,
                                      0,
                                      0,
                                      0,
                                      0,
                                      0,
                                      1,
                                      0,
                                      0,
                                      2.2,
                                      0,
                                      0,
                                      0,
                                      -45,
                                    ]),
                                    child: Image.asset(
                                      asset,
                                      width: 56,
                                      height: 31.5,
                                      fit: BoxFit.fill,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          tabs[i].$1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.0,
                            leadingDistribution: TextLeadingDistribution.even,
                            fontWeight: selectedIndex == tabs[i].$2 ? FontWeight.bold : FontWeight.normal,
                            color: selectedIndex == tabs[i].$2 ? activeFg : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _leaguePickerWidth(BuildContext context) {
    const style = TextStyle(fontSize: 11, height: 1.0, color: Colors.white, fontWeight: FontWeight.bold);
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: const TextSpan(text: 'リーグごとに表示', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    // フォント未読込の初回は漢字が狭く測られることがある。
    final floor = 11.0 * scaler.scale(1) * 7;
    final textW = painter.width > floor ? painter.width : floor;
    // 矢印分だけ足す（横余白は最小）。
    return textW + 18;
  }

  String _gamesInitialDate() {
    final now = DateTime.now();
    if (_seasonYear == now.year) return DateFormatUtil.ymdWithOffset(0);
    DateTime? latest;
    void consider(dynamic raw) {
      final text = gameDateOnly(raw);
      final parsed = DateTime.tryParse(text);
      if (parsed == null) return;
      if (latest == null || parsed.isAfter(latest!)) latest = parsed;
    }
    for (final game in games) {
      consider(game['date_game']);
    }
    for (final game in postseasonGames) {
      consider(game['date_game']);
    }
    latest ??= DateTime(_seasonYear, 10, 15);
    return DateFormatUtil.ymd(latest!);
  }

  Widget _yearPicker() {
    final selected = _seasonYear;
    final first = _orgKind == OrgKind.mlb ? 1876 : 1936;
    return SizedBox(
      width: 56,
      height: TAB_BAR_H,
      child: Material(
        color: Colors.black,
        borderRadius: BorderRadius.circular(TAB_RADIUS),
        clipBehavior: Clip.antiAlias,
        child: PopupMenuButton<int>(
          tooltip: '年度を選択',
          color: Colors.black,
          initialValue: selected,
          position: PopupMenuPosition.under,
          onSelected: (year) => unawaited(_selectItemYear(year)),
          itemBuilder: (_) => [
            for (var year = DateTime.now().year; year >= first; year--)
              PopupMenuItem<int>(
                value: year,
                height: 34,
                child: Text(
                  '$year',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
          ],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$selected',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.white, size: 15),
            ],
          ),
        ),
      ),
    );
  }

  Widget _viewModePicker() {
    return SizedBox(
      width: _leaguePickerWidth(context),
      height: TAB_BAR_H,
      child: Material(
        color: Colors.black,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Colors.black),
          borderRadius: BorderRadius.circular(TAB_RADIUS),
        ),
        child: PopupMenuButton<bool>(
          padding: EdgeInsets.zero,
          tooltip: '',
          color: Colors.black,
          initialValue: _viewByItem,
          position: PopupMenuPosition.under,
          onSelected: (value) {
            if (value == _viewByItem) return;
            setState(() => _viewByItem = value);
            writeBrowserCookie(_viewCookie, value ? '1' : '0');
            if (value) {
              unawaited(_ensureItemYearLoaded(_itemTab));
            } else {
              unawaited(_restoreCurrentBoardParts());
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: false,
              height: 36,
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text('リーグごとに表示', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.0, color: Colors.white, fontWeight: FontWeight.bold))),
            ),
            PopupMenuItem(
              value: true,
              height: 36,
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text('項目ごとに表示', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.0, color: Colors.white, fontWeight: FontWeight.bold))),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 14),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  _viewByItem ? '項目ごとに表示' : 'リーグごとに表示',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.0,
                    leadingDistribution: TextLeadingDistribution.even,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Positioned(
                  right: 0,
                  child: Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Info と項目タブのあいだ。選択時は団体色＋ロゴ、非選択は薄いグレー。
  Widget _orgTabBar() {
    return SizedBox(
      height: TAB_BAR_H + 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: OrgConfig.tabIdleColor,
          borderRadius: BorderRadius.circular(TAB_RADIUS),
          border: Border.all(color: const Color(0xFFD0D0D6), width: 0.5),
        ),
        child: Row(
          children: [
            for (final kind in OrgKind.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Builder(
                    builder: (context) {
                      final org = OrgConfig.of(kind);
                      final selected = _orgKind == kind;
                      final bg = selected ? org.tabColor : OrgConfig.tabIdleColor;
                      final fg = selected ? org.tabForeground : Colors.black54;
                      return GestureDetector(
                        onTap: () => _changeOrg(kind),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(TAB_RADIUS - 2),
                            border: Border.all(
                              color: selected ? Colors.black54 : const Color(0xFFD0D0D6),
                              width: selected ? 1.2 : 0.5,
                            ),
                            boxShadow: selected
                                ? const [
                                    BoxShadow(
                                      color: Color(0x1A000000),
                                      blurRadius: 2,
                                      offset: Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                org.logoAsset,
                                width: kind == OrgKind.npb ? 22 : 18,
                                height: kind == OrgKind.npb ? 18 : 18,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const SizedBox(width: 18, height: 18),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                org.label,
                                style: TextStyle(
                                  fontSize: TAB_BAR_H / 2,
                                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                                  color: fg,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _boardTabBar() {
    final byLeague = !_viewByItem;
    return Row(
      children: [
        Expanded(
          child: byLeague
              ? _portraitLeagueTabBar()
              : _portraitTabBar(
                  tabs: const [
                    ('試合情報', 0),
                    ('チーム順位', 1),
                    ('個人成績', 2),
                  ],
                  selectedIndex: _itemTab,
                  onSelected: (i) {
                    if (i == _itemTab) return;
                    setState(() => _itemTab = i);
                    unawaited(_ensureItemYearLoaded(i));
                  },
                  selectedColor: _org.tabColor,
                  selectedForeground: _org.tabForeground,
                ),
        ),
      ],
    );
  }

  Widget _leaguePane({
    required int leagueId,
    required SeasonPane pane,
    bool portraitLayout = false,
  }) {
    final gamesForLeague = games.where((game) {
      final home = int.tryParse('${game['id_league_home']}') ?? 0;
      final away = int.tryParse('${game['id_league_away']}') ?? 0;
      return home == leagueId && away == leagueId;
    }).toList();
    return SeasonTableBlock(
      standings: standings,
      stats: npbPlayerStatsActual,
      games: gamesForLeague,
      onlyLeagueId: leagueId,
      gamesDateFilter: _gamesInitialDate(),
      portraitLayout: portraitLayout,
      pane: pane,
      org: _org,
      personalStatsLayout: _personalStatsLayout,
      onPersonalStatsLayoutChanged: _setPersonalStatsLayout,
      loadingStandings: !_partReady(_LoadPart.standings),
      loadingStats: !_partReady(_LoadPart.players),
      loadingGames: !_partReady(_LoadPart.games),
      seasonYear: _seasonYear,
      onNeedGameDate: _loadGameDate,
      shouldLoadGameDate: _shouldLoadGameDate,
      loadingGameDate: _loadingGameDate,
      gameDateOffset: _gameDateOffset,
      onGameDateOffsetChanged: _setGameDateOffset,
    );
  }

  Widget _itemBoard({bool wideLayout = false}) {
    if (_itemTab == 2) {
      if (!_partReady(_LoadPart.players)) {
        return const Center(child: CircularProgressIndicator());
      }
      // 横長は打者上段・投手下段の全グリッド。縦長のみセグメント／スクロール切替。
      if (wideLayout) {
        return DualBandBothLeaguePersonalStats(
          stats: npbPlayerStatsActual,
          org: _org,
        );
      }
      return BothLeaguePersonalStats(
        stats: npbPlayerStatsActual,
        org: _org,
        layout: _personalStatsLayout,
        onLayoutChanged: _setPersonalStatsLayout,
      );
    }
    if (_itemTab == 0) {
      final showBracket = _showPostseasonNow;
      if (!_partReady(_LoadPart.games) && !showBracket) {
        return const Center(child: CircularProgressIndicator());
      }
      return BothLeagueGameDay(
        key: ValueKey('both-${_orgKind.name}-$_seasonYear-${_gamesInitialDate()}'),
        games: games,
        playerStats: npbPlayerStatsActual,
        initialDate: _gamesInitialDate(),
        leading: showBracket ? [_postseasonBracket(), const SizedBox(height: 6)] : const [],
        leagues: [
          for (final league in _org.leagues) (id: league.id, name: league.name, color: league.color),
        ],
        onNeedGameDate: _loadGameDate,
        shouldLoadGameDate: _shouldLoadGameDate,
        loadingGameDate: _loadingGameDate,
        loadingGames: !_partReady(_LoadPart.games),
        dateOffset: _gameDateOffset,
        onDateOffsetChanged: _setGameDateOffset,
      );
    }
    if (!_partReady(_LoadPart.standings)) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        for (var i = 0; i < _org.leagues.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _leaguePane(leagueId: _org.leagues[i].id, pane: SeasonPane.standings, portraitLayout: true),
        ],
      ],
    );
  }

  static const _mlbPostseasonCodes = {
    'WC', 'DS', 'LCS', 'WS',
    'ALWC', 'NLWC', 'ALWC36', 'ALWC45', 'NLWC36', 'NLWC45',
    'ALDS', 'NLDS', 'ALDS1', 'ALDS2', 'NLDS1', 'NLDS2',
    'ALCS', 'NLCS',
  };

  /// postseason_games に加え、直近ゲームに付いた MLB ポストシーズン code も使う。
  List<Map<String, dynamic>> _mlbBracketGames() {
    final byId = <String, Map<String, dynamic>>{};
    void add(Map<String, dynamic> row) {
      final id = '${row['id_game'] ?? row['id'] ?? ''}';
      final key = id.isNotEmpty ? id : '${row['code_game']}_${row['id_team_home']}_${row['id_team_away']}_${row['date_game'] ?? ''}';
      byId.putIfAbsent(key, () => row);
    }

    for (final row in postseasonGames) {
      add(row);
    }
    for (final row in games) {
      final code = '${row['code_game'] ?? ''}'.trim().toUpperCase();
      if (_mlbPostseasonCodes.contains(code)) add(row);
    }
    return byId.values.toList();
  }

  Widget _postseasonBracket() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMlb = _orgKind == OrgKind.mlb;
        final boardW = isMlb ? MlbBracketGeom.w : BracketGeom.w;
        final boardH = isMlb ? MlbBracketGeom.h : BracketGeom.h;
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : boardW;
        final loadingTeams = !_partReady(_LoadPart.standings);
        return SizedBox(
          width: width,
          height: width * boardH / boardW,
          child: isMlb
              ? MlbPostseasonBracket(
                  standings: standings,
                  games: _mlbBracketGames(),
                  loadingTeams: loadingTeams,
                )
              : PostseasonBracket(
                  standings: standings,
                  games: postseasonGames,
                  loadingTeams: loadingTeams,
                ),
        );
      },
    );
  }

  Widget _portraitLeagueTabBar() {
    final assets = <int, String>{
      for (var i = 0; i < _org.leagues.length; i++)
        if (_org.leagues[i].logoAsset != null) i: _org.leagues[i].logoAsset!,
    };
    return _portraitTabBar(
      tabs: [
        for (var i = 0; i < _org.leagues.length; i++) (_org.leagues[i].name, i),
      ],
      selectedIndex: _portraitLeagueTab,
      onSelected: (i) {
        if (i == _portraitLeagueTab) return;
        setState(() => _portraitLeagueTab = i);
      },
      selectedColor: _org.leagueAt(_portraitLeagueTab).color,
      leadingAssets: assets.isEmpty ? null : assets,
    );
  }

  Widget _portraitCollapsibleSection({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
    bool showNew = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: Colors.white,
        border: Border.all(color: Colors.black87, width: 1.5),
        borderRadius: BorderRadius.circular(10),
          ),
      clipBehavior: Clip.antiAlias,
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Material(
            color: Colors.black,
            child: InkWell(
              onTap: onToggle,
              child: SizedBox(
                height: 24,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (showNew) ...[
                        const SizedBox(width: 6),
                        const BlinkNewMark(fontSize: 9),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: child,
            ),
        ],
      ),
    );
  }

  /// Info 用。NPB+MLB の当を合算し、団体タブ切替では数字が入れ替わらないようにする。
  Map<String, int> _infoAtariCounts() {
    final totals = <String, int>{'1': 0, '2': 0};
    for (final kind in OrgKind.values) {
      final ready = _partReady(_LoadPart.standings, kind) || _partReady(_LoadPart.players, kind);
      if (!ready) continue;
      final bundle = (kind == _orgKind) ? _snapshotCurrent() : _orgCache[kind];
      if (bundle == null) continue;
      final part = computeAtariCounts(
        npbPlayerStats: bundle.playerStats,
        standings: bundle.standings,
      );
      totals['1'] = (totals['1'] ?? 0) + (part['1'] ?? 0);
      totals['2'] = (totals['2'] ?? 0) + (part['2'] ?? 0);
    }
    return totals;
  }

  // 上部: Score + News + イベント日程（NPB/MLB 共通。団体タブでは内容を切り替えない）
  Widget _scoreNewsEventsRow({required bool portrait}) {
    final counts = _infoAtariCounts();
    final infoLoading = !_partReady(_LoadPart.info);
    // SCORE は NPB / MLB の合算値。片方だけの途中値を確定値のように見せない。
    final scoreLoading = OrgKind.values.any(
      (kind) => !_partReady(_LoadPart.standings, kind) || !_partReady(_LoadPart.players, kind),
    );
    final namesLoading = infoLoading && !_partReady(_LoadPart.standings);

    Widget _miniSpinner({double size = 18}) => SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );

    Widget _scoreBox({bool hideHeader = false, bool portraitCompact = false}) {
      // ログインユーザーを左、相手を右に並べる（id=1/2 の予想者）
      final loginId = AuthSession.instance.user?.id;
      final selfLeft = loginId == 2;
      final leftKey = selfLeft ? '2' : '1';
      final rightKey = selfLeft ? '1' : '2';
      final name1 = selfLeft ? _infoName2 : _infoName1;
      final name2 = selfLeft ? _infoName1 : _infoName2;
      final score1 = '${counts[leftKey] ?? 0}';
      final score2 = '${counts[rightKey] ?? 0}';
      final color1 = (selfLeft ? _infoColor2 : _infoColor1) ?? Colors.blue;
      final color2 = (selfLeft ? _infoColor1 : _infoColor2) ?? Colors.red;
      const double vBorder = 1.0;
      const double cellPad = 6.0;

      Widget _nameCell(String name, Color background, {bool leftBorder = false}) {
        final showSpinner = namesLoading && name.trim().isEmpty;
        return Expanded(
                child: Container(
            decoration: BoxDecoration(
              color: background,
              border: leftBorder ? const Border(left: BorderSide(color: Colors.black45, width: vBorder)) : null,
            ),
                  alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: cellPad, vertical: 4),
            child: showSpinner
                ? _miniSpinner(size: 16)
                : OneLineShrinkText(
                    name,
                    baseSize: 20,
                    minSize: 10,
                    weight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black87, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: portraitCompact ? MainAxisSize.min : MainAxisSize.max,
                  children: [
            if (!hideHeader)
                    Container(
                height: 30,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  border: Border(bottom: BorderSide(color: Colors.black45, width: vBorder)),
                ),
                      alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: cellPad, vertical: 4),
                child: const OneLineShrinkText(
                  'SCORE',
                  baseSize: 20,
                        minSize: 10,
                        weight: FontWeight.bold,
                  align: TextAlign.center,
                        color: Colors.white,
                      ),
                    ),
            // 2行目: 立石 | 江島
            Container(
              height: portraitCompact ? 26 : 32,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.black45, width: vBorder)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _nameCell(name1, color1),
                  _nameCell(name2, color2, leftBorder: true),
                ],
              ),
            ),
            // 3行目: 数字（両列とも同じフォントサイズ）
            if (portraitCompact)
              SizedBox(
                height: 46,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(cellPad),
                        alignment: Alignment.center,
                        child: scoreLoading
                            ? _miniSpinner(size: 20)
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  score1,
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.0),
                        ),
                      ),
                    ),
                    ),
                    Expanded(
                      child: Container(
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.black45, width: vBorder)),
                ),
                        padding: const EdgeInsets.all(cellPad),
                      alignment: Alignment.center,
                        child: scoreLoading
                            ? _miniSpinner(size: 20)
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  score2,
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.0),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              )
            else
                    Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final double halfW = c.maxWidth / 2;
                  final double availW = (halfW - cellPad * 2).clamp(0.0, double.infinity);
                  final double availH = (c.maxHeight - cellPad * 2).clamp(0.0, double.infinity);
                  final double byH = availH * 0.88;
                  final double byW = availW * 0.88;
                  final double scoreSize = (byH < byW ? byH : byW).clamp(16.0, 56.0);

                  Widget scoreCell(String value, {bool leftBorder = false}) {
                    return Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                        color: Colors.white,
                          border: leftBorder ? const Border(left: BorderSide(color: Colors.black45, width: vBorder)) : null,
                        ),
                        padding: const EdgeInsets.all(cellPad),
                        alignment: Alignment.center,
                        child: scoreLoading
                            ? _miniSpinner(size: 22)
                            : Text(
                                value,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: scoreSize,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0,
                        ),
                      ),
                    ),
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      scoreCell(score1),
                      scoreCell(score2, leftBorder: true),
                    ],
                  );
                }),
              ),
          ],
        ),
      );
    }

    Widget _newsBox({bool hideHeader = false, double? boxHeight, bool fill = false}) {
      Color parse(String? name, Color fallback) {
        final n = (name ?? '').toLowerCase().trim();
        const m = {
          'red': 0xFFF44336,
          'green': 0xFF4CAF50,
          'blue': 0xFF0000FF,
          'navy': 0xFF001F3F,
          'royalblue': 0xFF4169E1,
          'orange': 0xFFFF9800,
          'yellow': 0xFFFFEB3B,
          'gold': 0xFFFFD700,
          'lime': 0xFFCDDC39,
          'black': 0xFF000000,
          'gray': 0xFF9E9E9E,
          'grey': 0xFF9E9E9E,
          'crimson': 0xFFDC143C,
          'lightgreen': 0xFF8BC34A,
          'white': 0xFFFFFFFF,
        };
        if (m.containsKey(n)) return Color(m[n]!);
        return fallback;
      }

      const double tagW = 64.0;
      const double tagH = 20.0;

      Widget newsTag(String title, Color back, Color font) {
      return Container(
          constraints: const BoxConstraints(minWidth: tagW, minHeight: tagH),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
          decoration: BoxDecoration(
            color: back,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            title,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(fontSize: 12, color: font, height: 1.1),
          ),
        );
      }

      final h = boxHeight ?? 120.0;
      return Container(
        height: fill ? null : h,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black45),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hideHeader)
              Material(
                color: const Color(0xFF757575),
                borderRadius: BorderRadius.circular(3),
                child: InkWell(
                  onTap: AuthSession.instance.showNewsNew ? () => unawaited(_markRead('news')) : null,
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                children: [
                        const Text('News', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        if (AuthSession.instance.showNewsNew) ...[
                          const SizedBox(width: 8),
                          const BlinkNewMark(fontSize: 10),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('未読メッセージを一覧表示', style: TextStyle(color: Colors.white, fontSize: 11)),
                              ),
                            ),
                          ),
                  ),
                ],
                    ),
                  ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 4),
                    Expanded(
                      child: infoLoading
                          ? Center(child: _miniSpinner(size: 22))
                          : ListView(
                              padding: EdgeInsets.zero,
                              primary: false,
                              children: [
                      for (final n in notifications)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      primary: false,
                          child: Row(
                                        mainAxisSize: MainAxisSize.min,
                            children: [
                                          newsTag(
                                  (n['tag_main_title'] ?? '').toString(),
                                            parse(n['tag_main_color_back'], Colors.grey.shade300),
                                            parse(n['tag_main_color_font'], Colors.white),
                              ),
                              const SizedBox(width: 6),
                                          newsTag(
                                  (n['tag_sub_title'] ?? '').toString(),
                                            parse(n['tag_sub_color_back'], Colors.grey.shade300),
                                            parse(n['tag_sub_color_font'], Colors.white),
                              ),
                              const SizedBox(width: 6),
                                          Text(
                                  (n['title'] ?? '').toString(),
                                            maxLines: 1,
                                            softWrap: false,
                                            style: const TextStyle(fontSize: 12, height: 1.1, color: Colors.black87),
                                          ),
                                        ],
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget _eventsBox({bool hideHeader = false, double? boxHeight, bool fill = false}) {
      final evs = [...events];
      evs.sort((a, b) => (a['date_from_temp'] ?? '').toString().compareTo((b['date_from_temp'] ?? '').toString()));

      Color parse(String? name, Color fallback) {
        final n = (name ?? '').toLowerCase().trim();
        const m = {
          'red': 0xFFF44336,
          'green': 0xFF4CAF50,
          'blue': 0xFF0000FF,
          'navy': 0xFF001F3F,
          'royalblue': 0xFF4169E1,
          'orange': 0xFFFF9800,
          'yellow': 0xFFFFEB3B,
          'gold': 0xFFFFD700,
          'lime': 0xFFCDDC39,
          'black': 0xFF000000,
          'gray': 0xFF9E9E9E,
          'grey': 0xFF9E9E9E,
          'crimson': 0xFFDC143C,
          'lightgreen': 0xFF8BC34A,
          'white': 0xFFFFFFFF,
        };
        if (m.containsKey(n)) return Color(m[n]!);
        return fallback;
      }

      String formatEventTiming(dynamic value) {
        return (value ?? '').toString().replaceAllMapped(
              RegExp(r'(?:\d{4}年)?(\d{1,2})月(\d{1,2})日'),
              (m) => '${m[1]!.padLeft(2, '0')}/${m[2]!.padLeft(2, '0')}',
            );
      }

      final h = boxHeight ?? 120.0;
      final content = Container(
        height: fill ? null : h,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black45),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hideHeader)
            SizedBox(
              width: double.infinity,
                child: Material(
                  color: const Color(0xFF757575),
                  borderRadius: BorderRadius.circular(3),
                  child: InkWell(
                    onTap: AuthSession.instance.showEventNew ? () => unawaited(_markRead('event')) : null,
                    borderRadius: BorderRadius.circular(3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          const Text('イベント日程', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          if (AuthSession.instance.showEventNew) ...[
                            const SizedBox(width: 8),
                            const BlinkNewMark(fontSize: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                child: infoLoading
                    ? Center(child: _miniSpinner(size: 22))
                    : LayoutBuilder(
                  builder: (context, constraints) {
                    double measureTextWidth(String text) {
                      final painter = TextPainter(
                        text: TextSpan(
                            text: text,
                            style: const TextStyle(
                              fontSize: 12,
                            )),
                        maxLines: 1,
                        textDirection: TextDirection.ltr,
                      )..layout();
                      return painter.width;
                    }

                    double rawMaxTitleW = 0;
                    for (final e in evs) {
                      final t = (e['title_event'] ?? '').toString();
                      final w = measureTextWidth(t);
                      if (w > rawMaxTitleW) rawMaxTitleW = w;
                    }

                    // 狭い比率でも固定幅の合計が親幅を超えないよう、全列を利用可能幅から配分する。
                    const double spacing = 14; // category間6 + title前6 + date前2
                    final usableW = math.max(0.0, constraints.maxWidth - spacing);
                    final catW = math.min(64.0, usableW * 0.20);
                    final textW = math.max(0.0, usableW - catW * 2);
                    final wantedTitleW = rawMaxTitleW.clamp(0.0, textW);
                    final titleColW = math.min(wantedTitleW, textW * 0.62);
                    final dateColW = math.max(0.0, textW - titleColW);

                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          const Divider(height: 1),
                          const SizedBox(height: 4),
                          for (final e in evs)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(children: [
                                // 主カテゴリ
                                Container(
                                  width: catW,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: parse(e['event_category_color_back'], Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: OneLineShrinkText(
                                    (e['event_category'] ?? '').toString(),
                                    baseSize: 12,
                                    minSize: 8,
                                    color: parse(e['event_category_color_font'], Colors.white),
                                    align: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // サブカテゴリ
                                Container(
                                  width: catW,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: parse(e['event_category_sub_color_back'], Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: OneLineShrinkText(
                                    (e['event_category_sub'] ?? '').toString(),
                                    baseSize: 12,
                                    minSize: 8,
                                    color: parse(e['event_category_sub_color_font'], Colors.white),
                                    align: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // タイトル（最長幅に固定）
                                SizedBox(
                                  width: titleColW,
                                  child: Builder(builder: (context) {
                                    final String title = (e['title_event'] ?? '').toString();
                                    final bool isToday = e['flg_today'] == true;
                                    final double tw = measureTextWidth(title);
                                    final double frac = (tw / titleColW).clamp(0.0, 1.0);
                                    final BoxDecoration? deco = isToday
                                        ? BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.yellowAccent.withOpacity(1.0),
                                                Colors.yellowAccent.withOpacity(1.0),
                                                Colors.yellowAccent.withOpacity(0.0),
                                              ],
                                              stops: [0.0, frac, 1.0],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                            borderRadius: BorderRadius.circular(3),
                                          )
                                        : null;
                                    return Container(
                                      decoration: deco,
                                      child: OneLineShrinkText(
                                        title,
                                        baseSize: 12,
                                        minSize: 8,
                                        align: TextAlign.left,
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(width: 2),
                                // 日付（左詰め・最小/最大幅内で縮小）
                                SizedBox(
                                  width: dateColW,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: OneLineShrinkText(
                                      formatEventTiming(e['txt_timing']),
                                      baseSize: 12,
                                      minSize: 8,
                                      align: TextAlign.left,
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                        ],
                      ),
                    );
                  }, //builder
                ),
              ),
            ),
          ],
        ),
      );

      return content;
    }

    if (portrait) {
      const double panelH = 160.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _portraitCollapsibleSection(
            title: 'News',
            expanded: _newsExpanded,
            onToggle: _toggleNewsSection,
            showNew: AuthSession.instance.showNewsNew,
            child: _newsBox(hideHeader: true, boxHeight: panelH),
          ),
          _portraitCollapsibleSection(
            title: 'イベント日程',
            expanded: _eventsExpanded,
            onToggle: _toggleEventsSection,
            showNew: AuthSession.instance.showEventNew,
            child: _eventsBox(hideHeader: true, boxHeight: panelH),
          ),
          if (_showUserPredictions) _scoreBox(hideHeader: true, portraitCompact: true),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 下段 SeasonTable と同じ比率・隙間で幅を決める（左のリーグ名ヘッダー分は含めない）
        final double rowW = constraints.maxWidth;
        const int standingsFlex = 3;
        const int personalFlex = 2;
        const double seasonGap = 4.0; // SeasonTable 内の隙間と同じ

        final double standingsW = (rowW - seasonGap) * standingsFlex / (standingsFlex + personalFlex);
        final double personalW = rowW - seasonGap - standingsW;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // イベント120 + 間隔6 + スコア名26 + 得点46
            SizedBox(width: standingsW, height: 198, child: _newsBox(fill: true)),
            const SizedBox(width: seasonGap),
            SizedBox(
              width: personalW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _eventsBox(),
                  if (_showUserPredictions) ...[
                    const SizedBox(height: 6),
                    _scoreBox(hideHeader: true, portraitCompact: true),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 初回のみ全画面グルグル。エラー時もヘッダー〜団体タブは出す。
    if (isLoading && !_shellReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // フル幅表示（スケーリングなし）
        final designWidth = constraints.maxWidth;
        const double scale = 1.0;
        final compact = false;
        // 1セクションも来ていなければタブ下にグルグル。来たものから描画する。
        final orgContentLoading = !_boardContentReady && error == null;

        final shortestSide = constraints.maxWidth < constraints.maxHeight ? constraints.maxWidth : constraints.maxHeight;
        final isPortrait = constraints.maxHeight / constraints.maxWidth >= PORTRAIT_ASPECT_RATIO || shortestSide < COMPACT_LAYOUT_PX;

        Widget centralLeagueBoard({
          required int leagueId,
          required Color leagueColor,
          required String logoAsset,
          required String leagueLabelPrefix,
        }) {
          return LeagueBoardRow(
            leagueId: leagueId,
            leagueColor: leagueColor,
            logoAsset: logoAsset,
            leagueLabelPrefix: leagueLabelPrefix,
            predictions: predictions,
            standings: standings,
            npbPlayerStats: npbPlayerStats,
            npbPlayerStatsActual: npbPlayerStatsActual,
            games: games,
            usernameForId: _usernameForId,
            userNameFromPredictions: _userNameFromPredictions,
            compact: compact,
            portraitLayout: isPortrait,
            org: _org,
            personalStatsLayout: _personalStatsLayout,
            onPersonalStatsLayoutChanged: _setPersonalStatsLayout,
            loadingStandings: !_partReady(_LoadPart.standings),
            loadingStats: !_partReady(_LoadPart.players),
            loadingGames: !_partReady(_LoadPart.games),
            seasonYear: _seasonYear,
            gamesDateFilter: _gamesInitialDate(),
            onNeedGameDate: _loadGameDate,
            shouldLoadGameDate: _shouldLoadGameDate,
            loadingGameDate: _loadingGameDate,
            gameDateOffset: _gameDateOffset,
            onGameDateOffsetChanged: _setGameDateOffset,
          );
        }

        final Widget chrome = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: ALL_SPACE_BLOCK),
            _infoShell(
              expand: false,
              child: isPortrait
                  ? _scoreNewsEventsRow(portrait: true)
                  : (_infoExpanded ? _scoreNewsEventsRow(portrait: false) : const SizedBox.shrink()),
            ),
            const SizedBox(height: 8),
            _orgTabBar(),
          ],
        );

        Widget portraitLeaguePage({
          required int leagueId,
          required Color leagueColor,
          required String logoAsset,
          required String leagueLabelPrefix,
        }) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                centralLeagueBoard(
                  leagueId: leagueId,
                  leagueColor: leagueColor,
                  logoAsset: logoAsset,
                  leagueLabelPrefix: leagueLabelPrefix,
                ),
                SizedBox(height: ALL_SPACE_BLOCK),
              ],
            ),
          );
        }

        // 取れたデータがあるときはエラー表示で消さない
        final Widget orgBody = orgContentLoading
            ? const Center(child: CircularProgressIndicator())
            : (error != null && !_boardContentReady)
                ? Center(child: Text(error!))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      _boardTabBar(),
                      SizedBox(height: ALL_SPACE_BLOCK),
                      Expanded(
                        flex: isPortrait ? 1 : ALL_RATIO_BLOCK_H[1] * 2,
                        child: _viewByItem
                            ? _itemBoard(wideLayout: !isPortrait)
                            : isPortrait
                                ? IndexedStack(
                                    index: _portraitLeagueTab,
                                    children: [
                                      for (final league in _org.leagues)
                                        portraitLeaguePage(
                                          leagueId: league.id,
                                          leagueColor: league.color,
                                          logoAsset: league.logoAsset ?? '',
                                          leagueLabelPrefix: league.name.replaceAll('・リーグ', ''),
                                        ),
                                    ],
                                  )
                                : Builder(
                                    builder: (context) {
                                      final league = _org.leagueAt(_portraitLeagueTab);
                                      return centralLeagueBoard(
                                        leagueId: league.id,
                                        leagueColor: league.color,
                                        logoAsset: league.logoAsset ?? '',
                                        leagueLabelPrefix: league.name.replaceAll('・リーグ', ''),
                                      );
                                    },
                                  ),
                      ),
                      if (isPortrait) SizedBox(height: ALL_SPACE_BLOCK),
                    ],
                  );

        final Widget bodyContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            chrome,
            Expanded(child: orgBody),
          ],
        );

        // レイアウトを「リーグ×2行、各行に 予想・成績・試合情報」を配置
        return ShowUserPredictions(
          value: _showUserPredictions,
          child: Container(
          alignment: Alignment.topCenter,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: designWidth),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Headers.globalHeader(
                        context,
                        HEADER_GLOBAL_H,
                        ALL_COLOR_APP,
                        HEADER_TITLE,
                        HEADER_PAD_VERTICAL,
                        ALL_MARGIN_LEFT,
                        onAuthChanged: _onAuthChanged,
                        authReady: _authEntryReady,
                        actions: [
                          _yearPicker(),
                          const SizedBox(width: 6),
                          _viewModePicker(),
                          const SizedBox(width: 4),
                        ],
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: ALL_SPACE_BLOCK, left: ALL_MARGIN_LEFT, right: ALL_MARGIN_LEFT),
                          child: bodyContent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
