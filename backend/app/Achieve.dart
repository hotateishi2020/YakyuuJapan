import 'PlayLabel.dart';

/// 投球回（6.1 なら 6回1/3）をアウト数にする。
int baseballOuts(num innings) {
  if (innings <= 0) return 0;
  final whole = innings.truncate();
  var thirds = ((innings - whole) * 10).round();
  if (thirds < 0) thirds = 0;
  if (thirds > 2) thirds = 2;
  return whole * 3 + thirds;
}

/// アウト + 奪三振 - 失点×3 - 被安打×0.5 - 四死球×0.5。先発は5点引く。
double pitcherPoints({
  required num innings,
  required int strikeouts,
  required int runs,
  required int hits,
  required int walks,
  required int hbp,
  required bool starter,
}) {
  final points = baseballOuts(innings) + strikeouts - 3 * runs - 0.5 * hits - 0.5 * (walks + hbp);
  return starter ? points - 5 : points;
}

/// 投球回と失点は1ブロック、その右に四死球・被安打・奪三振を色分けして並べる。
String pitcherStatChips({
  required num innings,
  required int runs,
  required int hits,
  required int walks,
  required int hbp,
  required int strikeouts,
  required int pitches,
  required bool starter,
}) {
  final outs = baseballOuts(innings);
  if (outs <= 0) return '';
  final ip = outs / 3.0;
  final freePasses = walks + hbp;
  final runsLabel = runs == 0 ? '無失点' : '$runs失点';
  final runsTone = _lowerTone(runs / ip, const [0, 0.15, 0.30, 0.45, 0.6, 0.75]);
  final parts = <String>[
    '${_inningsLabel(innings)}$runsLabel|${runsTone == 'gray' ? 'dgray' : runsTone}',
    '${hits == 0 ? '無被安打' : '被安打$hits'}|${_lowerTone(hits / ip, const [0, 0.3, 0.6, 0.9, 1.2, 1.5])}',
    '四死球$freePasses|${_lowerTone(freePasses / ip, const [0, 0.15, 0.30, 0.45, 0.6, 0.75])}',
    '$strikeouts奪三振|${starter ? _higherTone(strikeouts / ip, const [1, 0.85, 0.7, 0.55, 0.4, 0.25]) : _reliefStrikeoutTone(strikeouts / ip)}',
  ];
  if (pitches > 0) parts.add('$pitches球|');
  return parts.join(' ');
}

String _inningsLabel(num innings) {
  final whole = innings.truncate();
  var thirds = ((innings - whole) * 10).round();
  if (thirds <= 0) return '$whole回';
  if (thirds > 2) thirds = 2;
  return '$whole.$thirds回';
}

/// 小さいほど良い指標。境界は各色の上限。
String _lowerTone(double rate, List<double> bounds) {
  const tones = ['crimson', 'rorange', 'yorange', 'yellow', 'green', 'blue'];
  for (var i = 0; i < bounds.length; i++) {
    if (rate <= bounds[i] + 1e-9) return tones[i];
  }
  return 'gray';
}

/// 大きいほど良い指標。境界は各色の下限。
String _higherTone(double rate, List<double> bounds) {
  const tones = ['crimson', 'rorange', 'yorange', 'yellow', 'green', 'blue'];
  for (var i = 0; i < bounds.length; i++) {
    if (rate + 1e-9 >= bounds[i]) return tones[i];
  }
  return 'gray';
}

String _reliefStrikeoutTone(double rate) {
  if (rate + 1e-9 >= 3) return 'crimson';
  if (rate + 1e-9 >= 2) return 'rorange';
  if (rate + 1e-9 >= 1) return 'yellow';
  return 'green';
}

/// 25以上クリムゾン、20以上赤橙、15以上黄橙、10以上黄、5以上緑、0以下青、その間はグレー。
String pitcherTone(double points) {
  if (points >= 25) return 'crimson';
  if (points >= 20) return 'rorange';
  if (points >= 15) return 'yorange';
  if (points >= 10) return 'yellow';
  if (points >= 5) return 'green';
  if (points <= 0) return 'blue';
  return 'gray';
}

/// 単打・二塁打・三塁打・本塁打が揃えばサイクルヒット、3種類ならサイクル未遂。
String cycleMark(Iterable<String> results) {
  const types = {'HIT1', 'HIT2', 'HIT3', 'HOMERUN'};
  final hit = results.where(types.contains).toSet();
  if (hit.length >= 4) return 'サイクルヒット|cycle';
  if (hit.length == 3) return 'サイクル未遂|cyclemis';
  return '';
}

/// 試合終了後の先発だけ、達成した記録を返す。
String pitcherMarks({
  required bool finished,
  required bool starter,
  required num innings,
  required int pitches,
  required int hits,
  required int walks,
  required int hbp,
  required int runs,
  required int earned,
  required int balks,
  required int gameInnings,
}) {
  if (!finished || !starter) return '';
  final outs = baseballOuts(innings);
  if (outs <= 0) return '';
  final need = (gameInnings <= 0 ? 9 : gameInnings) * 3;
  final complete = outs >= need;
  final shutout = complete && runs == 0;
  final nohit = complete && hits == 0;
  final perfect = nohit && shutout && walks == 0 && hbp == 0 && balks == 0;
  final maddux = shutout && pitches > 0 && pitches < 100;
  final marks = <String>[];
  if (perfect) marks.add('完全試合|perfect');
  if (nohit) marks.add('ノーヒットノーラン|nohit');
  if (maddux) marks.add('マダックス|maddux');
  if (shutout) marks.add('完封|shutout');
  if (complete) marks.add('完投|cg');
  if (outs >= 21 && earned <= 2) {
    marks.add('HQS|hqs');
  } else if (outs >= 18 && earned <= 3) {
    marks.add('QS|qs');
  }
  return marks.join(' ');
}

/// 単打・二塁打・三塁打・本塁打が3本以上なら猛打賞。
String multiHitMark(int hits) => hits >= 3 ? '猛打賞|multihit' : '';

/// 打席が2つ以上あり、すべて安打なら全打席安打、すべて出塁なら全打席出塁。
String plateFeatMarks({required int plates, required int reached, required int hits}) {
  if (plates < 2) return '';
  final marks = <String>[];
  if (hits == plates) marks.add('全打席安打|allhit');
  if (reached == plates) marks.add('全打席出塁|allreach');
  return marks.join(' ');
}

/// 公式の打席成績。ゴロ・フライなどの凡退、または犠打・犠飛があるときは記録しない。
/// 失策で出塁した打数は凡退に数えない。
String plateFeatsFromLine({
  required int atBats,
  required int hits,
  required int walks,
  required int hbp,
  required int sacrifices,
  required int errors,
}) {
  if (errors < 0) errors = 0;
  final outs = atBats - hits - errors;
  if (outs > 0 || sacrifices > 0) return '';
  final plates = hits + errors + walks + hbp;
  return plateFeatMarks(plates: plates, reached: plates, hits: hits);
}

bool _isHitResult(String result) {
  return result == 'HIT1' || result == 'HIT2' || result == 'HIT3' || result == 'HOMERUN';
}

bool _isReachedResult(String result) {
  return _isHitResult(result) || result == 'WALK' || result == 'WALK_DEAD' || result == 'ERROR' || result == 'ERROR_FIELDING' || result == 'INTERFERENCE_BATTING';
}

bool _isPlateResult(String result) {
  return _isReachedResult(result) ||
      result == 'OUT_FLY' ||
      result == 'OUT_GROUND' ||
      result == 'OUT_POP_UP' ||
      result == 'OUT_DOUBLE_PLAY' ||
      result == 'OUT_LINE_DRIVE' ||
      result == 'STRIKE_OUT' ||
      result == 'SACRIFICE_BUNT' ||
      result == 'SACRIFICE_FLY' ||
      result == 'SQUEEZE' ||
      result == 'INTERFERENCE_FIELDING';
}

/// テキスト速報の打席結果から、全打席安打・全打席出塁を選手ごとに作る。
Map<String, String> plateFeatMarksByPlayer(List<Map<String, dynamic>> rows) {
  final plates = <String, Map<String, String>>{};
  for (final row in rows) {
    final result = '${row['code_result'] ?? ''}';
    if (!_isPlateResult(result)) continue;
    final name = '${row['name_full'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final key = playPlayerKey(row['id_game'], row['id_team'], name);
    final plate = [
      row['int_inning'],
      row['flg_bottom'],
      row['int_batting_order'],
      row['cnt_out'],
      row['flg_runner_first'],
      row['flg_runner_second'],
      row['flg_runner_third'],
    ].join('|');
    plates.putIfAbsent(key, () => {}).putIfAbsent(plate, () => result);
  }
  final marks = <String, String>{};
  for (final entry in plates.entries) {
    final results = entry.value.values.toList();
    final text = plateFeatMarks(
      plates: results.length,
      reached: results.where(_isReachedResult).length,
      hits: results.where(_isHitResult).length,
    );
    if (text.isNotEmpty) marks[entry.key] = text;
  }
  return marks;
}

/// 打席結果から選手ごとの安打数を数える。同じ打席の重複は1本にする。
Map<String, int> hitCountsByPlayer(List<Map<String, dynamic>> rows) {
  final plates = <String, Set<String>>{};
  for (final row in rows) {
    final result = '${row['code_result'] ?? ''}';
    if (result != 'HIT1' && result != 'HIT2' && result != 'HIT3' && result != 'HOMERUN') continue;
    final name = '${row['name_full'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final key = playPlayerKey(row['id_game'], row['id_team'], name);
    final plate = [
      row['int_inning'],
      row['flg_bottom'],
      row['int_batting_order'],
      row['cnt_out'],
      row['flg_runner_first'],
      row['flg_runner_second'],
      row['flg_runner_third'],
    ].join('|');
    plates.putIfAbsent(key, () => {}).add(plate);
  }
  return {for (final entry in plates.entries) entry.key: entry.value.length};
}

/// 打席結果から選手ごとのサイクル表記を作る。
Map<String, String> cycleMarksByPlayer(List<Map<String, dynamic>> rows) {
  final kinds = <String, Set<String>>{};
  for (final row in rows) {
    final result = '${row['code_result'] ?? ''}';
    if (result != 'HIT1' && result != 'HIT2' && result != 'HIT3' && result != 'HOMERUN') continue;
    final name = '${row['name_full'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final key = playPlayerKey(row['id_game'], row['id_team'], name);
    kinds.putIfAbsent(key, () => {}).add(result);
  }
  final marks = <String, String>{};
  for (final entry in kinds.entries) {
    final text = cycleMark(entry.value);
    if (text.isNotEmpty) marks[entry.key] = text;
  }
  return marks;
}

/// テキスト速報に残っている最終イニング。無ければ 0。
Map<int, int> maxInningByGame(List<Map<String, dynamic>> rows) {
  final innings = <int, int>{};
  for (final row in rows) {
    final game = int.tryParse('${row['id_game']}') ?? 0;
    final inning = int.tryParse('${row['int_inning']}') ?? 0;
    if (game == 0 || inning <= 0) continue;
    final current = innings[game] ?? 0;
    if (inning > current) innings[game] = inning;
  }
  return innings;
}
