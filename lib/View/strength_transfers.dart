import 'player_detail_dialog.dart';
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
  @override
  Widget build(BuildContext context) {
    final rows = transferCandidates(widget.teams, widget.year);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${widget.year}年オフの移籍候補',
              style: const TextStyle(fontWeight: FontWeight.bold))),
      Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('この年度の移籍候補情報はありません。'))
              : LayoutBuilder(builder: (context, constraints) {
                  final width =
                      constraints.maxWidth < 760 ? 760.0 : constraints.maxWidth;
                  const columns = {
                    0: FixedColumnWidth(120),
                    1: FixedColumnWidth(120),
                    2: FixedColumnWidth(150),
                    3: FlexColumnWidth()
                  };
                  Widget cell(Widget child) =>
                      Padding(padding: const EdgeInsets.all(10), child: child);
                  return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                          width: width,
                          child: Column(children: [
                            Table(
                                columnWidths: columns,
                                border: TableBorder.all(color: Colors.grey),
                                children: [
                                  TableRow(
                                      decoration: const BoxDecoration(
                                          color: Colors.black),
                                      children: [
                                        for (final label in [
                                          'チーム名',
                                          '選手名',
                                          '移籍方式',
                                          '備考'
                                        ])
                                          cell(Text(label,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      ]),
                                ]),
                            Expanded(
                                child: SingleChildScrollView(
                                    child: Table(
                              key: const ValueKey('transfer-grid'),
                              columnWidths: columns,
                              border:
                                  TableBorder.all(color: Colors.grey.shade300),
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.middle,
                              children: [
                                for (final row in rows)
                                  TableRow(children: [
                                    TableCell(
                                        verticalAlignment:
                                            TableCellVerticalAlignment.fill,
                                        child: Container(
                                            padding: const EdgeInsets.all(10),
                                            alignment: Alignment.centerLeft,
                                            color: parseColorNameOrNull(
                                                    '${row['team']['color_back']}') ??
                                                Colors.blueGrey,
                                            child: Text(
                                                '${row['team']['name_team']}',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: parseColorNameOrNull(
                                                            '${row['team']['color_font']}') ??
                                                        Colors.white)))),
                                    cell(PlayerNameLink(
                                        player: {
                                          ...row['player'],
                                          'id_team': row['team']['id_team']
                                        },
                                        child: Text('${row['player']['name']}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold)))),
                                    cell(Text(
                                        (row['labels'] as List).join('・'))),
                                    cell(Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              '${row['status']} · ${row['contract']}',
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                          const SizedBox(height: 4),
                                          Text('${row['detail']}'),
                                        ])),
                                  ])
                              ],
                            ))),
                          ])));
                })),
    ]);
  }
}
