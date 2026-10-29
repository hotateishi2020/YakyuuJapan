import 'videos_board.dart';
import 'today_event_map.dart';
import '../logic/game_visibility.dart';
import '../logic/auth_session.dart';
import '../config/org_config.dart';
import 'season_titles_board.dart';
import 'home_games_behind_board.dart';
import 'season_schedule_board.dart';
import 'dart:convert';
import '../tools/home_data_cache.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import 'player_detail_dialog.dart';

class HomeBoard extends StatefulWidget {
  const HomeBoard({super.key, this.year, this.news, this.predictionScores, this.gameInformation, this.onNewsViewed});
  final int? year;
  final Widget? news;
  final Widget? predictionScores;
  final Widget? gameInformation;
  final void Function(int userId, DateTime? previousRead)? onNewsViewed;
  @override
  State<HomeBoard> createState() => _HomeBoardState();
}

class _HomeBoardState extends State<HomeBoard> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  int _request = 0;
  late String _scope;
  String get _sessionScope => '${AuthSession.instance.token}:${AuthSession.instance.showDetailedGames}:${AuthSession.instance.showSpecialMedia}';
  String get _cacheKey {
    final day = DateTime.now().toUtc().add(const Duration(hours: 9)).toIso8601String().substring(0,10);
    return 'dashboard:$day:$_scope';
  }
  @override
  void initState() {
    super.initState();
    _scope = _sessionScope;
    _data = HomeDataCache.peek(_cacheKey, maxAge: const Duration(seconds:45));
    AuthSession.instance.addListener(_sessionChanged);
    _scheduleNewsRead();
    _load();
  }
  int? _newsReadUser;
  void _sessionChanged() {
    _scheduleNewsRead();
    if (_scope != _sessionScope) {
      _scope = _sessionScope;
      _data = HomeDataCache.peek(_cacheKey, maxAge: const Duration(seconds:45));
      _load();
    }
  }
  bool _newsReadScheduled = false;
  void _scheduleNewsRead() {
    if (_newsReadScheduled) return;
    _newsReadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _newsReadScheduled = false;
      if (!mounted) return;
      final session = AuthSession.instance;
      if (!session.isLoggedIn) { _newsReadUser = null; return; }
      final id = session.user!.id;
      if (_newsReadUser == id) return;
      _newsReadUser = id;
      widget.onNewsViewed?.call(id, session.user!.dateReadNews);
      final error = await session.markRead('news');
      if (error != null && mounted) _newsReadUser = null;
    });
  }
  @override
  void dispose() {
    AuthSession.instance.removeListener(_sessionChanged);
    super.dispose();
  }
  Future<void> _load({bool refresh = false}) async {
    final request = ++_request;
    final token = AuthSession.instance.token;
    final key = _cacheKey;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await HomeDataCache.read(key, () async {
      final response = await http.get(Env.api(refresh ? '/home?fresh=1' : '/home'), headers: {if (token != null) 'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw const FormatException();
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map);
      }, refresh: refresh, maxAge: const Duration(seconds:45));
      if (mounted && request == _request) {
        setState(() => _data = data);
        if (AuthSession.instance.showSpecialMedia && listMapFromJson(data['heroes']).any((h) => h['character_image'] == null)) {
          _loadImages(key, token, request, refresh: refresh);
        }
      }
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = 'HOMEを取得できませんでした。再読み込みしてください。');
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }
  Future<void> _loadImages(String key, String? token, int request, {required bool refresh}) async {
    try {
      final ids = listMapFromJson(_data?['heroes']).map((h) => '${h['id_player']}').toSet().toList()..sort();
      final result = await HomeDataCache.read('$key:images:${ids.join(',')}', () async {
        final response = await http.get(Env.api('/home?section=images'), headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        }).timeout(const Duration(seconds:20));
        if (response.statusCode != 200) throw const FormatException();
        return Map<String,dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map);
      }, refresh: refresh, maxAge: const Duration(minutes:5));
      if (mounted && request == _request && result['images'] is Map) {
        final images = result['images'] as Map;
        setState(() => _data = {..._data!, 'heroes': [for (final hero in listMapFromJson(_data!['heroes'])) {
          ...hero, if (images['${hero['id_player']}'] != null) 'character_image': images['${hero['id_player']}'],
        }]});
      }
    } catch (_) { /* Optional images never block HOME content. */ }
  }
  void _openCalendar(int year) {
    showDialog<void>(context: context, builder: (context) {
      final size = MediaQuery.sizeOf(context);
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(width: size.width * .94, height: size.height * .88,
          child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            Row(children: [
              const Expanded(child: Text('1ヶ月分の日程', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(tooltip: '閉じる', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ]),
            Expanded(child: HomeSeasonCalendar(year: year)),
          ])),
        ),
      );
    });
  }
  Widget _section(String title, List<Widget> children) => Card(
    key: ValueKey('home-section-$title'),
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10), ...children,
    ])),
  );
  String _match(Map<String, dynamic> game) {
    final state = '${game['state'] ?? ''}';
    final score = game['score_home'] != null && game['score_away'] != null && '${game['score_home']}' != '-1' && !state.contains('試合前')
        ? '${game['score_home']}–${game['score_away']}' : 'vs';
    return "${game['org']}  ${game['name_team_home']} $score ${game['name_team_away']}  $state";
  }
  Widget _heroContent(Map<String, dynamic> hero) {
    final art = hero['character_image'];
    final url = art is Map ? art['url'] : null;
    final showImage = AuthSession.instance.showSpecialMedia && url is String && url.isNotEmpty;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showImage) ...[
        Image.network(Env.api(url).toString(), width: 88, height: 104,
          fit: BoxFit.contain, semanticLabel: '${hero['name_player']}の生成画像',
          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        const SizedBox(width: 10),
      ],
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${hero['org']}  ${hero['name_team']}  ${hero['name_player']}',
          style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final stats in (hero['appearance_stats'] as List? ?? const []))
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('$stats')),
        if ((hero['highlights'] as List? ?? const []).isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final text in hero['highlights'] as List)
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFFF0C2), borderRadius: BorderRadius.circular(4)),
                  child: Text('$text', style: const TextStyle(fontWeight: FontWeight.bold))),
            ])),
      ])),
    ]);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthSession.instance, builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final data = _data ?? {};
    final today = DateTime.tryParse('${data['today']}');
    final calendarYear = widget.year ?? today?.year ?? DateTime.now().year;
    final calendarDay = calendarYear == (today ?? DateTime.now()).year
        ? (today ?? DateTime.now()) : DateTime(calendarYear, 3, 1);
    final weekStart = calendarDay.subtract(Duration(days: calendarDay.weekday % 7));
    final games = listMapFromJson(AuthSession.instance.showDetailedGames ? data['games'] : publicGameData(data['games']));
    final heroes = listMapFromJson(data['heroes']);
    final birthdays = listMapFromJson(data['birthdays']);
    final todayGames = games.where((g) => g['date_game'] == data['today'] && '${g['state']}'.contains('試合終了')).toList();
    return ListView(key: const ValueKey('home-scroll'), padding: const EdgeInsets.all(12), children: [
      if (widget.news != null) ...[widget.news!, const SizedBox(height: 12)],
      if (widget.predictionScores != null)
        _section('予想対決のスコア', [widget.predictionScores!]),
      Align(alignment: Alignment.centerRight,
        child: IconButton(tooltip: '再読み込み', onPressed: _loading ? null : () => _load(refresh:true), icon: const Icon(Icons.refresh))),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      if (_data != null)
        _section('今日誕生日の選手', [
          if (birthdays.isEmpty)
            const Text('今日誕生日の選手はいません。')
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final player in birthdays)
                PlayerDetailScope(org: '${player['org']}', year: today?.year ?? calendarYear,
                  child: PlayerNameLink(player: player,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4DE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${player['name_player']}（${player['name_team']}）  ${player['age']}歳',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
            ]),
        ]),
      if (todayGames.isNotEmpty)
        _section("TODAY'S HERO — 今日の試合", [
          for (final game in todayGames)
            Padding(
              key: ValueKey('home-hero-game-${game['org']}-${game['id_game']}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_match(game)),
                for (final hero in heroes.where((h) =>
                    h['id_game'] != null && '${h['id_game']}' == '${game['id_game']}' &&
                    '${h['org']}'.toLowerCase() == '${game['org']}'.toLowerCase()))
                  Padding(padding: const EdgeInsets.only(top: 6),
                    child: PlayerDetailScope(org: '${hero['org']}'.toLowerCase(),
                      year: today?.year ?? DateTime.now().year,
                      child: PlayerNameLink(player: hero,
                        child: _heroContent(hero)))),
              ]),
            ),
          if (heroes.any((hero) => todayGames.any((game) =>
              hero['id_game'] != null && '${hero['id_game']}' == '${game['id_game']}' &&
              '${hero['org']}'.toLowerCase() == '${game['org']}'.toLowerCase())))
            const Text('アプリ独自選出：野手は塁打＋打点＋盗塁、投手は奪アウト＋奪三振−自責点×3で比較。公式のヒーロー表彰とは異なります。', style: TextStyle(fontSize: 11, color: Colors.black54)),
        ]),
      _section('今週・翌週のカレンダー（NPB・MLB）', [
        SizedBox(height: 480, child: HomeSeasonCalendar(year: calendarYear, weekStart: weekStart, weekCount: 2)),
        Align(alignment: Alignment.centerRight, child: TextButton(
          onPressed: () => _openCalendar(calendarYear), child: const Text('1ヶ月分の日程を見る'))),
      ]),
      const TodayEventMap(key: ValueKey('home-today-event-map')),
      if (widget.gameInformation != null)
        _section('試合情報', [widget.gameInformation!]),
      _section('順位・ゲーム差', [HomeStandingsBoard(year: calendarYear)]),
      _section('個人タイトル', [
        for (final org in [OrgConfig.npb, OrgConfig.mlb]) ...[
          if (org.kind == OrgKind.mlb)
            HomeStandingsBoard(year: calendarYear, org: OrgConfig.mlb)
          else
            Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(org.label, style: const TextStyle(fontWeight: FontWeight.bold))),
          PlayerDetailScope(org: org.kind.name, year: calendarYear,
            child: SeasonTitlesBoard(org: org, year: calendarYear, individualOnly: true)),
        ],
      ]),
      for (final org in [OrgConfig.npb, OrgConfig.mlb])
        _section('${org.label}の動画', [
          VideosBoard(key: ValueKey('home-videos-${org.kind.name}'),
            org: org.kind, color: org.tabColor, embedded: true),
        ]),
    ]);
  }
}
