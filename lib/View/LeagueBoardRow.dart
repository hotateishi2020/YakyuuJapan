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
  final bool portraitLayout;
  final bool portraitShowPersonal;

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
    this.portraitLayout = false,
    this.portraitShowPersonal = false,
  });

  List<Map<String, dynamic>> get _leagueGames => games.where((g) => (int.tryParse('${g['id_league_home']}') ?? 0) == leagueId && (int.tryParse('${g['id_league_away']}') ?? 0) == leagueId).toList();

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
    final table = SeasonTableBlock(
      standings: standings,
      stats: npbPlayerStatsActual,
      games: _leagueGames,
      onlyLeagueId: leagueId,
      gamesDateFilter: DateFormatUtil.ymdWithOffset(0),
      portraitLayout: portraitLayout,
      portraitShowPersonal: portraitShowPersonal,
    );

    // 縦型はリーグ切替タブがあるため左ヘッダー不要
    final Widget body = portraitLayout
        ? table
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: ALL_RATIO_BLOCK_W[0], child: _sideHeader()),
              Expanded(
                flex: ALL_RATIO_BLOCK_W[2] + ALL_RATIO_BLOCK_W[3],
                child: table,
              ),
            ],
          );

    // 縦型チーム成績: 順位表+試合の内容高さに合わせ、下余白を作らない
    if (portraitLayout && !portraitShowPersonal) {
      const double gridBodyH = 20.0;
      const double gamesBodyH = 130.0;
      final int teams = standings.where((e) => int.tryParse('${e['id_league']}') == leagueId).length;
      final double h = ALL_HEADER_H + teams * gridBodyH + 6 + ALL_HEADER_H + gamesBodyH;
      return SizedBox(height: h, width: double.infinity, child: body);
    }
    return body;
  }
}
