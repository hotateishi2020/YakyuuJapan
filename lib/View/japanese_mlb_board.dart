import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';
import '../widgets/baseball_loading.dart';
import 'player_detail_dialog.dart';

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
    return ListView(children: [
      Padding(padding: const EdgeInsets.all(8), child: Text('${widget.year}年 日本人選手のシーズン成績', style: const TextStyle(fontWeight: FontWeight.bold))),
      JapaneseMlbStatsGrid(players: players!.where((p) => p['pitching'] == true).toList(), pitching: true),
      const SizedBox(height: 16),
      JapaneseMlbStatsGrid(players: players!.where((p) => p['pitching'] != true).toList(), pitching: false),
      const Padding(padding: EdgeInsets.all(8), child: Text('— は未取得の成績です。二刀流選手は投手・野手それぞれの実績を表示します。', style: TextStyle(fontSize: 11))),
    ]);
  }
}

class JapaneseMlbStatsGrid extends StatefulWidget {
  const JapaneseMlbStatsGrid({super.key, required this.players, required this.pitching});
  final List<Map<String,dynamic>> players;
  final bool pitching;
  @override
  State<JapaneseMlbStatsGrid> createState() => _JapaneseMlbStatsGridState();
}

class _JapaneseMlbStatsGridState extends State<JapaneseMlbStatsGrid> {
  String? sort;
  bool ascending = false;
  @override
  Widget build(BuildContext context) {
    final columns = widget.pitching
        ? ['登板','勝利','敗戦','防御率','投球回','奪三振','セーブ','HP','WHIP']
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(color: widget.pitching ? Colors.blue.shade800 : Colors.red.shade800,
        padding: const EdgeInsets.all(8), child: Text(widget.pitching ? '投手' : '野手',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      if (players.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('この年度の成績は登録されていません'))
      else SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: DataTable(columnSpacing: 16, horizontalMargin: 8,
          headingRowHeight: 36, dataRowMinHeight: 36, dataRowMaxHeight: 48,
          sortColumnIndex: sort == null ? null : columns.indexOf(sort!) + 2,
          sortAscending: ascending,
          columns: [
            const DataColumn(label: Text('選手')), const DataColumn(label: Text('球団')),
            for (final title in columns) DataColumn(label: Text(title), numeric: true,
              onSort: (_, up) => setState(() { ascending = sort == title ? up : ['防御率','WHIP'].contains(title); sort = title; })),
          ],
          rows: [for (final player in players) DataRow(cells: [
            DataCell(PlayerNameLink(player: player, child: Text('${player['name_player']}', style: const TextStyle(fontSize: 14)))),
            DataCell(Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: parseColorNameOrNull('${player['color_back']}'),
              child: Text('${player['name_team']}', style: TextStyle(color: parseColorNameOrNull('${player['color_font']}'))))),
            for (final title in columns) DataCell(Text('${value(player,title) ?? '—'}')),
          ])],
        )),
    ]);
  }
}
