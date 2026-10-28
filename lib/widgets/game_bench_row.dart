import 'package:flutter/material.dart';
import '../logic/game_bench.dart';
import '../logic/mlb_event_name.dart';
import '../tools/json_utils.dart';

class GameBenchRow extends StatelessWidget {
  const GameBenchRow({super.key, required this.game, required this.stacked, this.headerWidth = 40, this.homeColor, this.awayColor});
  final Map<String, dynamic> game;
  final bool stacked;
  final double headerWidth;
  final Color? homeColor, awayColor;

  String _shownName(Map<String, dynamic> player) {
    final mlb = ['id_league_home', 'id_league_away'].any((key) => [3, 4].contains(int.tryParse('${game[key]}')));
    final name = '${player['name'] ?? ''}';
    return mlb
        ? mlbBattingName(name, [player, ...listMapFromJson(game['season_player_stats'])])
        : name.replaceAll(RegExp(r'[\s　]'), '');
  }

  static String group(Map<String, dynamic> player) {
    final pitcher = player['pitcher'] == true;
    final hands = '${player['hands'] ?? ''}'.replaceAll(RegExp(r'\s'), '');
    final match = RegExp(pitcher ? r'([左右両])投' : r'([左右両])打').firstMatch(hands);
    final compact = RegExp(r'^([左右両])([左右両])$').firstMatch(hands);
    final hand = match?.group(1) ?? compact?.group(pitcher ? 1 : 2);
    return hand == null ? (pitcher ? '投手（不明）' : '打者（不明）') : '$hand${pitcher ? '投手' : '打者'}';
  }

  static const groups = ['左投手', '右投手', '左打者', '右打者'];
  static List<String> groupsFor(List<Map<String, dynamic>> players) => [
        ...groups,
        for (final extra in ['両投手', '両打者', '投手（不明）', '打者（不明）'])
          if (players.any((p) => group(p) == extra)) extra,
      ];
  static double heightFor(Map<String, dynamic> game, bool stacked) {
    double height(String side) => groupsFor(unusedGameBench(game, int.tryParse('${game['id_team_$side']}') ?? 0)).length * 24.0;
    final home = height('home'), away = height('away');
    return stacked ? home + away : (home > away ? home : away);
  }

  static Color playerColor(Map<String, dynamic> player) {
    final position = '${player['position'] ?? ''}';
    if (player['pitcher'] == true) return const Color(0xFFFF4B7D);
    if (position.contains('捕')) return const Color(0xFF1E88E5);
    if (position.contains('外') || ['左', '中', '右'].contains(position)) {
      return const Color(0xFFC6FF00);
    }
    if (position.contains('内') || ['一', '二', '三', '遊'].contains(position)) {
      return const Color(0xFFFFEB3B);
    }
    if (position.contains('指')) return const Color(0xFF8E24AA);
    return const Color(0xFFEEEEEE);
  }

  Widget side(String side) {
    final players = unusedGameBench(game, int.tryParse('${game['id_team_$side']}') ?? 0);
    return ColoredBox(
        color: (side == 'home' ? homeColor : awayColor) ?? Colors.transparent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final category in groupsFor(players))
            SizedBox(
                height: 24,
                child: Row(children: [
                  SizedBox(width: 72, child: Text(category, textAlign: TextAlign.center, textScaler: TextScaler.noScaling, style: const TextStyle(fontSize: 10))),
                  Expanded(
                      child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            if (!players.any((p) => group(p) == category)) const Text('—', style: TextStyle(fontSize: 11)),
                            for (final p in players.where((p) => group(p) == category))
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Tooltip(message: '${p['position'] ?? ''} ${p['hands'] ?? ''}', child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: playerColor(p), borderRadius: BorderRadius.circular(3)), child: Text(_shownName(p), textScaler: TextScaler.noScaling, style: TextStyle(fontSize: 11, color: playerColor(p).computeLuminance() > .45 ? Colors.black : Colors.white)))),
                              ),
                          ]))),
                ])),
        ]));
  }

  Widget header() => SizedBox(width: headerWidth, child: const ColoredBox(color: Color(0xFF5A5A5A), child: Center(child: Text('控え', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))));
  @override
  Widget build(BuildContext context) => SizedBox(
      height: heightFor(game, stacked),
      child: DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black26))),
          child: stacked
              ? Column(children: [
                  for (final name in ['home', 'away']) Expanded(flex: groupsFor(unusedGameBench(game, int.tryParse('${game['id_team_$name']}') ?? 0)).length, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header(), Expanded(child: side(name))]))
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: side('home')), header(), Expanded(child: side('away'))])));
}
