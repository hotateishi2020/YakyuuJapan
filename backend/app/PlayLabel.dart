import '../tools/StringTool.dart';
import 'Value.dart';

/// 試合とチームと選手名から、打席結果の表示文を引くキー。
String playPlayerKey(dynamic idGame, dynamic idTeam, dynamic name) {
  return '${_asInt(idGame)}|${_asInt(idTeam)}|${StringTool.noSpace('$name')}';
}

/// t_game_details の行から、選手ごとの打席結果（選手名の右に並べる文言）を作る。
/// 各結果は「表示|種別」。その選手の最初の打席から記録順。
Map<String, String> playLabelsByPlayer(List<Map<String, dynamic>> rows) {
  _assignTimeline(rows);
  _attachNonBattingRunFlags(rows);
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final steal = _isSteal('${row['code_result'] ?? ''}');
    final runner = '${row['name_runner'] ?? ''}'.trim();
    final name = (steal && runner.isNotEmpty && runner != 'null') ? runner : '${row['name_full'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final team = steal && runner.isNotEmpty && _asInt(row['id_team_runner']) != 0 ? row['id_team_runner'] : row['id_team'];
    final key = playPlayerKey(row['id_game'], team, name);
    grouped.putIfAbsent(key, () => []).add(row);
  }
  final labels = <String, String>{};
  for (final entry in grouped.entries) {
    final text = formatPlayLabels(entry.value);
    if (text.isNotEmpty) labels[entry.key] = text;
  }
  return labels;
}

/// 1人分の打席を、最初の打席から記録順に連結する。
String formatPlayLabels(Iterable<Map<String, dynamic>> rows) {
  final ordered = rows.toList()
    ..sort((a, b) {
      final bySeq = _asInt(a['_seq']).compareTo(_asInt(b['_seq']));
      if (a.containsKey('_seq') && b.containsKey('_seq') && bySeq != 0) return bySeq;
      final byInning = _asInt(a['int_inning']).compareTo(_asInt(b['int_inning']));
      if (byInning != 0) return byInning;
      final byHalf = (_asBool(a['flg_bottom']) ? 1 : 0).compareTo(_asBool(b['flg_bottom']) ? 1 : 0);
      if (byHalf != 0) return byHalf;
      final byOrder = _asInt(a['int_batting_order']).compareTo(_asInt(b['int_batting_order']));
      if (byOrder != 0) return byOrder;
      return _asInt(a['id']).compareTo(_asInt(b['id']));
    });
  if (!ordered.any((row) => row.containsKey('_nonBattingRuns'))) {
    _attachNonBattingRunFlags(ordered);
  }
  final labels = <({String text, String kind})>[];
  final plate = <Map<String, dynamic>>[];
  String? plateKey;

  void flush() {
    for (final chip in _chipsForPlate(plate)) {
      labels.add((text: chip.text, kind: chip.kind));
    }
    plate.clear();
  }

  final seen = <String>{};
  for (final row in ordered) {
    if (!seen.add(_playIdentity(row))) continue;
    final key = _plateKey(row);
    final anotherResult = plateKey == key && _isBattingResult('${row['code_result'] ?? ''}') && plate.any((item) => _isBattingResult('${item['code_result'] ?? ''}'));
    if (plateKey != null && (key != plateKey || anotherResult)) flush();
    plateKey = key;
    plate.add(row);
  }
  if (plate.isNotEmpty) flush();
  return labels.map((chip) => '${chip.text}|${chip.kind}').join(' ');
}

bool _isNonBattingRunResult(String result) {
  return result == Value.CodeGameResult.WILD_PITCH ||
      result == Value.CodeGameResult.PASS_BALL ||
      result == Value.CodeGameResult.BALK ||
      result == Value.CodeGameResult.PICKOFF ||
      result == Value.CodeGameResult.STEAL_BASE_SAFE ||
      result == Value.CodeGameResult.STEAL_BASE_OUT;
}

bool _isNonBattingRunEvent(Map<String, dynamic> row) {
  if (_asInt(row['int_runs']) <= 0) return false;
  return _isNonBattingRunResult('${row['code_result'] ?? ''}');
}

void _attachNonBattingRunFlags(List<Map<String, dynamic>> rows) {
  for (final row in rows) {
    row.remove('_nonBattingRuns');
  }
  final ordered = rows.toList()
    ..sort((a, b) {
      final bySeq = _asInt(a['_seq']).compareTo(_asInt(b['_seq']));
      if (a.containsKey('_seq') && b.containsKey('_seq') && bySeq != 0) return bySeq;
      final byInning = _asInt(a['int_inning']).compareTo(_asInt(b['int_inning']));
      if (byInning != 0) return byInning;
      final byHalf = (_asBool(a['flg_bottom']) ? 1 : 0).compareTo(_asBool(b['flg_bottom']) ? 1 : 0);
      if (byHalf != 0) return byHalf;
      final byOrder = _asInt(a['int_batting_order']).compareTo(_asInt(b['int_batting_order']));
      if (byOrder != 0) return byOrder;
      return _asInt(a['id']).compareTo(_asInt(b['id']));
    });
  var pending = 0;
  for (final row in ordered) {
    if (_isNonBattingRunEvent(row)) {
      pending += _asInt(row['int_runs']);
      continue;
    }
    if (pending > 0 && _isBattingResult('${row['code_result'] ?? ''}')) {
      row['_nonBattingRuns'] = pending;
      pending = 0;
    }
  }
}

int _chipCount(String plays, bool Function(String kind) match) {
  var count = 0;
  for (final part in plays.split(' ')) {
    if (part.isEmpty) continue;
    final bar = part.lastIndexOf('|');
    final kind = bar < 0 ? '' : part.substring(bar + 1);
    if (match(kind.split('/').first)) count++;
  }
  return count;
}

/// 速報に残っていない本塁打だけ、公式成績の本数で補う。安打は出場記録の打席を使う。
String playsFilledFromLine(
  String plays, {
  required int homers,
}) {
  final extra = <String>[];
  final homerChips = _chipCount(plays, (kind) => kind == 'hr');
  for (var i = homerChips; i < homers; i++) {
    extra.add('ホームラン|hr');
  }
  if (extra.isEmpty) return plays;
  return [plays, ...extra].where((part) => part.trim().isNotEmpty).join(' ');
}

/// 速報に号数が無い本塁打へ、試合トップの号数を左から順に入れる。
String playsWithHomerNumbers(String plays, String totals) {
  final numbers = RegExp(r'\d+').allMatches(totals).map((match) => match.group(0)!).toList();
  if (plays.isEmpty || numbers.isEmpty) return plays;
  var index = 0;
  final out = <String>[];
  for (final part in plays.split(' ')) {
    if (part.isEmpty) continue;
    final bar = part.lastIndexOf('|');
    final label = bar < 0 ? part : part.substring(0, bar);
    final kind = bar < 0 ? '' : part.substring(bar + 1);
    final existing = RegExp(r'(\d+)号').firstMatch(label);
    if (kind != 'hr') {
      out.add(part);
      continue;
    }
    if (existing != null) {
      if (index < numbers.length && numbers[index] == existing.group(1)) index++;
      final moved = _homerNumberFirst(label);
      out.add(moved == label ? part : '$moved|$kind');
      continue;
    }
    if (index >= numbers.length) {
      out.add(part);
      continue;
    }
    out.add('${_homerNumberFirst(label, numbers[index])}|$kind');
    index++;
  }
  return out.join(' ');
}

String _homerNumberFirst(String label, [String? number]) {
  final head = RegExp(r'^(\d+回[表裏])').firstMatch(label);
  final prefix = head?.group(0) ?? '';
  final body = label.substring(prefix.length);
  final existing = RegExp(r'(\d+)号').firstMatch(body);
  if (existing != null) {
    if (existing.start == 0) return label;
    final token = existing.group(0)!;
    return '$prefix$token${body.substring(0, existing.start)}${body.substring(existing.end)}';
  }
  if (number == null || number.isEmpty) return label;
  return '$prefix$number号$body';
}

/// イニングの中は打順の回り順で並べる。登録順は打席の順と一致しない。
void _assignTimeline(List<Map<String, dynamic>> rows) {
  final games = <int, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    games.putIfAbsent(_asInt(row['id_game']), () => []).add(row);
  }
  for (final gameRows in games.values) {
    final halves = <String, List<Map<String, dynamic>>>{};
    for (final row in gameRows) {
      final half = '${_asInt(row['int_inning'])}|${_asBool(row['flg_bottom']) ? 1 : 0}';
      halves.putIfAbsent(half, () => []).add(row);
    }
    final halfKeys = halves.keys.toList()..sort((a, b) {
      final as = a.split('|');
      final bs = b.split('|');
      final inning = int.parse(as[0]).compareTo(int.parse(bs[0]));
      if (inning != 0) return inning;
      return int.parse(as[1]).compareTo(int.parse(bs[1]));
    });
    var seq = 0;
    for (final half in halfKeys) {
      final rows = halves[half]!;
      final ordered = _rowsInHalfOrder(rows, _leadoffOrder(rows));
      for (final row in ordered) {
        row['_seq'] = seq++;
      }
    }
  }
}

List<Map<String, dynamic>> _rowsInHalfOrder(List<Map<String, dynamic>> rows, int start) {
  final plates = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    plates.putIfAbsent(_plateKey(row), () => []).add(row);
  }
  int orderOf(List<Map<String, dynamic>> plate) => _asInt(plate.first['int_batting_order']);
  int outsOf(List<Map<String, dynamic>> plate) => _asInt(plate.first['cnt_out']);
  int dist(int order) {
    if (order < 1 || order > 9) return -1;
    return (order - start + 9) % 9;
  }

  final numbered = plates.values.where((plate) => dist(orderOf(plate)) >= 0).toList()
    ..sort((a, b) {
      final byOut = outsOf(a).compareTo(outsOf(b));
      if (byOut != 0) return byOut;
      final byDist = dist(orderOf(a)).compareTo(dist(orderOf(b)));
      if (byDist != 0) return byDist;
      return _asInt(a.first['id']).compareTo(_asInt(b.first['id']));
    });
  int nextOrder(int order) => order == 9 ? 1 : order + 1;
  int distanceFor(List<Map<String, dynamic>> plate) {
    final known = dist(orderOf(plate));
    if (known >= 0) return known;
    var expected = start;
    for (final earlier in numbered) {
      if (outsOf(earlier) < outsOf(plate)) expected = nextOrder(orderOf(earlier));
    }
    return dist(expected);
  }

  final orderedPlates = plates.values.toList()
    ..sort((a, b) {
      final byOut = outsOf(a).compareTo(outsOf(b));
      if (byOut != 0) return byOut;
      final byDist = distanceFor(a).compareTo(distanceFor(b));
      if (byDist != 0) return byDist;
      return _asInt(a.first['id']).compareTo(_asInt(b.first['id']));
    });
  final ordered = <Map<String, dynamic>>[];
  for (final plate in orderedPlates) {
    plate.sort((a, b) => _asInt(a['id']).compareTo(_asInt(b['id'])));
    ordered.addAll(plate);
  }
  return ordered;
}

int _leadoffOrder(List<Map<String, dynamic>> rows) {
  var start = 1;
  var bestOut = 99;
  var bestRunners = 99;
  for (final row in rows) {
    final order = _asInt(row['int_batting_order']);
    if (order < 1 || order > 9) continue;
    final outs = _asInt(row['cnt_out']);
    var runners = 0;
    if (_asBool(row['flg_runner_first'])) runners++;
    if (_asBool(row['flg_runner_second'])) runners++;
    if (_asBool(row['flg_runner_third'])) runners++;
    if (outs < bestOut || (outs == bestOut && runners < bestRunners)) {
      bestOut = outs;
      bestRunners = runners;
      start = order;
    }
  }
  return start;
}

String _plateKey(Map<String, dynamic> row) {
  return [
    _asInt(row['int_inning']),
    _asBool(row['flg_bottom']),
    _asInt(row['int_batting_order']),
    _asInt(row['cnt_out']),
    _asBool(row['flg_runner_first']),
    _asBool(row['flg_runner_second']),
    _asBool(row['flg_runner_third']),
  ].join('|');
}

List<({String text, String kind})> _chipsForPlate(List<Map<String, dynamic>> plate) {
  if (plate.isEmpty) return const [];
  final pinch = plate.any((row) => '${row['code_result'] ?? ''}' == Value.CodeGameResult.PINCH_HITTER);
  Map<String, dynamic>? batting;
  for (final row in plate) {
    if (_isBattingResult('${row['code_result'] ?? ''}')) batting = row;
  }
  final chips = <({String text, String kind})>[];
  var stealSafe = false;
  var stealOut = false;
  ({String text, String kind})? battingChip;
  for (final row in plate) {
    final result = '${row['code_result'] ?? ''}';
    if (result == Value.CodeGameResult.STEAL_BASE_SAFE) {
      stealSafe = true;
      continue;
    }
    if (result == Value.CodeGameResult.STEAL_BASE_OUT) {
      stealOut = true;
      continue;
    }
    if (!identical(row, batting)) continue;
    battingChip = _formatResult(
      result: result,
      pinch: pinch,
      state: _stateWord('${row['code_state_score'] ?? ''}'),
      goodbye: _asBool(row['flg_goodbye']),
      runs: _asInt(row['int_runs']),
      homerNumber: _asInt(row['cnt_homerun']),
      direction: _direction('${row['code_direction_batting'] ?? ''}'),
    );
  }
  if (battingChip != null) {
    var kind = battingChip.kind;
    if (stealSafe) kind = '$kind/steal';
    if (stealOut) kind = '$kind/stealout';
    if (pinch) kind = '$kind/pinch';
    final nonRbi = batting == null ? 0 : _asInt(batting['_nonBattingRuns']);
    if (nonRbi == 1) kind = '$kind/run';
    if (nonRbi > 1) kind = '$kind/run$nonRbi';
    chips.add((text: battingChip.text, kind: kind));
  } else {
    if (stealSafe) chips.add((text: '盗塁', kind: 'steal'));
    if (stealOut) chips.add((text: '盗塁失敗', kind: 'stealout'));
  }
  return chips;
}

String _playIdentity(Map<String, dynamic> row) {
  final result = '${row['code_result'] ?? ''}';
  final runner = _isSteal(result) ? '${row['name_runner'] ?? row['id_player_enter'] ?? ''}'.trim() : '';
  return '${_plateKey(row)}|$result|$runner';
}

bool _isSteal(String result) {
  return result == Value.CodeGameResult.STEAL_BASE_SAFE || result == Value.CodeGameResult.STEAL_BASE_OUT;
}

bool _isBattingResult(String result) {
  const results = {
    'HIT1',
    'HIT2',
    'HIT3',
    'HOMERUN',
    'OUT_FLY',
    'OUT_GROUND',
    'OUT_POP_UP',
    'OUT_DOUBLE_PLAY',
    'OUT_LINE_DRIVE',
    'SACRIFICE_BUNT',
    'SACRIFICE_FLY',
    'SQUEEZE',
    'STRIKE_OUT',
    'DROPPED_THIRD',
    'ERROR',
    'WALK',
    'WALK_DEAD',
    'ERROR_FIELDING',
    'INTERFERENCE_BATTING',
    'FIELDERS_CHOICE',
  };
  return results.contains(result);
}

({String text, String kind})? _formatResult({
  required String result,
  required bool pinch,
  required String state,
  required bool goodbye,
  required int runs,
  required int homerNumber,
  required String direction,
}) {
  final head = '$state${goodbye ? 'サヨナラ' : ''}';
  final pinchHead = '${pinch ? '代打' : ''}$head';
  if (result == Value.CodeGameResult.HOME_RUN) {
    final kind = switch (runs) {
      >= 4 => '満塁',
      3 => '3ラン',
      2 => '2ラン',
      _ => 'ソロ',
    };
    final number = homerNumber > 0 ? '$homerNumber号' : '';
    final mark = direction.isEmpty ? '' : '^$direction';
    return (text: '$number$pinchHead$kindホームラン$mark', kind: 'hr');
  }

  if (result == Value.CodeGameResult.HIT_SINGLE || result == Value.CodeGameResult.HIT_DOUBLE || result == Value.CodeGameResult.HIT_TRIPLE) {
    final hit = switch (result) {
      'HIT2' => 'ツーベース',
      'HIT3' => 'スリーベース',
      _ => 'ヒット',
    };
    final short = switch (result) {
      'HIT2' => '${direction}２',
      'HIT3' => '${direction}３',
      _ => direction.isEmpty ? '安' : '${direction}安',
    };
    if (runs > 0) {
      final points = runs >= 2 ? '$runs点' : '';
      // 速報が「タイムリーヒット」でも、ヒットよりタイムリーを優先する。二塁打・三塁打は種類を残す。
      final body = result == Value.CodeGameResult.HIT_SINGLE ? 'タイムリー' : 'タイムリー$hit';
      final mark = direction.isEmpty ? '' : '^$direction';
      return (text: '$pinchHead$points$body$mark', kind: 'timely');
    }
    final hitKind = switch (result) {
      'HIT3' => 'triple',
      'HIT2' => 'double',
      _ => 'single',
    };
    final mark = direction.isEmpty ? '' : '^$direction';
    if (state.isNotEmpty || goodbye) {
      return (text: '$head$hit$mark', kind: hitKind);
    }
    return (text: '$head$short', kind: hitKind);
  }

  if (result == 'OUT_GROUND' || result == 'OUT_FLY' || result == 'OUT_LINE_DRIVE' || result == 'OUT_POP_UP' || result == 'OUT_DOUBLE_PLAY' || result == 'STRIKE_OUT' || result == 'DROPPED_THIRD') {
    final word = switch (result) {
      'OUT_GROUND' => 'ゴロ',
      'OUT_FLY' => 'フライ',
      'OUT_LINE_DRIVE' => 'ライナー',
      'OUT_POP_UP' => '邪飛',
      'OUT_DOUBLE_PLAY' => '併殺',
      'STRIKE_OUT' => '三振',
      'DROPPED_THIRD' => '振逃',
      _ => '',
    };
    if (word.isEmpty) return null;
    final directed = result == 'STRIKE_OUT' || result == 'DROPPED_THIRD' || direction.isEmpty ? word : '$direction$word';
    final points = runs >= 2 ? '$runs点' : '';
    return (text: '$head$points$directed', kind: 'out');
  }

  final squeeze = result == Value.CodeGameResult.SQUEEZE || (result == Value.CodeGameResult.SACRIFICE_BUNT && runs > 0);
  final body = switch (result) {
    'WALK' => '四球',
    'WALK_DEAD' => '死球',
    'SQUEEZE' => 'スクイズ',
    'SACRIFICE_BUNT' => squeeze ? 'スクイズ' : '犠打',
    'SACRIFICE_FLY' => '犠飛',
    'ERROR' || 'ERROR_FIELDING' => direction.isEmpty ? '失策' : '${direction}失',
    'FIELDERS_CHOICE' => direction.isEmpty ? '野選' : '${direction}野選',
    'INTERFERENCE_BATTING' => '打撃妨害',
    _ => '',
  };
  if (body.isEmpty) return null;
  final kind = switch (result) {
    'WALK' => 'walk',
    'ERROR' || 'ERROR_FIELDING' => 'error',
    'FIELDERS_CHOICE' => 'fc',
    'WALK_DEAD' || 'INTERFERENCE_BATTING' => 'dead',
    'SACRIFICE_FLY' => 'sacfly',
    'SQUEEZE' || 'SACRIFICE_BUNT' => squeeze ? 'squeeze' : 'sacbunt',
    _ => 'out',
  };
  if (kind == 'out') return null;
  return (text: '$head$body', kind: kind);
}

String _stateWord(String code) {
  return switch (code.trim()) {
    'FIRST' => '先制',
    'TIE' => '同点',
    'REVERSE' => '逆転',
    'GO_AHEAD' => '勝ち越し',
    'DECISIVE' => '決勝',
    _ => '',
  };
}

String _direction(String code) {
  return switch (code.trim()) {
    'LEFT' || 'LF' => '左',
    'RIGHT' || 'RF' => '右',
    'CENTER' || 'CF' => '中',
    'FIRST' => '一',
    'SECOND' => '二',
    'THIRD' => '三',
    'SS' => '遊',
    'P' => '投',
    'C' => '捕',
    '' => '',
    final other => other,
  };
}

int _asInt(dynamic value) => int.tryParse('$value') ?? (value is int ? value : 0);

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final text = '$value'.trim().toLowerCase();
  return text == 'true' || text == 't' || text == '1';
}
