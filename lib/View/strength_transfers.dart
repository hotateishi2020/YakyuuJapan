import 'dart:math' as math;
import 'player_detail_dialog.dart';
import 'compact_layout.dart';
import 'pinned_horizontal_row.dart';
import 'package:flutter/material.dart';
import '../logic/transfer_candidates.dart';
import '../tools/color_parse.dart';

class StrengthTransfers extends StatefulWidget {
  const StrengthTransfers({super.key, required this.teams, required this.year});
  final List<Map<String, dynamic>> teams;
  final int year;
  @override
  State<StrengthTransfers> createState() => _StrengthTransfersState();
}

class _StrengthTransfersState extends State<StrengthTransfers> {
  final _horizontal = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = transferCandidates(widget.teams, widget.year);
    final compact = compactBaseballLayout(context);
    final teamWidth = compact ? 48.0 : 120.0;
    const playerWidth = 120.0;
    final pinnedWidth = teamWidth + playerWidth;
    Widget cell(Widget child, double width, {Color color = Colors.white}) =>
        Container(
            width: width,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color,
                border: Border.all(color: Colors.grey.shade300, width: .5)),
            child: child);
    Widget pinned(Widget team, Widget player) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [team, player]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${widget.year}年オフの移籍候補',
              style: const TextStyle(fontWeight: FontWeight.bold))),
      Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('この年度の移籍候補情報はありません。'))
              : LayoutBuilder(builder: (context, constraints) {
                  final width = math.max(760.0, constraints.maxWidth);
                  return SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      key: const ValueKey('transfer-horizontal-scroll'),
                      child: SizedBox(
                          width: width,
                          child: Column(children: [
                            PinnedHorizontalRow(
                                controller: _horizontal,
                                pinnedWidth: pinnedWidth,
                                minHeight: 60,
                                children: [
                                  pinned(
                                      cell(
                                          const Text('チーム名',
                                              style: TextStyle(
                                                  color: Colors.white)),
                                          teamWidth,
                                          color: Colors.black),
                                      cell(
                                          const Text('選手名',
                                              style: TextStyle(
                                                  color: Colors.white)),
                                          playerWidth,
                                          color: Colors.black)),
                                  cell(
                                      const Text('移籍方式',
                                          style:
                                              TextStyle(color: Colors.white)),
                                      150,
                                      color: Colors.black),
                                  cell(
                                      const Text('備考',
                                          style:
                                              TextStyle(color: Colors.white)),
                                      width - pinnedWidth - 150,
                                      color: Colors.black),
                                ]),
                            Expanded(
                                child: ListView(
                                    key: const ValueKey('transfer-grid'),
                                    children: [
                                  for (final row in rows)
                                    PinnedHorizontalRow(
                                        controller: _horizontal,
                                        pinnedWidth: pinnedWidth,
                                        minHeight: 64,
                                        children: [
                                          pinned(
                                              cell(
                                                  Text(
                                                      '${compact ? row['team']['name_shortest'] ?? row['team']['name_team'] : row['team']['name_team']}',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: parseColorNameOrNull(
                                                                  '${row['team']['color_font']}') ??
                                                              Colors.white)),
                                                  teamWidth,
                                                  color: parseColorNameOrNull(
                                                          '${row['team']['color_back']}') ??
                                                      Colors.blueGrey),
                                              cell(
                                                  PlayerNameLink(
                                                      player: {
                                                        ...row['player'],
                                                        'id_team': row['team']
                                                            ['id_team']
                                                      },
                                                      child: Text(
                                                          '${row['player']['name']}',
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold))),
                                                  playerWidth)),
                                          cell(
                                              Text((row['labels'] as List)
                                                  .join('・')),
                                              150),
                                          cell(
                                              Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                        '${row['status']} · ${row['contract']}',
                                                        style: const TextStyle(
                                                            fontSize: 12)),
                                                    const SizedBox(height: 4),
                                                    Text('${row['detail']}'),
                                                  ]),
                                              width - pinnedWidth - 150),
                                        ]),
                                ])),
                          ])));
                })),
    ]);
  }
}
