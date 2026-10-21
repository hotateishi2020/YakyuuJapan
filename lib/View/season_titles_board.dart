import 'player_detail_dialog.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/org_config.dart';
import '../tools/Env.dart';
import '../widgets/baseball_loading.dart';
import '../logic/season_titles.dart';
import 'season_titles_table.dart';

class SeasonTitlesBoard extends StatefulWidget {
  const SeasonTitlesBoard({super.key, required this.org, required this.year});
  final OrgConfig org;
  final int year;
  @override
  State<SeasonTitlesBoard> createState() => _SeasonTitlesBoardState();
}

class _SeasonTitlesBoardState extends State<SeasonTitlesBoard> {
  Map<String, dynamic>? data;
  bool failed = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(SeasonTitlesBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year ||
        oldWidget.org.kind != widget.org.kind) {
      load();
    }
  }

  Future<void> load() async {
    final token = ++request;
    setState(() {
      data = null;
      failed = false;
    });
    try {
      final response = await http
          .get(Env.api(
              '/records?org=${widget.org.kind.name}&year=${widget.year}&section=titles'))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) throw const FormatException();
      final parsed = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(response.bodyBytes)));
      if (mounted && token == request) setState(() => data = parsed);
    } catch (_) {
      if (mounted && token == request) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('タイトル情報を取得できませんでした'),
        TextButton(onPressed: load, child: const Text('再読み込み'))
      ]));
    }
    if (data == null) return const Center(child: BaseballLoading());
    if (data!['pending'] == true) return Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Text('${data!['message']}'),
        TextButton(onPressed: load, child: const Text('再読み込み')),
      ]));
    return SeasonTitlesGrid(data: data!, year: widget.year, org: widget.org);
  }
}

class SeasonTitlesGrid extends StatelessWidget {
  const SeasonTitlesGrid(
      {super.key, required this.data, required this.year, required this.org});
  final Map<String, dynamic> data;
  final int year;
  final OrgConfig org;
  @override
  Widget build(BuildContext context) {
    final groups = buildSeasonTitles(data, year);
    final mlb = org.kind == OrgKind.mlb;
    if (org.kind == OrgKind.npb) {
      return SeasonTitlesTable(groups: groups, year: year);
    }
    final labels = {...seasonTitleSections}
      ..remove('allstar_roster')
      ..remove('fresh_roster')
      ..remove('minor');
    if (mlb) {
      for (final key in [
        'cs_mvp',
        'sawamura',
        'nagashima',
        'shoriki',
        'best9',
        'fresh_mvp',
        'fresh_roster',
        'interleague_champion',
        'interleague_mvp'
      ]) {
        labels.remove(key);
      }
      labels.addAll({
        'series_mvp': 'ワールドシリーズMVP',
        'series_champion': 'ワールドシリーズ優勝チーム',
        'series_entrants': 'ワールドシリーズ進出チーム',
        'weekly': '週間MVP'
      });
    }
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 3
          : constraints.maxWidth >= 600
              ? 2
              : 1;
      final width = (constraints.maxWidth - 16 - (columns - 1) * 8) / columns;
      return SingleChildScrollView(
          child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$year年 タイトル',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17)),
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('「現在首位」は受賞確定ではありません。未定の項目は受賞者を表示していません。',
                            style: TextStyle(fontSize: 12))),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in labels.entries)
                          SizedBox(
                              width: width,
                              child: Card(
                                  margin: EdgeInsets.zero,
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                            color: org.tabColor,
                                            padding: const EdgeInsets.all(8),
                                            child: Text(entry.value,
                                                style: TextStyle(
                                                    color: org.tabForeground,
                                                    fontWeight:
                                                        FontWeight.bold))),
                                        if (groups[entry.key]!.isEmpty)
                                          Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Text(
                                                  entry.key == 'nagashima' &&
                                                          year < 2026
                                                      ? '創設前（2026年から）'
                                                      : '未定',
                                                  style: const TextStyle(
                                                      color: Colors.black54,
                                                      fontSize: 12)))
                                        else
                                          for (final row in groups[entry.key]!)
                                            Container(
                                                decoration: BoxDecoration(
                                                    border: Border(
                                                        bottom: BorderSide(
                                                            color: Colors.grey
                                                                .shade200))),
                                                padding:
                                                    const EdgeInsets.all(8),
                                                child: Tooltip(
                                                    message:
                                                        '${row['source'] ?? ''}',
                                                    triggerMode:
                                                        TooltipTriggerMode.tap,
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          if ('${row['detail'] ?? ''}'
                                                              .isNotEmpty)
                                                            Text(
                                                                '${row['detail']}',
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color: Colors
                                                                        .black54)),
                                                          PlayerNameLink(
                                                              player: row,
                                                              enabled: ![
                                                                'series_champion',
                                                                'series_entrants',
                                                                'league_champion',
                                                                'cs_champion',
                                                                'fresh_champion',
                                                                'allstar_champion',
                                                                'interleague_champion'
                                                              ].contains(
                                                                  entry.key),
                                                              child: Text(
                                                                  '${row['name'] ?? '—'}',
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          15,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold))),
                                                          if ('${row['team'] ?? ''}'
                                                              .isNotEmpty)
                                                            Text(
                                                                '${row['team']}',
                                                                style:
                                                                    const TextStyle(
                                                                        fontSize:
                                                                            12)),
                                                          if (row['value'] !=
                                                                  null &&
                                                              row['value'] !=
                                                                  '受賞')
                                                            Text(
                                                                '${row['value']}${row['unit'] ?? ''}',
                                                                style:
                                                                    const TextStyle(
                                                                        fontSize:
                                                                            12)),
                                                          if (row['confirmed'] !=
                                                              true)
                                                            Text(
                                                                row['statistical'] ==
                                                                        true
                                                                    ? '指標首位（表彰対象外を含む）'
                                                                    : '現在首位（暫定）',
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color: Colors
                                                                        .orange
                                                                        .shade900)),
                                                        ]))),
                                      ])))
                      ],
                    ),
                  ])));
    });
  }
}
