import 'package:flutter/material.dart';
import '../logic/game_replay.dart';

/// Only consume frames up to the current position, including when rewinding.
Map<String, int?> replayInningScores(List<ReplayFrame> frames, int index) {
  final result = <String, int?>{};
  int? home = 0, away = 0, baseline;
  String? half;
  for (var i = 0; i <= index && i < frames.length; i++) {
    final f = frames[i];
    final key = '${f.inning}:${f.bottom}';
    if (key != half) {
      baseline = i == 0 && f.inning != 1
          ? null
          : f.bottom
              ? home
              : away;
      half = key;
    }
    final score = f.bottom ? f.homeScore : f.awayScore;
    result[key] = score == null || baseline == null ? null : score - baseline;
    home = f.homeScore;
    away = f.awayScore;
  }
  return result;
}

class ReplayScoreboard extends StatelessWidget {
  const ReplayScoreboard(
      {super.key,
      required this.frames,
      required this.index,
      required this.home,
      required this.away});
  final List<ReplayFrame> frames;
  final int index;
  final String home, away;
  @override
  Widget build(BuildContext context) {
    final f = frames[index];
    final scores = replayInningScores(frames, index);
    final innings = f.inning > 9 ? f.inning : 9;
    Widget cell(String text, {bool active = false, Key? key}) => Container(
        key: key,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        decoration: BoxDecoration(
            color: active ? Colors.white24 : null,
            border: Border.all(color: Colors.white24, width: .5)),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: active ? Colors.yellow : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold)));
    return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: const Color(0xFF163F31),
            borderRadius: BorderRadius.circular(8)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${f.inning}回${f.bottom ? '裏' : '表'}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          Row(children: [
            Expanded(
                child: Text(away,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white))),
            AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: Text('${f.awayScore ?? '—'} - ${f.homeScore ?? '—'}',
                    key: ValueKey('replay-score-${f.awayScore}-${f.homeScore}'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold))),
            Expanded(
                child: Text(home,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white)))
          ]),
          LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                      width: innings > 9
                          ? c.maxWidth + (innings - 9) * 26
                          : c.maxWidth,
                      child: Table(columnWidths: const {
                        0: FixedColumnWidth(64)
                      }, children: [
                        TableRow(children: [
                          cell(''),
                          for (var i = 1; i <= innings; i++) cell('$i'),
                          cell('計')
                        ]),
                        for (final bottom in [false, true])
                          TableRow(children: [
                            cell(
                                '${bottom ? '裏' : '表'} ${bottom ? home : away}'),
                            for (var i = 1; i <= innings; i++)
                              cell(
                                  scores.containsKey('$i:$bottom')
                                      ? '${scores['$i:$bottom'] ?? '—'}'
                                      : '',
                                  active: i == f.inning && bottom == f.bottom,
                                  key: ValueKey('inning-$i-$bottom')),
                            cell(
                                '${(bottom ? f.homeScore : f.awayScore) ?? '—'}')
                          ]),
                      ]))))
        ]));
  }
}
