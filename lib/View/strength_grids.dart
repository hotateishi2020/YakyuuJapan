import 'dart:convert';
import 'package:flutter/services.dart';
import '../logic/roster_transfer_status.dart';
import '../logic/display_settings.dart';
import 'strength_vertical_label.dart';
import '../widgets/navigation_picker.dart';
import 'compact_layout.dart';
import 'team_section_layout.dart';
import '../logic/roster_contract_status.dart';
import '../logic/roster_leadership.dart';
import 'player_detail_dialog.dart';
import 'package:flutter/material.dart';
import '../logic/strength_usage.dart';
import '../logic/strength_analytics.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';

class StrengthRegularGrid extends StatefulWidget {
  const StrengthRegularGrid({super.key, required this.teams, this.battingOrder, this.bench = false, this.columnWidth, this.teamHeader = '球団'});
  /// 固定表示する場合のモード。球団ページでは守備位置・打順・代打代走のグリッドを並べる。
  final bool? battingOrder;
  final bool bench;
  final double? columnWidth;
  final String teamHeader;
  final List<Map<String, dynamic>> teams;
  @override
  State<StrengthRegularGrid> createState() => _StrengthRegularGridState();
}

class _StrengthRegularGridState extends State<StrengthRegularGrid> {
  bool _selectedBattingOrder = false;
  bool _selectedBench = false;
  bool get _bench => widget.bench || (widget.battingOrder == null && _selectedBench);
  bool get _battingOrder => widget.battingOrder ?? _selectedBattingOrder;
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

  Iterable<String> get _slots => _bench
      ? benchRegularSlots.keys
      : _battingOrder
      ? [for (var i = 1; i <= 9; i++) '$i']
      : [
          if (widget.teamHeader == '年度' && widget.teams.any((t) => listMapFromJson(t['pitching_workload']).isEmpty && listMapFromJson(t['positions']).any((p) => p['slot'] == 'P'))) 'P',
          ...pitcherAceSlots.keys,
          ...usagePositions.keys.where((slot) => slot != 'P'),
        ];
  int get _positionSlotCount => pitcherAceSlots.length + usagePositions.length - 1 +
      (widget.teamHeader == '年度' && widget.teams.any((t) => listMapFromJson(t['pitching_workload']).isEmpty && listMapFromJson(t['positions']).any((p) => p['slot'] == 'P')) ? 1 : 0);
  double _commonColumnWidth(double width, bool hideTeam) {
    final fitted = width / (_positionSlotCount + (hideTeam ? 0 : 1));
    // Landscape position, batting-order and bench grids share this width.
    // A minimum width here would push the DH column outside the viewport.
    return hideTeam && !compactBaseballLayout(context)
        ? fitted
        : fitted.clamp(128.0, double.infinity);
  }
  Color _positionColor(String slot) => switch (slot) {
        'PH_L' ||
        'PH_R' ||
        'PR' ||
        'DEF_IF' ||
        'DEF_OF' =>
          const Color(0xFF757575),
        'P' || 'SP_L' || 'SP_R' || 'RP_L' || 'RP_R' || 'CL' => const Color(0xFFEF5350),
        'C' => const Color(0xFF2196F3),
        '1B' || '2B' || '3B' || 'SS' => const Color(0xFFFFD54F),
        'LF' || 'CF' || 'RF' => const Color(0xFF43A047),
        _ => const Color(0xFF9C27B0),
      };
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (TeamSectionLayout.embedded(context) && widget.battingOrder == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final mode in [0, 1, 2]) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(['守備位置別', '打順別', '代打・代走・代守'][mode],
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: compactBaseballLayout(context) ? constraints.maxWidth :
                      (mode == 0 ? _positionSlotCount : mode == 1 ? 9 : benchRegularSlots.length) * _commonColumnWidth(constraints.maxWidth, true),
                    child: StrengthRegularGrid(teams: widget.teams, battingOrder: mode == 1, bench: mode == 2,
                      columnWidth: _commonColumnWidth(constraints.maxWidth, true)),
                  ),
                ),
              ],
            ],
          );
        }
        final compact = compactBaseballLayout(context);
        final hideTeam = TeamSectionLayout.embedded(context);
        final transpose = hideTeam && compact;
        final columnWidth = widget.columnWidth ?? _commonColumnWidth(constraints.maxWidth, hideTeam);
        final teamWidth = compact ? 30.0 : columnWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncHeader();
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!TeamSectionLayout.embedded(context) && widget.battingOrder == null)
              if (NavigationPickerScope.enabled(context))
                NavigationPicker(level: 3,
                  labels: const {0: '守備位置別', 1: '打順別', 2: '代打・代走・代守'},
                  value: _bench ? 2 : _battingOrder ? 1 : 0,
                  onChanged: (value) => setState(() {
                    _selectedBattingOrder = value == 1;
                    _selectedBench = value == 2;
                  }), color: Colors.blueGrey, foreground: Colors.white)
              else Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: const Text('守備位置別'),
                  selected: !_battingOrder && !_bench,
                  onSelected: (_) => setState(() { _selectedBattingOrder = false; _selectedBench = false; })),
              ChoiceChip(
                  label: const Text('打順別'),
                  selected: _battingOrder && !_bench,
                  onSelected: (_) => setState(() { _selectedBattingOrder = true; _selectedBench = false; })),
              ChoiceChip(
                  label: const Text('代打・代走・代守'),
                  selected: _bench,
                  onSelected: (_) => setState(() { _selectedBattingOrder = false; _selectedBench = true; })),
            ]),
            if (!hideTeam) Row(children: [
              if (!hideTeam) _fixedCell(widget.teamHeader, Colors.grey.shade200, Colors.black87,
                  height: 44, width: teamWidth),
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
                          if (!hideTeam) Column(children: [
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
                                  vertical: compact,
                                  width: teamWidth),
                          ]),
                          Expanded(
                              child: sectionScrollView(context, 
                            key: const ValueKey('regular-horizontal-scroll'),
                            controller: _horizontal,
                            scrollDirection: Axis.horizontal,
                            child: Table(
                              key: ValueKey(transpose ? 'regular-vertical-table-${_bench ? 'bench' : _battingOrder}' : 'regular-table-${_bench ? 'bench' : _battingOrder}'),
                              defaultColumnWidth: FixedColumnWidth(columnWidth),
                              columnWidths: transpose ? {0: const FixedColumnWidth(80), for (var i=0;i<widget.teams.length;i++) i+1: const FlexColumnWidth()} : null,
                              border:
                                  TableBorder.all(color: Colors.grey.shade600),
                              children: [
                                // Embedded grids use one table for both headings
                                // and players so constraints cannot size them differently.
                                if (hideTeam && !transpose) TableRow(children: [
                                  for (final slot in _slots)
                                    _fixedCell(
                                      (_battingOrder ? '$slot番' : pitcherAceSlots[slot] ?? usagePositions[slot] ?? benchRegularSlots[slot])!,
                                      _positionColor(slot),
                                      ['1B', '2B', '3B', 'SS'].contains(slot) ? Colors.black87 : Colors.white,
                                      height: 44, width: columnWidth,
                                    ),
                                ]),
                                if (transpose)
                                  for (final entry in _slots.indexed) TableRow(children: [
                                    _fixedCell((_battingOrder ? '${entry.$2}番' : pitcherAceSlots[entry.$2] ?? usagePositions[entry.$2] ?? benchRegularSlots[entry.$2])!,
                                      _positionColor(entry.$2), ['1B','2B','3B','SS'].contains(entry.$2) ? Colors.black87 : Colors.white,
                                      height: 84, width: 80),
                                    for (final team in widget.teams) _row(team).children[entry.$1],
                                  ])
                                else
                                  for (final team in widget.teams) _row(team)
                              ],
                            ),
                          )),
                        ]),
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                            _battingOrder
                                ? '打順別のスタメン数・起用率。各打順の最多スタメン数の70%以上の選手も表示します。重複選手は起用率の高い打順を優先し、追加の選手は薄い背景で表示します。'
                                : '先発エースは左右別の先発投球回最多、リリーフエースは守護神を除く左右別のホールド最多（同数は救援投球回）、守護神はセーブ最多。WHIPはシーズン通算。守備位置別のスタメン数・起用率。各位置の最多スタメン数の70%以上の選手も表示します。重複選手は起用率の高い位置を優先し、追加の選手は薄い背景で表示します。途中出場は既存レギュラーを除外し、各項目の最多起用者とその70%以上を表示。両打ちは左右の候補とし重複表示しません。代守は出場時の守備位置で分類します。',
                            style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
            )),
          ],
        );
      });

  Widget _fixedCell(String label, Color background, Color foreground,
          {required double height, required double width, bool vertical = false}) =>
      Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
              color: background,
              border: Border.all(color: Colors.grey.shade600)),
          child: vertical ? Tooltip(message: label, child: StrengthVerticalLabel(label, minFontSize: 4, style: TextStyle(color: foreground))) : FittedBox(
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
    if (!_battingOrder && _slots.contains('P')) {
      final group = listMapFromJson(team['positions']).where((p) => p['slot'] == 'P').firstOrNull;
      final players = listMapFromJson(group?['players']);
      final total = usageInt(group?['total']);
      final most = players.fold<int>(0, (n, p) => usageInt(p['count']) > n ? usageInt(p['count']) : n);
      if (total > 0 && most > 0) {
        selected['P'] = [
        for (final player in players.where((p) => usageInt(p['count']) == most))
          {...player, 'usage_rate': most / total}
        ];
      }
    }
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
  List<Map<String, dynamic>> _draftPicks = [];
  String? _draftError;
  @override
  void initState() {
    super.initState();
    _loadTransferDrafts();
  }
  @override
  void didUpdateWidget(covariant StrengthRosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != year) _loadTransferDrafts();
  }
  Future<void> _loadTransferDrafts() async {
    final requestedYear = year;
    _draftPicks = [];
    _draftError = null;
    try {
      final sources = await Future.wait([
        rootBundle.loadString('backend/assets/data/draft_history.json'),
        rootBundle.loadString('backend/assets/data/active_draft_history.json'),
      ]);
      final picks = <Map<String, dynamic>>[];
      for (final source in sources) {
        final data = jsonDecode(source) as Map;
        final entry = (data['years'] as Map?)?['$requestedYear'];
        if (entry is Map) picks.addAll(listMapFromJson(entry['picks']));
      }
      if (mounted && requestedYear == year) setState(() => _draftPicks = picks);
    } catch (_) {
      if (mounted && requestedYear == year) setState(() => _draftError = 'ドラフト指名選手を読み込めませんでした');
    }
  }
  int _rosterView = 1;
  bool get _usageOrder => _rosterView != 0;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Set<String>>(
      valueListenable: DisplaySettings.instance,
      builder: (context, _, child) => Column(children: [
        Row(children: [
          for (final view in [0, 1, 2])
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                    label: Text(['年齢順', '起用順', '移籍状況'][view]),
                    selected: _rosterView == view,
                    onSelected: (_) => setState(() => _rosterView = view))),
        ]),
        SectionExpanded(child: _rosterView == 2 ? _transfers(context) : _grid(context)),
      ]));
  Widget _transfers(BuildContext context) {
    final groups = List.generate(3, (_) => <Map<String, dynamic>>[]);
    for (final player in rosterWithDraftArrivals(listMapFromJson(team['roster']), _draftPicks, team, year)) {
      groups[rosterTransferBlock(player, team, year)].add(player);
    }
    for (final group in groups) {
      group.sort((a, b) => compareRosterUsage(a, b, team));
    }
    int arrivalOrder(Map<String, dynamic> p) {
      final pos = rosterPosition(p, team);
      if (_pitching(pos) || p['position_group'] == '投手') return 0;
      if (pos == '捕手' || p['position_group'] == '捕手') return 1;
      if (['一塁', '二塁', '三塁', '遊撃', '内野手'].contains(pos)) return 2;
      if (['左翼', '中堅', '右翼', '外野手'].contains(pos)) return 3;
      return 4;
    }
    groups[0].sort((a, b) {
      final transfer = rosterArrivalGroupPriority(a).compareTo(rosterArrivalGroupPriority(b));
      if (transfer != 0) return transfer;
      final order = arrivalOrder(a).compareTo(arrivalOrder(b));
      return order != 0 ? order : compareRosterArrivalDraft(a, b, team);
    });
    const positions = ['投手', '捕手', '一塁', '二塁', '三塁', '遊撃', '左翼', '中堅', '右翼'];
    String residentPosition(Map<String, dynamic> p) {
      final pos = rosterPosition(p, team);
      return _pitching(pos) ? '投手' : pos;
    }
    Widget residents() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final pos in positions)
          Expanded(child: Padding(
            key: ValueKey('transfer-resident-$pos'),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(height: 32, alignment: Alignment.center,
                color: _positionColor(pos),
                child: Text(pos, style: TextStyle(color: _positionForeground(pos), fontSize: 12))),
              const SizedBox(height: 4),
              for (final p in groups[1].where((p) => residentPosition(p) == pos)) _player(p, pos),
            ]),
          )),
      ]),
      if (groups[1].any((p) => !positions.contains(residentPosition(p)))) ...[
        const Text('守備位置未確認', style: TextStyle(fontSize: 11)),
        for (final p in groups[1].where((p) => !positions.contains(residentPosition(p))))
          _player(p, residentPosition(p)),
      ],
    ]);
    const titles = ['入団選手', '在籍選手', '退団確定'];
    const descriptions = ['開幕後の加入・翌年度の新戦力', '開幕時の所属選手・移籍未確定', '移籍・引退・戦力外など確定済み'];
    const colors = [Colors.green, Colors.blue, Colors.grey];
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.clamp(1352.0, double.infinity);
      return sectionScrollView(context, child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: width, child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (var index = 0; index < 3; index++)
            Expanded(flex: index == 1 ? 9 : 2, child: Container(
              key: ValueKey('roster-transfer-block-$index'),
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: colors[index].withValues(alpha: .08), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${titles[index]}（${groups[index].length}人）', style: TextStyle(fontWeight: FontWeight.bold, color: colors[index])),
                Text(descriptions[index], style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 8),
                if (index == 0 && _draftError != null) Text(_draftError!),
                if (groups[index].isEmpty) const Text('該当選手なし'),
                if (index == 1) residents()
                else for (final player in groups[index]) _player(player, rosterPosition(player, team)),
              ]),
            )),
          ],
        )),
      ));
    });
  }

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
      final narrowHeader = compactBaseballLayout(context) && TeamSectionLayout.embedded(context);
      final columnWidth = (constraints.maxWidth / (columns.length + 1))
          .clamp(_minColumnWidth, double.infinity);
      final sideWidth = narrowHeader ? 28.0 : columnWidth;
      return _WideGrid(
        child: SizedBox(
          width: columnWidth * columns.length + sideWidth,
          child: Column(children: [
            Row(children: [
              _rosterHeader(_usageOrder ? '起用' : '年齢', sideWidth,
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
                  '', sideWidth, _usageOrder ? Colors.black : Colors.grey.shade200, _usageOrder ? Colors.white : Colors.black87),
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
                        0: FixedColumnWidth(sideWidth),
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
                                child: narrowHeader ? Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: SizedBox(height: 72, child: StrengthVerticalLabel(_usageOrder ? (age == 0 ? '起用未確認' : '$age軍') : (age == null ? '不明' : '$age歳'), style: TextStyle(color: _usageOrder ? Colors.white : Colors.black87)))) : _cell(_usageOrder
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
          child: width == 28 ? StrengthVerticalLabel(label, minFontSize: 8, maxFontSize: 10, style: TextStyle(color: foreground)) : FittedBox(
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
    final uniformNumber = '${p['uniform_number'] ?? ''}'.trim();
    final departure = rosterDepartureLabel(p);
    final muteDeparture = departure != null && _rosterView != 2;
    final moveLabels = <String>{
      ...rosterMoveLabels(p, year).where((label) =>
          !['国内FA権保有', '海外FA権保有', 'FA権保有'].contains(label)),
      ...rosterContractLabels(p, team, year),
    }.toList();
    final newArrival = p['new_arrival'] == true && [year, year + 1].contains(usageInt(p['arrival_year'])) && departure == null;
    final former = p['previous_team'] is Map ? Map<String, dynamic>.from(p['previous_team'] as Map) : <String, dynamic>{};
    final formerColor = parseColorNameOrNull('${former['color_back']}') ?? Colors.blueGrey;
    final formerText = parseColorNameOrNull('${former['color_font']}') ?? (formerColor.computeLuminance() > .45 ? Colors.black : Colors.white);
    final firstTeamRow = _usageOrder && rosterMainLevel(p) == 1;
    final leadership = rosterLeadershipRoles(p, team, year);
    final marks = [
      if (p['flg_injury'] == true && DisplaySettings.instance.shows('flg_injury')) '🤕',
      if (usageInt(p['contract_end_year']) == year) '契',
      if (p['departure_confirmed'] == true) '退'
    ];
    return Tooltip(
        message: [
          if (p['lower_level_usage'] is Map)
            for (final entry in (p['lower_level_usage'] as Map).entries)
              '${entry.key}軍起用：${entry.value['coverage'] == 'verified_partial' ? '公開記録の一部' : '公式戦'} ${entry.value['appearances']}試合',
          if (p['status_as_of'] != null) '確認日：${p['status_as_of']}',
          if (newArrival) '前所属：${former['name'] ?? '未確認'}',
          if (p['status_source'] != null) '出典：${p['status_source']}',
          if (p['arrival_label_source'] != null) '入団情報：${p['arrival_label_source']}',
          if (p['level_appearances'] is Map)
            '出場数：${(p['level_appearances'] as Map).entries.map((e) => '${e.key}軍 ${e.value}').join('／')}',
        ].join('\n'),
        child: Container(
          key: ValueKey('roster-card-${p['player_key']}'),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: muteDeparture
                  ? Colors.white
                  : Color.lerp(Colors.white, _positionColor(position),
                      rosterCardTint(p)),
              borderRadius: BorderRadius.circular(4)),
          child: DefaultTextStyle.merge(
              style: TextStyle(color: muteDeparture ? Colors.grey : null),
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
                    if (newArrival)
                      Wrap(spacing: 3, runSpacing: 3, children: [
                        _NewArrivalBadge(child: Container(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1), color: Colors.red.shade700, child: _fitRosterText('${rosterMovePeriod(p, year, dateField: 'arrival_as_of', eventYear: usageInt(p['arrival_year']))} 新戦力', bold: true, color: Colors.white))),
                        if ('${former['label'] ?? ''}'.isNotEmpty)
                          Tooltip(message: '前所属：${former['name']}', child: Container(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1), color: formerColor, child: _fitRosterText('${former['label']}', bold: true, color: formerText))),
                      ]),
                    for (final label in moveLabels)
                      Padding(padding: const EdgeInsets.only(top: 2), child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        color: label.contains('未定') || label.contains('権保有') ? Colors.amber.shade100 : Colors.blue.shade50,
                        child: _fitRosterText(rosterTimedMoveLabel(label, p, year), bold: true, color: Colors.black87),
                      )),
                    if (_rosterView == 2 && p['draft_status'] != null) _fitRosterText('${p['draft_status']}'),
                    if (departure != null)
                      _fitRosterText('${rosterMovePeriod(p, year, dateField: 'departure_as_of')} $departure', color: Colors.red, bold: true),
                    if (rosterUsageUnknown(p, team)) _fitRosterText('（起用不明）'),
                    if (!firstTeamRow) _fitRosterText(rosterLevel(p)),
                    if (_usageOrder)
                      _fitRosterText(
                          rosterWorkloadLabel(p, team, rosterMainLevel(p))),
                    if (p['registration'] != null &&
                        !(firstTeamRow && p['registration'] == '支配下'))
                      _fitRosterText('${p['registration']}'),
                    if (RegExp(r'^\d+$').hasMatch(uniformNumber))
                      Align(alignment: Alignment.bottomRight, child: Text(
                        '#$uniformNumber',
                        key: ValueKey('roster-number-${p['player_key']}'),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      )),
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
        child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 12),
            child: widget.child),
      );
}

class _NewArrivalBadge extends StatefulWidget {
  const _NewArrivalBadge({required this.child});
  final Widget child;
  @override
  State<_NewArrivalBadge> createState() => _NewArrivalBadgeState();
}
class _NewArrivalBadgeState extends State<_NewArrivalBadge> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) { controller.stop(); controller.value = 1; }
    else { controller.repeat(reverse: true); }
  }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(opacity: Tween<double>(begin: .35, end: 1).animate(controller), child: widget.child);
}
