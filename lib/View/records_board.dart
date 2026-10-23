import '../logic/record_sawamura.dart';
import 'LeagueLogo.dart';
import '../widgets/special_media.dart';
import '../widgets/navigation_picker.dart';
import '../tools/browser_cookie.dart';
import '../widgets/collapsible_menu.dart';
import 'player_detail_dialog.dart';
import 'allstar_history_board.dart';
import '../logic/record_awards.dart';
import 'additional_records_board.dart';
import 'adaptive_section_selector.dart';
import 'baseball_catalog_boards.dart';
import 'compact_layout.dart';
import 'club_records_board.dart';
import '../logic/favorite_team.dart';
import 'draft_history_board.dart';
import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';
import '../tools/tab_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import '../tools/color_parse.dart';
import 'GamesBoard.dart' show teamLogoVisual;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../config/org_config.dart';
import '../config/app_design.dart';
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../tools/network_error.dart';
import 'strength_research.dart';

const recordTabs = ['🗓️年表', '👑個人タイトル', '⚾️シーズン記録', '👣通算記録', '🚥連続記録', '🏆功績', '🌱新人ドラフト', '🏢球団記録', '🍁現役ドラフト', '🔢背番号', '⚜️殿堂入り・名球会', '👴年齢記録', '📶回数記録', '😎レギュラー', '⭐️オールスター'];

/// Franchise IDs keep former team names in the same championship history.
List<Map<String, dynamic>> championshipIntervals(List<Map<String, dynamic>> seasons, int year, {bool mlb = false}) {
  final history = seasons.where((s) => (int.tryParse('${s['year']}') ?? 0) <= year).toList()..sort((a, b) => (int.tryParse('${b['year']}') ?? 0).compareTo(int.tryParse('${a['year']}') ?? 0));
  if (history.isEmpty) return [];
  String key(Map<String, dynamic> t) => '${t['id_team'] ?? t['name']}';
  final current = [for (final l in listMapFromJson(history.first['leagues'])) ...listMapFromJson(l['teams'])];
  return [
    for (final team in current)
      (() {
        int? leagueYear, championYear;
        for (final season in history) {
          final y = int.tryParse('${season['year']}') ?? 0;
          for (final league in listMapFromJson(season['leagues'])) {
            for (final t in listMapFromJson(league['teams'])) {
              if (key(t) != key(team)) continue;
              if (t['league_champion'] == true || (!mlb && '${t['rank']}' == '1')) {
                leagueYear ??= y;
              }
              if (t['champion'] == true) championYear ??= y;
            }
          }
        }
        return {...team, 'league_years': leagueYear == null ? null : year - leagueYear, 'champion_years': championYear == null ? null : year - championYear};
      })()
  ];
}

class RecordsBoard extends StatefulWidget {
  const RecordsBoard({super.key, required this.org, required this.year});
  final OrgConfig org;
  final int year;
  @override
  State<RecordsBoard> createState() => _RecordsBoardState();
}

class _RecordsBoardState extends State<RecordsBoard> {
  final _timelineHorizontal = ScrollController();

  @override
  void dispose() {
    _timelineHorizontal.dispose();
    super.dispose();
  }

  int tab = 0;
  List<int> get _tabs => widget.org.kind == OrgKind.npb ? [0, 1, 14, 2, 3, 4, 7, 11, 12, 13, 5, 6, 8, 9, 10] : [0, 1, 2, 3, 4, 11, 12, 13, 5, 9, 10];
  final Set<int> _visibleStandingsLeagues = {};
  int _titlesLeague = 0;
  String? _selectedTeam;
  String _teamKey(Map<String, dynamic> team) => team['id_team'] != null ? 'id:${team["id_team"]}' : 'name:${team["name"]}';
  Map<String, dynamic>? data;
  String? error;
  int request = 0;
  bool _showTimelineEvents = readBrowserCookie('timeline-show-events') != 'false';
  bool _showInterleagueRanks = readBrowserCookie('timeline-show-interleague') != 'false';
  bool _showCs = readBrowserCookie('timeline-show-cs') != 'false';
  bool _showManagers = readBrowserCookie('timeline-show-managers') == 'true';
  @override
  void initState() {
    super.initState();
    _restoreStandingsLeague();
    tab = readSavedTab('records_${widget.org.kind.name}', _tabs, fallback: 0);
    load();
  }

  @override
  void didUpdateWidget(RecordsBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.org.kind != widget.org.kind || oldWidget.year != widget.year) {
      _selectedTeam = null;
      _restoreStandingsLeague();
      tab = readSavedTab('records_${widget.org.kind.name}', _tabs, fallback: 0);
      load();
    }
  }

  Future<void> load() async {
    final id = ++request;
    setState(() {
      data = null;
      error = null;
    });
    try {
      final response = await http.get(Env.api('/records?org=${widget.org.kind.name}&year=${widget.year}${tab == 0 ? '&section=timeline' : ''}')).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const FormatException('記録を取得できませんでした');
      }
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('記録データの形式が不正です');
      }
      if (mounted && id == request) {
        setState(() {
          if (value['pending'] == true) {
            error = '${value['message']}';
          } else {
            data = value;
          }
        });
      }
    } catch (e) {
      if (mounted && id == request) {
        setState(() => error = networkErrorMessage(e, fallback: '記録を取得できませんでした。'));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AdaptiveSectionSelector(
            fitLabels: true,
            pickerKey: ValueKey('records-picker-${widget.org.kind.name}'),
            itemKeyPrefix: 'records-tab-',
            labels: {for (final i in _tabs) i: recordTabs[i]},
            value: tab,
            background: widget.org.tabColor,
            foreground: widget.org.tabForeground,
            onChanged: (i) {
              saveTab('records_${widget.org.kind.name}', i);
              final reload = (tab == 0) != (i == 0);
              setState(() => tab = i);
              if (reload) load();
            }),
        const MenuGap(height: ALL_SPACE_BLOCK),
        Expanded(
            child: tab == 13
                ? RegularHistoryLoader(org: widget.org.kind.name, year: widget.year)
                : tab == 14
                    ? AllStarHistoryBoard(year: widget.year)
                    : tab == 9
                        ? UniformHistoryBoard(org: widget.org.kind.name, year: widget.year)
                        : tab == 10
                            ? HallOfFameBoard(org: widget.org.kind.name, year: widget.year)
                            : tab == 8
                                ? DraftHistoryBoard(key: ValueKey('active-${widget.year}'), year: widget.year, activeDraft: true)
                                : tab == 6
                                    ? (widget.org.kind == OrgKind.npb ? DraftHistoryBoard(key: ValueKey(widget.year), year: widget.year) : const SizedBox.shrink())
                                    : tab == 5
                                        ? RecordsHonors(org: widget.org, year: widget.year)
                                        : error != null
                                            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), OutlinedButton(onPressed: load, child: const Text('再読み込み'))]))
                                            : data == null
                                                ? const Center(child: BaseballLoading())
                                                : switch (tab) {
                                                    11 => AgeRecordsBoard(rows: listMapFromJson(data!['age_records'])),
                                                    12 => CountRecordsBoard(records: listMapFromJson(data!['count_records'])),
                                                    13 => RegularHistoryBoard(rows: listMapFromJson(data!['regular_history'])),
                                                    0 => standings(),
                                                    1 => titles(),
                                                    7 => ClubRecordsBoard(data: Map<String, dynamic>.from(data!['club_records'] as Map? ?? {})),
                                                    _ => recordComparison(['', '', 'season', 'career', 'streaks'][tab]),
                                                  }),
      ]);

  void _restoreStandingsLeague() {
    _titlesLeague = readSavedTab('titles_league_${widget.org.kind.name}', [0, ...widget.org.leagueIds], fallback: 0);
    _visibleStandingsLeagues
      ..clear()
      ..addAll(widget.org.leagueIds.where((id) => readBrowserCookie('timeline-league-${widget.org.kind.name}-$id') != 'false'));
  }

  Widget standings() => Column(children: [
        MenuBand(
          level: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _timelineOptions(),
          ),
        ),
        Expanded(child: _standingsTable()),
      ]);

  Widget _timelineOptions() => Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final league in widget.org.leagues)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(
              key: ValueKey('timeline-league-${league.id}'),
              value: _visibleStandingsLeagues.contains(league.id),
              visualDensity: VisualDensity.compact,
              onChanged: (value) => setState(() {
                final checked = value ?? false;
                if (checked) {
                  _visibleStandingsLeagues.add(league.id);
                } else {
                  _visibleStandingsLeagues.remove(league.id);
                }
                writeBrowserCookie('timeline-league-${widget.org.kind.name}-${league.id}', '$checked');
              }),
            ),
            Text(league.name, style: const TextStyle(fontSize: 12)),
          ]),
        for (final option in [
          ('timeline-show-events', '出来事を表示する', _showTimelineEvents),
          if (widget.org.kind == OrgKind.npb) ('timeline-show-interleague', '交流戦順位を表示する', _showInterleagueRanks),
          if (widget.org.kind == OrgKind.npb) ('timeline-show-cs', 'CS関連列を表示する', _showCs),
          ('timeline-show-managers', '監督を表示する', _showManagers),
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(
              key: ValueKey(option.$1),
              value: option.$3,
              visualDensity: VisualDensity.compact,
              onChanged: (value) => setState(() {
                final checked = value ?? false;
                writeBrowserCookie(option.$1, '$checked');
                if (option.$1 == 'timeline-show-events') {
                  _showTimelineEvents = checked;
                } else if (option.$1 == 'timeline-show-interleague') {
                  _showInterleagueRanks = checked;
                } else if (option.$1 == 'timeline-show-cs') {
                  _showCs = checked;
                } else {
                  _showManagers = checked;
                }
              }),
            ),
            Text(option.$2, style: const TextStyle(fontSize: 12)),
          ]),
        const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Text('気になる球団を押してみてね！', style: TextStyle(fontSize: 12)),
        ),
      ]);

  Widget _standingsTable() {
    List<Map<String, dynamic>> visibleLeagues(Map<String, dynamic> season) {
      final leagues = listMapFromJson(season['leagues']);
      if (_visibleStandingsLeagues.isEmpty) return [];
      // The pre-1950 single league is shared history, not a C/P league row.
      if (widget.org.kind == OrgKind.npb && (int.tryParse('${season['year']}') ?? 0) < 1950) return leagues;
      return leagues.where((l) => widget.org.leagues.any((selected) =>
          _visibleStandingsLeagues.contains(selected.id) &&
          ('${l['id_league']}' == '${selected.id}' || l['name'] == selected.name))).toList();
    }

    final allSeasons = listMapFromJson(data!['standings']);
    final seasons = allSeasons.where((s) => visibleLeagues(s).isNotEmpty).toList();
    if (allSeasons.isEmpty && listMapFromJson(data!['championship_summary']).isEmpty) return const Center(child: Text('歴代順位はまだ登録されていません。'));
    final mlbCount = allSeasons.expand((s) => listMapFromJson(s['leagues'])).map((l) => listMapFromJson(l['teams']).length).fold<int>(1, math.max);
    int columnsFor(Map<String, dynamic> season) => widget.org.kind == OrgKind.npb ? ((int.tryParse('${season['year']}') ?? 0) < 1958 ? 9 : 6) : mlbCount;
    final singleLeague = _visibleStandingsLeagues.length == 1;
    final compact = compactBaseballLayout(context);
    final platform = Theme.of(context).platform;
    final tapToShowName = compact || (kIsWeb && (platform == TargetPlatform.android || platform == TargetPlatform.iOS));
    final championLogoOnly = compact;
    final yearWidth = compact ? 40.0 : 48.0;
    final leagueWidth = compact ? 36.0 : 80.0;
    var championWidth = championLogoOnly ? 48.0 : 240.0;
    for (final season in seasons) {
      for (final league in listMapFromJson(season['leagues'])) {
        final teams = listMapFromJson(league['teams']);
        for (final team in teams.where((t) => t['champion'] == true)) {
          final painter = TextPainter(text: TextSpan(text: '${team['name'] ?? '—'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), textScaler: MediaQuery.textScalerOf(context), textDirection: Directionality.of(context))..layout();
          if (!championLogoOnly && team['champion'] == true) {
            championWidth = math.max(championWidth, painter.width + 42);
          }
          painter.dispose();
        }
      }
    }
    final rankWidth = _showManagers ? 80.0 : 64.0;
    final maxColumns = seasons.map(columnsFor).fold<int>(1, math.max);
    final interleagueWidth = widget.org.kind == OrgKind.npb && _showInterleagueRanks ? rankWidth : 0.0;
    bool hasInterleague(Map<String, dynamic> season) => interleagueWidth > 0;
    final historyColumns = _showTimelineEvents
        ? const <String, String>{
            'rules': 'ルール変更',
            'recruitment': '選手採用規約',
            'records': '記録',
            'incidents': '事件',
            'international': '国際大会結果',
          }
        : const <String, String>{};
    const historyColumnWidth = 240.0;
    final timeline = listMapFromJson(data!['timeline']);
    List<Map<String, dynamic>> eventsFor(Map<String, dynamic> season, String category) => timeline.where((event) => '${event['year']}' == '${season['year']}' && event['category'] == category).toList();
    final leagueRows = seasons.fold<int>(1, (count, season) => math.max(count, visibleLeagues(season).length));
    final timelineRowHeight = (_showManagers
            ? leagueRows * 56.0
            : _showTimelineEvents
                ? math.max(72.0, leagueRows * 32.0)
                : leagueRows * 28.0) *
        math.max(1.0, MediaQuery.textScalerOf(context).scale(12) / 12);
    double seasonHeight(Map<String, dynamic> _) => timelineRowHeight;
    final csColumns = widget.org.kind == OrgKind.npb && _showCs
        ? const {
            'cs_final_winner': '日本\nシリーズ\n進出',
            'cs_final_loser': 'FINAL\nSTAGE\n敗退',
            'cs_first_loser': '1st\nSTAGE\n敗退',
          }
        : const <String, String>{};
    final csWidth = compact ? 64.0 : 80.0;
    final headerHeight = csColumns.isEmpty ? 26.0 : 52.0 * math.max(1.0, MediaQuery.textScalerOf(context).scale(11) / 11);
    final fixedWidth = yearWidth + championWidth + csColumns.length * csWidth + (singleLeague ? 0 : leagueWidth);
    return LayoutBuilder(builder: (context, constraints) {
      Widget cell(Widget child, double w, double h, {Color color = Colors.white, Gradient? gradient}) => Container(width: w, height: h, alignment: Alignment.center, decoration: BoxDecoration(color: gradient == null ? color : null, gradient: gradient, border: const Border(right: BorderSide(color: Color(0xFFDDDDDD), width: .5), bottom: BorderSide(color: Color(0xFFDDDDDD), width: .5))), child: child);
      Widget label(String text, {Color color = Colors.black, bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal)));
      Widget teamCell(Map<String, dynamic> team, double w, double h, {bool logo = false, bool logoOnly = false, bool showManager = true, bool selectableLogo = false, Color rankBackground = Colors.white, Color? backgroundOverride, Object? year}) {
        final name = logo ? '${team['name'] ?? '—'}' : '${team['short_name'] ?? team['name'] ?? '—'}';
        final teamKey = _teamKey(team);
        final canSelect = (!logo || selectableLogo) && name != '—';
        final highlighted = canSelect && _selectedTeam == teamKey;
        final background = highlighted
            ? parseColorName('${team['color_back'] ?? ''}', Colors.white)
            : backgroundOverride ?? (logo ? parseColorName('${team['color_back'] ?? ''}', Colors.white) : rankBackground);
        final fg = backgroundOverride != null && !highlighted
            ? Colors.black
            : logo || highlighted
                ? parseColorName('${team['color_font'] ?? ''}', background.computeLuminance() > .45 ? Colors.black : Colors.white)
                : Colors.black87;
        final savedLogo = '${team['logo_url'] ?? ''}';
        final visual = savedLogo.startsWith('asset:')
            ? (asset: savedLogo.substring(6).replaceFirst('images/history_', 'images/thumb_history_'), networkUrl: null)
            : savedLogo.isNotEmpty
                ? (asset: null, networkUrl: savedLogo)
                : team['historical_identity'] == true
                    ? (asset: null, networkUrl: null)
                    : teamLogoVisual('${team['name'] ?? name}', abbrev: '${team['name_shortest'] ?? ''}', mlb: widget.org.kind == OrgKind.mlb);
        final hasLogo = visual.asset != null || visual.networkUrl != null;
        Widget fallback() => label(logoOnly ? '—' : name, color: fg, bold: logo);
        final image = visual.asset != null
            ? SpecialMedia(fallback: label(name, color: fg), child: Image.asset(visual.asset!, cacheWidth: 112, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback()))
            : visual.networkUrl != null
                ? SpecialMedia(fallback: label(name, color: fg), child: Image.network(visual.networkUrl!, cacheWidth: 112, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback()))
                : null;
        final manager = _showManagers && showManager && !logo ? '${team['manager'] ?? ''}' : '';
        Widget withManager(Widget child) => manager.isEmpty
            ? child
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                child,
                Padding(padding: const EdgeInsets.only(top: 3), child: Text(manager, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 10, height: 1.1, color: fg))),
              ]);
        final content = Tooltip(
            message: '${team['name'] ?? name}',
            child: Semantics(
                label: '${team['name'] ?? name}',
                child: cell(
                    withManager(Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (hasLogo) SizedBox(width: logo ? 28 : math.min(w - 6, 54), height: 28, child: image),
                      if ((!logoOnly && logo) || !hasLogo) Flexible(child: fallback()),
                    ])),
                    w,
                    h,
                    color: background)));
        if (tapToShowName && !logoOnly) {
          return _TappedTeamName(
            key: ValueKey(logo ? 'champion-team-$year-$teamKey' : 'rank-team-$year-$teamKey'),
            name: '${team['name'] ?? name}',
            background: background,
            foreground: fg,
            width: w,
            height: h,
            onTap: logo
                ? null
                : () => setState(() {
                      _selectedTeam = _selectedTeam == teamKey ? null : teamKey;
                    }),
            child: content,
          );
        }
        if (!canSelect) return content;
        return MouseRegion(
          key: ValueKey('rank-team-$year-$teamKey'),
          cursor: SystemMouseCursors.click,
          child: Semantics(
              button: true,
              selected: highlighted,
              child: InkWell(
                  hoverColor: Colors.transparent,
                  onTap: () => setState(() {
                        _selectedTeam = _selectedTeam == teamKey ? null : teamKey;
                      }),
                  child: content)),
        );
      }

      Color leagueColor(Map<String, dynamic> league) => widget.org.leagues.where((l) => l.id == league['id_league'] || l.name == league['name']).firstOrNull?.color ?? Colors.grey;
      Color leagueBackground(Map<String, dynamic> league) => Color.lerp(leagueColor(league), Colors.white, .88)!;

      // Keep the year in the same vertical sliver as its row. Compensate only
      // for horizontal movement so row heights and vertical scrolling stay shared.
      Widget pinnedYearRow({Key? key, Key? yearKey, required List<Widget> children}) => Stack(
            key: key,
            children: [
              Row(children: [SizedBox(width: yearWidth), ...children.skip(1)]),
              Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedBuilder(
                    animation: _timelineHorizontal,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(_timelineHorizontal.hasClients ? _timelineHorizontal.offset : 0, 0),
                      child: child,
                    ),
                    child: KeyedSubtree(key: yearKey, child: children.first),
                  )),
            ],
          );

      Widget header(int count, double teamWidth, bool interleague) => pinnedYearRow(children: [
            cell(label('年度', bold: true, color: Colors.white), yearWidth, headerHeight, color: Colors.grey.shade800),
            cell(label(widget.org.kind == OrgKind.npb ? '日本一' : 'WS優勝', bold: true), championWidth, headerHeight, color: const Color(0xFFFFF0BF)),
            for (final title in csColumns.values) Tooltip(message: '2004〜2006年はパ・リーグのプレーオフ、2007年以降はCSの結果。未開催・未確定・未収録は —。', child: cell(Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), csWidth, headerHeight, color: const Color(0xFFFFF0BF))),
            if (!singleLeague) cell(label('リーグ', bold: true), leagueWidth, headerHeight, color: Colors.grey.shade200),
            for (var rank = 1; rank <= count; rank++) cell(label('$rank位', bold: true), teamWidth, headerHeight, color: Colors.grey.shade200),
            if (interleague)
              for (var rank = 1; rank <= 12; rank++) cell(label('交流$rank位', bold: true), interleagueWidth, headerHeight, color: const Color(0xFFFFF0BF)),
            for (final title in historyColumns.values) cell(label(title, bold: true), historyColumnWidth, headerHeight, color: Colors.grey.shade200),
          ]);
      final savedSummary = listMapFromJson(data!['championship_summary']);
      final intervals = savedSummary.isNotEmpty
          ? savedSummary
          : championshipIntervals(allSeasons, widget.year, mlb: widget.org.kind == OrgKind.mlb);
      final recordColumns = <String, String>{
        'champion_count': widget.org.kind == OrgKind.npb ? '日本一回数' : 'WS優勝回数',
        'champion_streak': widget.org.kind == OrgKind.npb ? '連続日本一記録' : 'WS連覇記録',
        'league_count': 'リーグ優勝回数',
        'league_streak': 'リーグ連覇記録',
        if (widget.org.kind == OrgKind.npb) 'interleague_count': '交流戦優勝回数',
        if (widget.org.kind == OrgKind.npb) 'interleague_streak': '交流戦連覇記録',
      };
      final mostRecords = {
        for (final field in recordColumns.keys) field: intervals.map((team) => team[field]).whereType<num>().fold<num?>(null, (most, value) => most == null ? value : math.max(most, value)),
      };
      final longestIntervals = {
        for (final field in ['league_years', 'champion_years']) field: intervals.map((team) => team[field]).whereType<int>().fold<int?>(null, (longest, years) => longest == null ? years : math.max(longest, years)),
      };
      final summaryHeight = intervals.isEmpty ? 0.0 : (intervals.length + 1) * 32.0 + 22;
      double measure(String text) {
        final painter = TextPainter(text: TextSpan(text: text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
        final value = painter.width;
        painter.dispose();
        return value;
      }

      final summaryWidths = [
        intervals.fold<double>(60, (w, t) => math.max(w, measure('${t['name'] ?? ''}') + 56)),
        measure('最後のリーグ優勝から') + 14,
        measure('最後のリーグ優勝から') + 14,
        for (final title in recordColumns.values) measure(title) + 20,
      ];
      Widget summary(double width) {
        Widget summaryRow(List<String> texts, {bool heading = false}) => Row(children: [
              for (final entry in texts.indexed) cell(label(entry.$2, color: heading ? Colors.white : Colors.black, bold: heading), summaryWidths[entry.$1], 32, color: heading ? Colors.black : Colors.white),
            ]);
        String years(Object? value) => value == null ? '—' : '$value年';
        String recordLabel(Map<String, dynamic> team, String field) {
          final value = team[field] as num?;
          if (value == null) return '—';
          if (field.endsWith('_streak')) return value < 2 ? 'ー' : '$value連覇';
          return '$value回';
        }
        Color teamBackground(Map<String, dynamic> team) => Color.lerp(parseColorName('${team['color_back'] ?? ''}', Colors.white), Colors.white, .88)!;
        Widget intervalCell(Map<String, dynamic> team, String field) {
          final value = team[field];
          final longest = value != null && value == longestIntervals[field];
          return cell(label(years(value), color: longest ? Colors.red : Colors.black, bold: longest), summaryWidths[field == 'league_years' ? 1 : 2], 32, color: teamBackground(team));
        }

        final gridWidth = summaryWidths.reduce((a, b) => a + b);
        return Padding(
            padding: EdgeInsets.only(top: 12, left: math.max(0, (constraints.maxWidth - gridWidth) / 2)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: gridWidth,
                  child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade700, width: 2)),
                      child: Column(children: [
                        summaryRow(['球団', widget.org.kind == OrgKind.npb ? '最後の日本一から' : '最後のWS優勝から', '最後のリーグ優勝から', ...recordColumns.values], heading: true),
                        for (final team in intervals)
                          Row(children: [
                            teamCell(team, summaryWidths[0], 32, logo: true, backgroundOverride: teamBackground(team)),
                            intervalCell(team, 'champion_years'),
                            intervalCell(team, 'league_years'),
                            for (final entry in recordColumns.keys.indexed) cell(label(recordLabel(team, entry.$2), bold: team[entry.$2] != null && team[entry.$2] == mostRecords[entry.$2]), summaryWidths[entry.$1 + 3], 32, color: teamBackground(team)),
                          ]),
                      ]))),
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('選択年度までの登録記録。連覇は最長記録。NPBは1950年以降（交流戦は2005年以降、2020年は開催なし）。— は未集計または優勝記録なし。', style: TextStyle(fontSize: 11))),
            ]));
      }

      final standingsWidth = fixedWidth + maxColumns * rankWidth;
      final width = math.max(standingsWidth + interleagueWidth * 12 + historyColumns.length * historyColumnWidth, summaryWidths.reduce((a, b) => a + b));
      double teamWidthFor(Map<String, dynamic> season) =>
          maxColumns * rankWidth / columnsFor(season);
      Widget seasonRow(int i) {
        final season = seasons[i];
        final seasonKey = season['phase'] == null ? '${season['year']}' : '${season['year']}-${season['phase']}';
        final count = columnsFor(season);
        final teamWidth = teamWidthFor(season);
        final leagues = visibleLeagues(season);
        final champion = listMapFromJson(season['leagues']).expand((l) => listMapFromJson(l['teams'])).where((t) => t['champion'] == true).firstOrNull;
        final interleagueTeams = listMapFromJson(season['leagues']).expand((l) => listMapFromJson(l['teams'])).toList();
        final height = seasonHeight(season);
        final leagueHeight = height / math.max(1, leagues.length);
        return pinnedYearRow(key: ValueKey('standings-year-$seasonKey'), yearKey: ValueKey('timeline-fixed-year-$seasonKey'), children: [
          cell(
              FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    label('${season['year']}', bold: true, color: Colors.white),
                    if (season['phase_label'] != null) label('${season['phase_label']}', bold: true, color: Colors.white),
                  ])),
              yearWidth,
              height,
              color: Colors.grey.shade800),
          teamCell(champion ?? {'name': season['champion'] ?? '—'}, championWidth, height, logo: true, logoOnly: championLogoOnly),
          for (final field in csColumns.keys)
            Column(children: [
              for (final league in leagues) KeyedSubtree(key: ValueKey('timeline-$field-$seasonKey-${league['id_league']}'), child: teamCell(listMapFromJson(league['teams']).where((t) => league[field] != null && '${t['id_team']}' == '${league[field]}').firstOrNull ?? {'name': '—'}, csWidth, leagueHeight, logo: true, logoOnly: true, selectableLogo: true, year: 'cs-$field-$seasonKey-${league['id_league']}', backgroundOverride: leagueBackground(league))),
            ]),
          Column(children: [
            for (final league in leagues)
              Row(children: [
                if (!singleLeague) cell(label(compact ? '${league['name']}'.replaceAll('リーグ', '') : '${league['name']}', color: Colors.white, bold: true), leagueWidth, leagueHeight, color: leagueColor(league)),
                for (final entry in listMapFromJson(league['teams']).take(count).indexed) teamCell(entry.$2, teamWidth, leagueHeight, rankBackground: leagueBackground(league), year: seasonKey),
                for (var n = listMapFromJson(league['teams']).length; n < count; n++) cell(const SizedBox.shrink(), teamWidth, leagueHeight, color: leagueBackground(league)),
              ])
          ]),
          if (hasInterleague(season))
            for (var rank = 1; rank <= 12; rank++) KeyedSubtree(key: ValueKey('interleague-rank-$seasonKey-$rank'), child: teamCell(interleagueTeams.where((team) => int.tryParse('${team['interleague_rank']}') == rank).firstOrNull ?? (rank == 1 && season['interleague_champion'] is Map ? Map<String, dynamic>.from(season['interleague_champion']) : {'name': '—'}), interleagueWidth, height, showManager: false, year: 'interleague-$seasonKey-$rank')),
          for (final category in historyColumns.keys)
            cell(
                Padding(
                    padding: const EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: eventsFor(season, category).isEmpty
                          ? const Text('—', style: TextStyle(fontSize: 12))
                          : SingleChildScrollView(
                              key: ValueKey('timeline-cell-scroll-$seasonKey-$category'),
                              primary: false,
                              child: Tooltip(
                                message: eventsFor(season, category).map((e) => '${e['text']}\n出典：${e['source']}').join('\n\n'),
                                triggerMode: TooltipTriggerMode.tap,
                                child: Text(eventsFor(season, category).map((e) => '• ${e['text']}').join('\n'), key: ValueKey('timeline-$seasonKey-$category'), style: const TextStyle(fontSize: 12, height: 1.4)),
                              )),
                    )),
                historyColumnWidth,
                height,
                color: leagues.isEmpty ? Colors.white : leagueBackground(leagues.first),
                gradient: leagues.length <= 1
                    ? null
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          for (final league in leagues) ...[leagueBackground(league), leagueBackground(league)]
                        ],
                        stops: [
                          for (var i = 0; i < leagues.length; i++) ...[i / leagues.length, (i + 1) / leagues.length]
                        ],
                      )),
        ]);
      }

      final sections = <(int, int)>[];
      for (var start = 0; start < seasons.length;) {
        var end = start + 1;
        while (end < seasons.length && columnsFor(seasons[end]) == columnsFor(seasons[start]) && hasInterleague(seasons[end]) == hasInterleague(seasons[start])) {
          end++;
        }
        sections.add((start, end));
        start = end;
      }
      return SingleChildScrollView(
          key: const ValueKey('standings-horizontal-scroll'),
          controller: _timelineHorizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: CustomScrollView(
                key: PageStorageKey('standings-vertical-scroll-${widget.org.kind.name}-${widget.org.leagueIds.where(_visibleStandingsLeagues.contains).join('-')}'),
                slivers: [
                  if (summaryHeight > 0) SliverToBoxAdapter(child: summary(width)),
                  for (final section in sections)
                    SliverMainAxisGroup(slivers: [
                      SliverPersistentHeader(pinned: true, delegate: _TimelineHeaderDelegate(KeyedSubtree(key: ValueKey('timeline-header-${seasons[section.$1]['year']}'), child: header(columnsFor(seasons[section.$1]), teamWidthFor(seasons[section.$1]), hasInterleague(seasons[section.$1]))), height: headerHeight)),
                      SliverFixedExtentList(itemExtent: timelineRowHeight, delegate: SliverChildBuilderDelegate((_, index) => seasonRow(section.$1 + index), childCount: section.$2 - section.$1)),
                    ]),
                ],
              )));
    });
  }

  Widget titles() => Column(children: [
        if (NavigationPickerScope.enabled(context))
          NavigationPicker(level: 3, labels: {0: '両リーグ', for (final league in widget.org.leagues) league.id: league.name}, value: _titlesLeague,
            onChanged: (value) { saveTab('titles_league_${widget.org.kind.name}', value); setState(() => _titlesLeague = value); },
            color: widget.org.tabColor, foreground: widget.org.tabForeground,
            itemColors: {for (final league in widget.org.leagues) league.id: league.color},
            logoAssets: {0: widget.org.logoAsset, for (final league in widget.org.leagues) if (league.logoAsset != null) league.id: league.logoAsset!})
        else
        MenuBand(
            level: 3,
            child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  for (final option in [(0, '両リーグ'), ...widget.org.leagues.map((l) => (l.id, l.name))])
                    Expanded(
                        child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Material(
                        color: _titlesLeague == option.$1 ? (widget.org.leagueById(option.$1)?.color ?? widget.org.tabColor) : Color.lerp(Colors.white, widget.org.leagueById(option.$1)?.color ?? widget.org.tabColor, .15),
                        borderRadius: BorderRadius.circular(TAB_RADIUS),
                        child: InkWell(
                          key: ValueKey('titles-league-${option.$1}'),
                          onTap: () {
                            saveTab('titles_league_${widget.org.kind.name}', option.$1);
                            setState(() => _titlesLeague = option.$1);
                          },
                          child: SizedBox(height: TAB_BAR_H, child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                            LeagueLogo(asset: widget.org.leagueById(option.$1)?.logoAsset ?? widget.org.logoAsset, height: TAB_BAR_H - 4),
                            const SizedBox(width: 6),
                            Text(option.$2, style: TextStyle(color: _titlesLeague == option.$1 ? Colors.white : Colors.black87)),
                          ]))),
                        ),
                      ),
                    )),
                ]))),
        Expanded(child: _titlesTable()),
      ]);

  Widget _titlesTable() {
    String leagueKey(Object? value) => '$value'.replaceAll(RegExp(r'[・\s]'), '');
    final selectedLeagues = widget.org.leagues.where((l) => _titlesLeague == 0 || l.id == _titlesLeague).toList();
    final rawSeasons = listMapFromJson(data!['titles']);
    final seasons = (widget.org.kind == OrgKind.npb ? withRecordSawamura(rawSeasons) : rawSeasons).map((s) => <String, dynamic>{...s, 'categories': normalizeRecordAwards(listMapFromJson(s['categories']))}).where((s) => _titlesLeague == 0 || selectedLeagues.any((l) => leagueKey(l.name) == leagueKey(s['league']))).toList();
    if (seasons.isEmpty) {
      return const Center(child: Text('個人タイトルはまだ登録されていません。'));
    }
    final categories = <String>{
      for (final s in seasons)
        for (final c in listMapFromJson(s['categories'])) '${c['label']}'
    }.toList();
    if (widget.org.kind == OrgKind.npb) {
      categories.remove('沢村賞');
      final mvp = categories.indexOf('リーグMVP');
      categories.insert(mvp < 0 ? 0 : mvp + 1, '沢村賞');
    }
    if (categories.contains('最多安打') && categories.contains('盗塁王')) {
      categories.remove('最多安打');
      categories.insert(categories.indexOf('盗塁王') + 1, '最多安打');
    }
    String compact(Object? value) => '${value ?? ''}'.replaceAll(RegExp(r'[\s　]+'), '');
    const style = TextStyle(fontSize: 12);
    double textWidth(String value) {
      final painter = TextPainter(text: TextSpan(text: value, style: style), textDirection: Directionality.of(context), maxLines: 1)..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final names = [
      ...categories,
      for (final s in seasons)
        for (final c in listMapFromJson(s['categories']))
          for (final p in listMapFromJson(c['players'])) compact(p['name']),
    ];
    final columnWidth = (names.map(textWidth).fold<double>(0, math.max) + 12).clamp(88.0, 140.0);
    const yearWidth = 88.0;
    const rowHeight = 60.0;
    Widget text(String value, {bool bold = false, Color color = Colors.black}) => FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1, style: style.copyWith(color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal)));
    Widget cell(Widget child, double width, {bool header = false, bool yearHeader = false, Key? key, Color? background, double? height}) => Container(key: key, width: width, height: height ?? (header ? 28 : rowHeight), padding: header || yearHeader ? const EdgeInsets.symmetric(horizontal: 3, vertical: 2) : EdgeInsets.zero, decoration: BoxDecoration(color: background ?? (header || yearHeader ? Colors.black : Colors.white), border: Border.all(color: Colors.grey.shade400, width: .5)), child: child);
    final years = seasons.map((s) => int.tryParse('${s['year']}') ?? 0).toSet().toList()..sort((a, b) => b.compareTo(a));
    final leagueNames = selectedLeagues.map((l) => l.name).toList();
    Color leagueColor(String name) => widget.org.leagues.where((league) => leagueKey(league.name) == leagueKey(name)).firstOrNull?.color ?? Colors.blueGrey;
    Color playerBackground(String name) => Color.lerp(leagueColor(name), Colors.white, .88)!;
    final grouped = <int, Map<String, List<Map<String, dynamic>>>>{};
    for (final season in seasons) {
      final year = int.tryParse('${season['year']}') ?? 0;
      final leagues = grouped.putIfAbsent(year, () => {});
      leagues.putIfAbsent(leagueKey(season['league']), () => []).addAll(listMapFromJson(season['categories']));
    }
    Color titleFont(Map<String, dynamic> p) => parseColorName(p['color_font']?.toString(), parseColorName(p['color_back']?.toString(), Colors.white).computeLuminance() > .45 ? Colors.black : Colors.white);
    String titleValue(Map<String, dynamic> p) => '${p['value'] ?? ''}'.trim() == '受賞' ? '' : '${p['value'] ?? ''}${p['unit'] ?? ''}';
    Widget winners(int year, String league, String category, double width) {
      final players = [
        for (final c in grouped[year]?[leagueKey(league)] ?? <Map<String, dynamic>>[])
          if (c['label'] == category) ...listMapFromJson(c['players'])
      ];
      return cell(
          players.isEmpty
              ? Center(child: text('—'))
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final p in players)
                    Expanded(
                        child: Container(
                      color: playerBackground(league),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Tooltip(
                          message: '${compact(p['name'])} ${titleValue(p)} ${p['team'] ?? ''}',
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            SizedBox(
                                height: 20,
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      if (recordShortestTeam(p).isNotEmpty) Container(margin: const EdgeInsets.only(right: 4), padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1), color: parseColorName(p['color_back']?.toString(), Colors.white), child: Text(recordShortestTeam(p), style: style.copyWith(color: titleFont(p)))),
                                      PlayerNameLink(player: p, child: Text(compact(p['name']), style: style.copyWith(fontWeight: FontWeight.bold))),
                                    ]))),
                            if (titleValue(p).isNotEmpty) SizedBox(height: 16, child: text(titleValue(p))),
                          ])),
                    )),
                ]),
          width,
          background: playerBackground(league),
          key: ValueKey('title-league-$year-$category-$league'));
    }

    return _PinnedTitleTable(
      yearWidth: yearWidth,
      contentWidth: columnWidth * selectedLeagues.length * categories.length,
      rowHeight: rowHeight,
      yearHeader: cell(text('年度', bold: true, color: Colors.white), yearWidth, header: true, height: 56, key: const ValueKey('title-merged-year-header')),
      header: Row(children: [
        for (final category in categories)
          Column(children: [
            cell(text(category, bold: true, color: Colors.white), columnWidth * selectedLeagues.length, header: true),
            Row(children: [for (final league in selectedLeagues) cell(text(league.name.substring(0, 1), bold: true, color: Colors.white), columnWidth, header: true, background: league.color)]),
          ]),
      ]),
      years: [
        for (final year in years)
          cell(
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                text('$year年', bold: true, color: Colors.white),
                if (widget.org.kind == OrgKind.npb && year < 1950) text('1リーグ制', color: Colors.white),
              ]),
              yearWidth,
              yearHeader: true,
              key: ValueKey('title-fixed-year-$year')),
      ],
      rows: [
        for (final entry in years.indexed)
          Row(key: ValueKey('title-year-${entry.$1}'), children: [
            for (final category in categories)
              Row(key: ValueKey('title-cell-${entry.$1}-$category'), children: [
                if (widget.org.kind == OrgKind.npb && entry.$2 < 1950)
                  winners(entry.$2, '日本野球連盟', category, columnWidth * selectedLeagues.length)
                else
                  for (final league in leagueNames) winners(entry.$2, league, category, columnWidth),
              ]),
          ]),
      ],
    );
  }

  Widget careerRecords(List<Map<String, dynamic>> records) {
    final columns = <Map<int, List<Map<String, dynamic>>>>[];
    for (final record in records) {
      final ranks = <int, List<Map<String, dynamic>>>{};
      final leaders = listMapFromJson(record['leaders']);
      for (var i = 0; i < leaders.length; i++) {
        final rank = int.tryParse('${leaders[i]['rank']}') ?? i + 1;
        if (rank >= 1 && rank <= 50) {
          ranks.putIfAbsent(rank, () => []).add(leaders[i]);
        }
      }
      columns.add(ranks);
    }
    final rowHeight = math.max(66.0, 54 * MediaQuery.textScalerOf(context).scale(12) / 12);
    final rowCount = columns.expand((c) => c.entries).fold<int>(50, (n, e) => math.max(n, e.key + e.value.length - 1));
    void source(Map<String, dynamic> record) => showStrengthSource(context, '${record['label']}', '${record['note'] ?? ''}\n確認日：${record['checked_at'] ?? '—'}', [for (final url in (record['sources'] as List? ?? [])) '$url']);
    Widget text(String value, {bool bold = false, Color color = Colors.black}) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, maxLines: 1, style: TextStyle(fontSize: 12, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal)));
    Widget cell(Widget child, double width, {bool header = false, int span = 1, Key? key}) => Container(key: key, width: width, height: header ? 32 : rowHeight * span, decoration: BoxDecoration(color: header ? Colors.black : Colors.white, border: Border.all(color: Colors.grey.shade400, width: .5)), child: child);
    Widget entry(Map<String, dynamic> p, Map<String, dynamic> record) {
      final status = p['status'];
      final detail = [if (p['combined'] == true) '日米通算', if ('${p['team'] ?? ''}'.isNotEmpty) '${p['team']}', if ('${p['period'] ?? ''}'.isNotEmpty) '${p['period']}', if (p['year'] != null) '${p['year']}年'].join(' ');
      return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: status == 'active'
              ? const Color(0xFFFFF9C4)
              : status == 'retired'
                  ? Colors.white
                  : const Color(0xFFFFF3D6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.center, children: [
            text('${p['name'] ?? '—'}', bold: true),
            text('${p['value'] ?? '—'}${record['unit'] ?? ''}', bold: true),
            if (detail.isNotEmpty) text(detail),
          ]));
    }

    return LayoutBuilder(builder: (context, constraints) {
      const rankWidth = 44.0;
      // Keep record columns compact even when the viewport has spare room.
      // Cell text already scales down to fit long player and team names.
      const columnWidth = 128.0;
      return Column(children: [
        Expanded(
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                    width: rankWidth + columnWidth * records.length,
                    child: Column(children: [
                      Row(children: [
                        cell(Center(child: text('順位', color: Colors.white, bold: true)), rankWidth, header: true),
                        for (final record in records) cell(InkWell(onTap: () => source(record), child: Center(child: text('${record['label']}', color: Colors.white, bold: true))), columnWidth, header: true),
                      ]),
                      Expanded(
                          child: SingleChildScrollView(
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Column(children: [for (var rank = 1; rank <= rowCount; rank++) cell(Center(child: text('$rank位')), rankWidth)]),
                        for (var c = 0; c < records.length; c++)
                          Column(children: [
                            for (var rank = 1; rank <= rowCount; rank++)
                              if (!columns[c].entries.any((e) => e.key < rank && rank < e.key + e.value.length))
                                cell(
                                    InkWell(
                                        onTap: () => source(records[c]),
                                        child: columns[c][rank] == null
                                            ? Center(child: text('—'))
                                            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                                for (final p in columns[c][rank]!) Expanded(child: entry(p, records[c])),
                                              ])),
                                    columnWidth,
                                    span: columns[c][rank]?.length ?? 1,
                                    key: ValueKey('career-cell-$c-$rank')),
                          ]),
                      ]))),
                    ])))),
        const Padding(padding: EdgeInsets.all(8), child: Text('日米通算を含む比較順位。薄黄色：現役　白：引退　薄橙色：区分未確認。記録名・セルを押すと集計条件を表示します。')),
      ]);
    });
  }

  Widget seasonRecords(List<Map<String, dynamic>> records, {String section = 'season'}) {
    double? value(Map<String, dynamic> player) {
      final number = double.tryParse('${player['numeric_value'] ?? player['value'] ?? ''}'.replaceAll(',', ''));
      return number != null && number.isFinite && number >= 0 ? number : null;
    }

    return ListView(children: [
      for (final record in records)
        Builder(builder: (context) {
          final historical = listMapFromJson(record['leaders']);
          final current = listMapFromJson(record['current']);
          final maximum = [...historical, ...current].map(value).whereType<double>().fold<double>(0, math.max);
          final key = '${record['key'] ?? record['label']}';
          Widget group(String label, List<Map<String, dynamic>> players, Color color, String kind) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                if (players.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(kind == 'current' ? '${record['current_message'] ?? 'データなし'}' : 'データなし')),
                if (kind == 'current' && players.isNotEmpty && '${record['current_message'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${record['current_message']}', style: const TextStyle(fontSize: 11, color: Colors.black54))),
                for (var i = 0; i < players.length; i++)
                  Padding(
                      padding: const EdgeInsets.only(top: 3, bottom: 6),
                      child: Column(children: [
                        Row(children: [
                          Expanded(child: PlayerNameLink(player: players[i], child: Text('${players[i]['name'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis))),
                          if (players[i]['year'] != null) Text('${players[i]['year']}年　', style: const TextStyle(fontSize: 12)),
                          Text('${players[i]['value'] ?? '—'}${record['unit'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 3),
                        Container(height: 12, alignment: Alignment.centerLeft, color: Colors.grey.shade200, child: FractionallySizedBox(widthFactor: maximum > 0 ? (value(players[i]) ?? 0) / maximum : 0, child: Container(key: ValueKey('$section-bar-$key-$kind-$i'), color: color))),
                      ])),
              ]);
          return Card(
              child: InkWell(
                  onTap: () => showStrengthSource(context, '${record['label']}', '${record['note'] ?? ''}\n${record['current_note'] ?? ''}', [for (final url in (record['sources'] as List? ?? [])) '$url']),
                  child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(key: ValueKey('$section-record-$key'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${record['label']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 6),
                        group('歴代記録', historical, const Color(0xFF546E7A), 'historical'),
                        const SizedBox(height: 4),
                        group('${record['current_label'] ?? '今シーズン記録'}（${widget.year}年）', current, widget.org.leagues.first.color, 'current'),
                      ]))));
        }),
    ]);
  }

  Widget recordComparison(String section) {
    final records = listMapFromJson(data![section]);
    if (records.isEmpty) {
      return const Center(child: Text('確認済みの記録はまだ登録されていません。'));
    }
    if (section == 'career') return careerRecords(records);
    return seasonRecords(records, section: section);
  }
}

class RecordsHonors extends StatefulWidget {
  const RecordsHonors({super.key, required this.org, required this.year});
  final OrgConfig org;
  final int year;
  @override
  State<RecordsHonors> createState() => _RecordsHonorsState();
}

class _RecordsHonorsState extends State<RecordsHonors> {
  List<Map<String, dynamic>>? teams;
  String? error;
  bool comparison = true;
  int selected = 0;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(RecordsHonors oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.org.kind != widget.org.kind || oldWidget.year != widget.year) {
      comparison = true;
      selected = 0;
      load();
    }
  }

  Future<void> load() async {
    final id = ++request;
    setState(() {
      teams = null;
      error = null;
    });
    try {
      final response = await http.get(Env.api('/team-strength?org=${widget.org.kind.name}&year=${widget.year}')).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const FormatException('功績を取得できませんでした');
      }
      final result = listMapFromJson(jsonDecode(utf8.decode(response.bodyBytes))['teams']);
      if (mounted && id == request) {
        setState(() {
          teams = result;
          final favorite = favoriteTeamRow(result);
          selected = favorite == null ? 0 : result.indexOf(favorite);
          comparison = true;
        });
      }
    } catch (e) {
      if (mounted && id == request) {
        setState(() => error = networkErrorMessage(e, fallback: '功績を取得できませんでした。'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), OutlinedButton(onPressed: load, child: const Text('再読み込み'))]));
    }
    if (teams == null) return const Center(child: BaseballLoading());
    if (teams!.isEmpty) return const Center(child: Text('功績データはまだ登録されていません。'));
    return Column(children: [
      Wrap(spacing: 8, children: [
        ChoiceChip(label: Text(widget.org.kind == OrgKind.npb ? '12球団比較' : '30球団比較'), selected: comparison, onSelected: (_) => setState(() => comparison = true)),
        ChoiceChip(label: const Text('各球団'), selected: !comparison, onSelected: (_) => setState(() => comparison = false)),
        if (!comparison) DropdownButton<int>(value: selected, items: [for (var i = 0; i < teams!.length; i++) DropdownMenuItem(value: i, child: Text('${teams![i]['name_team']}'))], onChanged: (i) => setState(() => selected = i ?? 0)),
      ]),
      Expanded(child: StrengthAchievements(team: teams![selected], year: widget.year, comparisonTeams: comparison ? teams : null)),
    ]);
  }
}

/// Touch screens show the historical team name in the tapped logo's cell.
class _TappedTeamName extends StatefulWidget {
  const _TappedTeamName({super.key, required this.name, required this.background, required this.foreground, required this.width, required this.height, required this.child, this.onTap});
  final String name;
  final Color background, foreground;
  final double width, height;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_TappedTeamName> createState() => _TappedTeamNameState();
}

class _TappedTeamNameState extends State<_TappedTeamName> {
  Timer? _timer;
  bool _showName = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.name,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _timer?.cancel();
            setState(() => _showName = true);
            widget.onTap?.call();
            _timer = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => _showName = false);
            });
          },
          child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Stack(fit: StackFit.expand, children: [
                widget.child,
                if (_showName)
                  Positioned.fill(
                      child: Container(
                    key: const ValueKey('tapped-team-name'),
                    color: widget.background,
                    padding: const EdgeInsets.all(2),
                    alignment: Alignment.center,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: widget.width - 4,
                          child: Text(widget.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, height: 1.1, fontWeight: FontWeight.bold, color: widget.foreground)),
                        )),
                  )),
              ])),
        ),
      );
}

/// Year stays outside the horizontal viewport; both vertical panes move together.
class _PinnedTitleTable extends StatefulWidget {
  const _PinnedTitleTable({required this.yearWidth, required this.contentWidth, required this.rowHeight, required this.yearHeader, required this.header, required this.years, required this.rows});
  final double yearWidth, contentWidth, rowHeight;
  final Widget yearHeader, header;
  final List<Widget> years, rows;
  @override
  State<_PinnedTitleTable> createState() => _PinnedTitleTableState();
}

class _PinnedTitleTableState extends State<_PinnedTitleTable> {
  final _years = ScrollController();
  final _body = ScrollController();
  bool _syncing = false;
  void _sync(ScrollController source, ScrollController target) {
    if (_syncing || !source.hasClients || !target.hasClients) return;
    final offset = source.offset.clamp(target.position.minScrollExtent, target.position.maxScrollExtent);
    if (offset == target.offset) return;
    _syncing = true;
    target.jumpTo(offset);
    _syncing = false;
  }

  @override
  void initState() {
    super.initState();
    _years.addListener(() => _sync(_years, _body));
    _body.addListener(() => _sync(_body, _years));
  }

  @override
  void dispose() {
    _years.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            width: widget.yearWidth,
            child: Column(children: [
              widget.yearHeader,
              Expanded(child: ListView.builder(key: const ValueKey('title-years-scroll'), controller: _years, padding: EdgeInsets.zero, itemExtent: widget.rowHeight, itemCount: widget.years.length, itemBuilder: (_, i) => widget.years[i])),
            ])),
        Expanded(
            child: SingleChildScrollView(
                key: const ValueKey('title-horizontal-scroll'),
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                    width: widget.contentWidth,
                    child: Column(children: [
                      widget.header,
                      Expanded(child: ListView.builder(key: const ValueKey('title-body-scroll'), controller: _body, padding: EdgeInsets.zero, itemExtent: widget.rowHeight, itemCount: widget.rows.length, itemBuilder: (_, i) => widget.rows[i])),
                    ])))),
      ]);
}

class _TimelineHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TimelineHeaderDelegate(this.child, {this.height = 26});
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override
  bool shouldRebuild(covariant _TimelineHeaderDelegate oldDelegate) => true;
}
