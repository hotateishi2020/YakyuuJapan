/// 1シーズンの試合数。日程が最後まで入っていないときの残り試合の下限に使う。
const npbSeasonGames = 143;

/// クライマックスシリーズと日本シリーズの星・敗退・勝ち上がり。
///
/// 2026年の規定:
/// - ファーストステージは3試合制・先に2勝。アドバンテージはない。
/// - ファイナルは原則6試合制。1位に1勝のアドバンテージがあり、先に4勝。
/// - ファーストステージ勝者の勝率が5割未満、または1位とのゲーム差が10以上なら、
///   アドバンテージは2勝、先に5勝（最大7試合）。両方を満たしても2勝まで。
class BracketTeam {
  final int id;
  final int leagueId;
  final int rank;
  final String name;
  final String colorBack;
  final String colorFont;
  final int wins;
  final int losses;
  final double? gamesBehind;

  const BracketTeam({
    required this.id,
    required this.leagueId,
    required this.rank,
    required this.name,
    required this.colorBack,
    required this.colorFont,
    required this.wins,
    required this.losses,
    required this.gamesBehind,
  });

  double? get winRate {
    final decided = wins + losses;
    if (decided <= 0) return null;
    return wins / decided;
  }
}

class BracketGame {
  final String code;
  final int homeId;
  final int awayId;
  final int scoreHome;
  final int scoreAway;
  final String state;

  const BracketGame({
    required this.code,
    required this.homeId,
    required this.awayId,
    required this.scoreHome,
    required this.scoreAway,
    required this.state,
  });
}

class StageResult {
  final int slots;
  final int advantage;
  final int winsHigh;
  final int winsLow;
  final bool decided;
  final int? winnerId;
  final int? loserId;

  const StageResult({
    required this.slots,
    required this.advantage,
    required this.winsHigh,
    required this.winsLow,
    required this.decided,
    required this.winnerId,
    required this.loserId,
  });

  static const empty = StageResult(slots: 0, advantage: 0, winsHigh: 0, winsLow: 0, decided: false, winnerId: null, loserId: null);
}

class PostseasonBoard {
  final BracketTeam central1;
  final BracketTeam central2;
  final BracketTeam central3;
  final BracketTeam pacific3;
  final BracketTeam pacific2;
  final BracketTeam pacific1;
  final StageResult cs1Central;
  final StageResult cs1Pacific;
  final StageResult finalCentral;
  final StageResult finalPacific;
  final StageResult japan;
  final Set<int> eliminatedIds;

  const PostseasonBoard({
    required this.central1,
    required this.central2,
    required this.central3,
    required this.pacific3,
    required this.pacific2,
    required this.pacific1,
    required this.cs1Central,
    required this.cs1Pacific,
    required this.finalCentral,
    required this.finalPacific,
    required this.japan,
    required this.eliminatedIds,
  });

  bool eliminated(int id) => id > 0 && eliminatedIds.contains(id);
}

const _placeholder = BracketTeam(
  id: 0,
  leagueId: 0,
  rank: 0,
  name: '',
  colorBack: '',
  colorFont: '',
  wins: 0,
  losses: 0,
  gamesBehind: null,
);

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value'.trim()) ?? 0;
}

double? gamesBehindOf(dynamic raw) {
  final text = '$raw'.trim().replaceAll('ゲーム', '').replaceAll('差', '').replaceAll('．', '.');
  if (text.isEmpty || text == 'null' || text == '優勝' || text == '-' || text == '−') return 0;
  return double.tryParse(text);
}

/// 1位とのゲーム差。順位表の game_behind は直上の球団との差なので、勝敗から計算する。
double gamesBehindFirst(BracketTeam team, BracketTeam leader) {
  return ((leader.wins - team.wins) + (team.losses - leader.losses)) / 2;
}

/// ファーストステージ勝者が、ファイナルのアドバンテージを2勝にする条件を満たすか。
/// 勝率は5割未満。ちょうど5割は対象にならない。
/// [leader] があるときは、その球団とのゲーム差を勝敗から出す。
bool finalistTakesExtraAdvantage(BracketTeam finalist, {BracketTeam? leader}) {
  final behind = leader == null || leader.id <= 0 ? finalist.gamesBehind : gamesBehindFirst(finalist, leader);
  if (behind != null && behind >= 10) return true;
  final rate = finalist.winRate;
  if (rate != null && rate < 0.5) return true;
  return false;
}

BracketTeam _listedRank(List<Map<String, dynamic>> standings, int leagueId, int rank) {
  for (final row in standings) {
    if (_asInt(row['id_league']) == leagueId && _asInt(row['int_rank']) == rank) {
      return _teamFromRow(row);
    }
  }
  return _blankRank(leagueId, rank);
}

/// 今のゲーム差のまま終わったとき、2位でも3位でも新規定に当たるか。
bool projectedFinalTakesExtra(List<Map<String, dynamic>> standings, int leagueId) {
  final first = _listedRank(standings, leagueId, 1);
  final second = _listedRank(standings, leagueId, 2);
  final third = _listedRank(standings, leagueId, 3);
  if (first.id <= 0 || second.id <= 0 || third.id <= 0) return false;
  return finalistTakesExtraAdvantage(second, leader: first) && finalistTakesExtraAdvantage(third, leader: first);
}

class _Tally {
  int wins = 0;
  int unfinished = 0;
}

StageResult scoreSeries({
  required BracketTeam high,
  required BracketTeam low,
  required List<BracketGame> games,
  required int advantageHigh,
  required int winsNeeded,
  required int maxGames,
  required bool tieGoesToHigh,
}) {
  final tally = <int, _Tally>{};
  _Tally bucket(int id) => tally.putIfAbsent(id, () => _Tally());
  if (high.id > 0) bucket(high.id);
  if (low.id > 0) bucket(low.id);
  var closed = 0;

  for (final game in games) {
    final involves = game.homeId == high.id || game.awayId == high.id || game.homeId == low.id || game.awayId == low.id;
    if (!involves || high.id == 0 || low.id == 0) continue;
    final state = game.state.trim();
    if (state == '試合中止') {
      closed += 1;
      continue;
    }
    if (state != '試合終了') {
      bucket(high.id).unfinished += 1;
      continue;
    }
    closed += 1;
    if (game.scoreHome < 0 || game.scoreAway < 0 || game.scoreHome == game.scoreAway) continue;
    final winner = game.scoreHome > game.scoreAway ? game.homeId : game.awayId;
    if (winner == high.id || winner == low.id) bucket(winner).wins += 1;
  }

  final gameWinsHigh = tally[high.id]?.wins ?? 0;
  final gameWinsLow = tally[low.id]?.wins ?? 0;
  final unfinished = high.id == 0 || low.id == 0 ? 0 : (tally[high.id]?.unfinished ?? 0);
  final totalHigh = gameWinsHigh + advantageHigh;
  final cardComplete = closed + unfinished >= maxGames;

  bool decided = false;
  var highWon = false;
  if (high.id > 0 && low.id > 0) {
    final highReached = totalHigh >= winsNeeded;
    final lowReached = gameWinsLow >= winsNeeded;
    if (highReached && !lowReached) {
      decided = true;
      highWon = true;
    } else if (lowReached && !highReached) {
      decided = true;
      highWon = false;
    } else if (cardComplete && unfinished == 0 && closed > 0) {
      if (totalHigh > gameWinsLow) {
        decided = true;
        highWon = true;
      } else if (gameWinsLow > totalHigh) {
        decided = true;
        highWon = false;
      } else if (tieGoesToHigh) {
        decided = true;
        highWon = true;
      }
    } else if (cardComplete && tieGoesToHigh && totalHigh >= gameWinsLow + unfinished && (gameWinsHigh + gameWinsLow + unfinished) > 0) {
      decided = true;
      highWon = true;
    } else if (cardComplete && !tieGoesToHigh && totalHigh > gameWinsLow + unfinished && totalHigh > 0) {
      decided = true;
      highWon = true;
    } else if (cardComplete && gameWinsLow > totalHigh + unfinished && gameWinsLow > 0) {
      decided = true;
      highWon = false;
    }
  }

  return StageResult(
    slots: winsNeeded,
    advantage: advantageHigh,
    winsHigh: totalHigh,
    winsLow: gameWinsLow,
    decided: decided,
    winnerId: decided ? (highWon ? high.id : low.id) : null,
    loserId: decided ? (highWon ? low.id : high.id) : null,
  );
}

BracketTeam _teamFromRow(Map<String, dynamic> row) {
  final nameShort = '${row['name_team'] ?? ''}'.trim();
  final nameFull = '${row['name_team_full'] ?? ''}'.trim();
  return BracketTeam(
    id: _asInt(row['id_team']),
    leagueId: _asInt(row['id_league']),
    rank: _asInt(row['int_rank']),
    name: nameShort.isNotEmpty ? nameShort : nameFull,
    colorBack: '${row['color_back'] ?? ''}',
    colorFont: '${row['color_font'] ?? ''}',
    wins: _asInt(row['int_win']),
    losses: _asInt(row['int_lose']),
    gamesBehind: gamesBehindOf(row['game_behind']),
  );
}

/// その順位の球団が、残り試合をすべて勝敗に振っても動かないときだけ true。
/// 勝率は勝利数 / (勝利数 + 敗戦数)。引き分けは数えない。同率になり得る場合は未確定。
/// 残り試合が両球団とも 0 なら、順位表の並びを確定として扱う。
bool rankIsConfirmed(List<Map<String, dynamic>> standings, int leagueId, int rank) {
  final league = <_Club>[];
  for (final row in standings) {
    if (_asInt(row['id_league']) != leagueId) continue;
    final clubRank = _asInt(row['int_rank']);
    if (clubRank <= 0) continue;
    league.add(_Club(row));
  }
  _Club? me;
  for (final club in league) {
    if (club.rank == rank) me = club;
  }
  if (me == null || me.id <= 0) return false;
  for (final other in league) {
    if (other.id == me.id) continue;
    if (other.remaining == 0 && me.remaining == 0) continue;
    final below = other.rank > me.rank;
    final caught = below
        ? _canMatchOrPass(
            chaserWins: other.wins + other.remaining,
            chaserLosses: other.losses,
            leaderWins: me.wins,
            leaderLosses: me.losses + me.remaining,
          )
        : _canMatchOrPass(
            chaserWins: me.wins + me.remaining,
            chaserLosses: me.losses,
            leaderWins: other.wins,
            leaderLosses: other.losses + other.remaining,
          );
    if (caught) return false;
  }
  return true;
}

class _Club {
  final int id;
  final int rank;
  final int wins;
  final int losses;
  final int remaining;

  _Club(Map<String, dynamic> row)
      : id = _asInt(row['id_team']),
        rank = _asInt(row['int_rank']),
        wins = _asInt(row['int_win']),
        losses = _asInt(row['int_lose']),
        remaining = remainingGamesOf(row);
}

/// 日程上の未消化試合と、143試合に足りない分の大きい方。最終日を過ぎていれば呼び出し側が 0 を渡す。
int remainingGamesOf(Map<String, dynamic> row) {
  if (row.containsKey('int_game_left')) {
    final left = _asInt(row['int_game_left']);
    return left < 0 ? 0 : left;
  }
  final played = _asInt(row['int_game']);
  final fromRecord = _asInt(row['int_win']) + _asInt(row['int_lose']) + _asInt(row['int_draw']);
  final games = played > 0 ? played : fromRecord;
  if (games <= 0) return 0;
  final left = npbSeasonGames - games;
  return left < 0 ? 0 : left;
}

/// 追い上げ側の最良勝率が、相手の最悪勝率以上になり得るか。
bool _canMatchOrPass({
  required int chaserWins,
  required int chaserLosses,
  required int leaderWins,
  required int leaderLosses,
}) {
  final chaserDecided = chaserWins + chaserLosses;
  final leaderDecided = leaderWins + leaderLosses;
  if (chaserDecided <= 0 || leaderDecided <= 0) return true;
  return chaserWins * leaderDecided >= leaderWins * chaserDecided;
}

BracketTeam _blankRank(int leagueId, int rank) {
  return BracketTeam(
    id: 0,
    leagueId: leagueId,
    rank: rank,
    name: '',
    colorBack: '',
    colorFont: '',
    wins: 0,
    losses: 0,
    gamesBehind: null,
  );
}

BracketTeam _pick(List<Map<String, dynamic>> standings, int leagueId, int rank) {
  if (!rankIsConfirmed(standings, leagueId, rank)) return _blankRank(leagueId, rank);
  for (final row in standings) {
    if (_asInt(row['id_league']) == leagueId && _asInt(row['int_rank']) == rank) {
      return _teamFromRow(row);
    }
  }
  return _blankRank(leagueId, rank);
}

/// 9月15日から、次の開幕日の前日まで。サーバが true のときはそちらに従う。
/// サーバが false のときも、開幕日（3月26日）の前日までは同じ窓で出す。
bool postseasonBoardVisible({required bool serverFlag, required DateTime today}) {
  if (serverFlag) return true;
  if (today.month > 9) return true;
  if (today.month == 9 && today.day >= 15) return true;
  if (today.month < 3) return true;
  if (today.month == 3 && today.day < 26) return true;
  return false;
}

List<BracketGame> _gamesOf(List<Map<String, dynamic>> games, String code, Set<int> ids) {
  final out = <BracketGame>[];
  for (final row in games) {
    if ('${row['code_game'] ?? ''}'.trim() != code) continue;
    final home = _asInt(row['id_team_home']);
    final away = _asInt(row['id_team_away']);
    if (!ids.contains(home) && !ids.contains(away)) continue;
    out.add(BracketGame(
      code: code,
      homeId: home,
      awayId: away,
      scoreHome: _asInt(row['score_home']),
      scoreAway: _asInt(row['score_away']),
      state: '${row['state'] ?? ''}',
    ));
  }
  return out;
}

PostseasonBoard buildPostseasonBoard({
  required List<Map<String, dynamic>> standings,
  required List<Map<String, dynamic>> games,
}) {
  final c1 = _pick(standings, 1, 1);
  final c2 = _pick(standings, 1, 2);
  final c3 = _pick(standings, 1, 3);
  final p1 = _pick(standings, 2, 1);
  final p2 = _pick(standings, 2, 2);
  final p3 = _pick(standings, 2, 3);

  StageResult cs1(BracketTeam second, BracketTeam third) {
    return scoreSeries(
      high: second,
      low: third,
      games: _gamesOf(games, 'CS1', {second.id, third.id}),
      advantageHigh: 0,
      winsNeeded: 2,
      maxGames: 3,
      tieGoesToHigh: true,
    );
  }

  final cs1C = cs1(c2, c3);
  final cs1P = cs1(p2, p3);

  BracketTeam challenger(StageResult series, BracketTeam second, BracketTeam third) {
    if (series.winnerId == third.id) return third;
    if (series.winnerId == second.id) return second;
    return _placeholder;
  }

  StageResult finalStage(BracketTeam first, BracketTeam rival) {
    final extra = (rival.id > 0 && finalistTakesExtraAdvantage(rival, leader: first)) || (rival.id == 0 && projectedFinalTakesExtra(standings, first.leagueId));
    return scoreSeries(
      high: first,
      low: rival.id > 0 ? rival : _placeholder,
      games: _gamesOf(games, 'CSF', {first.id, if (rival.id > 0) rival.id}),
      advantageHigh: extra ? 2 : 1,
      winsNeeded: extra ? 5 : 4,
      maxGames: extra ? 7 : 6,
      tieGoesToHigh: true,
    );
  }

  final finC = finalStage(c1, challenger(cs1C, c2, c3));
  final finP = finalStage(p1, challenger(cs1P, p2, p3));

  final centralRep = finC.winnerId == c1.id
      ? c1
      : finC.winnerId == c2.id
          ? c2
          : finC.winnerId == c3.id
              ? c3
              : _placeholder;
  final pacificRep = finP.winnerId == p1.id
      ? p1
      : finP.winnerId == p2.id
          ? p2
          : finP.winnerId == p3.id
              ? p3
              : _placeholder;

  final japan = scoreSeries(
    high: centralRep.id > 0 ? centralRep : _placeholder,
    low: pacificRep.id > 0 ? pacificRep : _placeholder,
    games: _gamesOf(games, 'JS', {
      if (centralRep.id > 0) centralRep.id,
      if (pacificRep.id > 0) pacificRep.id,
    }),
    advantageHigh: 0,
    winsNeeded: 4,
    maxGames: 7,
    tieGoesToHigh: false,
  );

  final eliminated = <int>{
    if (cs1C.loserId != null) cs1C.loserId!,
    if (cs1P.loserId != null) cs1P.loserId!,
    if (finC.loserId != null) finC.loserId!,
    if (finP.loserId != null) finP.loserId!,
    if (japan.loserId != null) japan.loserId!,
  };

  return PostseasonBoard(
    central1: c1,
    central2: c2,
    central3: c3,
    pacific3: p3,
    pacific2: p2,
    pacific1: p1,
    cs1Central: cs1C,
    cs1Pacific: cs1P,
    finalCentral: finC,
    finalPacific: finP,
    japan: japan,
    eliminatedIds: eliminated,
  );
}
