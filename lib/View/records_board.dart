import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/org_config.dart';
import '../config/app_design.dart';
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../tools/network_error.dart';
import 'strength_research.dart';

const recordTabs = ['優勝チーム', '個人タイトル', 'シーズン記録', '通算記録', '連続記録', '功績'];

class RecordsBoard extends StatefulWidget {
  const RecordsBoard({super.key, required this.org, required this.year});
  final OrgConfig org;
  final int year;
  @override
  State<RecordsBoard> createState() => _RecordsBoardState();
}

class _RecordsBoardState extends State<RecordsBoard> {
  int tab = 0;
  Map<String, dynamic>? data;
  String? error;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(RecordsBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.org.kind != widget.org.kind || oldWidget.year != widget.year) {
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
              for (var i = 0; i < recordTabs.length; i++)
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Material(
                    color:
                        tab == i ? widget.org.tabColor : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(TAB_RADIUS),
                    child: InkWell(
                      key: ValueKey('records-tab-$i'),
                      onTap: () => setState(() => tab = i),
                      child: Center(
                          child: FittedBox(
                              child: Text(recordTabs[i],
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
            child: tab == 5
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
                        ? const Center(child: CircularProgressIndicator())
                        : switch (tab) {
                            0 => standings(),
                            1 => titles(),
                            _ => recordComparison(
                                ['', '', 'season', 'career', 'streaks'][tab]),
                          }),
      ]);

  Widget standings() {
    final seasons = listMapFromJson(data!['standings']);
    if (seasons.isEmpty) return const Center(child: Text('歴代順位はまだ登録されていません。'));
    return ListView.builder(
        itemCount: seasons.length,
        itemBuilder: (context, i) {
          final season = seasons[i];
          final leagues = listMapFromJson(season['leagues']);
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${season['year']}年',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(
                            '${widget.org.kind == OrgKind.npb ? '日本一' : 'WS優勝'}：${season['champion'] ?? '未確定・未登録'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF946300))),
                        const SizedBox(height: 6),
                        LayoutBuilder(
                            builder: (context, constraints) =>
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final league in leagues)
                                    SizedBox(
                                        width: constraints.maxWidth < 600
                                            ? constraints.maxWidth
                                            : (constraints.maxWidth - 8) / 2,
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text('${league['name']}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              for (final team
                                                  in listMapFromJson(
                                                      league['teams']))
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      vertical: 5,
                                                      horizontal: 6),
                                                  color: team['champion'] ==
                                                          true
                                                      ? const Color(0xFFFFF0BF)
                                                      : team['postseason'] ==
                                                              true
                                                          ? const Color(
                                                              0xFFE3F2FD)
                                                          : null,
                                                  child: Text(
                                                      '${team['rank']}位  ${team['name']}  ${team['wins']}勝${team['losses']}敗${team['draws'] == 0 ? '' : '${team['draws']}分'}${team['postseason'] == true ? '  PS進出' : ''}${team['champion'] == true ? '  🏆' : ''}'),
                                                ),
                                            ])),
                                ])),
                        const Text('青：ポストシーズン進出　金：日本一／WS優勝（確認済みの試合記録による）',
                            style: TextStyle(fontSize: 10)),
                      ])));
        });
  }

  Widget player(Map<String, dynamic> p) {
    final status = p['status'];
    final color = status == 'active'
        ? const Color(0xFFE0F2E9)
        : status == 'retired'
            ? const Color(0xFFE5E7EB)
            : const Color(0xFFFFF3D6);
    return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(6),
        color: color,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['name'] ?? '—'}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
              '${p['value'] ?? '—'}${p['unit'] ?? ''}${p['year'] == null ? '' : '（${p['year']}年）'}'),
          if ('${p['team'] ?? ''}'.isNotEmpty)
            Text('${p['team']}', style: const TextStyle(fontSize: 11)),
          Text(
              status == 'active'
                  ? '現役'
                  : status == 'retired'
                      ? '引退'
                      : '現役区分未確認',
              style: const TextStyle(fontSize: 10)),
        ]));
  }

  Widget titles() {
    final seasons = listMapFromJson(data!['titles']);
    if (seasons.isEmpty) {
      return const Center(child: Text('個人タイトルはまだ登録されていません。'));
    }
    final categories = <String>{
      for (final s in seasons)
        for (final c in listMapFromJson(s['categories'])) '${c['label']}'
    }.toList();
    Widget gridRow(List<Widget> cells) => Table(
          columnWidths: const {0: FixedColumnWidth(150)},
          defaultColumnWidth: const FixedColumnWidth(190),
          border: TableBorder.all(color: Colors.grey.shade400),
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [TableRow(children: cells)],
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
          padding: EdgeInsets.all(6),
          child: Text('同率首位は全員表示。未確定年度は現在の首位。制度が異なる過去年度は登録済み成績の首位を表示します。')),
      Expanded(
          child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
            width: 150 + 190.0 * categories.length,
            child: Column(children: [
              gridRow([
                const Padding(
                    padding: EdgeInsets.all(8), child: Text('年度・リーグ')),
                for (final c in categories)
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(c,
                          style: const TextStyle(fontWeight: FontWeight.bold)))
              ]),
              Expanded(
                  child: ListView.builder(
                      itemCount: seasons.length,
                      itemBuilder: (context, index) {
                        final s = seasons[index];
                        return gridRow([
                          Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                  '${s['year']}年\n${s['league']}\n${s['provisional'] == true ? '現在の首位（未確定）' : ''}')),
                          for (final category in categories)
                            Padding(
                                padding: const EdgeInsets.all(4),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final c
                                          in listMapFromJson(s['categories']))
                                        if (c['label'] == category)
                                          for (final p
                                              in listMapFromJson(c['players']))
                                            player(p),
                                    ])),
                        ]);
                      })),
            ])),
      )),
    ]);
  }

  Widget recordComparison(String section) {
    final records = listMapFromJson(data![section]);
    if (records.isEmpty) {
      return const Center(child: Text('確認済みの記録はまだ登録されていません。'));
    }
    return ListView(children: [
      const Padding(
          padding: EdgeInsets.all(8),
          child: Text('緑：現役　灰：引退　黄：区分未確認。各記録を押すと出典・集計条件を表示します。')),
      for (final record in records)
        Card(
            child: InkWell(
          onTap: () => showStrengthSource(
              context,
              '${record['label']}',
              '${record['note'] ?? ''}\n${record['current_note'] ?? ''}\n確認日：${record['checked_at'] ?? '—'}',
              [
                for (final url in (record['sources'] as List? ?? [])) '$url',
                for (final p in listMapFromJson(record['current']))
                  if (p['source'] != null) '${p['source']}'
              ]),
          child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${record['label']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    if ('${record['note'] ?? ''}'.isNotEmpty)
                      Text('${record['note']}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54)),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                const Text('歴代記録',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                if (listMapFromJson(record['leaders']).isEmpty)
                                  const Text('確認済みデータなし'),
                                for (final p
                                    in listMapFromJson(record['leaders']))
                                  player({...p, 'unit': record['unit']}),
                              ])),
                          if (section != 'career') ...[
                            const SizedBox(width: 8),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  Text(
                                      '${widget.year}年の${section == 'streaks' ? '確認範囲の最長' : '首位記録'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  if (section == 'streaks' ||
                                      listMapFromJson(record['current'])
                                          .isEmpty)
                                    Text(
                                        '${record['current_note'] ?? '確認済みデータなし'}'),
                                  for (final p
                                      in listMapFromJson(record['current']))
                                    player({...p, 'unit': record['unit']}),
                                ]))
                          ],
                        ]),
                  ])),
        )),
    ]);
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
      if (mounted && id == request) setState(() => teams = result);
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
    if (teams == null) return const Center(child: CircularProgressIndicator());
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
