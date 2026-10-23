import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/org_config.dart';
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../widgets/baseball_loading.dart';
import 'SeasonTable.dart';

/// HOME shares the standings page's chart and its special-media visibility rules.
class HomeGamesBehindBoard extends StatefulWidget {
  const HomeGamesBehindBoard({super.key, required this.org, required this.year, this.horizontal = false});
  final OrgConfig org;
  final int year;
  final bool horizontal;

  @override
  State<HomeGamesBehindBoard> createState() => _HomeGamesBehindBoardState();
}

class _HomeGamesBehindBoardState extends State<HomeGamesBehindBoard> {
  late Future<List<Map<String, dynamic>>> _rows;

  Future<List<Map<String, dynamic>>> _load() async {
    final response = await http.get(Env.api(
        '/predictions/part?org=${widget.org.kind.name}&part=standings&year=${widget.year}'))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw const FormatException();
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    if (data['pending'] == true) throw const FormatException();
    return listMapFromJson(data['stats_team']).where(widget.org.rowBelongs).toList();
  }

  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  @override
  void didUpdateWidget(HomeGamesBehindBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year || oldWidget.org.kind != widget.org.kind) {
      _rows = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _rows,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Column(children: [
          const Text('ゲーム差を取得できませんでした。'),
          TextButton(onPressed: () => setState(() => _rows = _load()),
            child: const Text('再読み込み')),
        ]);
      }
      if (!snapshot.hasData) return const SizedBox(height: 140, child: Center(child: BaseballLoading()));
      final rows = snapshot.data!;
      if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('順位情報はまだありません。'));
      return LayoutBuilder(builder: (context, constraints) {
        const gap = 12.0;
        final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
        final groups = <({int league, List<Map<String, dynamic>> rows})>[
          for (final league in widget.org.leagues)
            for (final area in widget.org.kind == OrgKind.mlb ? ['EAST', 'CENTER', 'WEST'] : [''])
              (league: league.id, rows: rows.where((r) => '${r['id_league']}' == '${league.id}' &&
                  (area.isEmpty || '${r['code_area']}'.trim().toUpperCase() == area)).toList()),
        ].where((g) => g.rows.isNotEmpty).toList();
        final slots = widget.org.kind == OrgKind.mlb ? 3 : 2;
        final availableWidth = (constraints.maxWidth - gap * (slots - 1)) / slots;
        final width = availableWidth > 0 ? availableWidth : 0.0;
        // Use the same three-division budget for every HOME team-name column,
        // including NPB, so narrower MLB panels determine the shared limit.
        final nameBudget = ((constraints.maxWidth - gap * 2) / 3) * (portrait ? 1 : .65) - 28 - 8;
        final preferredNameWidth = MediaQuery.textScalerOf(context).scale(144);
        final teamNameWidth = nameBudget.clamp(0.0, preferredNameWidth).toDouble();
        final panels = [
          for (final group in groups)
            SizedBox(width: width, child: SeasonTableBlock(
              standings: group.rows, stats: const [], org: widget.org,
              seasonYear: widget.year, onlyLeagueId: group.league,
              pane: SeasonPane.standings, portraitLayout: true,
              standingsChartBeside: !portrait, standingsChartBelow: portrait,
              standingsChartHeight: 200,
              standingsNamesOnly: true,
              useFullStandingsTeamNames: widget.org.kind == OrgKind.mlb,
              standingsTeamNameWidth: teamNameWidth, showPredictionColumns: false,
              includeMlbWildcard: false,
            )),
        ];
        Widget panelRow(List<Widget> items) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: gap), items[i],
          ]],
        );
        final content = widget.org.kind == OrgKind.mlb
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final league in widget.org.leagues)
                  Padding(padding: const EdgeInsets.only(bottom: gap), child: panelRow([
                    for (var i = 0; i < groups.length; i++)
                      if (groups[i].league == league.id) panels[i],
                  ])),
              ])
            : panelRow(panels);
        return content;
      });
    },
  );
}

/// HOME standings: NPB side by side; MLB divisions in AL and NL rows.
class HomeStandingsBoard extends StatelessWidget {
  const HomeStandingsBoard({super.key, required this.year, this.org = OrgConfig.npb});
  final int year;
  final OrgConfig org;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(org.label, style: const TextStyle(fontWeight: FontWeight.bold))),
      HomeGamesBehindBoard(org: org, year: year, horizontal: true),
    ],
  );
}
