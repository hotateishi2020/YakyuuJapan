import 'package:flutter/material.dart';
import '../config/app_design.dart';
import '../tools/date_format.dart';
import 'SeasonTable.dart';

class LeagueBoardRow extends StatelessWidget {
  final int leagueId;
  final Color leagueColor;
  final String logoAsset;
  final List<Map<String, dynamic>> predictions;
  final List<Map<String, dynamic>> standings;
  final List<Map<String, dynamic>> npbPlayerStats;
  final List<Map<String, dynamic>> npbPlayerStatsActual;
  final List<Map<String, dynamic>> games;
  final String Function(String idUser) usernameForId;
  final String Function(String idUser) userNameFromPredictions;
  final bool compact;

  final String leagueLabelPrefix;

  const LeagueBoardRow({
    super.key,
    required this.leagueId,
    required this.leagueColor,
    required this.logoAsset,
    required this.leagueLabelPrefix,
    required this.predictions,
    required this.standings,
    required this.npbPlayerStats,
    required this.npbPlayerStatsActual,
    required this.games,
    required this.usernameForId,
    required this.userNameFromPredictions,
    required this.compact,
  });

  List<Map<String, dynamic>> get _leagueGames => games
      .where((g) =>
          (int.tryParse('${g['id_league_home']}') ?? 0) == leagueId &&
          (int.tryParse('${g['id_league_away']}') ?? 0) == leagueId)
      .toList();

  Widget _sideHeader() {
    return Container(
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: leagueColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Image.asset(
                logoAsset,
                width: 20,
                height: 20,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(height: 20),
              ),
            ),
            Text(leagueLabelPrefix, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const Text('・', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const Text('リ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const Text('|', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const Text('グ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: ALL_RATIO_BLOCK_W[0], child: _sideHeader()),
        Expanded(
          // 旧: 成績ブロック + 右の試合ブロック分の幅をまとめて使う
          flex: ALL_RATIO_BLOCK_W[2] + ALL_RATIO_BLOCK_W[3],
          child: SeasonTableBlock(
            standings: standings,
            stats: npbPlayerStatsActual,
            games: _leagueGames,
            onlyLeagueId: leagueId,
            gamesDateFilter: DateFormatUtil.ymdWithOffset(0),
          ),
        ),
      ],
    );
  }
}
