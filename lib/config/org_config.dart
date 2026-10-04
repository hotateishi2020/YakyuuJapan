import 'package:flutter/material.dart';

/// NPB / MLB など、画面上部で切り替える競技団体。
enum OrgKind { npb, mlb }

class OrgLeague {
  final int id;
  final String name;
  final Color color;
  final String? logoAsset;

  const OrgLeague({
    required this.id,
    required this.name,
    required this.color,
    this.logoAsset,
  });
}

class OrgConfig {
  final OrgKind kind;
  final String label;
  final String logoAsset;
  final Color tabColor;
  final Color tabForeground;
  final List<OrgLeague> leagues;
  final String gamesFetchPath;
  final String teamStatsFetchPath;
  final String playerStatsFetchPath;

  const OrgConfig({
    required this.kind,
    required this.label,
    required this.logoAsset,
    required this.tabColor,
    required this.tabForeground,
    required this.leagues,
    required this.gamesFetchPath,
    required this.teamStatsFetchPath,
    required this.playerStatsFetchPath,
  });

  Set<int> get leagueIds => {for (final league in leagues) league.id};

  OrgLeague leagueAt(int index) => leagues[index.clamp(0, leagues.length - 1)];

  OrgLeague? leagueById(int id) {
    for (final league in leagues) {
      if (league.id == id) return league;
    }
    return null;
  }

  String leagueName(int id) => leagueById(id)?.name ?? '';

  Color leagueColor(int id) => leagueById(id)?.color ?? const Color(0xFF37474F);

  bool containsLeague(int? id) => id != null && leagueIds.contains(id);

  bool gameBelongs(Map<String, dynamic> game) {
    final home = int.tryParse('${game['id_league_home']}') ?? 0;
    final away = int.tryParse('${game['id_league_away']}') ?? 0;
    return containsLeague(home) || containsLeague(away);
  }

  bool rowBelongs(Map<String, dynamic> row) {
    final id = int.tryParse('${row['id_league']}') ?? 0;
    if (containsLeague(id)) return true;
    final name = '${row['league_name'] ?? row['name_league'] ?? ''}'.trim();
    return leagues.any((league) => league.name == name);
  }

  /// 非選択時のタブ背景（薄いグレー）。
  static const tabIdleColor = Color(0xFFE8E8ED);

  static const npb = OrgConfig(
    kind: OrgKind.npb,
    label: 'NPB',
    logoAsset: 'backend/assets/images/logo_npb.png',
    // 添付 NPB ロゴの赤（#CB0115）
    tabColor: Color(0xFFCB0115),
    tabForeground: Colors.white,
    leagues: [
      OrgLeague(id: 1, name: 'セ・リーグ', color: Color(0xFF0E8E2D), logoAsset: 'backend/assets/images/k-central.webp'),
      OrgLeague(id: 2, name: 'パ・リーグ', color: Color(0xFF01B1EA), logoAsset: 'backend/assets/images/k-pacific.webp'),
    ],
    gamesFetchPath: '/fetchGamesNPB',
    teamStatsFetchPath: '/fetchStatsTeamNPB',
    playerStatsFetchPath: '/fetchStatsPlayerNPB',
  );

  static const mlb = OrgConfig(
    kind: OrgKind.mlb,
    label: 'MLB',
    logoAsset: 'backend/assets/images/logo_mlb.webp',
    tabColor: Color(0xFF002D72),
    tabForeground: Colors.white,
    leagues: [
      OrgLeague(id: 3, name: 'ア・リーグ', color: Color(0xFFC8102E)),
      OrgLeague(id: 4, name: 'ナ・リーグ', color: Color(0xFF002D72)),
    ],
    gamesFetchPath: '/fetchGamesMLB',
    teamStatsFetchPath: '/fetchStatsTeamMLB',
    playerStatsFetchPath: '/fetchStatsPlayerMLB',
  );

  static OrgConfig of(OrgKind kind) => kind == OrgKind.mlb ? mlb : npb;
}
