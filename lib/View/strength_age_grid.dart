import 'pinned_horizontal_row.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';
import '../logic/strength_usage.dart';
import 'personal_stats_style.dart';
import 'player_detail_dialog.dart';

Color? _agePositionColor(String position) {
  final color = personalStatPositionColor(position);
  return color == null ? null : Color.lerp(Colors.white, color, 2.2);
}

/// 日本の学年は4月2日から翌年4月1日生まれまで。
int? playerSchoolYear(dynamic raw) {
  final birth = DateTime.tryParse('$raw');
  if (birth == null) return null;
  return birth.year - (birth.month < 4 || (birth.month == 4 && birth.day == 1) ? 1 : 0);
}

class StrengthAgeGrid extends StatefulWidget {
  const StrengthAgeGrid({super.key, required this.teams, required this.year, required this.org});
  final List<Map<String, dynamic>> teams;
  final int year;
  final String org;
  @override
  State<StrengthAgeGrid> createState() => _StrengthAgeGridState();
}

class _StrengthAgeGridState extends State<StrengthAgeGrid> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <Map<int?, List<Map<String, dynamic>>>>[];
    final cohorts = <int>{};
    var unknown = false;
    for (final team in widget.teams) {
      final grouped = <int?, List<Map<String, dynamic>>>{};
      final seen = <String>{};
      for (final player in listMapFromJson(team['roster'])) {
        if (!seen.add(usagePlayerKey(player))) continue;
        final cohort = playerSchoolYear(player['date_birth']);
        if (cohort == null) {
          unknown = true;
        } else {
          cohorts.add(cohort);
        }
        grouped.putIfAbsent(cohort, () => []).add(player);
      }
      for (final players in grouped.values) {
        players.sort((a, b) => '${a['date_birth']}'.compareTo('${b['date_birth']}'));
      }
      groups.add(grouped);
    }
    final years = <int?>[...(cohorts.toList()..sort()), if (unknown) null];
    if (years.isEmpty) return const Center(child: Text('選手名簿は未取得です。'));
    return PlayerDetailScope(org: widget.org, year: widget.year,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          double textWidth(String text, {bool bold = false}) {
            final painter = TextPainter(
              text: TextSpan(text: text, style: TextStyle(fontSize: 12,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }
          final sideWidth = textWidth('出生年度（年齢）', bold: true) + 12;
          final teamWidths = [for (var i = 0; i < widget.teams.length; i++)
            groups[i].values.expand((players) => players).fold<double>(
              textWidth('${widget.teams[i]['name_team'] ?? '球団'}', bold: true) + 12,
              (width, player) => math.max(width,
                textWidth('${player['name'] ?? player['name_player'] ?? player['name_full'] ?? '—'}'
                  .replaceAll(RegExp(r'[\s　]'), '')) + 20)),
          ];
          final width = sideWidth + teamWidths.fold<double>(0, (a, b) => a + b);
          Widget cell(Widget child, {Color color = Colors.white, Alignment alignment = Alignment.center}) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            decoration: BoxDecoration(color: color, border: Border.all(color: const Color(0xFFE2E8F0), width: .5)),
            alignment: alignment, child: child);
          Widget row(List<Widget> cells, {Key? key}) => PinnedHorizontalRow(
            key: key, controller: _horizontal, pinnedWidth: sideWidth,
            children: [cells.first,
              for (var i = 1; i < cells.length; i++) SizedBox(width: teamWidths[i - 1], child: cells[i]),
            ],
          );
          return Align(alignment: Alignment.topCenter,
            child: SizedBox(width: math.min(width, constraints.maxWidth),
              child: Scrollbar(controller: _horizontal, thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(controller: _horizontal, scrollDirection: Axis.horizontal,
              key: const ValueKey('strength-age-horizontal'),
              child: SizedBox(width: width, height: constraints.maxHeight,
                child: Column(children: [
                  row([
                    cell(const Text('出生年度（年齢）', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)), color: const Color(0xFF424242)),
                    for (final team in widget.teams)
                      cell(Text('${team['name_team'] ?? '球団'}', textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        color: Color.lerp(parseColorNameOrNull('${team['color_back']}') ?? Colors.grey, Colors.white, .60)!),
                  ]),
                  Expanded(child: Scrollbar(controller: _vertical,
                    child: ListView.builder(controller: _vertical,
                      key: const ValueKey('strength-age-vertical'),
                      itemCount: years.length + 1,
                      itemBuilder: (context, index) {
                        if (index == years.length) { return Align(alignment: Alignment.centerLeft, child: SizedBox(width: math.min(width, constraints.maxWidth), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text('4月2日〜翌4月1日生まれを同じ学年として表示。年齢は${widget.year + 1}年4月1日時点。',
              style: const TextStyle(fontSize: 11, color: Colors.black54))))); }
                        final cohort = years[index];
                        return row(key: ValueKey('strength-age-row-${cohort ?? 'unknown'}'), [
                          cell(Text(cohort == null ? '生年月日不明' : '$cohort年度\n（${widget.year - cohort}歳）',
                            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                            color: const Color(0xFF424242)),
                          for (var i = 0; i < widget.teams.length; i++)
                            cell(Column(mainAxisSize: MainAxisSize.min, children: [
                              if ((groups[i][cohort] ?? []).isEmpty) const Text('—', style: TextStyle(color: Colors.black26)),
                              for (final player in groups[i][cohort] ?? <Map<String, dynamic>>[])
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: PlayerNameLink(player: {
                                    ...player, 'id_team': widget.teams[i]['id_team'],
                                    'id_league': widget.teams[i]['id_league'],
                                  }, child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _agePositionColor('${player['position_group'] ?? player['txt_position'] ?? ''}'),
                                      borderRadius: BorderRadius.circular(4)),
                                    child: Text('${player['name'] ?? player['name_player'] ?? player['name_full'] ?? '—'}'.replaceAll(RegExp(r'[\s　]'), ''),
                                      textAlign: TextAlign.center, maxLines: 2,
                                      style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                  ))),
                            ]), alignment: Alignment.topCenter),
                        ]);
                      },
                    ),
                  )),
                ]),
              ),
            ),
          )));
        })),
      ]),
    );
  }
}
