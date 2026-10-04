/// NPB / MLB のリーグ ID とスクレイプ設定。フロントの OrgConfig と揃える。
class OrgLeague {
  final int id;
  final String nameShort;

  const OrgLeague(this.id, this.nameShort);
}

class OrgKind {
  final String code;
  final String label;
  final List<OrgLeague> leagues;
  final String scheduleUrlPrefix;
  final String standingsUrl;
  final String statsUrlPrefix;

  const OrgKind({
    required this.code,
    required this.label,
    required this.leagues,
    required this.scheduleUrlPrefix,
    required this.standingsUrl,
    required this.statsUrlPrefix,
  });

  List<int> get leagueIds => [for (final league in leagues) league.id];

  static const npb = OrgKind(
    code: 'npb',
    label: 'NPB',
    leagues: [
      OrgLeague(1, 'セ・リーグ'),
      OrgLeague(2, 'パ・リーグ'),
    ],
    scheduleUrlPrefix: 'https://baseball.yahoo.co.jp/npb/schedule/?date=',
    standingsUrl: 'https://baseball.yahoo.co.jp/npb/standings/',
    statsUrlPrefix: 'https://baseball.yahoo.co.jp/npb/stats/',
  );

  static const mlb = OrgKind(
    code: 'mlb',
    label: 'MLB',
    leagues: [
      OrgLeague(3, 'ア・リーグ'),
      OrgLeague(4, 'ナ・リーグ'),
    ],
    scheduleUrlPrefix: 'https://baseball.yahoo.co.jp/mlb/schedule/first/all?date=',
    standingsUrl: 'https://baseball.yahoo.co.jp/mlb/standings/',
    statsUrlPrefix: 'https://baseball.yahoo.co.jp/mlb/stats/',
  );

  static OrgKind parse(String? raw) {
    final text = (raw ?? '').trim().toLowerCase();
    if (text == 'mlb' || text == 'メジャー') return mlb;
    return npb;
  }
}
