import '../View/season_titles_board.dart';
import '../View/japanese_mlb_board.dart';
import '../View/other_baseball_board.dart';
import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';
import '../View/videos_board.dart';
import '../tools/tab_preferences.dart';
import '../View/retained_tab_body.dart';
import '../View/player_detail_dialog.dart';
import '../View/records_board.dart';
import '../tools/network_error.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../tools/Env.dart';
import '../tools/app_logger.dart';
import '../tools/board_session.dart';
import '../tools/browser_cookie.dart';
import '../tools/page_visibility.dart';
import '../tools/startup_response.dart';
import '../config/app_design.dart';
import '../config/org_config.dart';
import '../tools/json_utils.dart';
import '../tools/date_format.dart';
import '../logic/auth_session.dart';
import '../logic/show_user_predictions.dart';
import '../View/EventCalendar.dart';
import '../View/season_schedule_board.dart';
import '../View/Headers.dart';
import '../View/GamesBoard.dart';
import '../View/LeagueLogo.dart';
import '../View/SeasonTable.dart';
import '../View/team_strength_board.dart';
import '../View/MlbPostseasonBracket.dart';
import '../View/PostseasonBracket.dart';
import '../View/PredictGroupBoard.dart';
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
  bool get hasContent => readyParts.contains(_LoadPart.standings) || readyParts.contains(_LoadPart.players) || readyParts.contains(_LoadPart.games);

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
  bool _sharedInfoReady = false;
  final List<VoidCallback> _infoDialogListeners = [];
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
  static const _bracketCookie = 'koko_bracket_open';
  bool _bracketOpen = true;
  static const _orgCookie = 'koko_org';
  bool _otherOpen = false;
  OrgKind _orgKind = OrgKind.npb;
  final Map<OrgKind, _OrgBundle> _orgCache = {};
  final Map<OrgKind, Future<void>> _orgLoadFutures = {};
  int _itemTab = 0;
  int _seasonYear = DateTime.now().year;
  final Map<String, int> _loadedPartYears = {};
  PersonalStatsLayout _personalStatsLayout = PersonalStatsLayout.segment;
  Timer? _gamesPollTimer;
  bool _initialGamesDisplayComplete = false;
  bool _gamesWatchNotified = false;
  bool _gamesWatchNotifying = false;
  bool _predictGroupsOpen = false;
  bool _predictGroupsLoading = false;
  String? _predictGroupsError;
  List<Map<String, dynamic>> _predictGroups = const [];
  List<Map<String, dynamic>> _predictInvites = const [];
  List<Map<String, dynamic>> _predictTitleCatalog = const [];
  bool _gamesPollRunning = false;
  final Map<OrgKind, int> _gameDayOffset = {};
  final Map<OrgKind, String?> _loadingGameDateByOrg = {};
  final Set<String> _pastDateInflight = {};
  Map<String, dynamic>? _boardSession;

  int get _gameDateOffset => _gameDayOffset[_orgKind] ?? 0;

  String? get _loadingGameDate => _loadingGameDateByOrg[_orgKind];

  void _setGameDateOffset(int offset) {
    if (_gameDayOffset[_orgKind] == offset) return;
    setState(() => _gameDayOffset[_orgKind] = offset);
  }

  OrgConfig get _org => OrgConfig.of(_orgKind);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bindPageVisibility(_onPageBecameVisible);
    // cookie のタブをそのまま初回表示（predict / npb / mlb）
    final savedTab = readBrowserCookie(_orgCookie);
    _otherOpen = savedTab == 'other';
    if (savedTab == 'mlb') {
      _orgKind = OrgKind.mlb;
    } else if (savedTab == 'predict') {
      _predictGroupsOpen = true;
      _predictGroupsLoading = true;
      _orgKind = OrgKind.npb;
    } else {
      _orgKind = OrgKind.npb;
    }
    _itemTab = readSavedTab('main_${_orgKind.name}', [0, 1, 2, 3, 4, 5, 6, 8, if (_orgKind == OrgKind.mlb) 7], fallback: 0);
    _personalStatsLayout = readPersonalStatsLayout();
    if (readBrowserCookie(_bracketCookie) == '0') _bracketOpen = false;
    // First paint contains only the header/tabs; cache decoding and requests follow.
    _shellReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(Future<void>.delayed(Duration.zero, () {
        if (!mounted) return;
        setState(() {
          _restoreBoardSession();
          if (_predictGroupsOpen) _restorePredictSession(allowCookieUser: true);
        });
        unawaited(_bootstrapWithAuth());
      }));
    });
  }

  bool get _showUserPredictions => AuthSession.instance.isLoggedIn;

  bool _partReady(_LoadPart part, [OrgKind? kind]) => _readyParts[kind ?? _orgKind]?.contains(part) ?? false;

  bool get _boardContentReady => _partReady(_LoadPart.standings) || _partReady(_LoadPart.games) || _partReady(_LoadPart.players);

  Future<void> _bootstrapWithAuth() async {
    final authRestore = AuthSession.instance.restore();
    // 試合・順位はログイン確認を待たない。確認中に DB が塞がってもタブ取得を遅らせない。
    // 予想タブでは、表示しない試合の取得で予想一覧の DB 接続を奪わない。
    Future<void>? boardLoad = _predictGroupsOpen ? null : _loadThenWatchGames();
    try {
      await authRestore.timeout(const Duration(seconds: 15));
    } catch (e, st) {
      unawaited(AuthSession.instance.reportTimeout(e, st));
    }
    if (!mounted) return;
    setState(() => _authEntryReady = true);
    if (_predictGroupsOpen) {
      if (AuthSession.instance.isLoggedIn) {
        final userId = AuthSession.instance.user?.id ?? 0;
        final savedUser = _savedPredictUserId();
        if (savedUser > 0 && userId > 0 && savedUser != userId) {
          _predictGroups = const [];
          _predictTitleCatalog = const [];
        }
        if (_predictGroups.isEmpty) _restorePredictSession();
        if (mounted) {
          setState(() => _predictGroupsLoading = _predictGroups.isEmpty);
        }
        await _loadInitialPredictGroups();
      } else if (mounted) {
        setState(() {
          _predictGroups = const [];
          _predictGroupsLoading = false;
          _predictGroupsError = null;
        });
      }
    }
    if (!mounted) return;
    boardLoad ??= _loadThenWatchGames();
    try {
      await boardLoad;
    } catch (e, st) {
      unawaited(AuthSession.instance.reportTimeout(e, st));
    }
    if (!mounted) return;
    if (AuthSession.instance.isLoggedIn) unawaited(_fetchPredictInvites());
    if (_boardContentReady) {
      unawaited(AuthSession.instance.reportAction('初期表示を読み込んだ'));
    }
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (AuthSession.instance.isLoggedIn) {
      setState(() => _authEntryReady = true);
      unawaited(_fetchPredictInvites());
      if (_predictGroupsOpen) unawaited(_fetchPredictGroups());
      return;
    }
    _clearPredictSession();
    setState(() {
      _predictInvites = const [];
      _predictGroups = const [];
      _predictTitleCatalog = const [];
      _predictGroupsLoading = false;
      _predictGroupsError = null;
    });
    unawaited(_holdLoginUntilBoardReady());
  }

  Future<void> _holdLoginUntilBoardReady() async {
    if (!mounted) return;
    setState(() => _authEntryReady = false);
    try {
      await Future.wait([
        for (final part in _partsForItemView(null)) _fetchPart(_orgKind, part, _seasonYear, background: false, force: true),
      ]).timeout(const Duration(seconds: 45));
    } catch (e, st) {
      unawaited(AuthSession.instance.reportTimeout(e, st));
    }
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
    _scheduleTeamLogoPrecache(standings);
  }

  /// キャッシュへ保存（リストはコピーして参照共有を避ける）
  void _storeCache(OrgKind kind, _OrgBundle bundle) {
    _orgCache[kind] = bundle.copy();
    _readyParts[kind] = {...bundle.readyParts};
  }

  /// Info（ニュース・イベント・予想者名）は NPB/MLB 共通。空応答で消さない。
  void _applySharedInfo(Map<String, dynamic> map, {required bool settles}) {
    final evts = listMapFromJson(map['events']);
    final notifs = listMapFromJson(map['notification']);
    if (evts.isNotEmpty) events = evts;
    if (notifs.isNotEmpty) notifications = notifs;
    if (settles) _sharedInfoReady = true;
  }

  void addInfoDialogListener(VoidCallback listener) {
    _infoDialogListeners.add(listener);
  }

  void removeInfoDialogListener(VoidCallback listener) {
    _infoDialogListeners.remove(listener);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (_infoDialogListeners.isEmpty) return;
    for (final listener in List<VoidCallback>.of(_infoDialogListeners)) {
      listener();
    }
  }

  Map<String, dynamic> _sessionMap() {
    final cached = _boardSession;
    if (cached != null) return cached;
    final raw = readBoardSession();
    if (raw == null || raw.isEmpty) {
      _boardSession = <String, dynamic>{};
      return _boardSession!;
    }
    try {
      final decoded = jsonDecode(raw);
      _boardSession = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    } catch (_) {
      _boardSession = <String, dynamic>{};
    }
    return _boardSession!;
  }

  void _writeBoardSession() {
    try {
      writeBoardSession(jsonEncode(_sessionMap()));
    } catch (_) {}
  }

  int _jsonInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  _OrgBundle _bundleFromSession(Map<dynamic, dynamic> raw) {
    final predictions = listMapFromJson(raw['predictions']);
    final standings = listMapFromJson(raw['standings']);
    final playerStats = listMapFromJson(raw['playerStats']);
    final playerStatsActual = listMapFromJson(raw['playerStatsActual']);
    final games = listMapFromJson(raw['games']);
    final postseasonGames = listMapFromJson(raw['postseasonGames']);
    final parts = <_LoadPart>{};
    final names = raw['parts'];
    if (names is List) {
      for (final name in names) {
        for (final part in _LoadPart.values) {
          if (part != _LoadPart.info && part.name == '$name') parts.add(part);
        }
      }
    }
    if (parts.isEmpty) {
      if (standings.isNotEmpty || predictions.isNotEmpty) {
        parts.add(_LoadPart.standings);
      }
      if (playerStats.isNotEmpty || playerStatsActual.isNotEmpty) {
        parts.add(_LoadPart.players);
      }
      if (games.isNotEmpty || postseasonGames.isNotEmpty) {
        parts.add(_LoadPart.games);
      }
    }
    return _OrgBundle(
      predictions: predictions,
      standings: standings,
      playerStats: playerStats,
      playerStatsActual: playerStatsActual,
      games: games,
      postseasonGames: postseasonGames,
      showPostseasonBoard: raw['showPostseasonBoard'] == true,
      readyParts: parts,
    );
  }

  Map<String, dynamic> _bundleToSession(_OrgBundle bundle) => {
        'predictions': bundle.predictions,
        'standings': bundle.standings,
        'playerStats': bundle.playerStats,
        'playerStatsActual': bundle.playerStatsActual,
        'games': bundle.games,
        'postseasonGames': bundle.postseasonGames,
        'showPostseasonBoard': bundle.showPostseasonBoard,
        'parts': [
          for (final part in bundle.readyParts)
            if (part != _LoadPart.info) part.name,
        ],
      };

  void _restoreBoardSession() {
    final map = _sessionMap();
    if (_jsonInt(map['year']) != _seasonYear) return;
    final orgs = map['orgs'];
    if (orgs is Map) {
      for (final kind in OrgKind.values) {
        final raw = orgs[kind.name];
        if (raw is! Map) continue;
        final bundle = _bundleFromSession(raw);
        if (!bundle.hasContent) continue;
        _orgCache[kind] = bundle;
        _readyParts[kind] = {...bundle.readyParts};
      }
    }
    final current = _orgCache[_orgKind];
    if (current != null && current.hasContent) {
      _applyBundle(current, kind: _orgKind);
      isLoading = false;
    }
    final evts = listMapFromJson(map['events']);
    final notifs = listMapFromJson(map['notifications']);
    if (evts.isNotEmpty) events = evts;
    if (notifs.isNotEmpty) notifications = notifs;
  }

  void _persistBoardSession() {
    final orgs = <String, dynamic>{};
    for (final kind in OrgKind.values) {
      final bundle = _orgCache[kind];
      if (bundle == null || !bundle.hasContent) continue;
      orgs[kind.name] = _bundleToSession(bundle);
    }
    if (orgs.isEmpty && events.isEmpty && notifications.isEmpty) return;
    final map = _sessionMap();
    map['year'] = _seasonYear;
    map['orgs'] = orgs;
    map['events'] = events;
    map['notifications'] = notifications;
    _writeBoardSession();
  }

  int _savedPredictUserId() {
    final predict = _sessionMap()['predict'];
    if (predict is! Map) return 0;
    return _jsonInt(predict['userId']);
  }

  int? _cookieUserId() {
    if (readBrowserCookie(authManualLogoutCookie) == '1') return null;
    final token = readBrowserCookie(authTokenCookie);
    if (token == null || token.isEmpty) return null;
    final raw = readBrowserCookie(authUserCookie);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final id = _jsonInt(decoded['id']);
      return id > 0 ? id : null;
    } catch (_) {
      return null;
    }
  }

  bool _restorePredictSession({bool allowCookieUser = false}) {
    final predict = _sessionMap()['predict'];
    if (predict is! Map) return false;
    final savedUser = _jsonInt(predict['userId']);
    if (savedUser <= 0) return false;
    final sessionUser = AuthSession.instance.user?.id ?? 0;
    if (sessionUser > 0) {
      if (sessionUser != savedUser) return false;
    } else if (allowCookieUser) {
      if (_cookieUserId() != savedUser) return false;
    } else {
      return false;
    }
    final groups = listMapFromJson(predict['groups']);
    if (groups.isEmpty) return false;
    _predictGroups = groups;
    _predictTitleCatalog = listMapFromJson(predict['catalog']);
    _predictGroupsLoading = false;
    _predictGroupsError = null;
    return true;
  }

  void _persistPredictSession() {
    final userId = AuthSession.instance.user?.id ?? 0;
    if (userId <= 0 || _predictGroups.isEmpty) return;
    final map = _sessionMap();
    map['year'] = map['year'] ?? _seasonYear;
    map['predict'] = {
      'userId': userId,
      'groups': _predictGroups,
      'catalog': _predictTitleCatalog,
    };
    _writeBoardSession();
  }

  void _clearPredictSession() {
    final map = _sessionMap();
    if (!map.containsKey('predict')) return;
    map.remove('predict');
    _writeBoardSession();
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

  Future<String?> _savePredictGroupName(int id, String name) async {
    final token = AuthSession.instance.token;
    if (!AuthSession.instance.isLoggedIn || token == null || token.isEmpty) {
      return 'ログインしてください';
    }
    try {
      final res = await http
          .post(
            Env.api('/predict-group-name'),
            headers: {
              'Authorization': 'Bearer $token',
              'content-type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({'id': id, 'txt_name': name}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 401) return 'ログインしてください';
      if (res.statusCode != 200) return 'グループ名を保存できませんでした';
      final decoded = jsonDecode(res.body);
      final saved = decoded is Map ? decoded['group'] : null;
      if (saved is! Map) return 'グループ名を保存できませんでした';
      final savedId = int.tryParse('${saved['id']}') ?? id;
      final savedName = '${saved['txt_name'] ?? name}';
      if (!mounted) return null;
      setState(() {
        _predictGroups = [
          for (final row in _predictGroups)
            if ((int.tryParse('${row['id']}') ?? 0) == savedId) {...row, 'txt_name': savedName} else row,
        ];
      });
      return null;
    } catch (e) {
      return networkErrorMessage(e, fallback: 'グループ名を保存できませんでした');
    }
  }

  Future<List<Map<String, dynamic>>> _searchPredictNames(String kind, int leagueId, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final res = await http.get(Env.api('/predict-names?kind=$kind&league=$leagueId&q=${Uri.encodeQueryComponent(trimmed)}')).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      final raw = decoded is Map ? decoded['names'] : null;
      if (raw is! List) return const [];
      return [
        for (final row in raw)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _savePredictSetting(Map<String, dynamic> setting) async {
    final token = AuthSession.instance.token;
    if (!AuthSession.instance.isLoggedIn || token == null || token.isEmpty) {
      return 'ログインしてください';
    }
    try {
      final res = await http
          .post(
            Env.api('/predict-settings'),
            headers: {
              'Authorization': 'Bearer $token',
              'content-type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(setting),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 401) return 'ログインしてください';
      final decoded = jsonDecode(res.body);
      if (res.statusCode != 200) {
        final message = decoded is Map ? '${decoded['error'] ?? ''}'.trim() : '';
        return message.isEmpty ? '予想設定を保存できませんでした' : message;
      }
      if (!mounted) return null;
      final reloaded = await _fetchPredictGroups();
      final pending = decoded is Map && decoded['setting'] is Map && decoded['setting']['proposal_pending'] == true;
      if (pending) {
        return reloaded ? 'notice:予想は保存しました。期限とルールの変更は、参加ユーザー全員の賛成後に反映されます' : 'notice:期限とルールの変更案を保存しました。画面を開き直してください';
      }
      return reloaded ? null : '保存しました。画面を開き直してください';
    } catch (e) {
      return networkErrorMessage(e, fallback: '予想設定を保存できませんでした');
    }
  }

  Future<String?> _postPredict(String path, Map<String, dynamic> body, String failure) async {
    final token = AuthSession.instance.token;
    if (!AuthSession.instance.isLoggedIn || token == null || token.isEmpty) {
      return 'ログインしてください';
    }
    try {
      final res = await http
          .post(
            Env.api(path),
            headers: {
              'Authorization': 'Bearer $token',
              'content-type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(res.body);
      if (res.statusCode == 401) return 'ログインしてください';
      if (res.statusCode != 200) {
        final message = decoded is Map ? '${decoded['error'] ?? ''}'.trim() : '';
        return message.isEmpty ? failure : message;
      }
      if (!mounted) return null;
      await _fetchPredictGroups();
      await _fetchPredictInvites();
      return null;
    } catch (e) {
      return networkErrorMessage(e, fallback: failure);
    }
  }

  Future<String?> _createPredictGroup(String name, List<int> userIds) {
    return _postPredict('/predict-group', {'txt_name': name, 'user_ids': userIds}, 'グループを作成できませんでした');
  }

  Future<String?> _answerPredictInvite(int inviteId, bool accept) {
    return _postPredict('/predict-invite-answer', {'id': inviteId, 'accept': accept}, '招待への回答に失敗しました');
  }

  Future<String?> _deletePredictGroup(int groupId) {
    return _postPredict('/predict-group-delete', {'id': groupId}, '削除を保存できませんでした');
  }

  Future<String?> _createPredictYear(int groupId, int year) {
    return _postPredict('/predict-year', {'id': groupId, 'int_year': year}, '年度を追加できませんでした');
  }

  Future<List<Map<String, dynamic>>> _searchPredictUsers(String query) async {
    final token = AuthSession.instance.token;
    final trimmed = query.trim();
    if (!AuthSession.instance.isLoggedIn || token == null || token.isEmpty || trimmed.isEmpty) {
      return const [];
    }
    try {
      final res = await http.get(
        Env.api('/predict-users?q=${Uri.encodeQueryComponent(trimmed)}'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      final raw = decoded is Map ? decoded['users'] : null;
      if (raw is! List) return const [];
      return [
        for (final row in raw)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _fetchPredictInvites() async {
    final token = AuthSession.instance.token;
    if (!AuthSession.instance.isLoggedIn || token == null || token.isEmpty) {
      if (mounted && _predictInvites.isNotEmpty) {
        setState(() => _predictInvites = const []);
      }
      return;
    }
    try {
      final res = await http.get(
        Env.api('/predict-invites'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      if (!mounted || res.statusCode != 200) return;
      final decoded = jsonDecode(res.body);
      final raw = decoded is Map ? decoded['invites'] : null;
      setState(() {
        _predictInvites = [
          if (raw is List)
            for (final row in raw)
              if (row is Map) Map<String, dynamic>.from(row),
        ];
      });
    } catch (_) {}
  }

  Future<String?> _votePredictRule(int settingId) async {
    final token = AuthSession.instance.token;
    if (!AuthSession.instance.isLoggedIn || token == null || token.isEmpty) {
      return 'ログインしてください';
    }
    try {
      final res = await http
          .post(
            Env.api('/predict-setting-vote'),
            headers: {
              'Authorization': 'Bearer $token',
              'content-type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({'id_setting': settingId}),
          )
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(res.body);
      if (res.statusCode == 401) return 'ログインしてください';
      if (res.statusCode != 200) {
        final message = decoded is Map ? '${decoded['error'] ?? ''}'.trim() : '';
        return message.isEmpty ? '賛成を保存できませんでした' : message;
      }
      if (!mounted) return null;
      await _fetchPredictGroups();
      final applied = decoded is Map && decoded['vote'] is Map && decoded['vote']['applied'] == true;
      return applied ? 'notice:applied' : 'notice:pending';
    } catch (e) {
      return networkErrorMessage(e, fallback: '賛成を保存できませんでした');
    }
  }

  Future<bool> _fetchPredictGroups() async {
    final token = AuthSession.instance.token;
    if (!AuthSession.instance.isLoggedIn || token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _predictGroups = const [];
          _predictGroupsLoading = false;
          _predictGroupsError = null;
        });
      }
      return true;
    }
    final res = await http.get(
      Env.api('/predict-groups'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 60));
    if (!mounted || !AuthSession.instance.isLoggedIn || AuthSession.instance.token != token) {
      return true;
    }
    if (res.statusCode != 200) return false;
    final decoded = jsonDecode(res.body);
    final raw = decoded is Map ? decoded['groups'] : null;
    final catalogRaw = decoded is Map ? decoded['title_catalog'] : null;
    final groups = <Map<String, dynamic>>[
      if (raw is List)
        for (final row in raw)
          if (row is Map) Map<String, dynamic>.from(row),
    ];
    final catalog = <Map<String, dynamic>>[
      if (catalogRaw is List)
        for (final row in catalogRaw)
          if (row is Map) Map<String, dynamic>.from(row),
    ];
    setState(() {
      _predictGroups = groups;
      _predictTitleCatalog = catalog;
      _predictGroupsLoading = false;
      _predictGroupsError = null;
    });
    _persistPredictSession();
    unawaited(_fetchPredictInvites());
    return true;
  }

  Future<void> _loadInitialPredictGroups() async {
    try {
      final loaded = await _fetchPredictGroups();
      if (!mounted || loaded) return;
      setState(() {
        _predictGroupsLoading = false;
        _predictGroupsError = '予想グループを読み込めませんでした';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _predictGroupsLoading = false;
        _predictGroupsError = networkErrorMessage(e, fallback: '予想グループを読み込めませんでした');
      });
    }
  }

  Future<void> _openPredictGroups() async {
    setState(() => _otherOpen = false);
    writeBrowserCookie(_orgCookie, 'predict');
    if (_predictGroupsOpen && _predictGroups.isNotEmpty) return;
    setState(() {
      _predictGroupsOpen = true;
      _predictGroupsLoading = _predictGroups.isEmpty;
      _predictGroupsError = null;
    });
    unawaited(AuthSession.instance.reportAction('予想タブを開いた'));
    try {
      final loaded = await _fetchPredictGroups();
      if (!mounted || loaded) return;
      setState(() {
        _predictGroupsLoading = false;
        _predictGroupsError = '予想グループを読み込めませんでした';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _predictGroupsLoading = false;
        _predictGroupsError = networkErrorMessage(e, fallback: '予想グループを読み込めませんでした');
      });
    }
  }

  Future<void> _changeOrg(OrgKind kind) async {
    if (_otherOpen) {
      writeBrowserCookie(_orgCookie, kind.name);
      setState(() => _otherOpen = false);
    }
    if (kind == _orgKind && !_predictGroupsOpen) return;
    if (_predictGroupsOpen && kind == _orgKind) {
      writeBrowserCookie(_orgCookie, OrgConfig.of(kind).label.toLowerCase());
      setState(() => _predictGroupsOpen = false);
      unawaited(_loadThenWatchGames());
      return;
    }
    unawaited(AuthSession.instance.reportAction(kind == OrgKind.npb ? 'npbタブを開いた' : 'mlbタブを開いた'));
    writeBrowserCookie(_orgCookie, OrgConfig.of(kind).label.toLowerCase());
    // 離れる団体の表示内容を必ず保持
    _storeCache(_orgKind, _snapshotCurrent());
    final cached = _orgCache[kind];
    final usable = cached != null && cached.hasContent;
    setState(() {
      _predictGroupsOpen = false;
      _orgKind = kind;
      _itemTab = readSavedTab('main_${kind.name}', [0, 1, 2, 3, 4, 5, 6, 8, if (kind == OrgKind.mlb) 7], fallback: 0);
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
    _gamesPollTimer?.cancel();
    await _loadThenWatchGames();
  }

  Future<void> _prefetchOtherOrg() async {
    await Future<void>.delayed(const Duration(seconds: 20));
    if (!mounted) return;
    final other = _orgKind == OrgKind.npb ? OrgKind.mlb : OrgKind.npb;
    if ((_orgCache[other]?.hasContent ?? false) || _orgLoadFutures.containsKey(other)) {
      return;
    }
    await fetchData(kind: other, background: true);
  }

  Future<void> _ensureSharedInfo() {
    if (_sharedInfoReady) return Future<void>.value();
    return _fetchPart(OrgKind.npb, _LoadPart.info, _seasonYear, background: true);
  }

  void _openInfoPopup() {
    unawaited(AuthSession.instance.reportAction('news・イベント日程ポップアップを開いた'));
    if (AuthSession.instance.showNewsNew) unawaited(_markRead('news'));
    if (AuthSession.instance.showEventNew) unawaited(_markRead('event'));
    if (!_sharedInfoReady) unawaited(_ensureSharedInfo());
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _LiveInfoDialog(host: this),
    );
  }

  Widget _infoPopup(BuildContext dialogContext) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
          child: Row(
            children: [
              const Text('News・イベント', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              IconButton(
                tooltip: '閉じる',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(child: _newsEventsRow(portrait: false, popup: true)),
      ],
    );
  }

  Widget _infoButton() {
    final unread = AuthSession.instance.showNewsNew || AuthSession.instance.showEventNew || AuthSession.instance.showInfoNew;
    return SizedBox(
      width: TAB_BAR_H,
      height: TAB_BAR_H,
      child: Material(
        color: Colors.black,
        borderRadius: BorderRadius.circular(TAB_RADIUS),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openInfoPopup,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.newspaper, color: Colors.white, size: 16),
              if (unread)
                const Positioned(
                  top: 3,
                  right: 3,
                  child: BlinkNewMark(fontSize: 8),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _startGamesWatch() async {
    if (!_canWatchGames) return;
    // 一部パート失敗の error があっても、取れたデータがあれば監視は続ける。
    // 再取得は登録済みの集計テーブルを読むだけで、スクレイピングは呼ばない。
    // t_game の更新日時が前回と同じときはサーバが集計SQLを出さない。
    if (error != null && !_boardContentReady) return;
    unawaited(_notifyGamesDisplayReady());
    _gamesPollTimer?.cancel();
    _gamesPollTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_pollDisplayedGames());
    });
  }

  bool get _canWatchGames => mounted && _initialGamesDisplayComplete && _partLoadedForYear(_orgKind, _LoadPart.games) && !_orgLoadFutures.containsKey(_orgKind) && _seasonYear == DateTime.now().year;

  Map<String, String> get _readHeaders {
    final token = AuthSession.instance.token;
    return {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'};
  }

  Future<void> _notifyGamesDisplayReady() async {
    if (!_canWatchGames || _gamesWatchNotified || _gamesWatchNotifying) return;
    _gamesWatchNotifying = true;
    try {
      final response = await http.post(Env.api('/predictions/ready'), headers: _readHeaders).timeout(const Duration(seconds: 10));
      _gamesWatchNotified = response.statusCode == 204;
    } catch (_) {
      // 通知失敗で表示を止めず、次の定期取得時に再通知する。
    } finally {
      _gamesWatchNotifying = false;
    }
  }

  Future<void> _pollDisplayedGames() async {
    if (!_canWatchGames || _gamesPollRunning) return;
    unawaited(_notifyGamesDisplayReady());
    _gamesPollRunning = true;
    try {
      await _fetchPart(_orgKind, _LoadPart.games, _seasonYear, background: true, force: true);
    } finally {
      _gamesPollRunning = false;
    }
  }

  Future<void> _loadThenWatchGames() async {
    final kind = _orgKind;
    final year = _seasonYear;
    _initialGamesDisplayComplete = false;
    _gamesPollTimer?.cancel();
    await fetchData(kind: kind);
    if (!mounted || kind != _orgKind || year != _seasonYear) return;
    unawaited(_ensureSharedInfo());
    if (!mounted) return;
    if (!_shellReady || isLoading) {
      setState(() {
        _shellReady = true;
        isLoading = false;
      });
    }
    if (error != null && !_boardContentReady) return;
    // 応答の受信だけでなく、読み込んだ内容の描画を待って定期取得を許可する。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || kind != _orgKind || year != _seasonYear) return;
    _initialGamesDisplayComplete = true;
    await _startGamesWatch();
    unawaited(_prefetchOtherOrg());
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
    bool haveGames = false,
    String? date,
    String? from,
    String? to,
  }) {
    final path = StringBuffer(
      '/predictions/part?org=${OrgConfig.of(kind).label.toLowerCase()}&part=$part&year=$year',
    );
    if (fresh) path.write('&fresh=1');
    if (haveGames) path.write('&have=1');
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
    return (_orgCache[kind]?.partReady(part) ?? false) && _loadedPartYears['${kind.name}|${part.name}'] == _seasonYear;
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
    if (item >= 3) return; // 戦力・記録・動画はタブを開いたときだけデータを取得する。
    final kind = _orgKind;
    final year = _seasonYear;
    // 試合画面はトーナメントの順位と先発投手の個人成績も使用する。
    await _ensureSeasonYearLoaded(only: item == 0 ? const [_LoadPart.games, _LoadPart.standings, _LoadPart.players] : [_partForItem(item)]);
    if (item != 0 || !mounted || _itemTab != item || kind != _orgKind || year != _seasonYear || _initialGamesDisplayComplete) {
      return;
    }
    // 戦力タブで年度を変更したあとも、試合表示が整ってから定期取得を再開する。
    if (!_partLoadedForYear(kind, _LoadPart.games)) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _itemTab != item || kind != _orgKind || year != _seasonYear) {
      return;
    }
    _initialGamesDisplayComplete = true;
    await _startGamesWatch();
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
    _initialGamesDisplayComplete = false;
    _gamesPollTimer?.cancel();
    unawaited(AuthSession.instance.reportAction('年度を変更した', year: year));
    setState(() {
      _seasonYear = year;
      _invalidateYearParts();
    });
    if (_itemTab >= 3) return;
    await _ensureSeasonYearLoaded();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || year != _seasonYear) return;
    _initialGamesDisplayComplete = true;
    if (year == DateTime.now().year) {
      unawaited(_startGamesWatch());
    } else {
      _gamesPollTimer?.cancel();
    }
    unawaited(_prefetchOtherOrg());
  }

  Future<void> _fetchOrgParts(
    OrgKind target, {
    required bool background,
    List<_LoadPart>? only,
  }) async {
    _ensureCache(target);
    // 試合が遅くても順位・個人成績を先に表示できるよう、取得を分ける。
    final year = _seasonYear;
    final parts = only ?? _partsForItemView(null);
    final pending = [
      for (final part in parts)
        if (!_partLoadedForYear(target, part)) part,
    ];
    // 個人成績を順位待ちにしない。案内情報は順位・成績の後に取得する。
    await Future.wait([
      if (pending.contains(_LoadPart.games)) _fetchPart(target, _LoadPart.games, year, background: background),
      () async {
        await Future.wait([
          for (final part in [_LoadPart.standings, _LoadPart.players])
            if (pending.contains(part)) _fetchPart(target, part, year, background: background),
        ]);
        if (!mounted || _seasonYear != year) return;
        if (pending.contains(_LoadPart.info)) {
          await _fetchPart(target, _LoadPart.info, year, background: background);
        }
      }(),
    ]);
  }

  /// 項目ごと表示。開いているタブに関係なく、試合・順位・個人成績と Info を取る。
  List<_LoadPart> _partsForItemView(List<_LoadPart>? requested) {
    const visible = [_LoadPart.games, _LoadPart.info, _LoadPart.standings, _LoadPart.players];
    if (requested == null) return visible;
    return [
      for (final part in requested)
        if (visible.contains(part)) part
    ];
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
      final cachedGames = _orgCache[target]?.games.isNotEmpty ?? false;
      final haveGames = part == _LoadPart.games && (_partLoadedForYear(target, part) || cachedGames);
      final uri = Env.api(_partPath(target, part.name, year, fresh: fresh, haveGames: haveGames, from: from, to: to));
      final startup = fresh ? null : await takeStartupResponse(uri);
      final res = startup ?? await http.get(uri, headers: _readHeaders).timeout(const Duration(seconds: 150));
      if (res.statusCode != 200) {
        logger.w('part ${part.name} HTTP ${res.statusCode}');
        _maybeSetPartError(target, background, 'HTTPエラー: ${res.statusCode}');
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (part == _LoadPart.games && map['unchanged'] == true && (_partLoadedForYear(target, part) || (_orgCache[target]?.games.isNotEmpty ?? false))) {
        _loadedPartYears['${target.name}|${part.name}'] = year;
        _ensureCache(target).readyParts.add(part);
        _readyParts.putIfAbsent(target, () => <_LoadPart>{}).add(part);
        return;
      }
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
          _applySharedInfo(map, settles: target == OrgKind.npb);
        }
        if (target == _orgKind) {
          switch (part) {
            case _LoadPart.info:
              break;
            case _LoadPart.standings:
              predictions = List<Map<String, dynamic>>.from(bundle.predictions);
              standings = List<Map<String, dynamic>>.from(bundle.standings);
              _scheduleTeamLogoPrecache(standings);
              break;
            case _LoadPart.players:
              npbPlayerStats = List<Map<String, dynamic>>.from(bundle.playerStats);
              npbPlayerStatsActual = List<Map<String, dynamic>>.from(bundle.playerStatsActual);
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
      _persistBoardSession();
    } catch (e, st) {
      unawaited(AuthSession.instance.reportTimeout(e, st));
      logger.e('part ${part.name} 通信/解析エラー: $e\n$st');
      _maybeSetPartError(target, background, networkErrorMessage(e, fallback: '通信エラー: $e'));
    }
  }

  /// 同じイニングの再取得で打者が一瞬欠けると Now が消える。直前の打者を残す。
  void _keepLiveBatters(List<Map<String, dynamic>> previous, List<Map<String, dynamic>> incoming) {
    final prevById = <String, Map<String, dynamic>>{};
    for (final game in previous) {
      final id = '${game['id_game'] ?? game['id'] ?? ''}'.trim();
      if (id.isNotEmpty && id != '0') prevById[id] = game;
    }
    for (final game in incoming) {
      if ('${game['name_batter'] ?? ''}'.trim().isNotEmpty) continue;
      final state = '${game['state'] ?? ''}';
      if (!state.contains('回') || state.contains('試合終了') || state.contains('コールド')) {
        continue;
      }
      final id = '${game['id_game'] ?? game['id'] ?? ''}'.trim();
      final old = prevById[id];
      if (old == null || '${old['state'] ?? ''}' != state) continue;
      final oldName = '${old['name_batter'] ?? ''}'.trim();
      if (oldName.isEmpty) continue;
      game['name_batter'] = oldName;
      game['id_team_batter'] = old['id_team_batter'];
      if (old['int_batter_order'] != null) {
        game['int_batter_order'] = old['int_batter_order'];
      }
      if (game['int_outs'] == null && old['int_outs'] != null) {
        game['int_outs'] = old['int_outs'];
      }
    }
  }

  void _applyGamesPayload(
    _OrgBundle bundle,
    Map<String, dynamic> map,
    OrgConfig org,
    int year,
  ) {
    final incoming = normalizeGames(listMapFromJson(map['games'])).where(org.gameBelongs).toList();
    _keepLiveBatters(bundle.games, incoming);
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
    if (_pastDateInflight.contains(inflightKey) || !_shouldLoadGameDate(date)) {
      return;
    }
    _pastDateInflight.add(inflightKey);
    if (mounted) setState(() => _loadingGameDateByOrg[kind] = ymd);
    try {
      final org = OrgConfig.of(kind);
      final res = await http.get(Env.api(_partPath(kind, 'games', _seasonYear, date: ymd)), headers: _readHeaders).timeout(const Duration(seconds: 60));
      if (!mounted) return;
      if (res.statusCode != 200) {
        logger.w('past games $ymd HTTP ${res.statusCode}');
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (map['unchanged'] == true) return;
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
      unawaited(AuthSession.instance.reportTimeout(e, st));
      logger.w('past games $ymd 失敗: $e\n$st');
    } finally {
      _pastDateInflight.remove(inflightKey);
      if (mounted) {
        setState(() {
          if (_loadingGameDateByOrg[kind] == ymd) {
            _loadingGameDateByOrg[kind] = null;
          }
        });
      }
    }
  }

  bool get _showPostseasonNow => showPostseasonBoard || postseasonBoardVisible(serverFlag: false, today: DateTime.now());

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

  Widget _portraitTabBar({
    required List<(String label, int index)> tabs,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    Color? selectedColor,
    Color? selectedForeground,
    Map<int, String>? leadingAssets,
    double height = TAB_BAR_H,
  }) {
    final assets = leadingAssets ?? const <int, String>{};
    final Color active = selectedColor ?? ALL_COLOR_APP;
    final Color activeFg = selectedForeground ?? TAB_COLOR_FONT;
    return LayoutBuilder(builder: (context, bounds) {
      final cellWidth = (bounds.maxWidth - (tabs.length - 1) * ALL_SPACE_BLOCK) / tabs.length;
      final fits = tabs.every((tab) {
        final painter = TextPainter(text: TextSpan(text: tab.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context), maxLines: 1)..layout();
        final needed = painter.width + 4 + (assets.containsKey(tab.$2) ? height * .72 + 6 : 0);
        painter.dispose();
        return needed <= cellWidth;
      });
      if (!fits) { return Container(height: height,
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(color: active, borderRadius: BorderRadius.circular(height / 2)),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: DropdownButtonHideUnderline(child: DropdownButton<int>(value: selectedIndex, isExpanded: true, isDense: true,
          dropdownColor: active, iconEnabledColor: activeFg,
          style: TextStyle(color: activeFg, fontSize: 12, fontWeight: FontWeight.bold),
          selectedItemBuilder: (_) => [for (final tab in tabs) Center(child: Text(tab.$1))],
          items: [for (final tab in tabs) DropdownMenuItem(value: tab.$2, child: Text(tab.$1))],
          onChanged: (i) { if (i != null) onSelected(i); }))); }
      return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
      height: height,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (assets[tabs[i].$2] case final asset?) ...[
                              LeagueLogo(asset: asset, height: height * 0.72),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              tabs[i].$1,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
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
              ),
            ),
          ],
        ],
      ),
    ));
    });
  }

  String _gamesInitialDate() {
    final now = DateTime.now();
    if (_seasonYear == now.year) return DateFormatUtil.ymdWithOffset(0);
    final latest = latestOrgGameDate(
      year: _seasonYear,
      mlb: _orgKind == OrgKind.mlb,
      games: games,
      postseasonGames: postseasonGames,
    );
    return DateFormatUtil.ymd(latest ?? DateTime(_seasonYear, 10, 15));
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
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$selected',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.white, size: 15),
            ],
          ),
        ),
      ),
    );
  }

  /// Info と項目タブのあいだ。選択時は団体色＋ロゴ、非選択は薄いグレー。
  Widget _orgTabBar() => SizedBox(
    height: TAB_BAR_H + 4,
    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final entry in [('predict', '予想対決'), ('npb', 'NPB'), ('mlb', 'MLB'), ('other', 'その他')])
        Expanded(child: Padding(padding: const EdgeInsets.all(2), child: Builder(builder: (context) {
          final selected = entry.$1 == 'other' ? _otherOpen : !_otherOpen &&
            (entry.$1 == 'predict' ? _predictGroupsOpen : !_predictGroupsOpen && entry.$1 == _orgKind.name);
          final org = entry.$1 == 'npb' ? OrgConfig.npb : entry.$1 == 'mlb' ? OrgConfig.mlb : null;
          return Material(color: selected ? org?.tabColor ?? Colors.black : OrgConfig.tabIdleColor,
            borderRadius: BorderRadius.circular(TAB_RADIUS),
            child: InkWell(key: ValueKey('org-tab-${entry.$1}'),
              onTap: () {
                if (entry.$1 == 'other') {
                  writeBrowserCookie(_orgCookie, 'other');
                  setState(() { _otherOpen = true; _predictGroupsOpen = false; });
                } else if (entry.$1 == 'predict') {
                  unawaited(_openPredictGroups());
                } else { _changeOrg(org!.kind); }
              },
              child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (org != null) ...[
                  Image.asset(org.logoAsset, width: 18, height: 18, errorBuilder: (_, __, ___) => const SizedBox(width: 18)),
                  const SizedBox(width: 4),
                ],
                Text(entry.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: selected ? org?.tabForeground ?? Colors.white : Colors.black54)),
                if (entry.$1 == 'predict' && _predictInvites.isNotEmpty)
                  const Icon(Icons.circle, size: 6, color: Colors.red),
              ]))),
            ));
        }))),
    ]),
  );

  Widget _boardTabBar() {
    return Row(
      children: [
        Expanded(
          child: _portraitTabBar(
            tabs: [
              ('日程', 5),
              if (_orgKind == OrgKind.mlb) ('日本人', 7),
              ('試合情報', 0),
              ('チーム順位', 1),
              ('個人成績', 2),
              ('タイトル', 8),
              ('戦力', 3),
              ('記録', 4),
              ('動画', 6),
            ],
            selectedIndex: _itemTab,
            onSelected: (i) {
              if (i == _itemTab) return;
              const actions = ['試合情報タブを開いた', 'チーム順位タブを開いた', '個人成績タブを開いた', '戦力タブを開いた', '記録タブを開いた', '日程タブを開いた', '動画タブを開いた', '日本人タブを開いた', 'タイトルタブを開いた'];
              if (i >= 0 && i < actions.length) {
                unawaited(AuthSession.instance.reportAction(actions[i]));
              }
              saveTab('main_${_orgKind.name}', i);
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
    List<Map<String, dynamic>> scheduleGames = const [],
  }) {
    final gamesForLeague = games.where((game) => gameVisibleInLeague(game, leagueId)).toList();
    return SeasonTableBlock(
      standings: standings,
      scheduleGames: scheduleGames,
      showScheduleColumns: pane == SeasonPane.standings,
      stats: npbPlayerStatsActual,
      games: gamesForLeague,
      seriesGames: postseasonGames,
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
    if (_itemTab == 8) return SeasonTitlesBoard(key: ValueKey("titles-${_orgKind.name}-$_seasonYear"), org: _org, year: _seasonYear);
    if (_itemTab == 7 && _orgKind == OrgKind.mlb) return JapaneseMlbBoard(key: ValueKey('japanese-$_seasonYear'), year: _seasonYear);
    if (_itemTab == 6) return VideosBoard(key: ValueKey(_orgKind), org: _orgKind, color: _org.tabColor);
    if (_itemTab == 5) {
      return SeasonCalendarBoard(org: _org, year: _seasonYear, events: events);
    }
    if (_itemTab == 4) {
      return RecordsBoard(org: _org, year: _seasonYear);
    }
    if (_itemTab == 3) {
      return TeamStrengthBoard(
        key: ValueKey('strength-${_orgKind.name}-$_seasonYear'),
        org: _org,
        year: _seasonYear,
        favoriteTeamId: AuthSession.instance.user?.idTeamFav,
      );
    }
    if (_itemTab == 2) {
      if (!_partReady(_LoadPart.players)) {
        return const Center(child: BaseballLoading());
      }
      // 横長は打者・投手のタブ切り替え。
      if (wideLayout) {
        return DualBandBothLeaguePersonalStats(
          stats: npbPlayerStatsActual,
          org: _org,
        );
      }
      return BothLeaguePersonalStats(
        segmentOnly: true,
        stats: npbPlayerStatsActual,
        org: _org,
        layout: _personalStatsLayout,
        onLayoutChanged: _setPersonalStatsLayout,
      );
    }
    if (_itemTab == 0) {
      final showBracket = _showPostseasonNow;
      if (!_partReady(_LoadPart.games) && !showBracket) {
        return const Center(child: BaseballLoading());
      }
      return BothLeagueGameDay(
        key: ValueKey('both-${_orgKind.name}-$_seasonYear-${_gamesInitialDate()}'),
        games: games,
        seriesGames: postseasonGames,
        playerStats: npbPlayerStatsActual,
        standings: standings,
        initialDate: _gamesInitialDate(),
        trailing: showBracket ? [const SizedBox(height: 12), _postseasonBracket()] : const [],
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
      return const Center(child: BaseballLoading());
    }
    return SeasonScheduleLoader(
        org: _org,
        year: _seasonYear,
        builder: (scheduleGames) => ListView(
              children: [
                for (var i = 0; i < _org.leagues.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _leaguePane(leagueId: _org.leagues[i].id, pane: SeasonPane.standings, scheduleGames: scheduleGames, portraitLayout: true),
                ],
                if (_org.kind == OrgKind.npb) InterleagueStandings(teams: standings, games: scheduleGames),
              ],
            ));
  }

  static const _mlbPostseasonCodes = {
    'WC',
    'DS',
    'LCS',
    'WS',
    'ALWC',
    'NLWC',
    'ALWC36',
    'ALWC45',
    'NLWC36',
    'NLWC45',
    'ALDS',
    'NLDS',
    'ALDS1',
    'ALDS2',
    'NLDS1',
    'NLDS2',
    'ALCS',
    'NLCS',
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.black,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                onTap: () {
                  setState(() => _bracketOpen = !_bracketOpen);
                  writeBrowserCookie(_bracketCookie, _bracketOpen ? '1' : '0');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(_bracketOpen ? Icons.expand_less : Icons.expand_more, color: Colors.white, size: 18),
                      const SizedBox(width: 4),
                      const Text('トーナメント', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            if (_bracketOpen)
              SizedBox(
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
              ),
          ],
        );
      },
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

  // 上部: News + イベント日程（NPB/MLB 共通。団体タブでは内容を切り替えない）
  Widget _newsEventsRow({required bool portrait, bool popup = false}) {
    final infoLoading = !_sharedInfoReady;

    Widget miniSpinner({double size = 18}) => SizedBox(
          width: size,
          height: size,
          child: const BaseballLoading(),
        );

    Widget newsBox({bool hideHeader = false, double? boxHeight, bool fill = false}) {
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

      Widget newsTag(String title, Color back, Color font, {double? width}) {
        return Container(
          width: width,
          height: tagH,
          constraints: BoxConstraints(minWidth: width ?? tagW, maxHeight: tagH),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(vertical: 2, horizontal: width == null ? 6 : 3),
          decoration: BoxDecoration(
            color: back,
            borderRadius: BorderRadius.circular(3),
          ),
          child: width == null
              ? Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 12, color: font, height: 1.1),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(fontSize: 12, color: font, height: 1.1),
                  ),
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
                color: Colors.black,
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
                          ? Center(child: miniSpinner(size: 22))
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  primary: false,
                                  child: SizedBox(
                                    height: constraints.maxHeight,
                                    child: SingleChildScrollView(
                                      primary: false,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          for (final n in notifications)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 2),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  newsTag(
                                                    (n['tag_main_title'] ?? '').toString(),
                                                    parse(n['tag_main_color_back'], Colors.grey.shade300),
                                                    parse(n['tag_main_color_font'], Colors.white),
                                                    width: tagW * 2 / 3,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  newsTag(
                                                    (n['tag_sub_title'] ?? '').toString(),
                                                    parse(n['tag_sub_color_back'], Colors.grey.shade300),
                                                    parse(n['tag_sub_color_font'], Colors.white),
                                                    width: tagW * 2 / 3,
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
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
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

    Widget eventsBox({bool hideHeader = false, double? boxHeight, bool fill = false}) {
      final evs = [...events];
      evs.sort((a, b) => (a['date_from_temp'] ?? '').toString().compareTo((b['date_from_temp'] ?? '').toString()));

      final h = boxHeight ?? 120.0;
      final content = Container(
        height: fill ? null : h,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black45),
          borderRadius: popup
              ? const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                )
              : BorderRadius.circular(4),
        ),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hideHeader)
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: Colors.black,
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
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: infoLoading ? Center(child: miniSpinner(size: 22)) : EventCalendar(events: evs),
              ),
            ),
          ],
        ),
      );

      return content;
    }

    if (popup) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: newsBox(fill: true),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                saveTab('main_${_orgKind.name}', 5);
                setState(() => _itemTab = 5);
              },
              child: const Text("イベント・試合日程を開く")),
        ],
      );
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
            child: newsBox(hideHeader: true, boxHeight: panelH),
          ),
          _portraitCollapsibleSection(
            title: 'イベント日程',
            expanded: _eventsExpanded,
            onToggle: _toggleEventsSection,
            showNew: AuthSession.instance.showEventNew,
            child: eventsBox(hideHeader: true, boxHeight: panelH),
          ),
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
            SizedBox(width: standingsW, height: 198, child: newsBox(fill: true)),
            const SizedBox(width: seasonGap),
            SizedBox(
              width: personalW,
              height: 198,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: eventsBox(fill: true)),
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
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Headers.globalHeader(context, HEADER_GLOBAL_H, ALL_COLOR_APP, HEADER_TITLE,
          HEADER_PAD_VERTICAL, ALL_MARGIN_LEFT, showRightActions: false),
        Padding(padding: const EdgeInsets.symmetric(horizontal: ALL_MARGIN_LEFT),
          child: Column(children: [
            const SizedBox(height: ALL_SPACE_BLOCK),
            _orgTabBar(),
            if (!_predictGroupsOpen && !_otherOpen) ...[
              _boardTabBar(),
            ],
          ])),
        Expanded(child: _otherOpen ? OtherBaseballBoard(year: _seasonYear) : const Center(child: BaseballLoading())),
      ]);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // フル幅表示（スケーリングなし）
        final designWidth = constraints.maxWidth;
        const double scale = 1.0;
        // 1セクションも来ていなければタブ下にグルグル。来たものから描画する。
        final orgContentLoading = !_boardContentReady && error == null;

        final shortestSide = constraints.maxWidth < constraints.maxHeight ? constraints.maxWidth : constraints.maxHeight;
        final isPortrait = constraints.maxHeight / constraints.maxWidth >= PORTRAIT_ASPECT_RATIO || shortestSide < COMPACT_LAYOUT_PX;

        final Widget chrome = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: ALL_SPACE_BLOCK),
            _orgTabBar(),
          ],
        );

        // 取れたデータがあるときはエラー表示で消さない
        final Widget orgBody = _otherOpen ? OtherBaseballBoard(year: _seasonYear) : _predictGroupsOpen
            ? (!AuthSession.instance.isLoggedIn
                ? const Center(child: Text('ログインすると予想を見られます'))
                : PredictGroupBoard(
                    loading: _predictGroupsLoading,
                    error: _predictGroupsError,
                    selectedYear: _seasonYear,
                    groups: _predictGroups,
                    titleCatalog: _predictTitleCatalog,
                    viewerId: AuthSession.instance.user?.id,
                    onSaveSetting: _savePredictSetting,
                    onApproveRule: _votePredictRule,
                    onRenameGroup: _savePredictGroupName,
                    invites: _predictInvites,
                    onSearchNames: _searchPredictNames,
                    onSearchUsers: _searchPredictUsers,
                    onCreateGroup: _createPredictGroup,
                    onAnswerInvite: _answerPredictInvite,
                    onDeleteGroup: _deletePredictGroup,
                    onCreateYear: _createPredictYear,
                  ))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _boardTabBar(),
                  const SizedBox(height: ALL_SPACE_BLOCK),
                  Expanded(
                    flex: isPortrait ? 1 : ALL_RATIO_BLOCK_H[1] * 2,
                    child: RetainedTabBody(
                      key: ValueKey('tabs-$_seasonYear'),
                      selected: '${_orgKind.name}-$_itemTab',
                      builder: (_) => _itemTab >= 3
                        ? _itemBoard(wideLayout: !isPortrait)
                        : orgContentLoading
                            ? const Center(child: BaseballLoading())
                            : error != null && !_boardContentReady
                                ? Center(child: Text(error!))
                                : _itemBoard(wideLayout: !isPortrait),
                    ),
                  ),
                  if (isPortrait) const SizedBox(height: ALL_SPACE_BLOCK),
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
                        showRightActions: _authEntryReady,
                        actions: [
                          const SizedBox(width: 4),
                          _yearPicker(),
                          const SizedBox(width: 4),
                          _infoButton(),
                          const SizedBox(width: 4),
                        ],
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: ALL_SPACE_BLOCK, left: ALL_MARGIN_LEFT, right: ALL_MARGIN_LEFT),
                          child: PlayerDetailScope(org: _org.kind.name, year: _seasonYear, child: bodyContent),
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

/// ページの setState に合わせて News・イベントを描き直す。
class _LiveInfoDialog extends StatefulWidget {
  const _LiveInfoDialog({required this.host});

  final _PredictionPageState host;

  @override
  State<_LiveInfoDialog> createState() => _LiveInfoDialogState();
}

class _LiveInfoDialogState extends State<_LiveInfoDialog> {
  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.host.addInfoDialogListener(_refresh);
  }

  @override
  void dispose() {
    widget.host.removeInfoDialogListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: size.width * 0.025, vertical: size.height * 0.025),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width * 0.95,
        height: size.height * 0.95,
        child: widget.host._infoPopup(context),
      ),
    );
  }
}
