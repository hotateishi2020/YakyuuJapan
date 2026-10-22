import '../widgets/collapsible_menu.dart';
import 'player_detail_dialog.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../widgets/baseball_loading.dart';

const _allStarInk = Color(0xff25324b);
const _allStarBorder = Color(0xffe4e9f0);

const allStarPositions = [
  '先発投手',
  '中継投手',
  '抑え投手',
  '投手',
  '捕手',
  '一塁手',
  '二塁手',
  '三塁手',
  '遊撃手',
  '内野手',
  '外野手',
  'DH'
];

List<Map<String, dynamic>> allStarYearRows(
    Map<String, dynamic> data, int throughYear, String league) {
  final grouped = <String, Map<String, dynamic>>{};
  for (final player in listMapFromJson(data['players'])) {
    final year = int.tryParse('${player['year']}');
    if (year == null ||
        year > throughYear ||
        (league.isNotEmpty && player['league'] != league)) {
      continue;
    }
    final row = grouped.putIfAbsent(
        '$year:${player['league']}',
        () => {
              'year': year,
              'league': player['league'],
              'players': <Map<String, dynamic>>[]
            });
    (row['players'] as List<Map<String, dynamic>>).add(player);
  }
  for (final year in data['cancelled_years'] as List? ?? []) {
    if (year is int && year <= throughYear) {
      grouped['$year:cancelled'] = {
        'year': year,
        'league': '',
        'cancelled': true,
        'players': <Map<String, dynamic>>[]
      };
    }
  }
  return grouped.values.toList()
    ..sort((a, b) {
      final cmp = (b['year'] as int).compareTo(a['year'] as int);
      return cmp != 0 ? cmp : '${a['league']}'.compareTo('${b['league']}');
    });
}

class AllStarHistoryBoard extends StatefulWidget {
  const AllStarHistoryBoard({super.key, required this.year});
  final int year;
  @override
  State<AllStarHistoryBoard> createState() => _AllStarHistoryBoardState();
}

class _AllStarHistoryBoardState extends State<AllStarHistoryBoard> {
  Map<String, dynamic>? data;
  bool failed = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(AllStarHistoryBoard old) {
    super.didUpdateWidget(old);
    if (old.year != widget.year) load();
  }

  Future<void> load() async {
    final token = ++request;
    setState(() {
      data = null;
      failed = false;
    });
    try {
      final response = await http
          .get(Env.api('/allstar-history?year=${widget.year}'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw const FormatException();
      final parsed = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(response.bodyBytes)));
      if (parsed['players'] is! List) throw const FormatException();
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
        const Text('オールスター情報を取得できませんでした'),
        TextButton(onPressed: load, child: const Text('再読み込み'))
      ]));
    }
    if (data == null) return const Center(child: BaseballLoading());
    return AllStarHistoryGrid(
        key: ValueKey(widget.year), data: data!, throughYear: widget.year);
  }
}

class AllStarHistoryGrid extends StatefulWidget {
  const AllStarHistoryGrid(
      {super.key, required this.data, required this.throughYear});
  final Map<String, dynamic> data;
  final int throughYear;
  @override
  State<AllStarHistoryGrid> createState() => _AllStarHistoryGridState();
}

class _AllStarHistoryGridState extends State<AllStarHistoryGrid> {
  String league = '';
  int? selectedYear;
  final years = ScrollController(),
      body = ScrollController(),
      horizontal = ScrollController();
  bool syncing = false;
  void sync(ScrollController from, ScrollController to) {
    if (syncing || !from.hasClients || !to.hasClients) return;
    final target = from.offset
        .clamp(to.position.minScrollExtent, to.position.maxScrollExtent);
    if (target == to.offset) return;
    syncing = true;
    to.jumpTo(target);
    syncing = false;
  }

  @override
  void initState() {
    super.initState();
    years.addListener(() => sync(years, body));
    body.addListener(() => sync(body, years));
  }

  @override
  void dispose() {
    years.dispose();
    body.dispose();
    horizontal.dispose();
    super.dispose();
  }

  void select(String value) {
    if (years.hasClients) years.jumpTo(0);
    if (body.hasClients) body.jumpTo(0);
    setState(() => league = value);
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
        final availableYears = allStarYearRows(widget.data, widget.throughYear, '')
            .map((row) => row['year'] as int).toSet().toList()..sort((a, b) => b.compareTo(a));
        final year = availableYears.contains(selectedYear)
            ? selectedYear! : availableYears.firstOrNull ?? widget.throughYear;
        final shownLeague = portrait && league.isEmpty ? 'セ・リーグ' : league;
        final rows = allStarYearRows(widget.data, widget.throughYear, shownLeague)
            .where((row) => !portrait || row['year'] == year).toList();
        final grouped = <int, List<Map<String, dynamic>>>{};
        for (final row in rows) {
          grouped.putIfAbsent(row['year'] as int, () => []).add(row);
        }
        final entries = grouped.entries.toList();
        final columns = <(String, int, Color, Color)>[
          ('投手', 5, const Color(0xffedb9c8), const Color(0xfffff7f9)),
          ('捕手', 1, const Color(0xffb8cef3), const Color(0xfff5f8ff)),
          for (final p in ['一塁手', '二塁手', '三塁手', '遊撃手'])
            (p, 1, const Color(0xffecd68e), const Color(0xfffffcf3)),
          ('外野手', 2, const Color(0xffb7d9bf), const Color(0xfff5faf6)),
          ('DH', 1, const Color(0xffcbbbe9), const Color(0xfff9f6ff)),
        ];
        String position(Map<String, dynamic> player) {
          final value =
              '${player['display_position'] ?? player['position'] ?? ''}';
          return value.contains('投手')
              ? '投手'
              : value == '内野手'
                  ? '守備位置未確認'
                  : value.isEmpty
                      ? '区分未確認'
                      : value;
        }

        for (final row in rows) {
          for (final player in listMapFromJson(row['players'])) {
            final p = position(player);
            if (!columns.any((c) => c.$1 == p)) {
              columns.add(
                  (p, 1, const Color(0xffecd68e), const Color(0xfffffcf3)));
            }
          }
        }
        if (portrait && !columns.any((column) => column.$1 == '守備位置未確認')) {
          columns.add(('守備位置未確認', 1, const Color(0xffecd68e), const Color(0xfffffcf3)));
        }
        final scale =
            math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
        final maxLabels = rows
            .expand((r) => listMapFromJson(r['players']))
            .fold<int>(
                1,
                (count, player) => math.max(
                    count,
                    (player['selections'] as List? ?? ['選出区分未確認']).length +
                        (player['withdrawn'] == true ? 1 : 0)));
        final cellHeight = (26.0 + maxLabels * 16) * scale;
        final yearWidth = 80.0 * scale;
        final columnCount = columns.fold<int>(0, (sum, c) => sum + c.$2);
        final availableWidth =
            math.max(0.0, constraints.maxWidth - 24 - yearWidth);
        final fits = availableWidth / columnCount >= 72 * scale;
        final tableWidth = fits ? availableWidth : columnCount * 112.0 * scale;
        final width = tableWidth / columnCount;
        List<Map<String, dynamic>> players(
                Map<String, dynamic> row, String p) =>
            listMapFromJson(row['players'])
                .where((v) => position(v) == p)
                .toList();
        int count(Map<String, dynamic> row) => columns.fold<int>(4,
            (n, c) => math.max(n, (players(row, c.$1).length / c.$2).ceil()));
        double rowHeight(Map<String, dynamic> row) => row['cancelled'] == true
            ? cellHeight * 2
            : cellHeight * ((league.isEmpty ? .5 : 0) + count(row));
        final heights = [
          for (final entry in entries)
            entry.value.fold<double>(0, (sum, row) => sum + rowHeight(row))
        ];
        Widget cell(String text, double w, double h, Color color,
                {bool white = false}) =>
            Container(
              width: w,
              height: h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: _allStarBorder, width: .5)),
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: white ? Colors.white : _allStarInk)),
            );
        if (portrait) {
          final tableWidth = math.max(0.0, constraints.maxWidth - 24);
          final playerWidth = tableWidth / 4;
          final roster = rows.expand((row) => listMapFromJson(row['players'])).toList();
          final cancelled = rows.any((row) => row['cancelled'] == true);
          return ColoredBox(color: const Color(0xfff6f8fb), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              MenuBand(level: 3, child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: [
                  SizedBox(width: 92, child: DropdownButtonHideUnderline(child: DropdownButton<int>(
                    key: const ValueKey('allstar-year-picker'),
                    value: year,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 13, color: _allStarInk),
                    items: [for (final option in availableYears.isEmpty ? [year] : availableYears)
                      DropdownMenuItem(value: option, child: Text('$option年'))],
                    onChanged: (value) {
                      if (value == null || value == year) return;
                      if (body.hasClients) body.jumpTo(0);
                      setState(() => selectedYear = value);
                    },
                  ))),
                  for (final value in ['セ・リーグ', 'パ・リーグ'])
                    Expanded(child: Padding(padding: const EdgeInsets.only(left: 4),
                      child: ChoiceChip(
                        key: ValueKey('allstar-league-$value'),
                        showCheckmark: false,
                        selectedColor: const Color(0xffedeafa),
                        backgroundColor: Colors.white,
                        side: BorderSide(color: shownLeague == value ? const Color(0xffcbbfe6) : _allStarBorder),
                        shape: const StadiumBorder(),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text(value)),
                        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: shownLeague == value ? const Color(0xff65519c) : _allStarInk),
                        selected: shownLeague == value,
                        onSelected: (_) => select(value),
                      ))),
                ]),
              )),
              Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: DecoratedBox(decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _allStarBorder),
                  boxShadow: const [BoxShadow(color: Color(0x080f172a), blurRadius: 12, offset: Offset(0, 3))],
                ), child: ClipRRect(borderRadius: BorderRadius.circular(12),
                  child: cancelled ? const Center(child: Text('開催中止'))
                    : roster.isEmpty ? const Center(child: Text('この年度・リーグの名簿は未取得です'))
                    : ListView(controller: body, key: const ValueKey('allstar-portrait-body'),
                        padding: EdgeInsets.zero, children: [
                          for (final column in columns) Builder(builder: (context) {
                            final members = roster.where((player) => position(player) == column.$1).toList();
                            final rowCount = math.max(1, (members.length / 4).ceil());
                            return Column(key: ValueKey('allstar-position-${column.$1}'), children: [
                              cell(column.$1, tableWidth, 32 * scale, column.$3),
                              for (var r = 0; r < rowCount; r++) Row(children: [
                                for (var c = 0; c < 4; c++)
                                  if (r * 4 + c < members.length)
                                    _AllStarPlayerCell(player: members[r * 4 + c], width: playerWidth,
                                      height: cellHeight, color: column.$4)
                                  else cell('', playerWidth, cellHeight, column.$4),
                              ]),
                            ]);
                          }),
                        ]),
                )),
              )),
              Padding(padding: const EdgeInsets.all(8), child: Text(
                '${widget.data['first_year'] ?? 1951}年以降の名簿。2001年以前は歴代資料、2002年以降はNPB公式。守備位置未確認の選手は区分未確認欄に表示します。選手名をタップすると球団・選出方法・辞退情報を確認できます。内野手は同年度の守備成績・オールスター出場記録などをもとに各守備位置へ表示します。',
                style: const TextStyle(fontSize: 11, color: Colors.black54))),
            ],
          ));
        }

        Widget leagueBlock(Map<String, dynamic> row) {
          if (row['cancelled'] == true) {
            return cell('開催中止', tableWidth, rowHeight(row), Colors.white);
          }
          final central = row['league'] == 'セ・リーグ';
          return Column(children: [
            if (league.isEmpty)
              cell(
                  central
                      ? 'セ'
                      : row['league'] == 'パ・リーグ'
                          ? 'パ'
                          : '${row['league']}',
                  tableWidth,
                  cellHeight / 2,
                  central ? const Color(0xffc6e5d1) : const Color(0xffc5e3f5)),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final column in columns)
                SizedBox(
                    width: width * column.$2,
                    child: Column(children: [
                      for (var r = 0; r < count(row); r++)
                        Row(children: [
                          for (var c = 0; c < column.$2; c++)
                            if (r * column.$2 + c <
                                players(row, column.$1).length)
                              _AllStarPlayerCell(
                                  player: players(
                                      row, column.$1)[r * column.$2 + c],
                                  width: width,
                                  height: cellHeight,
                                  color: column.$4)
                            else
                              cell('', width, cellHeight, column.$4),
                        ]),
                    ])),
            ]),
          ]);
        }

        return ColoredBox(
            color: const Color(0xfff6f8fb),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final value in ['', 'セ・リーグ', 'パ・リーグ'])
                          ChoiceChip(
                              showCheckmark: false,
                              selectedColor: const Color(0xffedeafa),
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                  color: league == value
                                      ? const Color(0xffcbbfe6)
                                      : _allStarBorder),
                              shape: const StadiumBorder(),
                              labelStyle: TextStyle(
                                  color: league == value
                                      ? const Color(0xff65519c)
                                      : _allStarInk,
                                  fontWeight: FontWeight.w600),
                              label: Text(value.isEmpty ? '両リーグ' : value),
                              selected: league == value,
                              onSelected: (_) => select(value)),
                      ])),
                  Expanded(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                          child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _allStarBorder),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x080f172a),
                                      blurRadius: 12,
                                      offset: Offset(0, 3))
                                ],
                              ),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: entries.isEmpty
                                      ? const Center(
                                          child: Text('この年度までの名簿は未取得です'))
                                      : Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                              SizedBox(
                                                  width: yearWidth,
                                                  child: Column(children: [
                                                    cell('年度', yearWidth,
                                                        cellHeight, _allStarInk,
                                                        white: true),
                                                    Expanded(
                                                        child: ListView.builder(
                                                            key: const ValueKey(
                                                                'allstar-years'),
                                                            controller: years,
                                                            padding:
                                                                EdgeInsets.zero,
                                                            itemCount:
                                                                entries.length,
                                                            itemExtentBuilder:
                                                                (i, _) =>
                                                                    heights[i],
                                                            itemBuilder:
                                                                (_, i) => cell(
                                                                    '${entries[i].key}',
                                                                    yearWidth,
                                                                    heights[i],
                                                                    _allStarInk,
                                                                    white:
                                                                        true))),
                                                  ])),
                                              Expanded(
                                                  child: Scrollbar(
                                                controller: horizontal,
                                                thumbVisibility: true,
                                                child: SingleChildScrollView(
                                                    key: const ValueKey(
                                                        'allstar-horizontal'),
                                                    controller: horizontal,
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: SizedBox(
                                                        width: tableWidth,
                                                        child: Column(
                                                            children: [
                                                              Row(children: [
                                                                for (final c
                                                                    in columns)
                                                                  cell(
                                                                      c.$1,
                                                                      width *
                                                                          c.$2,
                                                                      cellHeight,
                                                                      c.$3)
                                                              ]),
                                                              Expanded(
                                                                  child: ListView.builder(
                                                                      key: const ValueKey('allstar-body'),
                                                                      controller: body,
                                                                      padding: EdgeInsets.zero,
                                                                      itemCount: entries.length,
                                                                      itemExtentBuilder: (i, _) => heights[i],
                                                                      itemBuilder: (_, i) => Column(children: [
                                                                            for (final row
                                                                                in entries[i].value)
                                                                              leagueBlock(row),
                                                                          ]))),
                                                            ]))),
                                              )),
                                            ]))))),
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                          '${widget.data['first_year'] ?? 1951}年以降の名簿。2001年以前は歴代資料、2002年以降はNPB公式。守備位置未確認の選手は区分未確認欄に表示します。選手名をタップすると球団・選出方法・辞退情報を確認できます。内野手は同年度の守備成績・オールスター出場記録などをもとに各守備位置へ表示します。',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54))),
                ]));
      });
}

class _AllStarPlayerCell extends StatelessWidget {
  const _AllStarPlayerCell(
      {required this.player,
      required this.width,
      required this.height,
      required this.color});
  final Map<String, dynamic> player;
  final double width, height;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final details = [
      '${player['name'] ?? ''}',
      '${player['team'] ?? ''}',
      '${player['position'] ?? ''}',
      ...(player['selections'] as List? ?? ['選出区分未確認']).map((v) => '$v'),
      if (player['withdrawn'] == true) '出場辞退',
      if (player['display_position'] != null)
        '表示位置：${player['display_position']}（${player['position_basis'] ?? '同年度 ${player['position_games']}試合'}）',
      '${player['position_source'] ?? ''}',
      '${player['source'] ?? ''}',
    ].where((v) => v.isNotEmpty).join('\n');
    return Tooltip(
        message: details,
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
              color: color,
              border: Border.all(color: _allStarBorder, width: .5)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            PlayerNameLink(
                player: player,
                child: Text('${player['name'] ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _allStarInk))),
            for (final selection in [
              ...(player['selections'] as List? ?? ['選出区分未確認']),
              if (player['withdrawn'] == true) '出場辞退',
            ])
              Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                      color: switch (selection) {
                        'ファン投票' => const Color(0xfff7e7b5),
                        '選手間投票' => const Color(0xffd9e8fb),
                        '監督選抜' => const Color(0xffe6e9ee),
                        '出場辞退' => const Color(0xfff7d7dc),
                        _ => const Color(0xffe6def3),
                      },
                      borderRadius: BorderRadius.circular(3)),
                  child: Text('$selection',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 9, height: 1.3, color: _allStarInk))),
          ]),
        ));
  }
}
