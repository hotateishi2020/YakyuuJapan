import 'player_detail_dialog.dart';
import 'compact_layout.dart';
import '../logic/baseball_labor.dart';
import 'dart:math' as math;
import 'team_section_layout.dart';
import 'package:flutter/material.dart';
import '../logic/strength_usage.dart';
import '../logic/contract_fa.dart';
import '../logic/roster_contract_status.dart';
import 'strength_research.dart' show showStrengthSource;
import '../tools/json_utils.dart';
import '../tools/color_parse.dart';

String salaryAmount(int amount, String currency) {
  if (currency == 'USD') {
    final unit = amount > 100000000 ? 100000000 : 10000;
    final tenths = amount ~/ (unit ~/ 10);
    return '${tenths ~/ 10}.${tenths % 10}${unit == 100000000 ? '億' : '万'}ドル';
  }
  if (amount >= 100000000) {
    final tenths = amount ~/ 10000000;
    return '${tenths ~/ 10}.${tenths % 10}億円';
  }
  final oku = amount ~/ 100000000, remainder = amount % 100000000;
  final man = (remainder / 10000).toStringAsFixed(remainder % 10000 == 0 ? 0 : 1);
  return '${oku > 0 ? '$oku億' : ''}${remainder > 0 || oku == 0 ? '$man万' : ''}円';
}

String contractSalaryLabel(Map<String, dynamic> salary) {
  final currency = '${salary['currency'] ?? 'JPY'}';
  final amount = usageInt(salary['amount']);
  final label = salaryAmount(amount, currency);
  if (currency != 'USD') return label;
  final rate = double.tryParse('${salary['usd_jpy_rate']}');
  return rate != null && rate.isFinite && rate > 0 ? '$label（約${salaryAmount((amount * rate).floor(), 'JPY')}）' : '$label（円換算未確認）';
}

String contractExchangeTooltip(Map<String, dynamic> salary) {
  if (salary['projected'] == true) {
    return '${contractSalaryLabel(salary)}\n${salary['projection_note']}';
  }
  if (salary['usd_jpy_rate'] == null) return contractSalaryLabel(salary);
  return '${contractSalaryLabel(salary)}\n契約日：${salary['signed_date']}\n'
      '換算レート：${salary['exchange_date']}・1ドル＝${salary['usd_jpy_rate']}円（ECB）';
}

/// Fill future cells only within the current contract, keeping published pay intact.
/// These display projections are never written back as salary history.
List<Map<String, dynamic>> contractDisplaySalaries(List<Map<String, dynamic>> salaries, List<Map<String, dynamic>> periods, int year) {
  final result = [for (final s in salaries) Map<String, dynamic>.from(s)];
  final current = salaries.where((s) => usageInt(s['year']) == year && usageInt(s['amount']) > 0).firstOrNull;
  if (current == null) return result;
  final candidates = periods.where((p) => usageInt(p['start_year']) > 0 && usageInt(p['start_year']) <= year && usageInt(p['end_year']) > year && (p['team'] == null || current['team'] == null || p['team'] == current['team'])).toList();
  if (candidates.length != 1) return result;
  final contract = candidates.single;
  final start = usageInt(contract['start_year']), end = usageInt(contract['end_year']);
  if (end - start > 30 || contract['variable_salary'] == true || RegExp(r'変動|変額|年俸見直し|毎年更改|オプション|option|escalat|opt.out', caseSensitive: false).hasMatch('${contract['detail']} ${contract['total_label']}')) {
    return result;
  }
  final known = salaries.where((s) => usageInt(s['year']) >= start && usageInt(s['year']) <= end && s['amount'] != null);
  if (known.any((s) => usageInt(s['amount']) != usageInt(current['amount']) || (s['currency'] ?? 'JPY') != (current['currency'] ?? 'JPY'))) {
    return result;
  }
  for (var next = year + 1; next <= end; next++) {
    if (salaries.any((s) => usageInt(s['year']) == next)) continue;
    // A later contract/transfer takes precedence over the old term.
    if (periods.any((p) => !identical(p, contract) && usageInt(p['start_year']) > year && usageInt(p['start_year']) <= next && usageInt(p['end_year']) >= next)) {
      continue;
    }
    result.add({
      ...current,
      'year': next,
      'projected': true,
      'projection_note': '$year年の年俸が同額で継続すると仮定した表示（契約期限：$end年）',
      'contract_source_url': contract['source_url'],
    });
  }
  return result;
}

/// Explain future cells where a flat continuation cannot be shown.
Map<int, String> contractFutureNotes(List<Map<String, dynamic>> salaries, List<Map<String, dynamic>> periods, int year) {
  final notes = <int, String>{};
  for (final p in periods) {
    final start = usageInt(p['start_year']), end = usageInt(p['end_year']);
    if (start <= 0 || end < year || end - start > 30) continue;
    for (var next = math.max(year + 1, start); next <= end; next++) {
      final pay = salaries.where((s) => usageInt(s['year']) == next).firstOrNull;
      if (pay?['projected'] == true) continue;
      final text = [
        '${start == end ? '$start' : '$start–$end'}年 ${p['team'] ?? ''}',
        if ('${p['detail'] ?? ''}'.trim().isNotEmpty) '${p['detail']}',
        if ('${p['total_label'] ?? ''}'.trim().isNotEmpty) '${p['total_label']}',
        if (pay == null || pay['amount'] == null) '年俸額未公表',
      ].join('\n');
      notes[next] = [if (notes[next] != null) notes[next]!, text].join('\n');
    }
    if (end == year && !salaries.any((s) => usageInt(s['year']) == year + 1 && s['amount'] != null) && !periods.any((other) => usageInt(other['start_year']) <= year + 1 && usageInt(other['end_year']) > year)) {
      notes[year + 1] = '契約満了\n次期契約の内容・年俸は未確認';
    }
  }
  return notes;
}

/// Sum recorded annual salaries through the selected season, never contract totals.
String careerSalaryLabel(List<Map<String, dynamic>> salaries, int year) {
  final totals = <String, int>{};
  for (final salary in salaries) {
    final season = usageInt(salary['year']);
    final amount = usageInt(salary['amount']);
    if (season <= 0 || season > year || amount < 0) continue;
    final currency = '${salary['currency'] ?? 'JPY'}';
    totals[currency] = (totals[currency] ?? 0) + amount;
  }
  return totals.isEmpty ? '未確認' : totals.entries.map((e) => salaryAmount(e.value, e.key)).join('\n');
}

({int yen, int missing}) careerSalaryYen(List<Map<String, dynamic>> salaries, int year) {
  var yen = 0, missing = 0;
  for (final salary in salaries) {
    final season = usageInt(salary['year']);
    if (season <= 0 || season > year || salary['amount'] == null) continue;
    final amount = usageInt(salary['amount']);
    if (amount < 0) continue;
    final currency = '${salary['currency'] ?? 'JPY'}';
    if (currency == 'JPY') {
      yen += amount;
    } else {
      final rate = double.tryParse('${salary['usd_jpy_rate']}');
      if (currency == 'USD' && rate != null && rate.isFinite && rate > 0) {
        yen += (amount * rate).floor();
      } else {
        missing++;
      }
    }
  }
  return (yen: yen, missing: missing);
}

Color contractTeamColor(Map<String, dynamic> period, List<Map<String, dynamic>> teams) {
  final name = '${period['team'] ?? ''}'.trim();
  if (name.isNotEmpty) {
    for (final team in teams) {
      if (['name_team', 'name_shortest', 'name_full', 'abbreviation'].any((field) => '${team[field] ?? ''}'.trim() == name)) {
        return parseColorNameOrNull('${team['color_back']}') ?? Colors.blueGrey;
      }
    }
  }
  return Colors.blueGrey;
}

/// Annual evidence fills gaps without inventing a multi-year contract term.
List<Map<String, dynamic>> contractTimelineBands(List<Map<String, dynamic>> periods, List<Map<String, dynamic>> salaries, [List<Map<String, dynamic>> affiliations = const []]) {
  final bands = periods.where((p) => usageInt(p['start_year']) > 0 && usageInt(p['end_year']) >= usageInt(p['start_year'])).map((p) => Map<String, dynamic>.from(p)).toList();
  final confirmed = List<Map<String, dynamic>>.from(bands);
  final seen = <int>{};
  for (final salary in [
    ...salaries,
    ...affiliations,
    ...periods.where((p) => usageInt(p['start_year']) > 0).map((p) => {'year': p['start_year'], 'team': p['team']}),
  ]) {
    final year = usageInt(salary['year']);
    if (year <= 0 || !seen.add(year) || confirmed.any((p) => year >= usageInt(p['start_year']) && year <= usageInt(p['end_year']))) {
      continue;
    }
    bands.add({
      'start_year': year,
      'end_year': year,
      'team': salary['team'],
      'annual_evidence': true,
      'period': '$year年 所属履歴',
      'detail': '${salary['detail'] ?? ''}',
    });
  }
  return bands;
}

/// A horizontal banknote stack. Every bar uses the same currency-specific scale.
int salaryWrapAmount(String currency) => currency == 'USD' ? 20000000 : 500000000;
int salaryBarRows(int amount, int limit) => amount <= 0 || limit <= 0 ? 1 : (amount + limit - 1) ~/ limit;

String salaryBanknoteCurrency(Map<String, dynamic> salary) {
  if (salary['currency'] == 'USD' || salary['code_org'] == 'mlb') return 'USD';
  const mlbTeams = {
    'オリオールズ',
    'レッドソックス',
    'ヤンキース',
    'レイズ',
    'ブルージェイズ',
    'ホワイトソックス',
    'ガーディアンズ',
    'インディアンス',
    'タイガース',
    'ロイヤルズ',
    'ツインズ',
    'アストロズ',
    'エンゼルス',
    'アスレチックス',
    'マリナーズ',
    'レンジャーズ',
    'ブレーブス',
    'マーリンズ',
    'メッツ',
    'フィリーズ',
    'ナショナルズ',
    'エクスポズ',
    'カブス',
    'レッズ',
    'ブルワーズ',
    'パイレーツ',
    'カージナルス',
    'ダイヤモンドバックス',
    'ロッキーズ',
    'ドジャース',
    'パドレス',
    'ジャイアンツ',
    'BAL',
    'BOS',
    'NYY',
    'TB',
    'TOR',
    'CWS',
    'CLE',
    'DET',
    'KC',
    'MIN',
    'HOU',
    'LAA',
    'ATH',
    'OAK',
    'SEA',
    'TEX',
    'ATL',
    'MIA',
    'NYM',
    'PHI',
    'WSH',
    'CHC',
    'CIN',
    'MIL',
    'PIT',
    'STL',
    'AZ',
    'ARI',
    'COL',
    'LAD',
    'SD',
    'SF',
  };
  final teams = '${salary['team'] ?? ''}'.split(RegExp(r'\s*(?:→|/|、)\s*'));
  return teams.isNotEmpty && teams.every((t) => mlbTeams.contains(t.trim())) ? 'USD' : '${salary['currency'] ?? 'JPY'}';
}

class SalaryMoneyBar extends StatelessWidget {
  const SalaryMoneyBar({super.key, required this.amount, required this.maximum, this.currency = 'JPY', this.banknoteCurrency, this.wrapAt});
  final int amount;
  final int maximum;
  final int? wrapAt;
  final String currency;
  final String? banknoteCurrency;
  @override
  Widget build(BuildContext context) => Semantics(
      label: '年俸 ${salaryAmount(amount, currency)}',
      child: Tooltip(
          message: salaryAmount(amount, currency),
          child: LayoutBuilder(builder: (context, constraints) {
            final limit = wrapAt ?? maximum;
            final rows = wrapAt == null ? 1 : salaryBarRows(amount, limit);
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(rows, (index) {
                  final remaining = amount - index * limit;
                  final ratio = limit > 0 ? (remaining / limit).clamp(0.0, 1.0) : 0.0;
                  return SizedBox(height: 32, child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: constraints.maxWidth * ratio, height: 28, child: CustomPaint(painter: _MoneyBarPainter(banknoteCurrency ?? currency)))));
                }));
          })));
}

class _MoneyBarPainter extends CustomPainter {
  const _MoneyBarPainter(this.currency);
  final String currency;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final usd = currency == 'USD';
    final face = usd ? const Color(0xFFBDD0AE) : const Color(0xFFE5DCBC);
    final edge = usd ? const Color(0xFF668460) : const Color(0xFF9C8D64);
    final ink = usd ? const Color(0xFF315D3A) : const Color(0xFF675A3B);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Identical bundles overlap in one direction, from left to right.
    final count = ((size.width - 28) / 10).ceil().clamp(0, 1000) + 1;
    final step = count > 1 ? (size.width - 28) / (count - 1) : 0.0;
    if (size.width < 28) canvas.scale(size.width / 28, 1);
    for (var i = 0; i < count; i++) {
      final x = i * step;
      final side = Path()
        ..moveTo(x, 5)
        ..lineTo(x + 24, 5)
        ..lineTo(x + 28, 9)
        ..lineTo(x + 28, 24)
        ..lineTo(x + 4, 24)
        ..lineTo(x, 20)
        ..close();
      canvas.drawPath(side, Paint()..color = edge);
      for (var dy = 1.0; dy <= 3; dy++) {
        canvas.drawLine(
            Offset(x + 4, 20 + dy),
            Offset(x + 27, 20 + dy),
            Paint()
              ..color = face
              ..strokeWidth = .5);
      }
      final rect = Rect.fromLTWH(x, 4, 24, 16);
      canvas.drawRect(rect, Paint()..color = face);
      canvas.drawRect(
          rect.deflate(1),
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = .6);
      canvas.drawOval(Rect.fromLTWH(x + 13, 7, 7, 10), Paint()..color = edge);
      canvas.drawRect(Rect.fromLTWH(x + 9, 4, 3, 16), Paint()..color = const Color(0xFFF3F0DF));
      final text = TextPainter(text: TextSpan(text: usd ? '\$' : '¥', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: ink)), textDirection: TextDirection.ltr)..layout();
      text.paint(canvas, Offset(x + 2, 7));
      text.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MoneyBarPainter old) => old.currency != currency;
}

List<Map<String, dynamic>> teamSalaryTotals(List<Map<String, dynamic>> teams, int year) {
  final rows = <Map<String, dynamic>>[];
  for (final team in teams) {
    final totals = <String, int>{};
    final seen = <String>{};
    var count = 0;
    for (final player in listMapFromJson(team['contracts'])) {
      final key = usagePlayerKey(player);
      if (!seen.add(key)) continue;
      final salary = listMapFromJson(player['salary_history']).where((s) => usageInt(s['year']) == year && s['amount'] != null).firstOrNull;
      if (salary == null || usageInt(salary['amount']) < 0) continue;
      final currency = '${salary['currency'] ?? 'JPY'}';
      totals[currency] = (totals[currency] ?? 0) + usageInt(salary['amount']);
      count++;
    }
    rows.add({'team': team, 'totals': totals, 'count': count});
  }
  return rows;
}

class VerticalSalaryMoneyBar extends StatelessWidget {
  const VerticalSalaryMoneyBar({super.key, required this.amount, required this.maximum, required this.currency});
  final int amount;
  final int maximum;
  final String currency;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '総年俸 ${salaryAmount(amount, currency)}',
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: maximum > 0 ? (amount / maximum).clamp(0.0, 1.0) : 0,
            child: SizedBox(width: 56, child: CustomPaint(painter: _VerticalMoneyPainter(currency))),
          ),
        ),
      );
}

class _VerticalMoneyPainter extends CustomPainter {
  const _VerticalMoneyPainter(this.currency);
  final String currency;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Keep each banknote horizontal and stack identical bundles upward.
    final height = size.height < 24 ? 24.0 : size.height;
    if (size.height < 24) canvas.scale(1, size.height / 24);
    final count = ((height - 24) / 5).ceil() + 1;
    final step = count > 1 ? (height - 24) / (count - 1) : 0.0;
    for (var i = 0; i < count; i++) {
      canvas.save();
      canvas.translate(0, height - 24 - i * step - 4);
      canvas.scale(size.width / 28, 1);
      _MoneyBarPainter(currency).paint(canvas, const Size(28, 28));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VerticalMoneyPainter old) => old.currency != currency;
}

class TeamSalaryChart extends StatelessWidget {
  const TeamSalaryChart({super.key, required this.teams, required this.year});
  final List<Map<String, dynamic>> teams;
  final int year;

  @override
  Widget build(BuildContext context) {
    final rows = teamSalaryTotals(teams, year);
    final maxima = <String, int>{};
    for (final row in rows) {
      for (final entry in (row['totals'] as Map<String, int>).entries) {
        if (entry.value > (maxima[entry.key] ?? 0)) {
          maxima[entry.key] = entry.value;
        }
      }
    }
    final isMlb = teams.isNotEmpty && teams.every((t) => [3, 4].contains(usageInt(t['id_league'])));
    final compactNpb = !isMlb && compactBaseballLayout(context);
    Widget graphRow(List<Map<String, dynamic>> group) => SizedBox(
        height: 128,
        child: LayoutBuilder(builder: (context, constraints) {
          final availableWidth = constraints.maxWidth / (group.isEmpty ? 1 : group.length);
          final width = compactNpb ? availableWidth : availableWidth.clamp(94.0, 180.0);
          return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final row in group)
                  SizedBox(
                      width: width,
                      child: Tooltip(
                          message: '${row['team']['name_team']}：${row['count']}人分。未取得の年俸は含みません。',
                          child: Column(children: [
                            for (final entry in (row['totals'] as Map<String, int>).entries)
                              Expanded(
                                  child: Column(children: [
                                FittedBox(fit: BoxFit.scaleDown, child: Text(salaryAmount(entry.value, entry.key), maxLines: 1, style: const TextStyle(fontSize: 11))),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: VerticalSalaryMoneyBar(key: ValueKey('team-salary-bar-${row['team']['id_team']}-${entry.key}'), amount: entry.value, maximum: maxima[entry.key] ?? 0, currency: entry.key),
                                  ),
                                ),
                              ])),
                            if ((row['totals'] as Map).isEmpty) const Expanded(child: Center(child: Text('未確認', style: TextStyle(fontSize: 11)))),
                            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${compactNpb ? row['team']['name_shortest'] ?? row['team']['name_team'] : row['team']['name_team']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
                          ]))),
              ]));
        }));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('$year年度 球団別総年俸（取得済み・推定額を含む）', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        if (isMlb || compactNpb)
          for (final league in isMlb ? [3, 4] : [1, 2]) ...[
            Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 4), child: Text(const {1: 'セ・リーグ', 2: 'パ・リーグ', 3: 'ア・リーグ', 4: 'ナ・リーグ'}[league]!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
            graphRow(rows.where((row) => usageInt(row['team']['id_league']) == league).toList()),
          ]
        else
          graphRow(rows),
      ],
    );
  }
}

/// Selected-year, recorded salaries only; currencies are never mixed.
Map<String, List<Map<String, dynamic>>> teamSalaryShares(Map<String, dynamic> team, int year) {
  final groups = <String, List<Map<String, dynamic>>>{};
  final seen = <String>{};
  for (final player in listMapFromJson(team['contracts'])) {
    if (!seen.add(usagePlayerKey(player))) continue;
    final salary = listMapFromJson(player['salary_history']).where((s) => usageInt(s['year']) == year && s['amount'] != null).firstOrNull;
    if (salary == null || usageInt(salary['amount']) <= 0) continue;
    final currency = '${salary['currency'] ?? 'JPY'}';
    (groups[currency] ??= []).add({'player': player, 'amount': usageInt(salary['amount'])});
  }
  for (final players in groups.values) {
    players.sort((a, b) => (b['amount'] as int).compareTo(a['amount'] as int));
    final total = players.fold<int>(0, (sum, p) => sum + (p['amount'] as int));
    for (final player in players) {
      player['share'] = (player['amount'] as int) / total;
    }
  }
  return groups;
}

class TeamSalaryShareBands extends StatelessWidget {
  const TeamSalaryShareBands({super.key, required this.teams, required this.year});
  final List<Map<String, dynamic>> teams;
  final int year;

  String _label(Map<String, dynamic> p, String currency) =>
      '${p['player']['name']}  ${salaryAmount(p['amount'] as int, currency)}  ${((p['share'] as double) * 100).toStringAsFixed(1)}%';

  void _details(BuildContext context, Map<String, dynamic> team, String currency, List<Map<String, dynamic>> players) {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text('${team['name_team']}・$year年 年俸内訳'),
      content: SizedBox(width: 440, child: ListView.separated(
        shrinkWrap: true,
        itemCount: players.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => ListTile(dense: true,
          title: Text('${players[i]['player']['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(salaryAmount(players[i]['amount'] as int, currency)),
          trailing: Text('${((players[i]['share'] as double) * 100).toStringAsFixed(1)}%'),
        ),
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final maxima = <String, int>{};
    for (final row in teamSalaryTotals(teams, year)) {
      for (final entry in (row['totals'] as Map<String, int>).entries) {
        maxima[entry.key] = math.max(maxima[entry.key] ?? 0, entry.value);
      }
    }
    return Padding(
    padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('$year年度 球団総年俸の選手別割合', style: const TextStyle(fontWeight: FontWeight.bold)),
      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('帯の長さは球団総年俸、中の区画は選手別の割合です。通貨ごとに最大額の球団を基準に比較します。取得済みの推定額のみ集計。帯を押すと全選手の内訳を表示します。', style: TextStyle(fontSize: 11))),
      for (final team in teams) ...[
        Builder(builder: (context) {
          final groups = teamSalaryShares(team, year);
          final color = parseColorName('${team['color_back'] ?? ''}', Colors.blueGrey);
          return Column(children: [
            if (groups.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text('${team['name_team']}：年俸未取得')),
            for (final entry in groups.entries)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: LayoutBuilder(builder: (context, constraints) {
                final compact = constraints.maxWidth < 600;
                final total = entry.value.fold<int>(0, (sum, p) => sum + (p['amount'] as int));
                final ratio = total / maxima[entry.key]!;
                final availableWidth = constraints.maxWidth - (compact ? 0 : 136);
                final noteWidth = math.min(58.0, availableWidth);
                final bandWidth = (availableWidth - noteWidth) * ratio + noteWidth;
                final heading = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(color: Color.lerp(color, Colors.white, .55), borderRadius: BorderRadius.circular(5)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${team['name_team']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(salaryAmount(total, entry.key), style: const TextStyle(fontSize: 11)),
                  ]),
                );
                final band = Semantics(button: true, label: '${team['name_team']} 年俸内訳', child: InkWell(
                  onTap: () => _details(context, team, entry.key, entry.value),
                  child: SizedBox(key: ValueKey('salary-share-band-${team['id_team']}-${entry.key}'), width: bandWidth, height: 64, child: Row(children: [
                    Expanded(child: ClipRRect(borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)), child: CustomPaint(
                      foregroundPainter: const _SalaryStackTexture(),
                      child: Row(children: [
                        for (var i = 0; i < entry.value.length; i++)
                          Expanded(flex: entry.value[i]['amount'] as int, child: Tooltip(
                            message: _label(entry.value[i], entry.key),
                            child: Container(height: 64, alignment: Alignment.center,
                              decoration: BoxDecoration(color: Color.lerp(const Color(0xFFB8A77A), const Color(0xFFEDE4C9), const [0.15, 0.80, 0.40, 1.0, 0.60][i % 5]), border: const Border(right: BorderSide(color: Colors.white54))),
                              child: LayoutBuilder(builder: (_, box) => box.maxWidth < 42 ? const SizedBox.shrink() : Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  FittedBox(fit: BoxFit.scaleDown, child: Text(salaryAmount(entry.value[i]['amount'] as int, entry.key), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  Text('${entry.value[i]['player']['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  Text('${((entry.value[i]['share'] as double) * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11)),
                                ]),
                              )),
                            ),
                          )),
                      ]),
                    ))),
                    SizedBox(key: ValueKey('salary-banknote-${team['id_team']}-${entry.key}'), width: noteWidth, height: 64, child: ClipRect(child: CustomPaint(painter: _SalaryBanknoteTip(entry.key)))),
                  ])),
                ));
                return compact ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [heading, const SizedBox(height: 4), Align(alignment: Alignment.centerLeft, child: band)]) : Row(children: [SizedBox(width: 128, height: 64, child: heading), const SizedBox(width: 8), band]);
              })),
          ]);
        }),
      ],
    ]),
  );
  }
}

class _SalaryStackTexture extends CustomPainter {
  const _SalaryStackTexture();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x12645835)..strokeWidth = .6;
    for (double y = 2; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override
  bool shouldRepaint(_SalaryStackTexture old) => false;
}

class _SalaryBanknoteTip extends CustomPainter {
  const _SalaryBanknoteTip(this.currency);
  final String currency;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = const Color(0xFFE5DCBC));
    canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(4), const Radius.circular(3)), Paint()..color = const Color(0xFF9C8D64)..style = PaintingStyle.stroke..strokeWidth = 1.2);
    canvas.drawOval(Rect.fromCenter(center: rect.center, width: 33, height: 43), Paint()..color = const Color(0xFFD0C59E));
    final text = TextPainter(text: TextSpan(text: currency == 'USD' ? '\$' : '¥', style: const TextStyle(color: Color(0xFF675A3B), fontSize: 25, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
    text.paint(canvas, rect.center - Offset(text.width / 2, text.height / 2));
    text.dispose();
  }
  @override
  bool shouldRepaint(_SalaryBanknoteTip old) => old.currency != currency;
}

class StrengthContracts extends StatefulWidget {
  const StrengthContracts({super.key, required this.team, required this.year, this.comparisonTeams, this.colorTeams});
  final Map<String, dynamic> team;
  final int year;
  final List<Map<String, dynamic>>? comparisonTeams;
  final List<Map<String, dynamic>>? colorTeams;
  static const yearWidth = 160.0;
  @override
  State<StrengthContracts> createState() => _StrengthContractsState();
}

class _StrengthContractsState extends State<StrengthContracts> {
  final _horizontal = ScrollController(keepScrollOffset: false);
  String? _focusedDataset;
  bool _sortByCareer = false;
  static const yearWidth = StrengthContracts.yearWidth;
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  Widget _pinnedName(Widget child) => AnimatedBuilder(
        animation: _horizontal,
        child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: child),
        builder: (context, child) => Transform.translate(offset: Offset(_horizontal.hasClients ? _horizontal.offset : 0, 0), child: child),
      );

  Widget get _notes => const Padding(padding: EdgeInsets.all(8), child: Text('札束は1段につきNPBは5億円、MLBは2000万ドルで折り返します。年ごとの推定年俸を契約帯の下に表示します。契約期間未確認の年も、年俸・所属が確認できれば球団色で表示します。確認状況は帯の詳細で確認できます。生涯年俸は選択年度までに取得できた年俸の合計（推定額を含む）です。未取得年と将来年は含みません。生涯年俸の札束はNPBでは20億円、MLBでは2000万ドルごとに折り返します。NPBのドル建て年俸は契約時レートで円換算できた分のみ描画します。円と米ドルは別の尺度です。円換算は契約日当日（休業日は直前公表日）のECBレートによる概算です。契約日・レート未確認の場合は換算しません。FAラベルは確認できた取得年（再取得を含む）のみ表示します。将来の最短試算は「見込み」と表示し、一軍登録日数等により変わります。ラベルから根拠を確認できます。', style: TextStyle(fontSize: 11)));

  bool get _pinCareer => !compactBaseballLayout(context);
  Widget _careerCell(Widget child) => _pinCareer ? _pinnedName(child) : child;

  void _focusYear(String dataset, int first) {
    if (_focusedDataset == dataset) return;
    _focusedDataset = dataset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusedDataset != dataset || !_horizontal.hasClients) {
        return;
      }
      _horizontal.jumpTo((compactBaseballLayout(context) ? 0.0 : (widget.year - first) * yearWidth + (_pinCareer ? 0 : 180)).clamp(0.0, _horizontal.position.maxScrollExtent));
    });
  }

  double _textHeight(BuildContext context, String text, TextStyle style, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final year = widget.year;
        final compact = compactBaseballLayout(context);
        final careerWidth = compact ? 0.0 : 180.0;
        final teams = widget.comparisonTeams ?? [widget.team];
        final colorTeams = widget.colorTeams ?? teams;
        final entries = <Map<String, dynamic>>[];
        final years = <int>[year];
        for (final t in teams) {
          final records = listMapFromJson(t['contracts']);
          final roster = listMapFromJson(t['roster']);
          for (final player in [...roster, ...records.where((p) => !roster.any((r) => usagePlayerKey(r) == usagePlayerKey(p)))]) {
            final record = records.where((p) => usagePlayerKey(p) == usagePlayerKey(player)).firstOrNull;
            final periods = listMapFromJson(record?['periods']);
            final salaries = contractDisplaySalaries(listMapFromJson(record?['salary_history']), periods, year);
            final futureNotes = contractFutureNotes(salaries, periods, year);
            years.addAll(futureNotes.keys);
            final faEvents = [
              ...contractFaEvents(player, record, isNpb: npbContractTeam(t)),
              ...registrationExemptionEvents(player, record, isNpb: npbContractTeam(t)),
            ];
            years.addAll(faEvents.map((e) => usageInt(e['year'])));
            final affiliations = [
              ...listMapFromJson(record?['affiliation_history']),
              if (roster.any((p) => usagePlayerKey(p) == usagePlayerKey(player))) {'year': year, 'team': t['name_team']},
            ];
            for (final affiliation in affiliations) {
              if (usageInt(affiliation['year']) > 0) {
                years.add(usageInt(affiliation['year']));
              }
            }
            for (final salary in salaries) {
              if (usageInt(salary['year']) > 0) {
                years.add(usageInt(salary['year']));
              }
            }
            for (final period in periods) {
              for (final field in ['start_year', 'end_year']) {
                if (usageInt(period[field]) > 0) {
                  years.add(usageInt(period[field]));
                }
              }
            }
            entries.add({'order': entries.length, 'career_salary': salaries.where((s) => usageInt(s['year']) > 0 && usageInt(s['year']) <= year && s['amount'] != null).fold<int?>(null, (sum, s) => (sum ?? 0) + usageInt(s['amount'])), 'current_salary': salaries.where((salary) => usageInt(salary['year']) == year).firstOrNull?['amount'], 'player': player, 'team': t, 'salaries': salaries, 'future_notes': futureNotes, 'fa_events': faEvents, 'affiliations': affiliations, 'periods': periods, 'source': record?['source_url']});
          }
        }
        entries.sort((a, b) {
          final field = _sortByCareer && !compact ? 'career_salary' : 'current_salary';
          final left = a[field] == null ? -1 : usageInt(a[field]);
          final right = b[field] == null ? -1 : usageInt(b[field]);
          final salaryOrder = right.compareTo(left);
          return salaryOrder != 0 ? salaryOrder : usageInt(a['order']).compareTo(usageInt(b['order']));
        });
        years.sort();
        final first = compact ? year : years.first, last = compact ? year : years.last;
        final mlbContracts = teams.isNotEmpty && teams.every((t) => t['org'] == 'mlb' || [3, 4].contains(usageInt(t['id_league'])));
        Widget yearLabel(int y) {
          final labor = baseballLaborLabel(y, mlb: mlbContracts);
          return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$y年'),
            if (labor != null)
              Tooltip(
                  message: labor.note,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    color: labor.label.contains('未確定') ? Colors.amber.shade100 : Colors.red.shade50,
                    child: FittedBox(child: Text(labor.label, style: const TextStyle(fontSize: 9, color: Colors.red))),
                  )),
          ]);
        }

        Widget salaryHeader(String title) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFF455A64),
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        );

        final nameWidth = compactBaseballLayout(context) ? 80.0 : 160.0;
        final yearWidth = compact && constraints.maxWidth.isFinite ? (constraints.maxWidth - nameWidth).clamp(1.0, double.infinity) : StrengthContracts.yearWidth;
        final chartWidth = (last - first + 1) * yearWidth;
        _focusYear('$_sortByCareer/$year/$first/$last/${teams.map((t) => t['id_team']).join('-')}', first);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('今年度年俸順'), selected: compact || !_sortByCareer, onSelected: (_) => setState(() => _sortByCareer = false)),
              if (!compact) ChoiceChip(label: const Text('生涯年俸順'), selected: _sortByCareer, onSelected: (_) => setState(() => _sortByCareer = true)),
            ]),
          ),
          if (widget.comparisonTeams == null && TeamSectionLayout.embedded(context))
            TeamSalaryShareBands(teams: [widget.team], year: year),
          SectionExpanded(
              child: _ContractScroll(
                  key: const ValueKey('contract-vertical-scroll'),
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                        if (widget.comparisonTeams != null) ...[
                          SliverToBoxAdapter(child: salaryHeader('球団別年俸')),
                          SliverToBoxAdapter(child: TeamSalaryChart(teams: teams, year: year)),
                          SliverToBoxAdapter(child: TeamSalaryShareBands(teams: teams, year: year)),
                          SliverToBoxAdapter(child: salaryHeader('選手別年俸')),
                        ] else
                          SliverToBoxAdapter(child: TeamSalaryShareBands(teams: [widget.team], year: year)),
                      ],
                  body: SingleChildScrollView(
                      key: const ValueKey('contract-horizontal-scroll'),
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                          width: nameWidth + chartWidth + careerWidth,
                          child: Column(children: [
                            SizedBox(
                                height: 48,
                                child: Stack(children: [
                                  Row(children: [
                                    SizedBox(width: nameWidth + careerWidth),
                                    for (var y = first; y <= last; y++) Container(key: ValueKey('contract-year-$y'), width: yearWidth, height: 48, alignment: Alignment.center, color: y == year ? Colors.amber.shade300 : Colors.grey.shade200, child: yearLabel(y)),
                                  ]),
                                  if (!compact) Positioned(left: nameWidth, top: 0, bottom: 0, width: 180, child: _careerCell(Container(color: Colors.grey.shade200, alignment: Alignment.center, child: const Text('生涯年俸')))),
                                  Positioned(left: 0, top: 0, bottom: 0, width: nameWidth, child: _pinnedName(const Center(child: Text('球団・選手')))),
                                ])),
                            SectionExpanded(
                                child: ListView.builder(
                                    primary: !TeamSectionLayout.embedded(context),
                                    shrinkWrap: TeamSectionLayout.embedded(context),
                                    physics: TeamSectionLayout.embedded(context) ? const NeverScrollableScrollPhysics() : null,
                                    key: ValueKey('contract-rows-${teams.map((t) => t['id_team']).join('-')}'),
                                    itemCount: entries.length + 1,
                                    itemBuilder: (context, index) {
                                      if (index == entries.length) {
                                        return _pinnedName(Align(alignment: Alignment.centerLeft, child: SizedBox(width: MediaQuery.sizeOf(context).width, child: _notes)));
                                      }
                                      final e = entries[index];
                                      final periods = listMapFromJson(e['periods']);
                                      final salaries = listMapFromJson(e['salaries']).where((s) => !compact || usageInt(s['year']) == year).toList();
                                      final career = careerSalaryYen(salaries, year);
                                      final isMlb = e['team']['org'] == 'mlb' || [3, 4].contains(usageInt(e['team']['id_league']));
                                      final careerCurrency = isMlb ? 'USD' : 'JPY';
                                      final careerAmount = isMlb ? salaries.where((s) => usageInt(s['year']) > 0 && usageInt(s['year']) <= year && s['currency'] == 'USD').fold<int>(0, (sum, s) => sum + usageInt(s['amount'])) : career.yen;
                                      final careerWrap = isMlb ? 20000000 : 2000000000;
                                      final hasForeign = salaries.any((s) => usageInt(s['year']) > 0 && usageInt(s['year']) <= year && (s['currency'] ?? 'JPY') != 'JPY');
                                      final careerLabel = careerSalaryLabel(salaries, year) + (hasForeign ? '\n${career.missing > 0 ? '円換算確認分' : '円換算'}：${salaryAmount(career.yen, 'JPY')}' : '');
                                      final careerHeight = compact ? 0.0 : 16 + _textHeight(context, careerLabel, const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), 164) + (careerAmount > 0 ? salaryBarRows(careerAmount, careerWrap) * 32.0 : 0) + (career.missing > 0 ? _textHeight(context, '未換算：${career.missing}年分', const TextStyle(fontSize: 10), 164) : 0);
                                      final bands = contractTimelineBands(periods, salaries, listMapFromJson(e['affiliations'])).where((b) => !compact || usageInt(b['start_year']) <= year && usageInt(b['end_year']) >= year).toList();
                                      final lineHeight = _textHeight(context, '年俸', const TextStyle(fontSize: 11), yearWidth - 8);
                                      final periodHeight = (lineHeight + 4).clamp(22.0, double.infinity);
                                      final topHeight = 4.0 + (first == last || bands.isEmpty ? 0 : periodHeight + 2);
                                      final moneyHeight = salaries.any((s) => usageInt(s['year']) > 0) ? salaries.map((s) => salaryBarRows(usageInt(s['amount']), salaryWrapAmount('${s['currency'] ?? 'JPY'}'))).fold<int>(1, (a, b) => a > b ? a : b) * 32.0 + lineHeight + 2 : 0.0;
                                      final nameHeight = _textHeight(context, '${e['team']['name_team']}', const TextStyle(fontSize: 11), nameWidth - 16) + _textHeight(context, '${e['player']['name']}', const TextStyle(fontWeight: FontWeight.bold), nameWidth - 16) + 8;
                                      final futureNotes = {
                                        for (final entry in (e['future_notes'] as Map<int, String>).entries)
                                          if (!compact || entry.key == year) entry.key: entry.value
                                      };
                                      final noteHeight = futureNotes.isEmpty ? 0.0 : 68.0;
                                      final faByYear = <int, List<Map<String, dynamic>>>{};
                                      for (final event in listMapFromJson(e['fa_events']).where((e) => !compact || usageInt(e['year']) == year)) {
                                        faByYear.putIfAbsent(usageInt(event['year']), () => []).add(event);
                                      }
                                      final faLabelHeight = _textHeight(context, '国内FA権獲得（見込み）', const TextStyle(fontSize: 10), yearWidth - 16) + 8;
                                      final faHeight = faByYear.values.fold<double>(0, (h, events) => math.max(h, events.length * faLabelHeight));
                                      final rowHeight = (topHeight + moneyHeight + noteHeight + faHeight + 4).clamp(nameHeight > careerHeight ? nameHeight : careerHeight, double.infinity).ceilToDouble() + 1; // Bottom border.
                                      return Container(
                                          key: ValueKey('contract-player-${e['team']['id_team']}-${usagePlayerKey(e['player'])}'),
                                          height: rowHeight,
                                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade400))),
                                          child: Stack(children: [
                                            Positioned(
                                                left: nameWidth + careerWidth,
                                                top: 0,
                                                bottom: 0,
                                                child: SizedBox(
                                                    width: chartWidth,
                                                    child: Stack(children: [
                                                      for (var y = first; y <= last; y++) Positioned(left: (y - first) * yearWidth, top: 0, bottom: 0, child: Container(width: yearWidth, decoration: BoxDecoration(color: y == year ? Colors.amber.withValues(alpha: .18) : null, border: Border(left: BorderSide(color: Colors.grey.shade300))))),
                                                      if (first != last)
                                                        for (var i = 0; i < bands.length; i++) Positioned(left: (compact ? 0 : usageInt(bands[i]['start_year']) - first) * yearWidth + 2, top: 4, width: (compact ? 1 : usageInt(bands[i]['end_year']) - usageInt(bands[i]['start_year']) + 1) * yearWidth - 4, height: periodHeight, child: Tooltip(message: '${bands[i]['period'] ?? ''} ${bands[i]['detail'] ?? ''}', child: Container(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: contractTeamColor(bands[i], colorTeams), borderRadius: BorderRadius.circular(4)), child: Text(bands[i]['start_year'] == bands[i]['end_year'] ? '${bands[i]['start_year']} ${bands[i]['team'] ?? ''}' : '${bands[i]['start_year']}–${bands[i]['end_year']} ${bands[i]['team'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: contractTeamColor(bands[i], colorTeams).computeLuminance() > .179 ? Colors.black : Colors.white))))),
                                                      for (final note in futureNotes.entries)
                                                        Positioned(
                                                          left: (note.key - first) * yearWidth + 4,
                                                          top: topHeight + moneyHeight + 2,
                                                          width: yearWidth - 8,
                                                          height: noteHeight - 4,
                                                          child: Tooltip(
                                                            message: note.value,
                                                            child: InkWell(
                                                              onTap: () => showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text('${note.key}年の契約内容'), content: SelectableText(note.value), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))])),
                                                              child: Text(note.value, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black87)),
                                                            ),
                                                          ),
                                                        ),
                                                      for (final entry in faByYear.entries)
                                                        Positioned(
                                                          left: (entry.key - first) * yearWidth + 4,
                                                          top: topHeight + moneyHeight + noteHeight,
                                                          width: yearWidth - 8,
                                                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                                            for (final event in entry.value)
                                                              Tooltip(
                                                                message: '${event['detail']}',
                                                                child: InkWell(
                                                                  onTap: () => showStrengthSource(context, '${entry.key}年 ${contractFaLabel(event)}', '${event['detail'] ?? ''}', ['${event['source_url']}']),
                                                                  child: Container(
                                                                    height: faLabelHeight - 2,
                                                                    margin: const EdgeInsets.only(bottom: 2),
                                                                    alignment: Alignment.center,
                                                                    decoration: BoxDecoration(color: event['type'] == 'international' ? Colors.purple.shade100 : Colors.blue.shade100, borderRadius: BorderRadius.circular(4)),
                                                                    child: Text(contractFaLabel(event), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.black87)),
                                                                  ),
                                                                ),
                                                              ),
                                                          ]),
                                                        ),
                                                      for (final salary in salaries)
                                                        if (usageInt(salary['year']) > 0)
                                                          Positioned(
                                                              left: (usageInt(salary['year']) - first) * yearWidth + 4,
                                                              top: topHeight,
                                                              width: yearWidth - 8,
                                                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                                Tooltip(
                                                                  message: contractExchangeTooltip(salary),
                                                                  child: SizedBox(
                                                                    height: lineHeight + 2,
                                                                    child: FittedBox(
                                                                      fit: BoxFit.scaleDown,
                                                                      alignment: Alignment.centerLeft,
                                                                      child: Text(contractSalaryLabel(salary), style: const TextStyle(fontSize: 11)),
                                                                    ),
                                                                  ),
                                                                ),
                                                                SalaryMoneyBar(banknoteCurrency: salaryBanknoteCurrency(salary), amount: usageInt(salary['amount']), maximum: salaryWrapAmount('${salary['currency'] ?? 'JPY'}'), wrapAt: salaryWrapAmount('${salary['currency'] ?? 'JPY'}'), currency: '${salary['currency'] ?? 'JPY'}'),
                                                              ])),
                                                    ]))),
                                            if (!compact)
                                              Positioned(
                                                left: nameWidth,
                                                top: 0,
                                                bottom: 0,
                                                width: 180,
                                                child: _careerCell(Container(
                                                  key: ValueKey('career-salary-${e['team']['id_team']}-${usagePlayerKey(e['player'])}'),
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(color: Color.lerp(contractTeamColor({'team': e['team']['name_team']}, colorTeams), Colors.white, .85), border: Border(left: BorderSide(color: Colors.grey.shade300))),
                                                  child: Tooltip(
                                                    message: '$year年度までの取得済み年俸の合計。札束は${isMlb ? 'ドル建ての年俸を2000万ドル' : '円換算できた年俸を20億円'}ごとに折り返します。',
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(careerLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                        if (careerAmount > 0) SalaryMoneyBar(key: ValueKey('career-money-${e['team']['id_team']}-${usagePlayerKey(e['player'])}'), amount: careerAmount, currency: careerCurrency, maximum: careerWrap, wrapAt: careerWrap),
                                                        if (career.missing > 0) Text('未換算：${career.missing}年分', style: const TextStyle(fontSize: 10)),
                                                      ],
                                                    ),
                                                  ),
                                                )),
                                              ),
                                            Positioned(
                                              left: 0,
                                              top: 0,
                                              bottom: 0,
                                              width: nameWidth,
                                              child: _pinnedName(Container(
                                                key: ValueKey('contract-name-${e['team']['id_team']}-${usagePlayerKey(e['player'])}'),
                                                color: contractTeamColor({'team': e['team']['name_team']}, colorTeams),
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                child: DefaultTextStyle.merge(
                                                  style: TextStyle(color: contractTeamColor({'team': e['team']['name_team']}, colorTeams).computeLuminance() > .179 ? Colors.black : Colors.white),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text('${e['team']['name_team']}', style: const TextStyle(fontSize: 11)),
                                                      PlayerNameLink(player: {...e['player'], 'id_team': e['team']['id_team']}, child: Text('${e['player']['name']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                                    ],
                                                  ),
                                                ),
                                              )),
                                            ),
                                          ]));
                                    }))
                          ]))))),
        ]);
      });
}

/// Team pages share one vertical scrollbar; comparison retains its pinned chart.
class _ContractScroll extends StatelessWidget {
  const _ContractScroll({super.key, required this.headerSliverBuilder, required this.body});
  final NestedScrollViewHeaderSliversBuilder headerSliverBuilder;
  final Widget body;
  @override
  Widget build(BuildContext context) => TeamSectionLayout.embedded(context) ? body : NestedScrollView(headerSliverBuilder: headerSliverBuilder, body: body);
}
