import 'package:flutter/material.dart';
import '../logic/strength_usage.dart';
import '../logic/strength_analytics.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';

class StrengthRegularGrid extends StatefulWidget {
  const StrengthRegularGrid({super.key, required this.teams});
  final List<Map<String, dynamic>> teams;
  @override
  State<StrengthRegularGrid> createState() => _StrengthRegularGridState();
}

class _StrengthRegularGridState extends State<StrengthRegularGrid> {
  final _horizontal = ScrollController();
  final _header = ScrollController();
  final _vertical = ScrollController();

  @override
  void initState() {
    super.initState();
    _horizontal.addListener(_syncHeader);
  }

  void _syncHeader() {
    if (_header.hasClients && _horizontal.hasClients) {
      _header.jumpTo(
          _horizontal.offset.clamp(0.0, _header.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _horizontal.removeListener(_syncHeader);
    _horizontal.dispose();
    _header.dispose();
    _vertical.dispose();
    super.dispose();
  }

  Iterable<String> get _slots => [
        ...pitcherAceSlots.keys,
        ...usagePositions.keys.where((slot) => slot != 'P'),
        ...benchRegularSlots.keys
      ];
  Color _positionColor(String slot) => switch (slot) {
        'PH_L' ||
        'PH_R' ||
        'PR' ||
        'DEF_IF' ||
        'DEF_OF' =>
          const Color(0xFF757575),
        'SP_L' || 'SP_R' || 'RP_L' || 'RP_R' || 'CL' => const Color(0xFFEF5350),
        'C' => const Color(0xFF2196F3),
        '1B' || '2B' || '3B' || 'SS' => const Color(0xFFFFD54F),
        'LF' || 'CF' || 'RF' => const Color(0xFF43A047),
        _ => const Color(0xFF9C27B0),
      };
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth / (_slots.length + 1))
            .clamp(128.0, double.infinity);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncHeader();
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              _fixedCell('球団', Colors.grey.shade200, Colors.black87,
                  height: 44, width: columnWidth),
              Expanded(
                  child: SingleChildScrollView(
                controller: _header,
                physics: const NeverScrollableScrollPhysics(),
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final slot in _slots)
                    _fixedCell(
                        (pitcherAceSlots[slot] ??
                            usagePositions[slot] ??
                            benchRegularSlots[slot])!,
                        _positionColor(slot),
                        ['1B', '2B', '3B', 'SS'].contains(slot)
                            ? Colors.black87
                            : Colors.white,
                        height: 44,
                        width: columnWidth),
                ]),
              )),
            ]),
            Expanded(
                child: Scrollbar(
              controller: _horizontal,
              thumbVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                key: const ValueKey('regular-vertical-scroll'),
                controller: _vertical,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(children: [
                            for (final team in widget.teams)
                              _fixedCell(
                                  '${team['name_team']}',
                                  parseColorNameOrNull(
                                          '${team['color_back']}') ??
                                      Colors.blueGrey,
                                  parseColorNameOrNull(
                                          '${team['color_font']}') ??
                                      Colors.white,
                                  height: 84,
                                  width: columnWidth),
                          ]),
                          Expanded(
                              child: SingleChildScrollView(
                            key: const ValueKey('regular-horizontal-scroll'),
                            controller: _horizontal,
                            scrollDirection: Axis.horizontal,
                            child: Table(
                              defaultColumnWidth: FixedColumnWidth(columnWidth),
                              border:
                                  TableBorder.all(color: Colors.grey.shade600),
                              children: [
                                for (final team in widget.teams) _row(team)
                              ],
                            ),
                          )),
                        ]),
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                            '先発エースは左右別の先発投球回最多、リリーフエースは守護神を除く左右別のホールド最多（同数は救援投球回）、守護神はセーブ最多。WHIPはシーズン通算。守備位置別のスタメン数・起用率。各位置の最多スタメン数の70%以上の選手も表示します。重複選手は起用率の高い位置を優先し、追加の選手は薄い背景で表示します。途中出場は既存レギュラーを除外し、各項目の最多起用者とその70%以上を表示。両打ちは左右の候補とし重複表示しません。代守は出場時の守備位置で分類します。',
                            style: TextStyle(fontSize: 12))),
                  ],
                ),
              ),
            )),
          ],
        );
      });

  Widget _fixedCell(String label, Color background, Color foreground,
          {required double height, required double width}) =>
      Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
              color: background,
              border: Border.all(color: Colors.grey.shade600)),
          child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1,
                  style: TextStyle(fontSize: 12, color: foreground))));

  TableRow _row(Map<String, dynamic> team) {
    final selected = {
      ...selectRegularGroups(listMapFromJson(team['positions'])),
      ...selectPitcherAces(team)
    };
    selected.addAll(selectBenchRegulars(team, selected));
    final roster = listMapFromJson(team['roster']);
    final teamColor =
        parseColorNameOrNull('${team['color_back']}') ?? Colors.blueGrey;
    return TableRow(children: [
      for (final slot in _slots)
        SizedBox(
          height: 84,
          child: (selected[slot] ?? []).isEmpty
              ? ColoredBox(
                  color: benchRegularSlots.containsKey(slot)
                      ? Color.lerp(Colors.white, _positionColor(slot), 0.24)!
                      : Colors.transparent,
                  child: const Center(child: Text('—')))
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < selected[slot]!.length; i++)
                    Expanded(
                        child: Container(
                      decoration: BoxDecoration(
                          color: Color.lerp(Colors.white, _positionColor(slot),
                              i == 0 ? 0.24 : 0.10),
                          border: Border(
                            bottom: BorderSide(
                                color:
                                    Color.lerp(teamColor, Colors.white, 0.50)!,
                                width: 10),
                            left: i == 0
                                ? BorderSide.none
                                : const BorderSide(color: Color(0xFF757575)),
                          )),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      child: Column(children: [
                        _regularLine(
                            regularPlayerName(selected[slot]![i], roster),
                            bold: true),
                        if (pitcherAceSlots.containsKey(slot)) ...[
                          _regularLine(
                              'WHIP ${metricValue(selected[slot]![i]['whip'], 2)}'),
                          _regularLine(slot == 'CL'
                              ? '${usageInt(selected[slot]![i]['saves'])}セーブ'
                              : slot.startsWith('RP')
                                  ? '${usageInt(selected[slot]![i]['holds'])}ホールド'
                                  : inningsLabel(usageInt(
                                      selected[slot]![i]['starter_outs']))),
                        ] else ...[
                          _regularLine(
                              '${usageInt(selected[slot]![i]['count'])}${benchRegularSlots.containsKey(slot) ? '回' : '試合'}'),
                          _regularLine(
                              '${((selected[slot]![i]['usage_rate'] as double) * 100).toStringAsFixed(1)}%'),
                          _regularLine(battingMetricLabel(
                              strengthPlayerMetrics(team, selected[slot]![i]))),
                        ],
                      ]),
                    )),
                ]),
        ),
    ]);
  }

  Widget _regularLine(String text, {bool bold = false}) => Expanded(
        child: Center(
            child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(text,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            bold ? FontWeight.bold : FontWeight.normal)))),
      );
}

Widget _cell(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
    child: Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: color)));

class StrengthRosterGrid extends StatelessWidget {
  const StrengthRosterGrid({super.key, required this.team, required this.year});
  final Map<String, dynamic> team;
  final int year;
  static const _minColumnWidth = 104.0 * 0.7;
  @override
  Widget build(BuildContext context) {
    final roster = listMapFromJson(team['roster']);
    if (roster.isEmpty) return const Center(child: Text('選手一覧はまだ登録されていません。'));
    final positions = ['先発', '中継ぎ', '捕手', '一塁', '二塁', '三塁', '遊撃', '外野手'];
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final player in roster) {
      final rawPosition = rosterPosition(player, team);
      final pos = ['左翼', '中堅', '右翼'].contains(rawPosition)
          ? '外野手'
          : rawPosition == '抑え'
              ? '中継ぎ'
              : rawPosition;
      if (!positions.contains(pos)) {
        final after = {'投手': '中継ぎ', '内野手': '遊撃', '外野手': '右翼'}[pos];
        if (after == null) {
          positions.add(pos);
        } else {
          positions.insert(positions.indexOf(after) + 1, pos);
        }
      }
      groups.putIfAbsent(pos, () => []).add(player);
    }
    final columns = <({String position, String hand})>[];
    for (final pos in positions) {
      final pitching = ['先発', '中継ぎ', '抑え', '投手'].contains(pos);
      final field = pitching ? 'throws' : 'bats';
      final hands = [
        '右',
        '左',
        if ((groups[pos] ?? []).any((p) => p[field] == '両')) '両',
      ];
      for (final hand in hands) {
        columns.add((position: pos, hand: hand));
      }
    }
    final ages = roster.map((p) => rosterAge(p, year)).toSet().toList()
      ..sort((a, b) => (b ?? -1).compareTo(a ?? -1));
    return LayoutBuilder(builder: (context, constraints) {
      final columnWidth = (constraints.maxWidth / (columns.length + 1))
          .clamp(_minColumnWidth, double.infinity);
      return _WideGrid(
        child: SizedBox(
          width: columnWidth * (columns.length + 1),
          child: Column(children: [
            Row(children: [
              _rosterHeader(
                  '年齢', columnWidth, Colors.grey.shade200, Colors.black87),
              for (final position in positions)
                _rosterHeader(
                    position,
                    columnWidth *
                        columns.where((c) => c.position == position).length,
                    _positionColor(position),
                    _positionForeground(position)),
            ]),
            Row(children: [
              _rosterHeader(
                  '', columnWidth, Colors.grey.shade200, Colors.black87),
              for (final col in columns)
                _rosterHeader(
                    '${col.hand}${_pitching(col.position) ? '投げ' : '打ち'}',
                    columnWidth,
                    _positionColor(col.position),
                    _positionForeground(col.position)),
            ]),
            Expanded(
                child: SingleChildScrollView(
              key: const ValueKey('roster-vertical-scroll'),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Table(
                      defaultColumnWidth: FixedColumnWidth(columnWidth),
                      columnWidths: {
                        0: FixedColumnWidth(columnWidth),
                        for (var i = 0; i < positions.length; i++)
                          i + 1: FixedColumnWidth(columnWidth *
                              columns
                                  .where((c) => c.position == positions[i])
                                  .length),
                      },
                      border: TableBorder.all(color: Colors.grey.shade300),
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.intrinsicHeight,
                      children: [
                        for (final age in ages)
                          TableRow(children: [
                            ColoredBox(
                                color: Colors.grey.shade100,
                                child: _cell(age == null ? '不明' : '$age歳')),
                            for (final position in positions)
                              Container(
                                color: Color.lerp(Colors.white,
                                    _positionColor(position), 0.12),
                                child: _positionPlayers(
                                    position,
                                    (groups[position] ?? [])
                                        .where((p) => rosterAge(p, year) == age)
                                        .toList(),
                                    columns.any((c) =>
                                        c.position == position &&
                                        c.hand == '両')),
                              ),
                          ]),
                      ],
                    ),
                    Padding(
                      key: const ValueKey('roster-notes'),
                      padding: const EdgeInsets.all(8),
                      child: Text(
                          '年齢：${year == DateTime.now().year ? '本日時点' : '$year年末時点'}／投手は投げ腕、野手は打席で分類\n支配下・育成／起用が多い軍を併記。契＝契約満了、FA＝FA権あり、退＝退団決定。確認済みの情報のみ表示。\n一軍の起用位置が未確認の選手は「投手・内野手・外野手」の列に表示。',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
            )),
          ]),
        ),
      );
    });
  }

  Widget _positionPlayers(
      String position, List<Map<String, dynamic>> players, bool both) {
    Widget hand(String value) => Padding(
          padding: const EdgeInsets.all(4),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final player in players)
              if (_hand(player, position) == value) _player(player, position),
          ]),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
          flex: 2,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: hand('右')),
              Expanded(
                  child: Container(
                      decoration: BoxDecoration(
                          border: Border(
                              left: BorderSide(color: Colors.grey.shade300))),
                      child: hand('左'))),
            ]),
            if (players.any((p) => _hand(p, position) == '不明')) hand('不明'),
          ])),
      if (both)
        Expanded(
            child: Container(
                decoration: BoxDecoration(
                    border:
                        Border(left: BorderSide(color: Colors.grey.shade300))),
                child: hand('両'))),
    ]);
  }

  bool _pitching(String position) =>
      ['先発', '中継ぎ', '抑え', '投手'].contains(position);
  String _hand(Map<String, dynamic> player, String position) {
    final value = player[_pitching(position) ? 'throws' : 'bats'];
    return ['右', '左', '両'].contains(value) ? '$value' : '不明';
  }

  Color _positionColor(String position) => switch (position) {
        '先発' || '中継ぎ' || '抑え' || '投手' => const Color(0xFFEF5350),
        '捕手' => const Color(0xFF2196F3),
        '一塁' || '二塁' || '三塁' || '遊撃' || '内野手' => const Color(0xFFFFD54F),
        '左翼' || '中堅' || '右翼' || '外野手' => const Color(0xFF43A047),
        '指名打者' => const Color(0xFF9C27B0),
        _ => Colors.blueGrey,
      };
  Color _positionForeground(String position) =>
      ['一塁', '二塁', '三塁', '遊撃', '内野手'].contains(position)
          ? Colors.black87
          : Colors.white;

  Widget _rosterHeader(
          String label, double width, Color background, Color foreground) =>
      Container(
          width: width,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: background,
              border: Border.all(color: Colors.grey.shade300)),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 12, color: foreground))));

  Widget _fitRosterText(String text, {bool bold = false, double size = 10}) =>
      FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(text,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                  fontSize: size,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)));

  Widget _player(Map<String, dynamic> p, String position) {
    final marks = [
      if (usageInt(p['contract_end_year']) == year) '契',
      if (p['fa_eligible'] == true) 'FA',
      if (p['departure_confirmed'] == true) '退'
    ];
    return Tooltip(
        message: [
          if (p['status_source'] != null) '出典：${p['status_source']}',
          if (p['status_as_of'] != null) '確認日：${p['status_as_of']}',
          if (p['level_appearances'] is Map)
            '出場数：${(p['level_appearances'] as Map).entries.map((e) => '${e.key}軍 ${e.value}').join('／')}',
        ].join('\n'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: Color.lerp(
                  Colors.white, _positionColor(position), rosterCardTint(p)),
              borderRadius: BorderRadius.circular(4)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _fitRosterText(
                '${p['name']}${marks.isEmpty ? '' : ' 【${marks.join('・')}】'}',
                bold: true,
                size: 12),
            _fitRosterText(rosterLevel(p)),
            if (p['registration'] != null)
              _fitRosterText('${p['registration']}'),
          ]),
        ));
  }
}

class _WideGrid extends StatefulWidget {
  const _WideGrid({required this.child});
  final Widget child;
  @override
  State<_WideGrid> createState() => _WideGridState();
}

class _WideGridState extends State<_WideGrid> {
  final _controller = ScrollController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        scrollbarOrientation: ScrollbarOrientation.top,
        child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 12),
            child: widget.child),
      );
}
