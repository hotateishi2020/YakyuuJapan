import '../widgets/collapsible_menu.dart';
import 'player_detail_dialog.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import '../widgets/baseball_loading.dart';
import '../logic/favorite_team.dart';
import 'package:flutter/material.dart';
import '../tools/json_utils.dart';
import 'strength_grids.dart';

class AgeRecordsBoard extends StatelessWidget {
  const AgeRecordsBoard({super.key, required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xff243449);
    const muted = Color(0xff718096);
    final labels = rows.map((r) => '${r['label']}').toSet().toList();
    if (labels.isEmpty) {
      return const Center(child: Text('年齢記録は未取得です'));
    }

    Widget entries(String label, String edge, String field) {
      final people = rows.where((r) => r['label'] == label && '${r[edge]}' == '1');
      String value(Map<String, dynamic> row) {
        if (field == 'age') {
          return '${row['age_label'] ?? (row['age_years'] == null ? '未取得' : '${row['age_years']}歳${row['age_days'] ?? 0}日')}';
        }
        return '${row[field] ?? '未取得'}';
      }

      final tone = edge == 'youngest' ? const Color(0xff176c88) : const Color(0xff925e25);
      if (field == 'name' && people.isNotEmpty) {
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final person in people) PlayerNameLink(player: person, child: Text(value(person), softWrap: false, style: const TextStyle(color: ink, fontWeight: FontWeight.w600))),
        ]);
      }
      return Text(people.isEmpty ? '未取得' : people.map(value).join('\n'),
          softWrap: false,
          style: TextStyle(
              color: people.isEmpty || field == 'date'
                  ? muted
                  : field == 'age'
                      ? tone
                      : ink,
              fontWeight: field == 'date' ? FontWeight.normal : FontWeight.w600));
    }

    Widget cell(Widget child, int column, double height, {bool header = false, bool alternate = false}) {
      final young = column >= 1 && column <= 3;
      final old = column >= 4;
      final background = header
          ? young
              ? const Color(0xff176c88)
              : old
                  ? const Color(0xff925e25)
                  : const Color(0xff34465f)
          : young
              ? Color(alternate ? 0xffe7f3f8 : 0xfff0f8fc)
              : old
                  ? Color(alternate ? 0xfffaefdf : 0xfffff7ec)
                  : Color(alternate ? 0xfff1f4f8 : 0xfff8fafc);
      return Container(
        height: height,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: background,
          border: column == 1 || column == 4 ? Border(left: BorderSide(color: header ? Colors.white24 : const Color(0xffd6e0e8))) : null,
        ),
        child: DefaultTextStyle(
          style: TextStyle(fontSize: header ? 12 : 13, height: 1.3, fontWeight: header ? FontWeight.w600 : FontWeight.normal, color: header ? Colors.white : ink),
          child: child,
        ),
      );
    }

    double rowHeight(String label) {
      final youngest = rows.where((r) => r['label'] == label && '${r['youngest']}' == '1').length;
      final oldest = rows.where((r) => r['label'] == label && '${r['oldest']}' == '1').length;
      final lines = youngest > oldest ? youngest : oldest;
      return (lines > 0 ? lines : 1) * 17.0 + 17;
    }

    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xffdfe6ee)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: Table(
                      key: const ValueKey('age-records-grid'),
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      border: const TableBorder(horizontalInside: BorderSide(color: Color(0xffe5eaf0), width: .5)),
                      children: [
                        TableRow(children: [
                          for (final (column, label) in const ['記録', '最年少・選手名', '年齢', '日時', '最年長・選手名', '年齢', '日時'].indexed) cell(Text(label, softWrap: false), column, 40, header: true),
                        ]),
                        for (var i = 0; i < labels.length; i++)
                          TableRow(
                            children: [
                              cell(Text(labels[i], softWrap: false, style: const TextStyle(fontWeight: FontWeight.w600)), 0, rowHeight(labels[i]), alternate: i.isOdd),
                              for (final (edgeIndex, edge) in ['youngest', 'oldest'].indexed)
                                for (final (fieldIndex, field) in ['name', 'age', 'date'].indexed) cell(entries(labels[i], edge, field), 1 + edgeIndex * 3 + fieldIndex, rowHeight(labels[i]), alternate: i.isOdd)
                            ],
                          )
                      ],
                    ),
                ),
              ),
          ),
          ),
        ),
      ),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Text('通算達成記録はNPB公式一覧の年齢・順位。「取得済み試合」は登録された試合と生年月日から計算した範囲内の記録で、歴代公認記録とは異なります。', style: TextStyle(fontSize: 11, height: 1.5, color: muted))),
    ]);
  }
}

class CountRecordsBoard extends StatefulWidget {
  const CountRecordsBoard({super.key, required this.records});
  final List<Map<String, dynamic>> records;
  @override
  State<CountRecordsBoard> createState() => _CountRecordsBoardState();
}

class _CountRecordsBoardState extends State<CountRecordsBoard> {
  final _ranks = ScrollController();
  final _body = ScrollController();
  bool _syncing = false;
  String? _selectedLabel;

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    final offset = from.offset.clamp(to.position.minScrollExtent, to.position.maxScrollExtent);
    if (offset == to.offset) return;
    _syncing = true;
    to.jumpTo(offset);
    _syncing = false;
  }

  @override
  void initState() {
    super.initState();
    _ranks.addListener(() => _sync(_ranks, _body));
    _body.addListener(() => _sync(_body, _ranks));
  }

  @override
  void dispose() {
    _ranks.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableRecords = widget.records
        .where((record) => !const {
              '新人王',
              '最優秀新人',
              '最優秀新人賞',
            }.contains('${record['label']}'.trim()))
        .toList();
    if (availableRecords.isEmpty) {
      return const Center(child: Text('回数記録は未取得です'));
    }
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final selected = availableRecords.any((record) => record['label'] == _selectedLabel)
        ? _selectedLabel! : '${availableRecords.first['label']}';
    final records = portrait
        ? [availableRecords.firstWhere((record) => record['label'] == selected)]
        : availableRecords;
    return LayoutBuilder(builder: (context, constraints) {
      final columnWidth = portrait ? (constraints.maxWidth - 64).clamp(1.0, double.infinity) : 190.0;
      final textWidth = (columnWidth - 21).clamp(1.0, double.infinity);
      final ranked = [
        for (final record in records)
          [
            for (var rank = 1; rank <= 20; rank++) listMapFromJson(record['leaders']).where((p) => int.tryParse('${p['rank']}') == rank && (num.tryParse('${p['value']}') ?? 0) >= 3).toList(),
          ].where((players) => players.isNotEmpty).toList(),
      ];
      final rowCount = ranked.fold<int>(0, (count, groups) => groups.length > count ? groups.length : count);
      const playerStyle = TextStyle(fontSize: 13, color: Colors.black87);
      const headerStyle = TextStyle(color: Colors.white, fontWeight: FontWeight.bold);
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      double textHeight(String text, TextStyle style, double width) {
        final painter = TextPainter(text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)), textDirection: direction, textScaler: scaler)..layout(maxWidth: width);
        final height = painter.height;
        painter.dispose();
        return height;
      }

      String playerLabel(Map<String, dynamic> player, int column) => '${player['name']}　${player['value']}${records[column]['unit'] ?? '回'}';
      final heights = [
        for (var rank = 0; rank < rowCount; rank++)
          ranked.asMap().entries.fold<double>(textHeight('${rank + 1}位', const TextStyle(fontWeight: FontWeight.bold), 43), (height, entry) {
                final players = rank < entry.value.length ? entry.value[rank] : <Map<String, dynamic>>[];
                final content = players.fold<double>(0, (sum, player) => sum + textHeight(playerLabel(player, entry.key), playerStyle, textWidth) + 6);
                return content > height ? content : height;
              }) +
              25,
      ];
      final headerHeight = records.fold<double>(textHeight('順位', headerStyle, 43), (height, record) {
            final content = textHeight('${record['label']}', headerStyle, textWidth);
            return content > height ? content : height;
          }) +
          25;
      Widget cell(Widget child, double width, double height, Color color) => Container(width: width, height: height, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), decoration: BoxDecoration(color: color, border: Border.all(color: const Color(0xffdfe4ec), width: .5)), child: child);
      Color rowColor(int index) => index.isEven ? Colors.white : const Color(0xfff6f8fb);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (portrait) MenuBand(level: 3, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(
            key: const ValueKey('count-records-picker'),
            value: selected,
            isExpanded: true,
            items: [for (final record in availableRecords)
              DropdownMenuItem(value: '${record['label']}', child: Text('${record['label']}'))],
            onChanged: (value) {
              if (value == null || value == selected) return;
              if (_body.hasClients) _body.jumpTo(0);
              if (_ranks.hasClients) _ranks.jumpTo(0);
              setState(() => _selectedLabel = value);
            },
          )),
        )),
        Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              width: 64,
              child: Column(children: [
                cell(const Text('順位', style: headerStyle), 64, headerHeight, const Color(0xff25324b)),
                Expanded(
                    child: ListView(
                  key: const ValueKey('count-records-ranks'),
                  controller: _ranks,
                  padding: EdgeInsets.zero,
                  children: [
                    for (var rank = 0; rank < rowCount; rank++) cell(Text('${rank + 1}位', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xff25324b))), 64, heights[rank], rowColor(rank)),
                  ],
                )),
              ])),
          Expanded(
              child: SingleChildScrollView(
            key: const ValueKey('count-records-horizontal'),
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: records.length * columnWidth,
                child: Column(children: [
                  Row(children: [
                    for (final record in records) cell(Text('${record['label']}', textAlign: TextAlign.center, style: headerStyle), columnWidth, headerHeight, const Color(0xff25324b)),
                  ]),
                  Expanded(
                      child: ListView(
                    key: const ValueKey('count-records-body'),
                    controller: _body,
                    padding: EdgeInsets.zero,
                    children: [
                      for (var rank = 0; rank < rowCount; rank++)
                        Row(children: [
                          for (var i = 0; i < records.length; i++)
                            cell(
                                rank >= ranked[i].length
                                    ? const Text('—', style: TextStyle(color: Colors.black38))
                                    : Column(mainAxisSize: MainAxisSize.min, children: [
                                        for (final player in ranked[i][rank]) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: PlayerNameLink(player: player, child: Text(playerLabel(player, i), textAlign: TextAlign.center, style: playerStyle))),
                                      ]),
                                columnWidth,
                                heights[rank],
                                rowColor(rank)),
                        ]),
                    ],
                  )),
                ])),
          )),
        ])),
        const Padding(padding: EdgeInsets.all(8), child: Text('元の順位が20位以内・3回以上の選手を表示。同順位は一つのセルにまとめ、表示上の順位は欠番を詰めています。取得済み年度成績・確定タイトルの集計。規定打席は球団試合数×3.1（端数切捨て）、1957年以降。打率3割は規定打席到達者。未取得年度は回数に含みません。', style: TextStyle(fontSize: 11))),
      ]);
    });
  }
}

class RegularHistoryBoard extends StatefulWidget {
  const RegularHistoryBoard({super.key, required this.rows});
  final List<Map<String, dynamic>> rows;
  @override
  State<RegularHistoryBoard> createState() => _RegularHistoryBoardState();
}

class _RegularHistoryBoardState extends State<RegularHistoryBoard> {
  String? selected;
  bool batting = false;
  @override
  Widget build(BuildContext context) {
    final teams = {for (final r in widget.rows) '${r['id_team']}': '${r['name_team']}'};
    final favorite = favoriteTeamRow(widget.rows);
    final id = teams.containsKey(selected)
        ? selected
        : favorite == null
            ? teams.keys.firstOrNull
            : '${favorite['id_team']}';
    final rows = widget.rows.where((r) => '${r['id_team']}' == id).map((r) => {...r, 'name_team': '${r['year']}年'}).toList();
    return Column(children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final e in teams.entries) Padding(padding: const EdgeInsets.all(3), child: ChoiceChip(label: Text(e.value), selected: id == e.key, onSelected: (_) => setState(() => selected = e.key)))])),
      Row(children: [
        for (final e in const {false: 'ポジション', true: '打順'}.entries) TextButton(onPressed: () => setState(() => batting = e.key), child: Text(e.value, style: TextStyle(fontWeight: batting == e.key ? FontWeight.bold : FontWeight.normal)))
      ]),
      Expanded(child: rows.isEmpty ? const Center(child: Text('この球団の年度別起用情報は未取得です')) : StrengthRegularGrid(key: ValueKey('$id:$batting'), teams: rows, battingOrder: batting, teamHeader: '年度')),
      if (rows.any((r) => r['source_label'] == 'スタメンデータベース')) const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text('過去年の先発起用はスタメンデータベース、氏名・成績は取得できた年度のNPB公式記録で補完。途中出場や先発・救援別投球回など未確認の項目は「—」で表示します。', style: TextStyle(fontSize: 11, color: Colors.black54))),
    ]);
  }
}

class RegularHistoryLoader extends StatefulWidget {
  const RegularHistoryLoader({super.key, required this.org, required this.year});
  final String org;
  final int year;
  @override
  State<RegularHistoryLoader> createState() => _RegularHistoryLoaderState();
}

class _RegularHistoryLoaderState extends State<RegularHistoryLoader> {
  List<Map<String, dynamic>>? rows;
  bool failed = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(RegularHistoryLoader old) {
    super.didUpdateWidget(old);
    if (old.org != widget.org || old.year != widget.year) load();
  }

  Future<void> load() async {
    final token = ++request;
    setState(() {
      rows = null;
      failed = false;
    });
    try {
      final response = await http.get(Env.api('/regular-history?org=${widget.org}&year=${widget.year}')).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw const FormatException();
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['regular_history'] is! List) throw const FormatException();
      if (mounted && token == request) {
        setState(() => rows = listMapFromJson(data['regular_history']));
      }
    } catch (_) {
      if (mounted && token == request) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(child: TextButton(onPressed: load, child: const Text('レギュラー情報を再読み込み')));
    }
    if (rows == null) return const Center(child: BaseballLoading());
    return RegularHistoryBoard(rows: rows!);
  }
}
