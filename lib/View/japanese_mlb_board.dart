import '../config/org_config.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';
import '../widgets/baseball_loading.dart';
import 'player_detail_dialog.dart';

double _teamLabelWidth(BuildContext context, List<Map<String, dynamic>> players) {
  var width = 32.0;
  for (final player in players) {
    final painter = TextPainter(
      text: TextSpan(text: '${player['name_team']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    if (painter.width > width) width = painter.width;
    painter.dispose();
  }
  return width.ceilToDouble() + 24;
}

const _pitchingMetrics = ['規定到達率', '登板', '勝利', '敗戦', '防御率', '投球回', '奪三振', 'セーブ', 'ホールド', 'WHIP'];
const _battingMetrics = ['規定到達率', '打率', '打席', '打数', '安打', '本塁打', '打点', '盗塁', '出塁率', '長打率', 'OPS'];
String _playerName(Map<String, dynamic> p) => '${p['name_player'] ?? ''}'.replaceAll(RegExp(r'[（(]?\s*[0-9０-９]+(?:[.．][0-9０-９]+)?\s*[%％]\s*[）)]?'), '').replaceAll(RegExp(r'[\s　]+'), '');
String _contractText(Map<String, dynamic> p) => '年俸 ${p['salary_label'] ?? 'ー'}【${p['contract_label'] ?? 'ー'}】';
String _metricText(Map<String, dynamic> p, String title) {
  final value = (p['stats'] as Map? ?? {})[title];
  return value == null ? 'ー' : '$value${title == '規定到達率' ? '%' : ''}';
}

/// Measure both disciplines together. Only the final contract column stretches.
class _GridWidths {
  _GridWidths(BuildContext context, List<Map<String, dynamic>> players, double? teamWidth) {
    double measure(String text, double size, FontWeight weight, {bool figures = false}) {
      final painter = TextPainter(
          text: TextSpan(
              text: text,
              style: TextStyle(
                fontSize: size,
                fontWeight: weight,
                letterSpacing: .25,
                fontFeatures: figures ? const [FontFeature.tabularFigures()] : null,
              )),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context))
        ..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    double widest(Iterable<String> values, double size, FontWeight weight, {bool figures = false}) => values.fold<double>(0, (w, text) {
          final n = measure(text, size, weight, figures: figures);
          return n > w ? n : w;
        });
    league = widest(['リーグ', ...players.map((p) => '${p['name_league'] ?? 'ー'}')], 12, FontWeight.w700) + 18;
    area = widest(['地区', ...players.map((p) => '${p['name_area'] ?? 'ー'}')], 12, FontWeight.w700) + 18;
    team = teamWidth ?? _teamLabelWidth(context, players);
    name = widest(['選手', ...players.map(_playerName)], 14, FontWeight.w700) + 26;
    for (final title in {..._pitchingMetrics, ..._battingMetrics}) {
      // DataTable reserves 16px for the sort arrow and 2px padding, even while hidden.
      final heading = measure(title, 12, FontWeight.w700) + 8 + 18;
      final data = widest(players.map((p) => _metricText(p, title)), 14, FontWeight.w600, figures: true) + 8;
      metrics[title] = (heading > data ? heading : data) + 2;
    }
    final contract = widest(['契約内容', ...players.map(_contractText)], 12, FontWeight.w600) + 24;
    final pitch = _pitchingMetrics.fold<double>(0, (n, t) => n + metrics[t]!);
    final bat = _battingMetrics.fold<double>(0, (n, t) => n + metrics[t]!);
    total = league + area + team + name + (pitch > bat ? pitch : bat) + contract + 2;
  }
  late final double league, area, team, name, total;
  final metrics = <String, double>{};
}

class JapaneseMlbBoard extends StatefulWidget {
  const JapaneseMlbBoard({super.key, required this.year});
  final int year;
  @override
  State<JapaneseMlbBoard> createState() => _JapaneseMlbBoardState();
}

class _JapaneseMlbBoardState extends State<JapaneseMlbBoard> {
  List<Map<String, dynamic>>? players;
  bool failed = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(JapaneseMlbBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year) load();
  }

  Future<void> load() async {
    final token = ++request;
    setState(() {
      players = null;
      failed = false;
    });
    try {
      final response = await http.get(Env.api('/mlb-japanese-stats?year=${widget.year}')).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw const FormatException();
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['players'] is! List) throw const FormatException();
      if (mounted && token == request) setState(() => players = listMapFromJson(data['players']));
    } catch (_) {
      if (mounted && token == request) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('日本人選手の成績を取得できませんでした'),
        TextButton(onPressed: load, child: const Text('再読み込み')),
      ]));
    }
    if (players == null) return const Center(child: BaseballLoading());
    final teamLabelWidth = _teamLabelWidth(context, players!);
    return ListView(children: [
      Padding(padding: const EdgeInsets.all(8), child: Text('${widget.year}年 日本人選手のシーズン成績', style: const TextStyle(fontWeight: FontWeight.bold))),
      JapaneseMlbStatsGrid(players: players!.where((p) => p['pitching'] == true).toList(), pitching: true, teamLabelWidth: teamLabelWidth, layoutPlayers: players!),
      const SizedBox(height: 16),
      JapaneseMlbStatsGrid(players: players!.where((p) => p['pitching'] != true).toList(), pitching: false, teamLabelWidth: teamLabelWidth, layoutPlayers: players!),
      const Padding(padding: EdgeInsets.all(8), child: Text('ー は未取得・出場なしの成績です。規定到達率は球団の消化試合数を基準に算出し、100%を超えた場合も実際の割合を表示します。二刀流選手は投手・野手それぞれの実績を表示します。', style: TextStyle(fontSize: 11))),
    ]);
  }
}

class JapaneseMlbStatsGrid extends StatefulWidget {
  const JapaneseMlbStatsGrid({super.key, required this.players, required this.pitching, this.teamLabelWidth, this.layoutPlayers});
  final List<Map<String, dynamic>> players;
  final bool pitching;
  final double? teamLabelWidth;
  final List<Map<String, dynamic>>? layoutPlayers;
  @override
  State<JapaneseMlbStatsGrid> createState() => _JapaneseMlbStatsGridState();
}

class _JapaneseMlbStatsGridState extends State<JapaneseMlbStatsGrid> {
  String? sort;
  bool ascending = false;
  @override
  Widget build(BuildContext context) {
    final columns = widget.pitching ? _pitchingMetrics : _battingMetrics;
    Object? value(Map<String, dynamic> player, String metric) => (player['stats'] as Map? ?? {})[metric];
    final players = widget.players.where((p) => (p['pitching'] == true) == widget.pitching).toList();
    if (sort != null) {
      players.sort((a, b) {
        final av = num.tryParse('${value(a, sort!)}'.replaceAll(',', '').trim());
        final bv = num.tryParse('${value(b, sort!)}'.replaceAll(',', '').trim());
        if (av == null) return bv == null ? 0 : 1;
        if (bv == null) return -1;
        return ascending ? av.compareTo(bv) : bv.compareTo(av);
      });
    }
    final widths = _GridWidths(context, widget.layoutPlayers ?? widget.players, widget.teamLabelWidth);
    Widget leagueCell(Map<String, dynamic> player, String field) => Container(
          width: double.infinity,
          height: 28,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: OrgConfig.mlb.leagueColor(int.tryParse('${player['id_league']}') ?? 0),
          child: Text('${player[field] ?? 'ー'}', softWrap: false, style: const TextStyle(fontSize: 12, color: Colors.white)),
        );
    final accent = widget.pitching ? const Color(0xff234b70) : const Color(0xffa84256);
    const line = Color(0xffd5dde5);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
              width: widths.total,
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: line), boxShadow: const [BoxShadow(color: Color(0x0c16324f), blurRadius: 12, offset: Offset(0, 4))]),
                clipBehavior: Clip.antiAlias,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(color: accent.withValues(alpha: .07), border: const Border(bottom: BorderSide(color: line))),
                      child: Row(children: [
                        Container(width: 4, height: 20, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 10),
                        Text(widget.pitching ? '投手' : '野手', style: TextStyle(color: accent, fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 10),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: Text('${players.length}人', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600))),
                        const Spacer(),
                        Text(sort == null ? 'リーグ・地区・球団順' : '$sort順', style: const TextStyle(color: Color(0xff64748b), fontSize: 12)),
                      ])),
                  if (players.isEmpty)
                    const Padding(padding: EdgeInsets.all(24), child: Text('この年度の成績は登録されていません'))
                  else
                    DataTable(
                      columnSpacing: 0,
                      horizontalMargin: 0,
                      headingRowHeight: 42,
                      dataRowMinHeight: 28,
                      dataRowMaxHeight: 28,
                      headingRowColor: const WidgetStatePropertyAll(Color(0xffedf1f5)),
                      headingTextStyle: const TextStyle(color: Color(0xff475569), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .25),
                      dataTextStyle: const TextStyle(color: Color(0xff243447), fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .25),
                      border: const TableBorder(horizontalInside: BorderSide(color: line, width: .6), verticalInside: BorderSide(color: Color(0xffe7ecf1), width: .5)),
                      dividerThickness: 0,
                      sortColumnIndex: sort == null ? null : columns.indexOf(sort!) + 4,
                      sortAscending: ascending,
                      columns: [
                        DataColumn(columnWidth: FixedColumnWidth(widths.league), label: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('リーグ'))),
                        DataColumn(columnWidth: FixedColumnWidth(widths.area), label: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('地区'))),
                        DataColumn(columnWidth: FixedColumnWidth(widths.team), label: const Padding(padding: EdgeInsets.symmetric(horizontal: 9), child: Text('球団'))),
                        DataColumn(columnWidth: FixedColumnWidth(widths.name), label: const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('選手'))),
                        for (final title in columns)
                          DataColumn(
                              columnWidth: FixedColumnWidth(widths.metrics[title]!),
                              label: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(title)),
                              numeric: true,
                              onSort: (_, up) => setState(() {
                                    ascending = sort == title ? up : ['防御率', 'WHIP'].contains(title);
                                    sort = title;
                                  })),
                        const DataColumn(columnWidth: FlexColumnWidth(), label: Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('契約内容'))),
                      ],
                      rows: [
                        for (var i = 0; i < players.length; i++)
                          DataRow(
                              color: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.hovered)
                                  ? accent.withValues(alpha: .06)
                                  : i.isEven
                                      ? Colors.white
                                      : const Color(0xfff7f9fb)),
                              cells: [
                                DataCell(leagueCell(players[i], 'name_league')),
                                DataCell(leagueCell(players[i], 'name_area')),
                                DataCell(Container(width: double.infinity, height: 28, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 9), decoration: BoxDecoration(color: parseColorNameOrNull('${players[i]['color_back']}')), child: Text('${players[i]['name_team']}', softWrap: false, maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0, color: parseColorNameOrNull('${players[i]['color_font']}'))))),
                                DataCell(Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: PlayerNameLink(player: players[i], child: Text('${players[i]['name_player']}'.replaceAll(RegExp(r'[（(]?\s*[0-9０-９]+(?:[.．][0-9０-９]+)?\s*[%％]\s*[）)]?'), '').replaceAll(RegExp(r'[\s　]+'), ''), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xff243447)))))),
                                for (final title in columns) DataCell(Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(value(players[i], title) == null ? 'ー' : '${value(players[i], title)}${title == '規定到達率' ? '%' : ''}', style: TextStyle(color: value(players[i], title) == null ? const Color(0xff94a3b8) : null, fontFeatures: const [FontFeature.tabularFigures()])))),
                                DataCell(Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(_contractText(players[i]), maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, color: RegExp(r'[（(]2026年まで[）)]').hasMatch('${players[i]['contract_label'] ?? ''}') ? Colors.red : null)))),
                              ])
                      ],
                    ),
                ]),
              )),
        ),
      ),
    );
  }
}
