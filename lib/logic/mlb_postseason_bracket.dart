import 'postseason_bracket.dart';

/// MLB ポストシーズン用ボード。ア／ナ各6シードと WS までの枠。
class MlbPostseasonBoard {
  final List<BracketTeam> american; // seeds 1..6
  final List<BracketTeam> national; // seeds 1..6
  final StageResult alWc36;
  final StageResult alWc45;
  final StageResult nlWc36;
  final StageResult nlWc45;
  final StageResult alDs1;
  final StageResult alDs2;
  final StageResult nlDs1;
  final StageResult nlDs2;
  final StageResult alCs;
  final StageResult nlCs;
  final StageResult worldSeries;
  final Set<int> eliminatedIds;

  const MlbPostseasonBoard({
    required this.american,
    required this.national,
    required this.alWc36,
    required this.alWc45,
    required this.nlWc36,
    required this.nlWc45,
    required this.alDs1,
    required this.alDs2,
    required this.nlDs1,
    required this.nlDs2,
    required this.alCs,
    required this.nlCs,
    required this.worldSeries,
    required this.eliminatedIds,
  });

  bool eliminated(int id) => id > 0 && eliminatedIds.contains(id);
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value'.trim()) ?? 0;
}

BracketTeam _teamFromRow(
  Map<String, dynamic> row,
  int seed, {
  required String codeArea,
  required int divisionPlace,
}) {
  return BracketTeam(
    id: _asInt(row['id_team'] ?? row['id']),
    leagueId: _asInt(row['id_league']),
    rank: seed,
    name: '${row['name_team'] ?? row['name_short'] ?? ''}'.trim(),
    nameShortest: '${row['name_shortest'] ?? ''}'.trim(),
    colorBack: '${row['color_back'] ?? ''}',
    colorFont: '${row['color_font'] ?? ''}',
    wins: _asInt(row['int_win']),
    losses: _asInt(row['int_lose']),
    gamesBehind: gamesBehindOf(row['game_behind']),
    codeArea: codeArea,
    divisionPlace: divisionPlace,
  );
}

BracketTeam _blank(int leagueId, int seed) => BracketTeam(
      id: 0,
      leagueId: leagueId,
      rank: seed,
      name: '',
      nameShortest: '',
      colorBack: '',
      colorFont: '',
      wins: 0,
      losses: 0,
      gamesBehind: null,
    );

double _winPct(Map<String, dynamic> row) {
  final w = _asInt(row['int_win']);
  final l = _asInt(row['int_lose']);
  final d = w + l;
  if (d <= 0) return 0;
  return w / d;
}

int _compareStandingsRows(Map<String, dynamic> a, Map<String, dynamic> b) {
  // 順位表と同じ: 勝率優先、同率ならリーグ全体順位・勝利数で安定化。
  final byPct = _winPct(b).compareTo(_winPct(a));
  if (byPct != 0) return byPct;
  final byRank = _asInt(a['int_rank']).compareTo(_asInt(b['int_rank']));
  if (byRank != 0) return byRank;
  return _asInt(b['int_win']).compareTo(_asInt(a['int_win']));
}

String _areaOf(Map<String, dynamic> row) => '${row['code_area'] ?? ''}'.trim().toUpperCase();

/// カード見出し用。順位表の地区順位と一致させる（例: NL中1, AL東2）。
String mlbBracketLabel(String leagueCode, BracketTeam team) {
  final area = switch (team.codeArea) {
    'EAST' => '東',
    'CENTER' => '中',
    'WEST' => '西',
    _ => '',
  };
  if (area.isEmpty || team.divisionPlace <= 0) return '$leagueCode${team.rank}';
  return '$leagueCode$area${team.divisionPlace}';
}

/// 地区優勝3＋ワイルドカード3。
/// シード1〜3 = 各地区1位を勝率の高い順（最も高い地区優勝がシード1＝外側）。
/// シード4〜6 = それ以外を勝率の高い順。
List<BracketTeam> mlbSeeds(List<Map<String, dynamic>> standings, int leagueId) {
  final rows = standings.where((r) => _asInt(r['id_league']) == leagueId).toList();
  if (rows.isEmpty) {
    return [for (var i = 1; i <= 6; i++) _blank(leagueId, i)];
  }

  final byArea = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final area = _areaOf(row);
    final key = area.isEmpty ? '_ALL' : area;
    byArea.putIfAbsent(key, () => []).add(row);
  }

  final divisionMeta = <Map<String, dynamic>>[]; // row + place/area
  final otherMeta = <Map<String, dynamic>>[];

  if (byArea.keys.any((k) => k == 'EAST' || k == 'CENTER' || k == 'WEST')) {
    for (final area in const ['EAST', 'CENTER', 'WEST']) {
      final list = List<Map<String, dynamic>>.from(byArea[area] ?? const <Map<String, dynamic>>[])
        ..sort(_compareStandingsRows);
      for (var i = 0; i < list.length; i++) {
        final meta = {
          'row': list[i],
          'area': area,
          'place': i + 1,
        };
        if (i == 0) {
          divisionMeta.add(meta);
        } else {
          otherMeta.add(meta);
        }
      }
    }
    for (final entry in byArea.entries) {
      if (entry.key == 'EAST' || entry.key == 'CENTER' || entry.key == 'WEST') continue;
      final list = List<Map<String, dynamic>>.from(entry.value)..sort(_compareStandingsRows);
      for (var i = 0; i < list.length; i++) {
        otherMeta.add({'row': list[i], 'area': entry.key, 'place': i + 1});
      }
    }
  } else {
    final sorted = [...rows]..sort(_compareStandingsRows);
    return [
      for (var i = 0; i < 6; i++)
        i < sorted.length
            ? _teamFromRow(sorted[i], i + 1, codeArea: _areaOf(sorted[i]), divisionPlace: i + 1)
            : _blank(leagueId, i + 1),
    ];
  }

  // 地区優勝どうしは勝率の高い順 → シード1が最も外側。
  divisionMeta.sort((a, b) => _compareStandingsRows(a['row'] as Map<String, dynamic>, b['row'] as Map<String, dynamic>));
  otherMeta.sort((a, b) => _compareStandingsRows(a['row'] as Map<String, dynamic>, b['row'] as Map<String, dynamic>));

  final seeds = <Map<String, dynamic>>[
    ...divisionMeta.take(3),
    ...otherMeta.take(3),
  ];
  while (seeds.length < 6) {
    seeds.add({});
  }
  return [
    for (var i = 0; i < 6; i++)
      seeds[i].isEmpty
          ? _blank(leagueId, i + 1)
          : _teamFromRow(
              seeds[i]['row'] as Map<String, dynamic>,
              i + 1,
              codeArea: '${seeds[i]['area'] ?? ''}',
              divisionPlace: _asInt(seeds[i]['place']),
            ),
  ];
}

const _wcCodes = {'WC', 'ALWC', 'NLWC', 'ALWC36', 'ALWC45', 'NLWC36', 'NLWC45'};
const _dsCodes = {'DS', 'ALDS', 'NLDS', 'ALDS1', 'ALDS2', 'NLDS1', 'NLDS2'};
const _lcsCodes = {'LCS', 'ALCS', 'NLCS'};
const _wsCodes = {'WS'};

/// code 群に合う試合を返す。対戦カードの絞り込みは scoreSeries 側で行う。
List<BracketGame> _gamesOf(List<Map<String, dynamic>> games, Set<String> codes) {
  final out = <BracketGame>[];
  for (final row in games) {
    final code = '${row['code_game'] ?? ''}'.trim().toUpperCase();
    if (!codes.contains(code)) continue;
    out.add(BracketGame(
      code: code,
      homeId: _asInt(row['id_team_home']),
      awayId: _asInt(row['id_team_away']),
      scoreHome: _asInt(row['score_home']),
      scoreAway: _asInt(row['score_away']),
      state: '${row['state'] ?? ''}',
    ));
  }
  return out;
}

BracketTeam _byId(List<BracketTeam> seeds, int? id) {
  if (id == null || id <= 0) return _blank(0, 0);
  for (final t in seeds) {
    if (t.id == id) return t;
  }
  return _blank(0, 0);
}

/// DS 試合からシード対戦相手を推定（WC 試合が未取得でも星を付けられるようにする）。
BracketTeam _opponentFromGames(List<BracketGame> games, BracketTeam seed, List<BracketTeam> pool) {
  if (seed.id <= 0) return _blank(seed.leagueId, 0);
  for (final g in games) {
    final other = g.homeId == seed.id ? g.awayId : (g.awayId == seed.id ? g.homeId : 0);
    if (other <= 0) continue;
    final found = _byId(pool, other);
    if (found.id > 0) return found;
  }
  return _blank(seed.leagueId, 0);
}

StageResult _wcOrInferred({
  required StageResult scored,
  required BracketTeam inferredWinner,
  required BracketTeam high,
  required BracketTeam low,
}) {
  if (scored.decided || inferredWinner.id <= 0) return scored;
  final winnerIsHigh = inferredWinner.id == high.id;
  final winnerIsLow = inferredWinner.id == low.id;
  if (!winnerIsHigh && !winnerIsLow) return scored;
  return StageResult(
    slots: scored.slots,
    advantage: scored.advantage,
    winsHigh: winnerIsHigh ? scored.slots : scored.winsHigh,
    winsLow: winnerIsLow ? scored.slots : scored.winsLow,
    decided: true,
    winnerId: inferredWinner.id,
    loserId: winnerIsHigh ? low.id : high.id,
  );
}

MlbPostseasonBoard buildMlbPostseasonBoard({
  required List<Map<String, dynamic>> standings,
  required List<Map<String, dynamic>> games,
}) {
  final al = mlbSeeds(standings, 3);
  final nl = mlbSeeds(standings, 4);

  final wcGames = _gamesOf(games, _wcCodes);
  final dsGames = _gamesOf(games, _dsCodes);
  final lcsGames = _gamesOf(games, _lcsCodes);
  final wsGames = _gamesOf(games, _wsCodes);

  // WC: 3vs6 / 4vs5（先に2勝）。汎用 code=WC も対戦相手で振り分ける。
  var alWc36 = scoreSeries(
    high: al[2],
    low: al[5],
    games: wcGames,
    advantageHigh: 0,
    winsNeeded: 2,
    maxGames: 3,
    tieGoesToHigh: true,
  );
  var alWc45 = scoreSeries(
    high: al[3],
    low: al[4],
    games: wcGames,
    advantageHigh: 0,
    winsNeeded: 2,
    maxGames: 3,
    tieGoesToHigh: true,
  );
  var nlWc36 = scoreSeries(
    high: nl[2],
    low: nl[5],
    games: wcGames,
    advantageHigh: 0,
    winsNeeded: 2,
    maxGames: 3,
    tieGoesToHigh: true,
  );
  var nlWc45 = scoreSeries(
    high: nl[3],
    low: nl[4],
    games: wcGames,
    advantageHigh: 0,
    winsNeeded: 2,
    maxGames: 3,
    tieGoesToHigh: true,
  );

  // DS 出場相手から WC 勝者を補完
  final alDsOpp1 = _opponentFromGames(dsGames, al[0], al);
  final alDsOpp2 = _opponentFromGames(dsGames, al[1], al);
  final nlDsOpp1 = _opponentFromGames(dsGames, nl[0], nl);
  final nlDsOpp2 = _opponentFromGames(dsGames, nl[1], nl);
  alWc45 = _wcOrInferred(scored: alWc45, inferredWinner: alDsOpp1, high: al[3], low: al[4]);
  alWc36 = _wcOrInferred(scored: alWc36, inferredWinner: alDsOpp2, high: al[2], low: al[5]);
  nlWc45 = _wcOrInferred(scored: nlWc45, inferredWinner: nlDsOpp1, high: nl[3], low: nl[4]);
  nlWc36 = _wcOrInferred(scored: nlWc36, inferredWinner: nlDsOpp2, high: nl[2], low: nl[5]);

  final alDsLowA = alWc45.decided ? _byId(al, alWc45.winnerId) : alDsOpp1;
  final alDsLowB = alWc36.decided ? _byId(al, alWc36.winnerId) : alDsOpp2;
  final nlDsLowA = nlWc45.decided ? _byId(nl, nlWc45.winnerId) : nlDsOpp1;
  final nlDsLowB = nlWc36.decided ? _byId(nl, nlWc36.winnerId) : nlDsOpp2;

  // DS: 1 vs WC(4/5), 2 vs WC(3/6)（先に3勝）
  final alDs1 = scoreSeries(
    high: al[0],
    low: alDsLowA,
    games: dsGames,
    advantageHigh: 0,
    winsNeeded: 3,
    maxGames: 5,
    tieGoesToHigh: true,
  );
  final alDs2 = scoreSeries(
    high: al[1],
    low: alDsLowB,
    games: dsGames,
    advantageHigh: 0,
    winsNeeded: 3,
    maxGames: 5,
    tieGoesToHigh: true,
  );
  final nlDs1 = scoreSeries(
    high: nl[0],
    low: nlDsLowA,
    games: dsGames,
    advantageHigh: 0,
    winsNeeded: 3,
    maxGames: 5,
    tieGoesToHigh: true,
  );
  final nlDs2 = scoreSeries(
    high: nl[1],
    low: nlDsLowB,
    games: dsGames,
    advantageHigh: 0,
    winsNeeded: 3,
    maxGames: 5,
    tieGoesToHigh: true,
  );

  final alCsHigh = alDs1.decided ? _byId(al, alDs1.winnerId) : _blank(3, 0);
  final alCsLow = alDs2.decided ? _byId(al, alDs2.winnerId) : _blank(3, 0);
  final nlCsHigh = nlDs1.decided ? _byId(nl, nlDs1.winnerId) : _blank(4, 0);
  final nlCsLow = nlDs2.decided ? _byId(nl, nlDs2.winnerId) : _blank(4, 0);

  final alCs = scoreSeries(
    high: alCsHigh,
    low: alCsLow,
    games: lcsGames,
    advantageHigh: 0,
    winsNeeded: 4,
    maxGames: 7,
    tieGoesToHigh: true,
  );
  final nlCs = scoreSeries(
    high: nlCsHigh,
    low: nlCsLow,
    games: lcsGames,
    advantageHigh: 0,
    winsNeeded: 4,
    maxGames: 7,
    tieGoesToHigh: true,
  );

  final wsHigh = alCs.decided ? _byId(al, alCs.winnerId) : _blank(3, 0);
  final wsLow = nlCs.decided ? _byId(nl, nlCs.winnerId) : _blank(4, 0);
  final worldSeries = scoreSeries(
    high: wsHigh,
    low: wsLow,
    games: wsGames,
    advantageHigh: 0,
    winsNeeded: 4,
    maxGames: 7,
    tieGoesToHigh: true,
  );

  final eliminated = <int>{};
  void addLoser(StageResult s) {
    if (s.decided && s.loserId != null && s.loserId! > 0) eliminated.add(s.loserId!);
  }

  addLoser(alWc36);
  addLoser(alWc45);
  addLoser(nlWc36);
  addLoser(nlWc45);
  addLoser(alDs1);
  addLoser(alDs2);
  addLoser(nlDs1);
  addLoser(nlDs2);
  addLoser(alCs);
  addLoser(nlCs);
  addLoser(worldSeries);

  return MlbPostseasonBoard(
    american: al,
    national: nl,
    alWc36: alWc36,
    alWc45: alWc45,
    nlWc36: nlWc36,
    nlWc45: nlWc45,
    alDs1: alDs1,
    alDs2: alDs2,
    nlDs1: nlDs1,
    nlDs2: nlDs2,
    alCs: alCs,
    nlCs: nlCs,
    worldSeries: worldSeries,
    eliminatedIds: eliminated,
  );
}
