import 'package:flutter/material.dart';
import 'player_detail_dialog.dart';

const extraBattingTitles = ['ボール球見極め率', '代打起用数', '代打打率', '盗塁阻止率', '打席数'];
const extraPitchingTitles = ['BB/9', '四死球/9', '平均投球回', '投球回数', '登板回数'];
const metricNotes = {
  'ボール球見極め率': 'ストライクゾーン外の投球のうち、スイングしなかった割合（1 − O-Swing%）。投球位置・スイング判定が必要。',
  '代打起用数': '代打として起用された回数。代打打数とは異なり、四死球等も含む。',
  '代打打率': '代打安打÷代打打数。四死球・犠打・犠飛等を打数に含めない。',
  '盗塁阻止率': '盗塁阻止÷盗塁企図。捕手の成績。',
  'BB/9': '規定投球回到達投手のみ。四球×9÷投球回。死球を含まない。',
  '四死球/9': '規定投球回到達投手のみ。（四球＋死球）×9÷投球回。',
  '平均投球回': '全登板（先発・救援）における投球回÷登板数。小数表記。',
  '投球回数': '投球回。.1/.2は小数ではなく1/3回・2/3回。',
};
String statPlayerKey(Map<String, dynamic> r) => r['id_player'] != null
    ? 'id:${r['id_player']}'
    : '${r['id_team']}:${r['name_player'] ?? r['player_name']}';
num? statNumeric(Map<String, dynamic> r) {
  final explicit = num.tryParse('${r['numeric_value']}');
  if (explicit != null) return explicit;
  final text = '${r['stats'] ?? ''}'.trim();
  final innings = RegExp(r'^(\d+)\s+([12])/3$').firstMatch(text);
  if (innings != null) {
    return int.parse(innings[1]!) + int.parse(innings[2]!) / 3;
  }
  final match = RegExp(r'^[-+]?(?:\d+(?:\.\d+)?|\.\d+)').firstMatch(text);
  return match == null ? null : num.tryParse(match[0]!);
}

class PlayerStatsGrid extends StatefulWidget {
  const PlayerStatsGrid({super.key, required this.rows, required this.batting, this.showBallSelection = true});
  final List<Map<String, dynamic>> rows;
  final bool batting;
  final bool showBallSelection;
  @override
  State<PlayerStatsGrid> createState() => _PlayerStatsGridState();
}

class _PlayerStatsGridState extends State<PlayerStatsGrid> {
  String? sort;
  bool ascending = false;
  @override
  Widget build(BuildContext context) {
    final columns = <String>{
      for (final r in widget.rows)
        if ('${r['title'] ?? ''}'.isNotEmpty) '${r['title']}',
      ...(widget.batting ? extraBattingTitles : extraPitchingTitles)
    }.where((title) => widget.showBallSelection || title != 'ボール球見極め率').toList();
    final people = <String, Map<String, dynamic>>{};
    final values = <String, Map<String, Map<String, dynamic>>>{};
    for (final r in widget.rows) {
      final key = statPlayerKey(r);
      people.putIfAbsent(key, () => r);
      values.putIfAbsent(key, () => {})['${r['title']}'] = r;
    }
    final keys = people.keys.toList();
    if (sort != null) {
      keys.sort((a, b) {
        final av = statNumeric(values[a]?[sort] ?? {}),
            bv = statNumeric(values[b]?[sort] ?? {});
        if (av == null) return bv == null ? a.compareTo(b) : 1;
        if (bv == null) return -1;
        final cmp = av.compareTo(bv);
        return cmp == 0 ? a.compareTo(b) : (ascending ? cmp : -cmp);
      });
    }
    if (keys.isEmpty) return const Center(child: Text('成績はありません'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
          padding: EdgeInsets.all(4),
          child: Text('指標をクリックして並び替え。— は未取得・計算不能（0とは区別）。',
              style: TextStyle(fontSize: 11))),
      Expanded(
          child: SingleChildScrollView(
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                      columnSpacing: 22,
                      headingRowHeight: 54,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 42,
                      sortColumnIndex: sort == null || !columns.contains(sort)
                          ? null
                          : columns.indexOf(sort!) + 2,
                      sortAscending: ascending,
                      columns: [
                        const DataColumn(label: Text('選手')),
                        const DataColumn(label: Text('球団')),
                        for (final title in columns)
                          DataColumn(
                              label: Tooltip(
                                  message: metricNotes[title] ?? title,
                                  child: Text(title)),
                              numeric: true,
                              onSort: (_, asc) => setState(() {
                                    ascending = sort == title
                                        ? asc
                                        : [
                                            'BB/9',
                                            '四球/9',
                                            '四死球/9',
                                            '防御率',
                                            'WHIP',
                                            '被打率',
                                            '与四球率'
                                          ].contains(title);
                                    sort = title;
                                  }))
                      ],
                      rows: [
                        for (final key in keys)
                          DataRow(cells: [
                            DataCell(PlayerNameLink(
                                player: people[key]!,
                                child: Text(
                                    '${people[key]!['name_player'] ?? people[key]!['player_name'] ?? ''}'
                                        .replaceAll(RegExp(r'\(.*\)$'), '')))),
                            DataCell(
                                Text('${people[key]!['name_team'] ?? ''}')),
                            for (final title in columns)
                              DataCell(Tooltip(
                                  message:
                                      '${values[key]?[title]?['note'] ?? metricNotes[title] ?? title}\n${values[key]?[title]?['source'] ?? ''}',
                                  child: Text(
                                      '${values[key]?[title]?['stats'] ?? '—'}')))
                          ])
                      ]))))
    ]);
  }
}

/// Extra metrics use value order even if a stale API rank was inherited.
void sortPersonalStatRows(List<Map<String, dynamic>> rows) {
  rows.sort((a, b) {
    final title = '${a['title']}';
    if (extraBattingTitles.contains(title) ||
        extraPitchingTitles.contains(title) ||
        title == '四球/9') {
      final av = statNumeric(a), bv = statNumeric(b);
      if (av == null) return bv == null ? 0 : 1;
      if (bv == null) return -1;
      return ['BB/9', '四球/9', '四死球/9'].contains(title)
          ? av.compareTo(bv)
          : bv.compareTo(av);
    }
    return (int.tryParse('${a['int_rank']}') ?? 1000)
        .compareTo(int.tryParse('${b['int_rank']}') ?? 1000);
  });
}
