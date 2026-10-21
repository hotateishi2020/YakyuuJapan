import 'personal_stats_style.dart';
import '../tools/color_parse.dart';
import 'package:flutter/material.dart';
import 'player_detail_dialog.dart';

const extraBattingTitles = ['ボール球見極め率', '代打起用数', '得点圏打率', 'HR - 盗塁', '打席数', 'GG受賞回数', '盗塁阻止数'];
const extraPitchingTitles = ['BB/9', '四死球/9', '平均投球回', '投球回数', '登板回数', 'GG受賞回数'];
const metricNotes = {
  'GG受賞回数': '選択年度までのゴールデングラブ賞の通算受賞回数。移籍前の受賞も含む。',
  'ボール球見極め率': 'ストライクゾーン外の投球のうち、スイングしなかった割合（1 − O-Swing%）。投球位置・スイング判定が必要。',
  '代打起用数': '代打として起用された回数。代打打数とは異なり、四死球等も含む。',
  '得点圏打率': '規定打席到達選手のみ。二塁または三塁に走者がいる打席の安打÷打数。',
  '代打打率': '代打安打÷代打打数。四死球・犠打・犠飛等を打数に含めない。',
  '盗塁阻止数': '捕手が盗塁を阻止した回数。規定打席の条件なし。',
  'BB/9': '規定投球回到達投手のみ。四球×9÷投球回。死球を含まない。',
  '四死球/9': '規定投球回到達投手のみ。（四球＋死球）×9÷投球回。',
  '平均投球回': '全登板（先発・救援）における投球回÷登板数。小数表記。',
  '投球回数': '投球回。.1/.2は小数ではなく1/3回・2/3回。',
};
String statPlayerKey(Map<String, dynamic> r) => r['id_player'] != null
    ? 'id:${r['id_player']}'
    : '${r['id_team']}:${r['name_player'] ?? r['player_name']}';

/// A missing source metric stays unknown; never substitute zero for missing data.
List<Map<String, dynamic>> withHrStealStats(List<Map<String, dynamic>> rows) {
  final result = rows.where((r) => r['title'] != 'HR - 盗塁').toList();
  final byPlayer = <String, Map<String, Map<String, dynamic>>>{};
  for (final r in result) {
    byPlayer.putIfAbsent('${r['id_league']}:${statPlayerKey(r)}', () => {})['${r['title']}'] = r;
  }
  for (final stats in byPlayer.values) {
    final hr = stats['本塁打'] ?? stats['ホームラン'];
    final sb = stats['盗塁'];
    final h = hr == null ? null : statNumeric(hr), b = sb == null ? null : statNumeric(sb);
    if (h == null || b == null) continue;
    result.add({...hr!, 'title': 'HR - 盗塁', 'stats': '$h - $b', 'numeric_value': h < b ? h : b});
  }
  return result;
}

/// Combine steals with the same player's success percentage for display only.
String personalStatDisplay(Map<String, dynamic> row,
    Iterable<Map<String, dynamic>> rows) {
  final raw = '${row['stats'] ?? ''}'.trim();
  final value = raw.isEmpty ? '—' : raw;
  if (row['title'] == '代打起用数') {
    final rate = rows.where((r) => r['title'] == '代打打率' &&
      statPlayerKey(r) == statPlayerKey(row) && r['id_league'] == row['id_league']).firstOrNull;
    return '$value（${rate == null ? '—' : rate['stats'] ?? '—'}）';
  }
  if (row['title'] != '盗塁') return value;
  final key = statPlayerKey(row);
  final rateRow = rows.where((r) =>
      r['title'] == '盗塁成功率' &&
      statPlayerKey(r) == key &&
      r['id_league'] == row['id_league']).firstOrNull;
  final numeric = rateRow == null ? null : statNumeric(rateRow);
  final percent = numeric == null ? '—' : '${numeric.toStringAsFixed(1)}%';
  return '$value（$percent）';
}

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
      for (final r in withHrStealStats(widget.rows))
        if ('${r['title'] ?? ''}'.isNotEmpty && !['盗塁成功率', '代打打率'].contains(r['title'])) '${r['title']}',
      ...(widget.batting ? extraBattingTitles : extraPitchingTitles)
    }.where((title) => widget.showBallSelection || title != 'ボール球見極め率').toList();
    if (columns.contains('GG受賞回数') && columns.remove('盗塁阻止数')) {
      columns.insert(columns.indexOf('GG受賞回数') + 1, '盗塁阻止数');
    }
    final people = <String, Map<String, dynamic>>{};
    final values = <String, Map<String, Map<String, dynamic>>>{};
    for (final r in withHrStealStats(widget.rows)) {
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
                  child: DecoratedBox(
                    decoration: widget.batting ? statsBattingHeaderDecoration : statsPitchingHeaderDecoration,
                    child: DataTable(
                      border: TableBorder.all(color: Colors.black26, width: .5),
                      headingRowColor: const WidgetStatePropertyAll(Colors.transparent),
                      headingTextStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      dataTextStyle: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                      horizontalMargin: 6,
                      columnSpacing: 12,
                      headingRowHeight: 40,
                      dataRowMinHeight: 32,
                      dataRowMaxHeight: 32,
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
                        for (final key in keys.take(30))
                          DataRow(color: WidgetStatePropertyAll(personalStatPositionColor('${people[key]!['txt_position'] ?? ''}') ?? Colors.white), cells: [
                            DataCell(PlayerNameLink(
                                player: people[key]!,
                                child: Text(
                                    '${people[key]!['name_player'] ?? people[key]!['player_name'] ?? ''}'
                                        .replaceAll(RegExp(r'\(.*\)$'), ''), style: const TextStyle(fontSize: 14)))),
                            DataCell(Container(alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 4),
                                color: parseColorNameOrNull('${people[key]!['color_back'] ?? ''}'),
                                child: Text('${people[key]!['name_team'] ?? ''}', style: TextStyle(color: parseColorNameOrNull('${people[key]!['color_font'] ?? ''}'))))),
                            for (final title in columns)
                              DataCell(Tooltip(
                                  message:
                                      '${values[key]?[title]?['note'] ?? metricNotes[title] ?? title}',
                                  child: Text(
                                      personalStatDisplay(values[key]?[title] ?? {}, values[key]!.values))))
                          ])
                      ])))))
    ]);
  }
}

bool isPredictionStat(Map<String, dynamic> row) =>
    !extraBattingTitles.contains(row['title']) &&
    !extraPitchingTitles.contains(row['title']) &&
    !['代打打率', '盗塁成功率'].contains(row['title']);

bool isPredictedStatPlayer(Map<String, dynamic> row) =>
    isPredictionStat(row) && (
    '${row['id_users'] ?? ''}'.split('/').any((id) => (int.tryParse(id) ?? 0) > 0) ||
    '${row['colors_user'] ?? ''}'.split('/').any((color) => color.trim().isNotEmpty));

/// Keep the preview at ten rows, replacing the lowest non-predicted players.
List<Map<String, dynamic>> personalStatPreview(List<Map<String, dynamic>> ranked,
    {bool showPredictions = true, bool Function(Map<String, dynamic>)? isHighlighted}) {
  final result = ranked.take(10).toList();
  final outside = showPredictions ? ranked.skip(10).where(isPredictedStatPlayer).toList() : <Map<String, dynamic>>[];
  var slot = result.length - 1;
  for (final player in outside) {
    while (slot >= 0 && isPredictedStatPlayer(result[slot])) { slot--; }
    if (slot < 0) break;
    result[slot--] = player;
  }
  // Display retained rows in the same numeric order as the full ranking.
  final positions = {for (var i = 0; i < ranked.length; i++) ranked[i]: i};
  result.sort((a, b) => positions[a]!.compareTo(positions[b]!));
  final highlighted = isHighlighted == null ? null : ranked.where(isHighlighted).firstOrNull;
  if (highlighted != null && !result.contains(highlighted)) {
    if (result.length < 10) {
      result.add(highlighted);
    } else {
      result[result.length - 1] = highlighted;
    }
  }
  return result;
}

/// Qualification changes rank labels, not the numeric ordering of displayed rows.
void sortPersonalStatRows(List<Map<String, dynamic>> rows, {bool limitToThirty = true}) {
  rows.sort((a, b) {
    final title = '${a['title']}';
    final av = statNumeric(a), bv = statNumeric(b);
    if (av == null && bv != null) return 1;
    if (av != null && bv == null) return -1;
    if (av != null && bv != null) {
      final lowerIsBetter = ['防御率', 'WHIP', '被打率', '与四球率', 'BB/9', '四球/9', '四死球/9'].contains(title);
      final compared = lowerIsBetter ? av.compareTo(bv) : bv.compareTo(av);
      if (compared != 0) return compared;
    }
    return (int.tryParse('${a['int_rank']}') ?? 1000)
        .compareTo(int.tryParse('${b['int_rank']}') ?? 1000);
  });
  if (limitToThirty && rows.length > 30) {
    final predicted = rows.skip(30).where(isPredictedStatPlayer).toList();
    rows.removeRange(30, rows.length);
    rows.addAll(predicted);
  }
}

/// Japanese MLB players remain available beyond the normal popup cutoff.
List<Map<String, dynamic>> personalStatRankingDetail(List<Map<String, dynamic>> ranked, {bool includeJapanese = false}) {
  bool japanese(Map<String, dynamic> row) => ['true', 't', '1'].contains('${row['flg_japan']}'.toLowerCase());
  final top = (includeJapanese
      ? ranked.where((row) => int.tryParse('${row['int_rank']}') != 1000)
      : ranked).take(50).toSet();
  return ranked.where((row) => top.contains(row) || includeJapanese && japanese(row)).toList();
}
