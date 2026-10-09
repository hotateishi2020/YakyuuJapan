import 'package:flutter/material.dart';
import '../config/org_config.dart';
import '../logic/game_date_window.dart';
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
  final List<Map<String, dynamic>> seriesGames;
  final String Function(String idUser) usernameForId;
  final String Function(String idUser) userNameFromPredictions;
  final bool compact;
  final bool portraitLayout;
  final OrgConfig org;
  final PersonalStatsLayout personalStatsLayout;
  final ValueChanged<PersonalStatsLayout>? onPersonalStatsLayoutChanged;
  final bool loadingStandings;
  final bool loadingStats;
  final bool loadingGames;
  final int seasonYear;
  final String? gamesDateFilter;
  final Future<void> Function(DateTime date)? onNeedGameDate;
  final bool Function(DateTime date)? shouldLoadGameDate;
  final String? loadingGameDate;
  final int gameDateOffset;
  final ValueChanged<int>? onGameDateOffsetChanged;

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
    this.seriesGames = const [],
    required this.usernameForId,
    required this.userNameFromPredictions,
    required this.compact,
    this.portraitLayout = false,
    this.org = OrgConfig.npb,
    this.personalStatsLayout = PersonalStatsLayout.segment,
    this.onPersonalStatsLayoutChanged,
    this.loadingStandings = false,
    this.loadingStats = false,
    this.loadingGames = false,
    this.seasonYear = 0,
    this.gamesDateFilter,
    this.onNeedGameDate,
    this.shouldLoadGameDate,
    this.loadingGameDate,
    this.gameDateOffset = 0,
    this.onGameDateOffsetChanged,
  });

  List<Map<String, dynamic>> get _leagueGames => games.where((game) => gameVisibleInLeague(game, leagueId)).toList();

  @override
  Widget build(BuildContext context) {
    final table = SeasonTableBlock(
      standings: standings,
      stats: npbPlayerStatsActual,
      games: _leagueGames,
      seriesGames: seriesGames,
      onlyLeagueId: leagueId,
      gamesDateFilter: gamesDateFilter ?? DateFormatUtil.ymdWithOffset(0),
      portraitLayout: portraitLayout,
      org: org,
      personalStatsLayout: personalStatsLayout,
      onPersonalStatsLayoutChanged: onPersonalStatsLayoutChanged,
      loadingStandings: loadingStandings,
      loadingStats: loadingStats,
      loadingGames: loadingGames,
      seasonYear: seasonYear,
      onNeedGameDate: onNeedGameDate,
      shouldLoadGameDate: shouldLoadGameDate,
      loadingGameDate: loadingGameDate,
      gameDateOffset: gameDateOffset,
      onGameDateOffsetChanged: onGameDateOffsetChanged,
    );

    // リーグ切替タブがあるため左のリーグ名ヘッダーは出さない
    return table;
  }
}
