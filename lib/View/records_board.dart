import 'compact_layout.dart';
import 'club_records_board.dart';
import '../logic/favorite_team.dart';
import 'draft_history_board.dart';
import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';
import '../tools/tab_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;
import '../tools/color_parse.dart';
import 'GamesBoard.dart' show teamLogoVisual;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/org_config.dart';
import '../config/app_design.dart';
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../tools/network_error.dart';
import 'strength_research.dart';

const recordTabs = ['優勝チーム', '個人タイトル', 'シーズン記録', '通算記録', '連続記録', '功績', '新人ドラフト', '球団記録', '現役ドラフト'];

/// Franchise IDs keep former team names in the same championship history.
List<Map<String, dynamic>> championshipIntervals(List<Map<String, dynamic>> seasons, int year, {bool mlb = false}) {
  final history = seasons.where((s) => (int.tryParse('${s['year']}') ?? 0) <= year).toList()
    ..sort((a,b) => (int.tryParse('${b['year']}') ?? 0).compareTo(int.tryParse('${a['year']}') ?? 0));
  if (history.isEmpty) return [];
  String key(Map<String,dynamic> t) => '${t['id_team'] ?? t['name']}';
  final current = [for(final l in listMapFromJson(history.first['leagues'])) ...listMapFromJson(l['teams'])];
  return [for(final team in current) (() {
    int? leagueYear, championYear;
    for(final season in history) {
      final y = int.tryParse('${season['year']}') ?? 0;
      for(final league in listMapFromJson(season['leagues'])) {
        for(final t in listMapFromJson(league['teams'])) {
          if(key(t) != key(team)) continue;
          if(t['league_champion'] == true || (!mlb && '${t['rank']}' == '1')) leagueYear ??= y;
          if(t['champion'] == true) championYear ??= y;
        }
      }
    }
    return {...team, 'league_years':leagueYear == null ? null : year-leagueYear,
      'champion_years':championYear == null ? null : year-championYear};
  })()];
}

class RecordsBoard extends StatefulWidget {
  const RecordsBoard({super.key, required this.org, required this.year});
  final OrgConfig org;
  final int year;
  @override
  State<RecordsBoard> createState() => _RecordsBoardState();
}

class _RecordsBoardState extends State<RecordsBoard> {
  int tab = 0;
  List<int> get _tabs => widget.org.kind == OrgKind.npb ? [0, 1, 2, 3, 4, 7, 5, 6, 8] : [0, 1, 2, 3, 4, 5];
  int _standingsLeague = 0;
  int _titlesLeague = 0;
  String? _selectedTeam;
  String _teamKey(Map<String, dynamic> team) => team['id_team'] != null
      ? 'id:${team["id_team"]}' : 'name:${team["name"]}';
  Map<String, dynamic>? data;
  String? error;
  int request = 0;
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
      final response = await http
          .get(Env.api(
              '/records?org=${widget.org.kind.name}&year=${widget.year}'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const FormatException('記録を取得できませんでした');
      }
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('記録データの形式が不正です');
      }
      if (mounted && id == request) setState(() => data = value);
    } catch (e) {
      if (mounted && id == request) {
        setState(
            () => error = networkErrorMessage(e, fallback: '記録を取得できませんでした。'));
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            height: TAB_BAR_H,
            child: Row(children: [
              for (final i in _tabs)
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Material(
                    color:
                        tab == i ? widget.org.tabColor : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(TAB_RADIUS),
                    child: InkWell(
                      key: ValueKey('records-tab-$i'),
                      onTap: () {
                        saveTab('records_${widget.org.kind.name}', i);
                        setState(() => tab = i);
                      },
                      child: Center(
                          child: FittedBox(
                              child: Text(compactBaseballLayout(context) ? (const {0: '優勝', 1: '個人', 2: 'シーズン', 3: '通算', 4: '連続', 6: '新人ドラ', 7: '球団', 8: '現役ドラ'}[i] ?? recordTabs[i]) : recordTabs[i],
                                  style: TextStyle(
                                      color: tab == i
                                          ? widget.org.tabForeground
                                          : Colors.black87)))),
                    ),
                  ),
                ))
            ])),
        const SizedBox(height: 6),
        Expanded(
            child: tab == 8
                ? DraftHistoryBoard(key: ValueKey('active-${widget.year}'), year: widget.year, activeDraft: true)
                : tab == 6
                ? (widget.org.kind == OrgKind.npb ? DraftHistoryBoard(key: ValueKey(widget.year), year: widget.year) : const SizedBox.shrink())
                : tab == 5
                ? RecordsHonors(org: widget.org, year: widget.year)
                : error != null
                    ? Center(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                            Text(error!),
                            OutlinedButton(
                                onPressed: load, child: const Text('再読み込み'))
                          ]))
                    : data == null
                        ? const Center(child: BaseballLoading())
                        : switch (tab) {
                            0 => standings(),
                            1 => titles(),
                            7 => ClubRecordsBoard(data: Map<String, dynamic>.from(data!['club_records'] as Map? ?? {})),
                            _ => recordComparison(
                                ['', '', 'season', 'career', 'streaks'][tab]),
                          }),
      ]);

  void _restoreStandingsLeague() {
    _titlesLeague = readSavedTab('titles_league_${widget.org.kind.name}',
        [0, ...widget.org.leagueIds], fallback: 0);
    _standingsLeague = readSavedTab('standings_league_${widget.org.kind.name}',
        [0, ...widget.org.leagueIds], fallback: 0);
  }

  Widget standings() => Column(children: [
    Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      for (final option in [(0, '両リーグ'), ...widget.org.leagues.map((l) => (l.id, l.name))])
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: _standingsLeague == option.$1 ? widget.org.tabColor : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(TAB_RADIUS),
            child: InkWell(key: ValueKey('standings-league-${option.$1}'),
              onTap: () {
                saveTab('standings_league_${widget.org.kind.name}', option.$1);
                setState(() => _standingsLeague = option.$1);
              },
              child: SizedBox(height: 32, child: Center(child: Text(option.$2,
                style: TextStyle(color: _standingsLeague == option.$1 ? Colors.white : Colors.black87)))),
            ),
          ),
        )),
    ])),
    const Padding(
      padding: EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Text('気になる球団のロゴを押してみてください！', style: TextStyle(fontSize: 12)),
    ),
    Expanded(child: _standingsTable()),
  ]);

  Widget _standingsTable() {
    List<Map<String, dynamic>> visibleLeagues(Map<String, dynamic> season) {
      final leagues = listMapFromJson(season['leagues']);
      if (_standingsLeague == 0) return leagues;
      // リーグ別表示は1958年以降を対象にする。
      if ((int.tryParse('${season['year']}') ?? 0) < 1958) return [];
      final selected = widget.org.leagueById(_standingsLeague)!;
      return leagues.where((l) => '${l['id_league']}' == '${selected.id}' || l['name'] == selected.name).toList();
    }
    final seasons = listMapFromJson(data!['standings']).where((s) => visibleLeagues(s).isNotEmpty).toList();
    if (seasons.isEmpty) return const Center(child: Text('歴代順位はまだ登録されていません。'));
    final mlbCount = seasons.expand((s) => listMapFromJson(s['leagues']))
        .map((l) => listMapFromJson(l['teams']).length).fold<int>(1, math.max);
    int columnsFor(Map<String,dynamic> season) => widget.org.kind == OrgKind.npb
        ? ((int.tryParse('${season['year']}') ?? 0) < 1958 ? 9 : 6) : mlbCount;
    final singleLeague = _standingsLeague != 0;
    final compact = compactBaseballLayout(context);
    final championLogoOnly = compact;
    final yearWidth = compact ? 40.0 : 48.0;
    final leagueWidth = compact ? 36.0 : 80.0;
    var championWidth = championLogoOnly ? 48.0 : 240.0;
    for (final season in seasons) {
      for (final league in listMapFromJson(season['leagues'])) {
        final teams = listMapFromJson(league['teams']);
        for (final team in teams.where((t) => t['champion'] == true)) {
          final painter = TextPainter(text: TextSpan(text: '${team['name'] ?? '—'}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            textScaler: MediaQuery.textScalerOf(context), textDirection: Directionality.of(context))..layout();
          if (!championLogoOnly && team['champion'] == true) championWidth = math.max(championWidth, painter.width + 42);
          painter.dispose();
        }
      }
    }
    final fixedWidth = yearWidth + championWidth + (singleLeague ? 0 : leagueWidth);
    return LayoutBuilder(builder: (context, constraints) {
      Widget cell(Widget child, double w, double h, {Color color = Colors.white}) => Container(
        width: w, height: h, alignment: Alignment.center,
        decoration: BoxDecoration(color: color, border: const Border(
          right: BorderSide(color: Color(0xFFDDDDDD), width: .5),
          bottom: BorderSide(color: Color(0xFFDDDDDD), width: .5))),
        child: child);
      Widget label(String text, {Color color = Colors.black, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal)));
      Widget teamCell(Map<String, dynamic> team, double w, double h, {bool logo = false, bool logoOnly = false, Color rankBackground = Colors.white, Color? backgroundOverride, Object? year}) {
        final name = logo ? '${team['name'] ?? '—'}' : '${team['short_name'] ?? team['name'] ?? '—'}';
        final teamKey = _teamKey(team);
        final highlighted = !logo && _selectedTeam == teamKey;
        final background = backgroundOverride ?? (logo || highlighted
            ? parseColorName('${team['color_back'] ?? ''}', Colors.white)
            : rankBackground);
        final fg = backgroundOverride != null ? Colors.black : logo || highlighted
            ? parseColorName('${team['color_font'] ?? ''}',
                background.computeLuminance() > .45 ? Colors.black : Colors.white)
            : Colors.black87;
        final savedLogo = '${team['logo_url'] ?? ''}';
        final visual = savedLogo.startsWith('asset:') ? (asset: savedLogo.substring(6).replaceFirst('images/history_', 'images/thumb_history_'), networkUrl: null)
            : savedLogo.isNotEmpty ? (asset: null, networkUrl: savedLogo)
            : team['historical_identity'] == true ? (asset: null, networkUrl: null)
            : teamLogoVisual('${team['name'] ?? name}', abbrev: '${team['name_shortest'] ?? ''}', mlb: widget.org.kind == OrgKind.mlb);
        final hasLogo = visual.asset != null || visual.networkUrl != null;
        Widget fallback() => label(logoOnly ? '—' : name, color: fg, bold: logo);
        final image = visual.asset != null
            ? Image.asset(visual.asset!, cacheWidth: 112, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => fallback())
            : visual.networkUrl != null
                ? Image.network(visual.networkUrl!, cacheWidth: 112, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => fallback()) : null;
        final content = Tooltip(message: '${team['name'] ?? name}', child: Semantics(
          label: '${team['name'] ?? name}', child: cell(
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (hasLogo) SizedBox(width: logo ? 28 : math.min(w - 6, 54), height: 28, child: image),
            if ((!logoOnly && logo) || !hasLogo) Flexible(child: fallback()),
          ]), w, h, color: background)));
        if (logo) return content;
        return MouseRegion(
          key: ValueKey('rank-team-$year-$teamKey'),
          cursor: SystemMouseCursors.click,
          child: Semantics(button: true, selected: highlighted,
            child: InkWell(hoverColor: Colors.transparent, onTap: () => setState(() {
              _selectedTeam = _selectedTeam == teamKey ? null : teamKey;
            }), child: content)),
        );
      }

      Color leagueColor(Map<String, dynamic> league) => widget.org.leagues
          .where((l) => l.id == league['id_league'] || l.name == league['name'])
          .firstOrNull?.color ?? Colors.grey;
      Color leagueBackground(Map<String, dynamic> league) => Color.lerp(leagueColor(league), Colors.white, .88)!;

      Widget header(int count, double teamWidth) => Row(children: [
        cell(label('年度', bold: true), yearWidth, 26, color: Colors.grey.shade200),
        cell(label(widget.org.kind == OrgKind.npb ? '日本一' : 'WS優勝', bold: true), championWidth, 26, color: const Color(0xFFFFF0BF)),
        if (!singleLeague) cell(label('リーグ', bold: true), leagueWidth, 26, color: Colors.grey.shade200),
        for (var rank = 1; rank <= count; rank++)
          cell(label('$rank位', bold: true),
            teamWidth, 26, color: Colors.grey.shade200),
      ]);
      final intervals = singleLeague ? <Map<String,dynamic>>[] : championshipIntervals(seasons, widget.year, mlb: widget.org.kind == OrgKind.mlb);
      final longestIntervals = {
        for (final field in ['league_years', 'champion_years'])
          field: intervals.map((team) => team[field]).whereType<int>()
              .fold<int?>(null, (longest, years) => longest == null ? years : math.max(longest, years)),
      };
      final summaryHeight = intervals.isEmpty ? 0.0 : (intervals.length + 1) * 32.0 + 22;
      Widget summary(double width) {
        final columnWidth = math.min(width, math.max(constraints.maxWidth, 540.0)) / 3;
        Widget summaryRow(List<String> texts, {bool heading = false}) => Row(children: [
          for(final text in texts) cell(label(text, color: heading ? Colors.white : Colors.black, bold: heading), columnWidth, 32,
            color: heading ? Colors.black : Colors.white),
        ]);
        String years(Object? value) => value == null ? '—' : '$value年';
        Color teamBackground(Map<String, dynamic> team) => Color.lerp(
            parseColorName('${team['color_back'] ?? ''}', Colors.white),
            Colors.white, .88)!;
        Widget intervalCell(Map<String, dynamic> team, String field) {
          final value = team[field];
          final longest = value != null && value == longestIntervals[field];
          return cell(label(years(value), color: longest ? Colors.red : Colors.black,
              bold: longest), columnWidth, 32, color: teamBackground(team));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          summaryRow(['球団','最後のリーグ優勝から',widget.org.kind == OrgKind.npb ? '最後の日本一から' : '最後のWS優勝から'], heading:true),
          for(final team in intervals) Row(children: [
            teamCell(team, columnWidth, 32, logo: true, backgroundOverride: teamBackground(team)),
            intervalCell(team, 'league_years'),
            intervalCell(team, 'champion_years'),
          ]),
          const SizedBox(height:22, child: Text('選択年度を基準に算出。— は登録済みの優勝記録なし。', style:TextStyle(fontSize:11))),
        ]);
      }
      final maxColumns = seasons.map(columnsFor).fold<int>(1, math.max);
      final width = compact ? constraints.maxWidth : math.max(constraints.maxWidth, fixedWidth + maxColumns * 68.0);
      return SingleChildScrollView(
        key: const ValueKey('standings-horizontal-scroll'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: width, height: constraints.maxHeight,
          child: ListView.builder(
            key: PageStorageKey('standings-vertical-scroll-${widget.org.kind.name}-$_standingsLeague'),
            itemExtentBuilder: (index, _) {
              if (summaryHeight > 0 && index == 0) return summaryHeight;
              final i = index - (summaryHeight > 0 ? 1 : 0);
              final count = columnsFor(seasons[i]);
              final headerHeight = i == 0 || columnsFor(seasons[i - 1]) != count ? 26.0 : 0.0;
              return math.max(1, visibleLeagues(seasons[i]).length) * 30.0 + headerHeight;
            },
            itemCount: seasons.length + (summaryHeight > 0 ? 1 : 0), itemBuilder: (context, index) {
            if (summaryHeight > 0 && index == 0) return summary(width);
            final i = index - (summaryHeight > 0 ? 1 : 0);
            final season = seasons[i];
            final seasonKey = season['phase'] == null ? '${season['year']}' : '${season['year']}-${season['phase']}';
            final count = columnsFor(season);
            final teamWidth = (width - fixedWidth) / math.max(1, count);
            final showHeader = i == 0 || columnsFor(seasons[i - 1]) != count;
            final leagues = visibleLeagues(season);
            final champion = listMapFromJson(season['leagues']).expand((l) => listMapFromJson(l['teams']))
                .where((t) => t['champion'] == true).firstOrNull;
            final height = math.max(1, leagues.length) * 30.0;
            return Column(children: [
              if (showHeader) header(count, teamWidth),
              Row(key: ValueKey('standings-year-$seasonKey'), children: [
              cell(FittedBox(fit: BoxFit.scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: [
                  label('${season['year']}', bold: true),
                  if (season['phase_label'] != null) label('${season['phase_label']}', bold: true),
                ])), yearWidth, height),
              teamCell(champion ?? {'name': season['champion'] ?? '—'}, championWidth, height, logo: true, logoOnly: championLogoOnly),
              Column(children: [for (final league in leagues)
                Row(children: [
                  if (!singleLeague) cell(label(compact ? '${league['name']}'.replaceAll('リーグ', '') : '${league['name']}', color: Colors.white, bold: true), leagueWidth, 30,
                    color: leagueColor(league)),
                  for (final entry in listMapFromJson(league['teams']).take(count).indexed)
                    teamCell(entry.$2, teamWidth, 30,
                      rankBackground: leagueBackground(league), year: seasonKey),
                  for (var n = listMapFromJson(league['teams']).length; n < count; n++) cell(const SizedBox.shrink(), teamWidth, 30, color: leagueBackground(league)),
                ])]),
            ]),
            ]);
          })));
    });
  }

  Widget titles() => Column(children: [
    Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
      for (final option in [(0, '両リーグ'), ...widget.org.leagues.map((l) => (l.id, l.name))])
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: _titlesLeague == option.$1 ? widget.org.tabColor : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(TAB_RADIUS),
            child: InkWell(key: ValueKey('titles-league-${option.$1}'),
              onTap: () {
                saveTab('titles_league_${widget.org.kind.name}', option.$1);
                setState(() => _titlesLeague = option.$1);
              },
              child: SizedBox(height: 32, child: Center(child: Text(option.$2,
                style: TextStyle(color: _titlesLeague == option.$1 ? Colors.white : Colors.black87)))),
            ),
          ),
        )),
    ])),
    Expanded(child: _titlesTable()),
  ]);

  Widget _titlesTable() {
    String leagueKey(Object? value) => '$value'.replaceAll(RegExp(r'[・\s]'), '');
    final selectedLeagues = widget.org.leagues.where((l) => _titlesLeague == 0 || l.id == _titlesLeague).toList();
    final seasons = listMapFromJson(data!['titles']).where((s) => _titlesLeague == 0 ||
      selectedLeagues.any((l) => leagueKey(l.name) == leagueKey(s['league']))).toList();
    if (seasons.isEmpty) {
      return const Center(child: Text('個人タイトルはまだ登録されていません。'));
    }
    final categories = <String>{
      for (final s in seasons)
        for (final c in listMapFromJson(s['categories'])) '${c['label']}'
    }.toList();
    if (categories.contains('最多安打') && categories.contains('盗塁王')) {
      categories.remove('最多安打');
      categories.insert(categories.indexOf('盗塁王') + 1, '最多安打');
    }
    String compact(Object? value) => '${value ?? ''}'.replaceAll(RegExp(r'[\s　]+'), '');
    const style = TextStyle(fontSize: 12);
    double textWidth(String value) {
      final painter = TextPainter(text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context), maxLines: 1)..layout();
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
    Widget text(String value, {bool bold = false, Color color = Colors.black}) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1,
        style: style.copyWith(color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal)));
    Widget cell(Widget child, double width, {bool header = false, bool yearHeader = false, Key? key}) => Container(
      key: key, width: width, height: header ? 28 : rowHeight,
      padding: header || yearHeader ? const EdgeInsets.symmetric(horizontal: 3, vertical: 2) : EdgeInsets.zero,
      decoration: BoxDecoration(color: header || yearHeader ? Colors.black : Colors.white,
        border: Border.all(color: Colors.grey.shade400, width: .5)), child: child);
    final years = seasons.map((s) => int.tryParse('${s['year']}') ?? 0).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final leagueNames = selectedLeagues.map((l) => l.name).toList();
    final leagueLabels = selectedLeagues.map((l) => l.name.substring(0, 1)).toList();
    final grouped = <int, Map<String, List<Map<String, dynamic>>>>{};
    for (final season in seasons) {
      final year = int.tryParse('${season['year']}') ?? 0;
      final leagues = grouped.putIfAbsent(year, () => {});
      leagues.putIfAbsent(leagueKey(season['league']), () => []).addAll(listMapFromJson(season['categories']));
    }
    Color titleFont(Map<String, dynamic> p) => parseColorName(p['color_font']?.toString(),
      parseColorName(p['color_back']?.toString(), Colors.white).computeLuminance() > .45 ? Colors.black : Colors.white);
    String titleValue(Map<String, dynamic> p) => '${p['value'] ?? ''}'.trim() == '受賞'
        ? '' : '${p['value'] ?? ''}${p['unit'] ?? ''}';
    Widget winners(int year, String league, String category, double width) {
      final players = [
        for (final c in grouped[year]?[leagueKey(league)] ?? <Map<String, dynamic>>[])
          if (c['label'] == category) ...listMapFromJson(c['players'])
      ];
      return cell(players.isEmpty ? Center(child: text('—')) : Row(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final p in players)
          Expanded(child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Tooltip(message: '${compact(p['name'])} ${titleValue(p)} ${p['team'] ?? ''}',
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(height: 18, child: text(compact(p['name']), bold: true)),
                if (titleValue(p).isNotEmpty) SizedBox(height: 16, child: text(titleValue(p))),
                SizedBox(width: double.infinity, height: 18, child: '${p['team'] ?? ''}'.isEmpty ? null : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  color: parseColorName(p['color_back']?.toString(), Colors.white),
                  child: text('${p['team']}', color: titleFont(p)),
                )),
              ])),
          )),
      ]), width, key: ValueKey('title-league-$year-$category-$league'));
    }
    return SingleChildScrollView(scrollDirection: Axis.horizontal,
      child: SizedBox(width: yearWidth + columnWidth * selectedLeagues.length * categories.length,
        child: Column(children: [
          Row(children: [
            SizedBox(height: 56, child: Column(children: [
              cell(text('年度', bold: true, color: Colors.white), yearWidth, header: true),
              cell(const SizedBox.shrink(), yearWidth, header: true),
            ])),
            for (final category in categories)
              Column(children: [
                cell(text(category, bold: true, color: Colors.white), columnWidth * selectedLeagues.length, header: true),
                Row(children: [for (final label in leagueLabels)
                  cell(text(label, bold: true, color: Colors.white), columnWidth, header: true)]),
              ]),
          ]),
          Expanded(child: ListView.builder(itemCount: years.length, itemBuilder: (context, index) {
            final year = years[index];
            final unified = widget.org.kind == OrgKind.npb && year < 1950;
            return Row(key: ValueKey('title-year-$index'), children: [
              cell(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                text('$year年', bold: true, color: Colors.white), if (unified) text('1リーグ制', color: Colors.white),
              ]), yearWidth, yearHeader: true),
              for (final category in categories)
                Row(key: ValueKey('title-cell-$index-$category'), children: [
                  if (unified) winners(year, '日本野球連盟', category, columnWidth * selectedLeagues.length)
                  else for (final league in leagueNames) winners(year, league, category, columnWidth),
                ]),
            ]);
          })),
        ])));
  }

  Widget careerRecords(List<Map<String, dynamic>> records) {
    final columns = <Map<int, List<Map<String, dynamic>>>>[];
    for (final record in records) {
      final ranks = <int, List<Map<String, dynamic>>>{};
      final leaders = listMapFromJson(record['leaders']);
      for (var i = 0; i < leaders.length; i++) {
        final rank = int.tryParse('${leaders[i]['rank']}') ?? i + 1;
        if (rank >= 1 && rank <= 50) ranks.putIfAbsent(rank, () => []).add(leaders[i]);
      }
      columns.add(ranks);
    }
    final rowHeight = math.max(66.0, 54 * MediaQuery.textScalerOf(context).scale(12) / 12);
    final rowCount = columns.expand((c) => c.entries).fold<int>(50, (n, e) => math.max(n, e.key + e.value.length - 1));
    void source(Map<String, dynamic> record) => showStrengthSource(context,
      '${record['label']}', '${record['note'] ?? ''}\n確認日：${record['checked_at'] ?? '—'}',
      [for (final url in (record['sources'] as List? ?? [])) '$url']);
    Widget text(String value, {bool bold = false, Color color = Colors.black}) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
        child: Text(value, maxLines: 1, style: TextStyle(fontSize: 12,
          color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal)));
    Widget cell(Widget child, double width, {bool header = false, int span = 1, Key? key}) => Container(
      key: key, width: width, height: header ? 32 : rowHeight * span,
      decoration: BoxDecoration(color: header ? Colors.black : Colors.white,
        border: Border.all(color: Colors.grey.shade400, width: .5)),
      child: child);
    Widget entry(Map<String, dynamic> p, Map<String, dynamic> record) {
      final status = p['status'];
      final detail = [if (p['combined'] == true) '日米通算', if ('${p['team'] ?? ''}'.isNotEmpty) '${p['team']}',
        if ('${p['period'] ?? ''}'.isNotEmpty) '${p['period']}',
        if (p['year'] != null) '${p['year']}年'].join(' ');
      return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: status == 'active' ? const Color(0xFFFFF9C4)
          : status == 'retired' ? Colors.white : const Color(0xFFFFF3D6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center, children: [
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
        const Padding(padding: EdgeInsets.all(8),
          child: Text('日米通算を含む比較順位。薄黄色：現役　白：引退　薄橙色：区分未確認。記録名・セルを押すと集計条件を表示します。')),
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: SizedBox(width: rankWidth + columnWidth * records.length,
            child: Column(children: [
              Row(children: [
                cell(Center(child: text('順位', color: Colors.white, bold: true)), rankWidth, header: true),
                for (final record in records)
                  cell(InkWell(onTap: () => source(record), child: Center(
                    child: text('${record['label']}', color: Colors.white, bold: true))), columnWidth, header: true),
              ]),
              Expanded(child: SingleChildScrollView(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [for (var rank = 1; rank <= rowCount; rank++)
                  cell(Center(child: text('$rank位')), rankWidth)]),
                for (var c = 0; c < records.length; c++)
                  Column(children: [
                    for (var rank = 1; rank <= rowCount; rank++)
                      if (!columns[c].entries.any((e) => e.key < rank && rank < e.key + e.value.length))
                        cell(InkWell(onTap: () => source(records[c]), child:
                          columns[c][rank] == null ? Center(child: text('—')) : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            for (final p in columns[c][rank]!) Expanded(child: entry(p, records[c])),
                          ])), columnWidth, span: columns[c][rank]?.length ?? 1,
                          key: ValueKey('career-cell-$c-$rank')),
                  ]),
              ]))),
            ])))),
      ]);
    });
  }

  Widget seasonRecords(List<Map<String, dynamic>> records, {String section = 'season'}) {
    double? value(Map<String, dynamic> player) {
      final number = double.tryParse('${player['value'] ?? ''}'.replaceAll(',', ''));
      return number != null && number.isFinite && number >= 0 ? number : null;
    }
    return ListView(children: [
      for (final record in records)
        Builder(builder: (context) {
          final historical = listMapFromJson(record['leaders']);
          final current = listMapFromJson(record['current']);
          final maximum = [...historical, ...current].map(value).whereType<double>()
              .fold<double>(0, math.max);
          final key = '${record['key'] ?? record['label']}';
          Widget group(String label, List<Map<String, dynamic>> players, Color color, String kind) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              if (players.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(kind == 'current' ? '${record['current_message'] ?? 'データなし'}' : 'データなし')),
              for (var i = 0; i < players.length; i++)
                Padding(padding: const EdgeInsets.only(top: 3, bottom: 6), child: Column(children: [
                  Row(children: [
                    Expanded(child: Text('${players[i]['name'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (players[i]['year'] != null) Text('${players[i]['year']}年　', style: const TextStyle(fontSize: 12)),
                    Text('${players[i]['value'] ?? '—'}${record['unit'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 3),
                  Container(height: 12, alignment: Alignment.centerLeft, color: Colors.grey.shade200,
                    child: FractionallySizedBox(
                      widthFactor: maximum > 0 ? (value(players[i]) ?? 0) / maximum : 0,
                      child: Container(key: ValueKey('$section-bar-$key-$kind-$i'), color: color))),
                ])),
            ]);
          return Card(child: InkWell(onTap: () => showStrengthSource(context, '${record['label']}',
            '${record['note'] ?? ''}\n${record['current_note'] ?? ''}', [for (final url in (record['sources'] as List? ?? [])) '$url']), child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(key: ValueKey('$section-record-$key'), crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${record['label']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              group('歴代記録', historical, const Color(0xFF546E7A), 'historical'),
              const SizedBox(height: 4),
              group('今シーズン記録（${widget.year}年）', current, widget.org.leagues.first.color, 'current'),
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
    if (oldWidget.org.kind != widget.org.kind ||
        oldWidget.year != widget.year) {
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
      final response = await http
          .get(Env.api(
              '/team-strength?org=${widget.org.kind.name}&year=${widget.year}'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const FormatException('功績を取得できませんでした');
      }
      final result =
          listMapFromJson(jsonDecode(utf8.decode(response.bodyBytes))['teams']);
      if (mounted && id == request) { setState(() {
        teams = result;
        final favorite = favoriteTeamRow(result);
        selected = favorite == null ? 0 : result.indexOf(favorite);
        comparison = true;
      }); }
    } catch (e) {
      if (mounted && id == request) {
        setState(
            () => error = networkErrorMessage(e, fallback: '功績を取得できませんでした。'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!),
        OutlinedButton(onPressed: load, child: const Text('再読み込み'))
      ]));
    }
    if (teams == null) return const Center(child: BaseballLoading());
    if (teams!.isEmpty) return const Center(child: Text('功績データはまだ登録されていません。'));
    return Column(children: [
      Wrap(spacing: 8, children: [
        ChoiceChip(
            label: Text(widget.org.kind == OrgKind.npb ? '12球団比較' : '30球団比較'),
            selected: comparison,
            onSelected: (_) => setState(() => comparison = true)),
        ChoiceChip(
            label: const Text('各球団'),
            selected: !comparison,
            onSelected: (_) => setState(() => comparison = false)),
        if (!comparison)
          DropdownButton<int>(
              value: selected,
              items: [
                for (var i = 0; i < teams!.length; i++)
                  DropdownMenuItem(
                      value: i, child: Text('${teams![i]['name_team']}'))
              ],
              onChanged: (i) => setState(() => selected = i ?? 0)),
      ]),
      Expanded(
          child: StrengthAchievements(
              team: teams![selected],
              year: widget.year,
              comparisonTeams: comparison ? teams : null)),
    ]);
  }
}
