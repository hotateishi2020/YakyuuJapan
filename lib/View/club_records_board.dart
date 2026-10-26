import '../widgets/navigation_picker.dart';
import '../widgets/collapsible_menu.dart';
import '../config/app_design.dart';
import '../logic/favorite_team.dart';
import 'pinned_horizontal_row.dart';
import 'player_detail_dialog.dart';
import 'package:flutter/material.dart';
import '../tools/json_utils.dart';
import '../tools/color_parse.dart';

class ClubRecordsBoard extends StatefulWidget {
  const ClubRecordsBoard({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<ClubRecordsBoard> createState() => _ClubRecordsBoardState();
}

class _ClubRecordsBoardState extends State<ClubRecordsBoard> {
  String _group = 'season';
  String? _selectedTeam;
  final _horizontal = ScrollController();
  @override
  void dispose() { _horizontal.dispose(); super.dispose(); }
  Map<String, dynamic> get data => widget.data;
  @override
  Widget build(BuildContext context) {
    final allTeams = listMapFromJson(data['teams']);
    final metrics = listMapFromJson(data['metrics'])
        .where((m) => (m['group'] ?? 'season') == _group)
        .toList();
    if (allTeams.isEmpty) return const Center(child: Text('球団記録を取得できませんでした。'));
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    String teamKey(Map<String, dynamic> team) => '${team['id_team'] ?? team['name']}';
    final selected = allTeams.firstWhere((team) => teamKey(team) == _selectedTeam,
      orElse: () => favoriteTeamRow(allTeams) ?? allTeams.first);
    final teams = portrait ? [selected] : allTeams;
    Widget cell(Widget child, double width, {Color color = Colors.white}) =>
        Container(
            width: width,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color, border: Border.all(color: Colors.grey.shade300)),
            child: child);
    double? value(Map<String, dynamic> row) {
      final number = double.tryParse(
          '${row['numeric_value'] ?? row['value'] ?? ''}'.replaceAll(',', ''));
      return number != null && number.isFinite && number >= 0 ? number : null;
    }

    bool samePlayer(Map<String, dynamic> a, Map<String, dynamic> b) {
      final aId = int.tryParse('${a['id_player']}');
      final bId = int.tryParse('${b['id_player']}');
      if (aId != null && aId > 0 && bId != null && bId > 0) {
        return aId == bId;
      }
      String name(Map<String, dynamic> row) =>
          '${row['name'] ?? ''}'.replaceAll(RegExp(r'[\s\u3000]+'), '');
      return name(a).isNotEmpty && name(a) == name(b);
    }

    Widget entries(List<Map<String, dynamic>> rows, String unit,
            {required double maximum,
            required Color color,
            required String key,
            String emptyLabel = '未取得',
            bool past = false}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (rows.isEmpty) Text(emptyLabel, style: const TextStyle(fontSize: 11)),
          for (var i = 0; i < rows.length; i++)
            Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Tooltip(
                        message:
                            '${rows[i]['source_url'] ?? rows[i]['sources'] ?? ''}',
                        child: PlayerNameLink(
                            player: rows[i],
                            child: Text(
                                '${rows[i]['name']}\n${rows[i]['value']}$unit${past ? '（${rows[i]['year']}）' : ''}',
                                style: const TextStyle(fontSize: 11)))),
                    const SizedBox(height: 3),
                    if (value(rows[i]) != null)
                      Semantics(
                          label: '${rows[i]['name']} ${rows[i]['value']}$unit',
                          child: Container(
                            height: 12,
                            alignment: Alignment.centerLeft,
                            color: Colors.grey.shade200,
                            child: FractionallySizedBox(
                              key: ValueKey('$key-$i'),
                              widthFactor:
                                  maximum > 0 ? value(rows[i])! / maximum : 0,
                              child: Container(color: color),
                            ),
                          )),
                  ],
                )),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (portrait && NavigationPickerScope.enabled(context))
        NavigationPicker(level: 3, labels: {for (var i = 0; i < allTeams.length; i++) i: '${allTeams[i]['name_shortest'] ?? allTeams[i]['short_name'] ?? allTeams[i]['name']}'},
          value: allTeams.indexWhere((t) => teamKey(t) == teamKey(selected)),
          onChanged: (i) { if (_horizontal.hasClients) _horizontal.jumpTo(0); setState(() => _selectedTeam = teamKey(allTeams[i])); },
          color: parseColorNameOrNull('${selected['color_back']}') ?? Colors.blueGrey, foreground: Colors.white)
      else if (portrait) MenuBand(level: 3, child: LayoutBuilder(builder: (context, constraints) {
        final columns = allTeams.length < 6 ? allTeams.length : 6;
        final tabWidth = (constraints.maxWidth - (columns - 1) * ALL_SPACE_BLOCK) / columns;
        return Wrap(spacing: ALL_SPACE_BLOCK, runSpacing: ALL_SPACE_BLOCK, children: [
          for (final team in allTeams)
            SizedBox(width: tabWidth, height: TAB_BAR_H,
              child: Semantics(button: true, selected: teamKey(team) == teamKey(selected),
                child: Material(
                  color: teamKey(team) == teamKey(selected)
                    ? parseColorNameOrNull('${team['color_back']}') ?? Colors.blueGrey
                    : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(TAB_RADIUS),
                  child: InkWell(
                    key: ValueKey('club-records-team-${teamKey(team)}'),
                    borderRadius: BorderRadius.circular(TAB_RADIUS),
                    onTap: () {
                      if (_horizontal.hasClients) _horizontal.jumpTo(0);
                      setState(() => _selectedTeam = teamKey(team));
                    },
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Center(child: FittedBox(fit: BoxFit.scaleDown,
                        child: Text('${team['name_shortest'] ?? team['short_name'] ?? team['name']}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                            color: teamKey(team) == teamKey(selected)
                              ? parseColorNameOrNull('${team['color_font']}') ?? Colors.white
                              : Colors.black87))))),
                  ),
                ),
              )),
        ]);
      })),
      Wrap(spacing: 6, children: [
        for (final entry
            in {'season': 'シーズン記録', 'career': '通算記録', 'streak': '連続記録'}.entries)
          ChoiceChip(
              label: Text(entry.value),
              selected: _group == entry.key,
              onSelected: (_) => setState(() => _group = entry.key)),
      ]),
      Text(
          '${data['year']}年・球団別${{
            'season': 'シーズン記録',
            'career': '通算記録',
            'streak': '連続記録'
          }[_group]}',
          style: const TextStyle(fontWeight: FontWeight.bold)),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final width = portrait ? (constraints.maxWidth - 100).clamp(1.0, double.infinity)
            : ((constraints.maxWidth - 100) / teams.length)
            .clamp(190.0, 300.0)
            .toDouble();
        return SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: 100 + width * teams.length,
                child: Column(children: [
                  PinnedHorizontalRow(controller: _horizontal, pinnedWidth: 100,
                          children: [
                        cell(
                            const Text('記録',
                                style: TextStyle(color: Colors.white)),
                            100,
                            color: Colors.black),
                        for (final team in teams)
                          cell(
                              Text('${team['short_name'] ?? team['name']}',
                                  style: TextStyle(
                                      color: parseColorNameOrNull(
                                              '${team['color_font']}') ??
                                          Colors.white,
                                      fontWeight: FontWeight.bold)),
                              width,
                              color: parseColorNameOrNull(
                                      '${team['color_back']}') ??
                                  Colors.blueGrey),
                      ]),
                  Expanded(
                      child: ListView.builder(
                          itemCount: metrics.length,
                          itemBuilder: (context, index) {
                            final metric = metrics[index];
                            final cells = listMapFromJson(metric['cells']);
                            return PinnedHorizontalRow(controller: _horizontal, pinnedWidth: 100,
                                    children: [
                                  cell(
                                      Text('${metric['label']}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      100,
                                      color: Colors.grey.shade100),
                                  for (final team in teams)
                                    cell(Builder(builder: (context) {
                                      final item = cells
                                              .where((c) =>
                                                  c['id_team'] ==
                                                  team['id_team'])
                                              .firstOrNull ??
                                          {};
                                      final record =
                                          listMapFromJson(item['record']);
                                      final current =
                                          listMapFromJson(item['current']);
                                      final maximum = [...record, ...current]
                                          .map(value)
                                          .whereType<double>()
                                          .fold<double>(
                                              0, (a, b) => a > b ? a : b);
                                      final barKey =
                                          'club-bar-${metric['key'] ?? metric['label']}-${team['id_team']}';
                                      final previous = record.isEmpty
                                          ? null
                                          : value(record.first);
                                      final now = current.isEmpty
                                          ? null
                                          : value(current.first);
                                      final gap =
                                          (_group == 'streak' && item['historical_status'] != 'verified') || previous == null || now == null
                                              ? null
                                              : previous - now;
                                      final unchangedRecord = gap == 0 &&
                                          current.every((player) => record.any(
                                              (past) => samePlayer(player, past) &&
                                                  value(player) == value(past)));
                                      return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(_group == 'streak' ? '確認済みの歴代記録' : '歴代最高',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            entries(record, '${metric['unit']}',
                                                past: true,
                                                maximum: maximum,
                                                color: const Color(0xFF546E7A),
                                                key: '$barKey-record'),
                                            const SizedBox(height: 8),
                                            Text(
                                                _group == 'career'
                                                    ? '今季出場者の通算'
                                                    : '今季トップ',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            entries(
                                                current, '${metric['unit']}',
                                                emptyLabel: '${item['current_message'] ?? '未取得'}',
                                                maximum: maximum,
                                                color: parseColorNameOrNull(
                                                        '${team['color_back']}') ??
                                                    Colors.blue,
                                                key: '$barKey-current'),
                                            if (gap != null && !unchangedRecord)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 6),
                                                  child: gap < 0
                                                      ? const _RecordUpdatedLabel()
                                                      : Text(
                                                          gap == 0
                                                              ? '登録済み最高に並ぶ'
                                                              : 'あと${gap == gap.roundToDouble() ? gap.toInt() : gap.toStringAsFixed(2)}${metric['unit']}',
                                                          style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: gap <= 0
                                                                  ? Colors.red
                                                                  : Colors
                                                                      .black54))),
                                          ]);
                                    }), width,
                                        color: Color.lerp(
                                            parseColorNameOrNull(
                                                    '${team['color_back']}') ??
                                                Colors.blueGrey,
                                            Colors.white,
                                            .94)!),
                                ]);
                          })),
                ])));
      })),
      Text('${data['note'] ?? ''}',
          style: const TextStyle(fontSize: 11, color: Colors.black54)),
    ]);
  }
}

class _RecordUpdatedLabel extends StatefulWidget {
  const _RecordUpdatedLabel();

  @override
  State<_RecordUpdatedLabel> createState() => _RecordUpdatedLabelState();
}

class _RecordUpdatedLabelState extends State<_RecordUpdatedLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = Tween<double>(begin: 1, end: .25)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: const Text('球団記録更新',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
      );
}
