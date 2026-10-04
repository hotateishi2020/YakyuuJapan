import 'package:flutter/material.dart';
import '../config/org_config.dart';
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
  final OrgConfig org;

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
    this.org = OrgConfig.npb,
  });

  List<Map<String, dynamic>> get _leagueGames => games.where((g) => (int.tryParse('${g['id_league_home']}') ?? 0) == leagueId && (int.tryParse('${g['id_league_away']}') ?? 0) == leagueId).toList();

  @override
  Widget build(BuildContext context) {
    final table = SeasonTableBlock(
      standings: standings,
      stats: npbPlayerStatsActual,
      games: _leagueGames,
      onlyLeagueId: leagueId,
      gamesDateFilter: DateFormatUtil.ymdWithOffset(0),
      portraitLayout: portraitLayout,
      org: org,
    );

    // リーグ切替タブがあるため左のリーグ名ヘッダーは出さない
    return table;
  }
}
