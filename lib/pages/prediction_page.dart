import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../tools/Env.dart';
import '../tools/app_logger.dart';
import '../tools/browser_cookie.dart';
import '../tools/color_parse.dart';
import '../config/app_design.dart';
import '../tools/json_utils.dart';
import '../tools/date_format.dart';
import '../logic/atari_counts.dart';
import '../View/Headers.dart';
import '../View/Text.dart';
import '../View/LeagueBoardRow.dart';
import '../View/GamesBoard.dart';
import '../View/SeasonTable.dart';
import '../View/PostseasonBracket.dart';
import '../logic/postseason_bracket.dart';

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
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

  bool isLoading = true;
  String? error;

  bool _newsExpanded = false;
  bool _eventsExpanded = false;
  bool _infoExpanded = true;
  static const _infoCookie = 'koko_info_open';
  static const _viewCookie = 'koko_view_by_item';
  // 縦型: 0=セ・リーグ, 1=パ・リーグ
  int _portraitLeagueTab = 0;
  bool _viewByItem = false;
  int _itemTab = 0;
  int _batterPitcherTab = 0;
  Timer? _gamesRefreshTimer;
  bool _gamesRefreshRunning = false;
  bool _seasonStatsRefreshStarted = false;

  // 個人成績の id_user → 表示名
  String _usernameForId(String idUser) => lookupField(npbPlayerStats, 'id_user', idUser, 'username');

  String _userNameFromPredictions(String idUserStr) => lookupField(predictions, 'id_user', idUserStr, 'name_user_last');

  Color _userBackColorForId(String idUser, {required Color fallback}) {
    final teamColor = lookupField(predictions, 'id_user', idUser, 'code_color', fallback: '');
    final playerColor = lookupField(npbPlayerStats, 'id_user', idUser, 'code_color', fallback: '');
    return parseColorNameOrNull(teamColor) ?? parseColorNameOrNull(playerColor) ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    final saved = readBrowserCookie(_infoCookie);
    if (saved == '0') _infoExpanded = false;
    if (saved == '1') _infoExpanded = true;
    if (readBrowserCookie(_viewCookie) == '1') _viewByItem = true;
    _loadThenWatchGames();
  }

  void _toggleInfo() {
    setState(() => _infoExpanded = !_infoExpanded);
    writeBrowserCookie(_infoCookie, _infoExpanded ? '1' : '0');
  }

  Widget _infoShell({required Widget child, required bool expand}) {
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
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                        child: child,
                      ),
                    ),
                  )
                : ColoredBox(
                    color: Colors.white,
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
    _gamesRefreshTimer?.cancel();
    super.dispose();
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  Future<void> _loadThenWatchGames() async {
    await fetchData();
    if (!mounted || error != null) return;
    if (centralPacificGamesAllFinished(games, _todayKey())) {
      _refreshSeasonStatsOnce();
    }
    _gamesRefreshTimer?.cancel();
    _refreshGames();
    _gamesRefreshTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _refreshGames();
    });
  }

  Future<void> _refreshGames() async {
    if (!mounted || _gamesRefreshRunning || isLoading) return;
    final today = _todayKey();
    if (centralPacificGamesAreSettled(games, today)) {
      if (centralPacificGamesAllFinished(games, today)) {
        await _refreshSeasonStatsOnce();
      }
      return;
    }
    _gamesRefreshRunning = true;
    var refreshStats = false;
    try {
      // 11日分の取得は3分を超える。途中で切るとDBだけ更新されて画面が古いままになる。
      final scrape = await http.get(Env.api('/fetchGamesNPB')).timeout(const Duration(minutes: 10));
      if (!mounted || scrape.statusCode != 200) {
        logger.w('試合スクレイピング失敗: ${scrape.statusCode}');
        return;
      }
      if (scrape.body.contains('offseason')) {
        _gamesRefreshTimer?.cancel();
        return;
      }
      final res = await http.get(Env.api('/predictions')).timeout(const Duration(seconds: 30));
      if (!mounted || res.statusCode != 200) return;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final nextGames = normalizeGames(listMapFromJson(map['games']));
      setState(() {
        predictions = listMapFromJson(map['predict_team']);
        standings = listMapFromJson(map['stats_team']);
        npbPlayerStats = listMapFromJson(map['predict_player']);
        npbPlayerStatsActual = listMapFromJson(map['stats_player']);
        games = nextGames;
        postseasonGames = listMapFromJson(map['postseason_games']);
        showPostseasonBoard = postseasonBoardVisible(serverFlag: map['show_postseason_board'] == true, today: DateTime.now());
        events = listMapFromJson(map['events']);
        notifications = listMapFromJson(map['notification']);
      });
      refreshStats = centralPacificGamesAllFinished(nextGames, today);
    } catch (e, st) {
      logger.w('試合情報の定期更新に失敗: $e\n$st');
    } finally {
      _gamesRefreshRunning = false;
    }
    if (refreshStats) await _refreshSeasonStatsOnce();
  }

  Future<void> _refreshSeasonStatsOnce() async {
    if (!mounted || _seasonStatsRefreshStarted) return;
    if (!centralPacificGamesAllFinished(games, _todayKey())) return;
    _seasonStatsRefreshStarted = true;
    try {
      final team = await http.get(Env.api('/fetchStatsTeamNPB')).timeout(const Duration(minutes: 5));
      if (!mounted || team.statusCode != 200) {
        logger.w('チーム成績スクレイピング失敗: ${team.statusCode}');
        _seasonStatsRefreshStarted = false;
        return;
      }
      if (team.body.contains('offseason')) {
        _gamesRefreshTimer?.cancel();
        return;
      }
      final player = await http.get(Env.api('/fetchStatsPlayerNPB')).timeout(const Duration(minutes: 20));
      if (!mounted || player.statusCode != 200) {
        logger.w('個人成績スクレイピング失敗: ${player.statusCode}');
        _seasonStatsRefreshStarted = false;
        return;
      }
      final res = await http.get(Env.api('/predictions')).timeout(const Duration(seconds: 30));
      if (!mounted || res.statusCode != 200) {
        _seasonStatsRefreshStarted = false;
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        standings = listMapFromJson(map['stats_team']);
        npbPlayerStatsActual = listMapFromJson(map['stats_player']);
      });
    } catch (e, st) {
      _seasonStatsRefreshStarted = false;
      logger.w('チーム・個人成績の更新に失敗: $e\n$st');
    }
  }

  Future<void> fetchData() async {
    try {
      final uri = Uri.parse('${Env.baseUrl()}/predictions');
      final res = await http.get(uri);

      if (res.statusCode != 200) {
        setState(() {
          error = 'HTTPエラー: ${res.statusCode}';
          isLoading = false;
        });
        logger.w('HTTP ${res.statusCode} body: ${res.body.substring(0, res.body.length.clamp(0, 400))}');
        return;
      }

      final map = jsonDecode(res.body) as Map<String, dynamic>;

      final users = listMapFromJson(map['predict_team']);
      final npb = listMapFromJson(map['stats_team']);
      final statsPredict = listMapFromJson(map['predict_player']);
      final statsActual = listMapFromJson(map['stats_player']);
      final gms = listMapFromJson(map['games']);
      final evts = listMapFromJson(map['events']);
      final notifs = listMapFromJson(map['notification']);

      setState(() {
        predictions = users;
        standings = npb;
        npbPlayerStats = statsPredict; // 左
        npbPlayerStatsActual = statsActual; // 中央
        games = normalizeGames(gms);
        postseasonGames = listMapFromJson(map['postseason_games']);
        showPostseasonBoard = postseasonBoardVisible(serverFlag: map['show_postseason_board'] == true, today: DateTime.now());
        events = evts;
        notifications = notifs;
        isLoading = false;
      });
    } catch (e, st) {
      logger.e('通信/解析エラー: $e\n$st');
      setState(() {
        error = '通信エラー: $e';
        isLoading = false;
      });
    }
  }

  // flg_atari の合計（予想者のみ: id_user 1/2、セ+パ合算）

  Widget _portraitTabBar({
    required List<(String label, int index)> tabs,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    Color? selectedColor,
    Map<int, String> leadingAssets = const {},
  }) {
    final Color active = selectedColor ?? ALL_COLOR_APP;
    return SizedBox(
      height: TAB_BAR_H,
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: ALL_SPACE_BLOCK),
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(tabs[i].$2),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: TAB_PAD_VERTICAL, horizontal: TAB_PAD_HORIZONTAL),
                  decoration: BoxDecoration(
                    color: selectedIndex == tabs[i].$2 ? active : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(TAB_RADIUS),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (leadingAssets[tabs[i].$2] case final asset?) ...[
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
                        style: TextStyle(
                          fontSize: TAB_BAR_H / 2,
                          fontWeight: selectedIndex == tabs[i].$2 ? FontWeight.bold : FontWeight.normal,
                          color: selectedIndex == tabs[i].$2 ? TAB_COLOR_FONT : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _boardTabBar() {
    final byLeague = !_viewByItem;
    return Row(
      children: [
        SizedBox(
          width: 64,
          height: TAB_BAR_H,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black87),
              borderRadius: BorderRadius.circular(TAB_RADIUS),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<bool>(
                value: _viewByItem,
                isDense: true,
                isExpanded: true,
                padding: const EdgeInsets.only(left: 6, right: 2),
                style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: false, child: Text('リーグ', style: TextStyle(fontSize: 11, color: Colors.black87))),
                  DropdownMenuItem(value: true, child: Text('項目', style: TextStyle(fontSize: 11, color: Colors.black87))),
                ],
                onChanged: (value) {
                  if (value == null || value == _viewByItem) return;
                  setState(() => _viewByItem = value);
                  writeBrowserCookie(_viewCookie, value ? '1' : '0');
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: ALL_SPACE_BLOCK),
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
                  },
                  selectedColor: const Color(0xFF37474F),
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
      gamesDateFilter: DateFormatUtil.ymdWithOffset(0),
      portraitLayout: portraitLayout,
      pane: pane,
    );
  }

  Widget _itemBoard() {
    if (_itemTab == 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _portraitTabBar(
            tabs: const [
              ('打者', 0),
              ('投手', 1),
            ],
            selectedIndex: _batterPitcherTab,
            onSelected: (i) {
              if (i == _batterPitcherTab) return;
              setState(() => _batterPitcherTab = i);
            },
            selectedColor: _batterPitcherTab == 0 ? const Color(0xFFDC143C) : const Color(0xFF1E88E5),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: BothLeaguePersonalStats(
              stats: npbPlayerStatsActual,
              pitcher: _batterPitcherTab == 1,
            ),
          ),
        ],
      );
    }
    if (_itemTab == 0) {
      return BothLeagueGameDay(
        games: games,
        initialDate: DateFormatUtil.ymdWithOffset(0),
        leading: showPostseasonBoard ? [_postseasonBracket(), const SizedBox(height: 6)] : const [],
      );
    }
    return ListView(
      children: [
        _leaguePane(leagueId: 1, pane: SeasonPane.standings, portraitLayout: true),
        const SizedBox(height: 8),
        _leaguePane(leagueId: 2, pane: SeasonPane.standings, portraitLayout: true),
      ],
    );
  }

  Widget _postseasonBracket() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : BracketGeom.w;
        return SizedBox(
          width: width,
          height: width * BracketGeom.h / BracketGeom.w,
          child: PostseasonBracket(standings: standings, games: postseasonGames),
        );
      },
    );
  }

  Widget _portraitLeagueTabBar() {
    return _portraitTabBar(
      tabs: const [
        ('セ・リーグ', 0),
        ('パ・リーグ', 1),
      ],
      selectedIndex: _portraitLeagueTab,
      onSelected: (i) {
        if (i == _portraitLeagueTab) return;
        setState(() => _portraitLeagueTab = i);
      },
      selectedColor: _portraitLeagueTab == 0 ? const Color(0xFF0E8E2D) : const Color(0xFF01B1EA),
      leadingAssets: const {
        0: 'backend/assets/images/k-central.webp',
        1: 'backend/assets/images/k-pacific.webp',
      },
    );
  }

  Widget _portraitCollapsibleSection({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
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

  // 上部: Score + News + イベント日程
  Widget _scoreNewsEventsRow({required bool portrait}) {
    final counts = computeAtariCounts(
      npbPlayerStats: npbPlayerStats,
      npbPlayerStatsActual: npbPlayerStatsActual,
      predictions: predictions,
      standings: standings,
    );
    Widget _scoreBox({bool hideHeader = false, bool portraitCompact = false}) {
      final name1 = _userNameFromPredictions('1');
      final name2 = _userNameFromPredictions('2');
      final score1 = '${counts['1'] ?? 0}';
      final score2 = '${counts['2'] ?? 0}';
      final color1 = _userBackColorForId('1', fallback: Colors.blue);
      final color2 = _userBackColorForId('2', fallback: Colors.red);
      const double vBorder = 1.0;
      const double cellPad = 6.0;

      Widget _nameCell(String name, Color background, {bool leftBorder = false}) {
        return Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: background,
              border: leftBorder ? const Border(left: BorderSide(color: Colors.black45, width: vBorder)) : null,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: cellPad, vertical: 4),
            child: OneLineShrinkText(
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
                        child: FittedBox(
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
                        child: FittedBox(
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
                        child: Text(
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  children: [
                    const Text('News', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 4),
                    Expanded(
                      child: ListView(
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

      const catW = 64.0; // 主・サブの列幅（同一）

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
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('イベント日程', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                child: LayoutBuilder(
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

                    // 固定列幅計算
                    const double spacing = 6 + 6 + 4; // cat間+title-date間
                    const double minDate = 48;
                    final double fixedCats = catW * 2;
                    double titleColW = rawMaxTitleW;
                    final maxAllowed = constraints.maxWidth - fixedCats - spacing - minDate;
                    if (titleColW > maxAllowed) titleColW = maxAllowed;
                    if (titleColW < 60) titleColW = 60;

                    double dateMaxW = constraints.maxWidth - fixedCats - spacing - titleColW;
                    if (dateMaxW < minDate) dateMaxW = minDate;

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
                                Expanded(
                                  // constraints: BoxConstraints(minWidth: minDate, maxWidth: dateMaxW),
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
            onToggle: () => setState(() => _newsExpanded = !_newsExpanded),
            child: _newsBox(hideHeader: true, boxHeight: panelH),
          ),
          _portraitCollapsibleSection(
            title: 'イベント日程',
            expanded: _eventsExpanded,
            onToggle: () => setState(() => _eventsExpanded = !_eventsExpanded),
            child: _eventsBox(hideHeader: true, boxHeight: panelH),
          ),
          _scoreBox(hideHeader: true, portraitCompact: true),
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
                  const SizedBox(height: 6),
                  _scoreBox(hideHeader: true, portraitCompact: true),
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
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text(error!));

    return LayoutBuilder(
      builder: (context, constraints) {
        // フル幅表示（スケーリングなし）
        final designWidth = constraints.maxWidth;
        const double scale = 1.0;
        final compact = false;

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
          );
        }

        final Widget portraitTop = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: ALL_SPACE_BLOCK),
            _infoShell(
              expand: false,
              child: _scoreNewsEventsRow(portrait: true),
            ),
            const SizedBox(height: 8),
            _boardTabBar(),
            SizedBox(height: ALL_SPACE_BLOCK),
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

        final Widget bodyContent = isPortrait
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  portraitTop,
                  Expanded(
                    child: _viewByItem
                        ? _itemBoard()
                        : IndexedStack(
                            index: _portraitLeagueTab,
                            children: [
                              portraitLeaguePage(
                                leagueId: 1,
                                leagueColor: const Color(0xFF0E8E2D),
                                logoAsset: 'assets/images/logo_league_central.webp',
                                leagueLabelPrefix: 'セ',
                              ),
                              portraitLeaguePage(
                                leagueId: 2,
                                leagueColor: const Color(0xFF01B1EA),
                                logoAsset: 'assets/images/logo_league_pacific.png',
                                leagueLabelPrefix: 'パ',
                              ),
                            ],
                          ),
                  ),
                  SizedBox(height: ALL_SPACE_BLOCK),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: ALL_SPACE_BLOCK),
                  _infoShell(
                    expand: false,
                    child: _infoExpanded ? _scoreNewsEventsRow(portrait: false) : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 8),
                  _boardTabBar(),
                  SizedBox(height: ALL_SPACE_BLOCK),
                  Expanded(
                    flex: ALL_RATIO_BLOCK_H[1] * 2,
                    child: _viewByItem
                        ? _itemBoard()
                        : (_portraitLeagueTab == 0
                            ? centralLeagueBoard(
                                leagueId: 1,
                                leagueColor: const Color(0xFF0E8E2D),
                                logoAsset: 'assets/images/logo_league_central.webp',
                                leagueLabelPrefix: 'セ',
                              )
                            : centralLeagueBoard(
                                leagueId: 2,
                                leagueColor: const Color(0xFF01B1EA),
                                logoAsset: 'assets/images/logo_league_pacific.png',
                                leagueLabelPrefix: 'パ',
                              )),
                  ),
                ],
              );

        // レイアウトを「リーグ×2行、各行に 予想・成績・試合情報」を配置
        return Container(
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
                    Headers.globalHeader(HEADER_GLOBAL_H, ALL_COLOR_APP, HEADER_TITLE, HEADER_PAD_VERTICAL, ALL_MARGIN_LEFT),
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
        );
      },
    );
  }
}
