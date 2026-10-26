import 'package:flutter/material.dart';
import '../logic/game_bench.dart';

class GameBenchRow extends StatelessWidget {
  const GameBenchRow({super.key, required this.game, required this.stacked});
  final Map<String,dynamic> game;
  final bool stacked;
  static const teamHeight = 66.0;
  Widget side(String side) {
    final team = int.tryParse('${game['id_team_$side']}') ?? 0;
    final players = unusedGameBench(game, team);
    return SizedBox(height: teamHeight, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${game['name_team_$side']} 控え', textScaler: TextScaler.noScaling,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, height: 1.5)),
      for (final pitcher in [true,false]) SizedBox(height: 23, child: Row(children: [
        SizedBox(width: 30, child: Text(pitcher ? '投手' : '野手', style: const TextStyle(fontSize: 10))),
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          if (!players.any((p)=>p['pitcher']==pitcher)) const Text('—', style: TextStyle(fontSize: 11)),
          for (final p in players.where((p)=>p['pitcher']==pitcher)) Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(message: '${p['position']} ${p['hands'] ?? ''}', child: Text(
              '${p['name']}'.replaceAll(RegExp(r'[\s　]'), ''), textScaler: TextScaler.noScaling,
              style: const TextStyle(fontSize: 11))),
          ),
        ]))),
      ])),
    ]));
  }
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black26))),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: stacked
      ? Column(children:[side('home'),side('away')])
      : Row(children:[Expanded(child:side('home')), const SizedBox(width: 8), Expanded(child:side('away'))])),
  );
}
