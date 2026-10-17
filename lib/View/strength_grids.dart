import 'team_section_layout.dart';
import '../logic/roster_leadership.dart';
import 'player_detail_dialog.dart';
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
  bool _battingOrder = false;
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

  Iterable<String> get _slots => _battingOrder
      ? [for (var i = 1; i <= 9; i++) '$i']
      : [
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
            if (!TeamSectionLayout.embedded(context)) Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: const Text('守備位置別'),
                  selected: !_battingOrder,
                  onSelected: (_) => setState(() => _battingOrder = false)),
              ChoiceChip(
                  label: const Text('打順別'),
                  selected: _battingOrder,
                  onSelected: (_) => setState(() => _battingOrder = true)),
            ]),
            Row(children: [
              _fixedCell('球団', Colors.grey.shade200, Colors.black87,
                  height: 44, width: columnWidth),
              Expanded(
                  child: sectionScrollView(context, 
                controller: _header,
                physics: const NeverScrollableScrollPhysics(),
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final slot in _slots)
                    _fixedCell(
                        (_battingOrder
                            ? '$slot番'
                            : pitcherAceSlots[slot] ??
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
            SectionExpanded(
                child: SectionScrollbar(
              controller: _horizontal,
              thumbVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: sectionScrollView(context, 
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
                              child: sectionScrollView(context, 
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
    final selected = _battingOrder
        ? selectRegularGroups(listMapFromJson(team['batting_order']))
        : {
            ...selectRegularGroups(listMapFromJson(team['positions'])),
            ...selectPitcherAces(team)
          };
    if (!_battingOrder) selected.addAll(selectBenchRegulars(team, selected));
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
                        Expanded(child:PlayerNameLink(player:{...selected[slot]![i],'name':regularPlayerName(selected[slot]![i],roster),'id_team':team['id_team']},child:Center(child:FittedBox(fit:BoxFit.scaleDown,child:Text(regularPlayerName(selected[slot]![i],roster),style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)))))),
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

class StrengthRosterGrid extends StatefulWidget {
  const StrengthRosterGrid({super.key, required this.team, required this.year});
  final Map<String, dynamic> team;
  final int year;
  @override
  State<StrengthRosterGrid> createState() => _StrengthRosterGridState();
}

class _StrengthRosterGridState extends State<StrengthRosterGrid> {
  Map<String, dynamic> get team => widget.team;
  int get year => widget.year;
  bool _usageOrder = true;
  @override
  Widget build(BuildContext context) => Column(children: [
        if (!TeamSectionLayout.embedded(context)) Row(children: [
          for (final usage in [false, true])
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                    label: Text(usage ? '起用順' : '年齢順'),
                    selected: _usageOrder == usage,
                    onSelected: (_) => setState(() => _usageOrder = usage))),
        ]),
        SectionExpanded(child: _grid(context)),
      ]);
  static const _minColumnWidth = 104.0 * 0.7;
  Widget _grid(BuildContext context) {
    final roster = listMapFromJson(team['roster']);
    if (roster.isEmpty) return const Center(child: Text('選手一覧はまだ登録されていません。'));
    final positions = [
      '先発',
      '中継ぎ',
      '捕手',
      '一塁',
      '二塁',
      '三塁',
      '遊撃',
      '左翼',
      '中堅',
      '右翼'
    ];
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final player in roster) {
      final rawPosition = rosterPosition(player, team);
      final pos = rawPosition == '抑え' ? '中継ぎ' : rawPosition;
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
        '左',
        '右',
        if ((groups[pos] ?? []).any((p) => p[field] == '両')) '両',
      ];
      for (final hand in hands) {
        columns.add((position: pos, hand: hand));
      }
    }
    final ages = _usageOrder
        ? <int?>[1, 2, 3, 4, 0]
        : (roster.map((p) => rosterAge(p, year)).toSet().toList()
          ..sort((a, b) => (b ?? -1).compareTo(a ?? -1)));
    if (_usageOrder) {
      for (final players in groups.values) {
        players.sort((a, b) {
          final av = rosterWorkload(a, team, rosterMainLevel(a));
          final bv = rosterWorkload(b, team, rosterMainLevel(b));
          final order = (bv ?? -1).compareTo(av ?? -1);
          return order != 0 ? order : '${a['name']}'.compareTo('${b['name']}');
        });
      }
    }
    return LayoutBuilder(builder: (context, constraints) {
      final columnWidth = (constraints.maxWidth / (columns.length + 1))
          .clamp(_minColumnWidth, double.infinity);
      return _WideGrid(
        child: SizedBox(
          width: columnWidth * (columns.length + 1),
          child: Column(children: [
            Row(children: [
              _rosterHeader(_usageOrder ? '起用' : '年齢', columnWidth,
                  _usageOrder ? Colors.black : Colors.grey.shade200, _usageOrder ? Colors.white : Colors.black87),
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
                  '', columnWidth, _usageOrder ? Colors.black : Colors.grey.shade200, _usageOrder ? Colors.white : Colors.black87),
              for (final col in columns)
                _rosterHeader(
                    '${col.hand}${_pitching(col.position) ? '投げ' : '打ち'}',
                    columnWidth,
                    _positionColor(col.position),
                    _positionForeground(col.position)),
            ]),
            SectionExpanded(
                child: sectionScrollView(context, 
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
                                color: _usageOrder ? Colors.black : Colors.grey.shade100,
                                child: _cell(_usageOrder
                                    ? (age == 0 ? '起用未確認' : '$age軍')
                                    : (age == null ? '不明' : '$age歳'),
                                    color: _usageOrder ? Colors.white : Colors.black87)),
                            for (final position in positions)
                              Container(
                                color: Color.lerp(Colors.white,
                                    _positionColor(position), 0.12),
                                child: _positionPlayers(
                                    position,
                                    (groups[position] ?? [])
                                        .where((p) =>
                                            (_usageOrder
                                                ? rosterMainLevel(p)
                                                : rosterAge(p, year)) ==
                                            age)
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
                          '起用順は最多出場の軍に配置し、投手は投球回、野手は打席数の降順。未取得の数値は末尾に表示。\n年齢：${year == DateTime.now().year ? '本日時点' : '$year年末時点'}／投手は投げ腕、野手は打席で分類\n支配下・育成／起用が多い軍を併記。契＝契約満了、FA＝FA権あり、退＝退団決定。確認済みの情報のみ表示。\n起用位置は1軍から順に2〜4軍の取得済み記録で判定（内野は3軍まで）。判定できない投手は中継ぎ、外野手は右翼、内野手は一塁に「起用不明」と表示。',
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
              Expanded(child: hand('左')),
              Expanded(
                  child: Container(
                      decoration: BoxDecoration(
                          border: Border(
                              left: BorderSide(color: Colors.grey.shade300))),
                      child: hand('右'))),
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

  Widget _fitRosterText(String text,
          {bool bold = false, double size = 10, Color? color}) =>
      FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(text,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                  fontSize: size,
                  color: color,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)));

  Widget _player(Map<String, dynamic> p, String position) {
    final departure = rosterDepartureLabel(p);
    final firstTeamRow = _usageOrder && rosterMainLevel(p) == 1;
    final leadership = rosterLeadershipRoles(p, team, year);
    final marks = [
      if (usageInt(p['contract_end_year']) == year) '契',
      if (p['fa_eligible'] == true) 'FA',
      if (p['departure_confirmed'] == true) '退'
    ];
    return Tooltip(
        message: [
          if (p['lower_level_usage'] is Map)
            for (final entry in (p['lower_level_usage'] as Map).entries)
              '${entry.key}軍起用：${entry.value['coverage'] == 'verified_partial' ? '公開記録の一部' : '公式戦'} ${entry.value['appearances']}試合',
          if (p['status_as_of'] != null) '確認日：${p['status_as_of']}',
          if (p['level_appearances'] is Map)
            '出場数：${(p['level_appearances'] as Map).entries.map((e) => '${e.key}軍 ${e.value}').join('／')}',
        ].join('\n'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: departure != null
                  ? Colors.white
                  : Color.lerp(Colors.white, _positionColor(position),
                      rosterCardTint(p)),
              borderRadius: BorderRadius.circular(4)),
          child: DefaultTextStyle.merge(
              style: TextStyle(color: departure != null ? Colors.grey : null),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (leadership.isNotEmpty)
                      Wrap(spacing: 4, runSpacing: 3, children: [
                        for (final role in leadership)
                          Tooltip(
                            message: '$year年 ${role.label}${role.detail.isEmpty ? '' : '（${role.detail}）'}',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC143C),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: _fitRosterText(role.label, bold: true, size: 10,
                                color: Colors.white),
                            ),
                          ),
                      ]),
                    if (leadership.isNotEmpty) const SizedBox(height: 3),
                    PlayerNameLink(player:{...p,'id_team':team['id_team']},child:_fitRosterText(
                        '${p['name']}${marks.isEmpty ? '' : ' 【${marks.join('・')}】'}',
                        bold: true,
                        size: 12)),
                    if (departure != null)
                      _fitRosterText(departure, color: Colors.red, bold: true),
                    if (rosterUsageUnknown(p, team)) _fitRosterText('（起用不明）'),
                    if (!firstTeamRow) _fitRosterText(rosterLevel(p)),
                    if (_usageOrder)
                      _fitRosterText(
                          rosterWorkloadLabel(p, team, rosterMainLevel(p))),
                    if (p['registration'] != null &&
                        !(firstTeamRow && p['registration'] == '支配下'))
                      _fitRosterText('${p['registration']}'),
                  ])),
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
  Widget build(BuildContext context) => SectionScrollbar(
        controller: _controller,
        thumbVisibility: true,
        scrollbarOrientation: ScrollbarOrientation.top,
        child: sectionScrollView(context, 
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 12),
            child: widget.child),
      );
}
