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
  String _filter = 'すべて';
  @override
  Widget build(BuildContext context) {
    final rows = transferCandidates(widget.teams, widget.year)
        .where((r) =>
            _filter == 'すべて' ||
            (r['labels'] as List).any((label) => _filter == 'FA'
                ? '$label'.contains('FA')
                : '$label'.contains('ポスティング')))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${widget.year}年オフの移籍候補',
              style: const TextStyle(fontWeight: FontWeight.bold))),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(spacing: 6, children: [
            for (final filter in ['すべて', 'FA', 'ポスティング'])
              ChoiceChip(
                  label: Text(filter),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter)),
          ])),
      const Padding(
          padding: EdgeInsets.all(8),
          child: Text('権利保有と移籍報道を区別して掲載しています。移籍確定ではありません。',
              style: TextStyle(fontSize: 12))),
      Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('この年度の移籍候補情報はありません。'))
              : LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth < 760 ? 760.0 : constraints.maxWidth;
                  const columns = {0: FixedColumnWidth(120), 1: FixedColumnWidth(120), 2: FixedColumnWidth(150), 3: FlexColumnWidth()};
                  Widget cell(Widget child) => Padding(padding: const EdgeInsets.all(10), child: child);
                  return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: width, child: Column(children: [
                    Table(columnWidths: columns, border: TableBorder.all(color: Colors.grey), children: [
                      TableRow(decoration: const BoxDecoration(color: Colors.black), children: [
                        for (final label in ['チーム名', '選手名', '移籍方式', '備考']) cell(Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      ]),
                    ]),
                    Expanded(child: SingleChildScrollView(child: Table(
                      key: const ValueKey('transfer-grid'), columnWidths: columns,
                      border: TableBorder.all(color: Colors.grey.shade300),
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [for (final row in rows) TableRow(children: [
                        Container(padding: const EdgeInsets.all(10),
                          color: (parseColorNameOrNull('${row['team']['color_back']}') ?? Colors.blueGrey).withValues(alpha: .15),
                          child: Text('${row['team']['name_team']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                        cell(Text('${row['player']['name']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                        cell(Text((row['labels'] as List).join('・'))),
                        cell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${row['status']} · ${row['contract']}', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('${row['detail']}'),
                        ])),
                      ])],
                    ))),
                  ])));
                })),
    ]);
  }
}
