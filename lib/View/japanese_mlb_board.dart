import 'dart:ui' show FontFeature;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';
import '../widgets/baseball_loading.dart';
import 'player_detail_dialog.dart';

double _teamLabelWidth(BuildContext context, List<Map<String, dynamic>> players) {
  var width = 0.0;
  for (final player in players) {
    final painter = TextPainter(
      text: TextSpan(text: '${player['name_team']}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    if (painter.width > width) width = painter.width;
    painter.dispose();
  }
  return width.ceilToDouble() + 18;
}

class JapaneseMlbBoard extends StatefulWidget {
  const JapaneseMlbBoard({super.key, required this.year});
  final int year;
  @override
  State<JapaneseMlbBoard> createState() => _JapaneseMlbBoardState();
}

class _JapaneseMlbBoardState extends State<JapaneseMlbBoard> {
  List<Map<String,dynamic>>? players;
  bool failed = false;
  int request = 0;
  @override
  void initState() { super.initState(); load(); }
  @override
  void didUpdateWidget(JapaneseMlbBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year) load();
  }
  Future<void> load() async {
    final token = ++request;
    setState(() { players = null; failed = false; });
    try {
      final response = await http.get(Env.api('/mlb-japanese-stats?year=${widget.year}'))
          .timeout(const Duration(seconds: 30));
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
    if (failed) { return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('日本人選手の成績を取得できませんでした'),
      TextButton(onPressed: load, child: const Text('再読み込み')),
    ])); }
    if (players == null) return const Center(child: BaseballLoading());
    final teamLabelWidth = _teamLabelWidth(context, players!);
    return ListView(children: [
      Padding(padding: const EdgeInsets.all(8), child: Text('${widget.year}年 日本人選手のシーズン成績', style: const TextStyle(fontWeight: FontWeight.bold))),
      JapaneseMlbStatsGrid(players: players!.where((p) => p['pitching'] == true).toList(), pitching: true, teamLabelWidth: teamLabelWidth),
      const SizedBox(height: 16),
      JapaneseMlbStatsGrid(players: players!.where((p) => p['pitching'] != true).toList(), pitching: false, teamLabelWidth: teamLabelWidth),
      const Padding(padding: EdgeInsets.all(8), child: Text('— は未取得の成績です。二刀流選手は投手・野手それぞれの実績を表示します。', style: TextStyle(fontSize: 11))),
    ]);
  }
}

class JapaneseMlbStatsGrid extends StatefulWidget {
  const JapaneseMlbStatsGrid({super.key, required this.players, required this.pitching, this.teamLabelWidth});
  final List<Map<String,dynamic>> players;
  final bool pitching;
  final double? teamLabelWidth;
  @override
  State<JapaneseMlbStatsGrid> createState() => _JapaneseMlbStatsGridState();
}

class _JapaneseMlbStatsGridState extends State<JapaneseMlbStatsGrid> {
  String? sort;
  bool ascending = false;
  @override
  Widget build(BuildContext context) {
    final columns = widget.pitching
        ? ['登板','勝利','敗戦','防御率','投球回','奪三振','セーブ','ホールド','WHIP']
        : ['打率','打席','打数','安打','本塁打','打点','盗塁','出塁率','長打率','OPS'];
    Object? value(Map<String,dynamic> player, String metric) => (player['stats'] as Map? ?? {})[metric];
    final players = [...widget.players];
    if (sort != null) { players.sort((a,b) {
      final av = num.tryParse('${value(a,sort!)}'.replaceAll(',', '').trim());
      final bv = num.tryParse('${value(b,sort!)}'.replaceAll(',', '').trim());
      if (av == null) return bv == null ? 0 : 1;
      if (bv == null) return -1;
      return ascending ? av.compareTo(bv) : bv.compareTo(av);
    }); }
    final teamLabelWidth = widget.teamLabelWidth ?? _teamLabelWidth(context, widget.players);
    final accent = widget.pitching ? const Color(0xff234b70) : const Color(0xffa84256);
    const line = Color(0xffd5dde5);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(alignment: Alignment.topCenter,
        child: SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: SizedBox(width: 1100, child: Container(
            decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line),
              boxShadow: const [BoxShadow(color: Color(0x0c16324f), blurRadius: 12, offset: Offset(0, 4))]),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: accent.withValues(alpha: .07),
                  border: const Border(bottom: BorderSide(color: line))),
                child: Row(children: [
                  Container(width: 4, height: 20, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  Text(widget.pitching ? '投手' : '野手', style: TextStyle(color: accent, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 10),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Text('${players.length}人', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600))),
                  const Spacer(),
                  Text(sort == null ? '年齢順' : '$sort順', style: const TextStyle(color: Color(0xff64748b), fontSize: 12)),
                ])),
              if (players.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('この年度の成績は登録されていません'))
              else DataTable(columnSpacing: 20, horizontalMargin: 16,
                headingRowHeight: 42, dataRowMinHeight: 48, dataRowMaxHeight: 64,
                headingRowColor: const WidgetStatePropertyAll(Color(0xffedf1f5)),
                headingTextStyle: const TextStyle(color: Color(0xff475569), fontSize: 12, fontWeight: FontWeight.w700),
                dataTextStyle: const TextStyle(color: Color(0xff243447), fontSize: 14, fontWeight: FontWeight.w600),
                border: const TableBorder(horizontalInside: BorderSide(color: line, width: .6),
                  verticalInside: BorderSide(color: Color(0xffe7ecf1), width: .5)),
                dividerThickness: 0,
                sortColumnIndex: sort == null ? null : columns.indexOf(sort!) + 2,
                sortAscending: ascending,
                columns: [
                  const DataColumn(label: Text('選手')), const DataColumn(label: Text('球団')),
                  for (final title in columns) DataColumn(label: Text(title), numeric: true,
                    onSort: (_, up) => setState(() { ascending = sort == title ? up : ['防御率','WHIP'].contains(title); sort = title; })),
                ],
                rows: [for (var i = 0; i < players.length; i++) DataRow(
                  color: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.hovered)
                      ? accent.withValues(alpha: .06) : i.isEven ? Colors.white : const Color(0xfff7f9fb)),
                  cells: [
                    DataCell(PlayerNameLink(player: players[i], child: Text('${players[i]['name_player']}'.replaceAll(RegExp(r'[\s　]+'), ''),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xff243447))))),
                    DataCell(Container(width: teamLabelWidth, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: parseColorNameOrNull('${players[i]['color_back']}'), borderRadius: BorderRadius.circular(6)),
                      child: Text('${players[i]['name_team']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: parseColorNameOrNull('${players[i]['color_font']}'))))),
                    for (final title in columns) DataCell(Text('${value(players[i],title) ?? '—'}',
                      style: TextStyle(color: value(players[i],title) == null ? const Color(0xff94a3b8) : null,
                        fontFeatures: const [FontFeature.tabularFigures()]))),
                  ])],
              ),
            ]),
          )),
        ),
      ),
    );
  }
}
