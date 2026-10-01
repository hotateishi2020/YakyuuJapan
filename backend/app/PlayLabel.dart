import 'Value.dart';

/// 試合とチームと選手名から、打席結果の表示文を引くキー。
String playPlayerKey(dynamic idGame, dynamic idTeam, dynamic name) {
  return '${_asInt(idGame)}|${_asInt(idTeam)}|${'$name'.trim()}';
}

/// t_game_details の行から、選手ごとの打席結果（選手名の右に並べる文言）を作る。
/// 各結果は「表示|種別」。凡退は含めず、ホームラン→タイムリー→三塁打→二塁打→単打→犠飛・スクイズ・四球→犠打の順。
Map<String, String> playLabelsByPlayer(List<Map<String, dynamic>> rows) {
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

/// 1人分の打席を「ホームラン タイムリー 三塁打 二塁打 単打 犠飛 スクイズ 四球 犠打」の順で連結する。
String formatPlayLabels(Iterable<Map<String, dynamic>> rows) {
  final ordered = rows.toList();
  final labels = <({String text, String kind, int index})>[];
  final plate = <Map<String, dynamic>>[];
  String? plateKey;

  void flush() {
    for (final chip in _chipsForPlate(plate)) {
      if (chip.kind == 'out') continue;
      labels.add((text: chip.text, kind: chip.kind, index: labels.length));
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
  labels.sort((a, b) {
    final byKind = _playRank(a.kind).compareTo(_playRank(b.kind));
    if (byKind != 0) return byKind;
    return a.index.compareTo(b.index);
  });
  return labels.map((chip) => '${chip.text}|${chip.kind}').join(' ');
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
      out.add(part);
      continue;
    }
    if (index >= numbers.length) {
      out.add(part);
      continue;
    }
    out.add('${_insertHomerNumber(label, numbers[index])}|$kind');
    index++;
  }
  return out.join(' ');
}

String _insertHomerNumber(String label, String number) {
  for (final word in ['ソロ', '2ラン', '3ラン', '満塁']) {
    final at = label.indexOf(word);
    if (at >= 0) return '${label.substring(0, at)}$number号${label.substring(at)}';
  }
  final at = label.indexOf('ホームラン');
  if (at >= 0) return '${label.substring(0, at)}$number号${label.substring(at)}';
  return '$label$number号';
}

int _playRank(String kind) {
  return switch (kind) {
    'hr' => 0,
    'timely' => 1,
    'triple' => 2,
    'double' => 3,
    'single' => 4,
    'steal' => 5,
    'sacfly' => 6,
    'squeeze' => 7,
    'walk' => 8,
    'dead' => 9,
    'error' => 10,
    'sacbunt' => 11,
    _ => 99,
  };
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
  for (final row in plate) {
    final result = '${row['code_result'] ?? ''}';
    if (result == Value.CodeGameResult.STEAL_BASE_SAFE) {
      chips.add((text: '盗塁', kind: 'steal'));
      continue;
    }
    if (result == Value.CodeGameResult.STEAL_BASE_OUT) continue;
    if (!identical(row, batting)) continue;
    final chip = _formatResult(
      result: result,
      pinch: pinch,
      state: _stateWord('${row['code_state_score'] ?? ''}'),
      goodbye: _asBool(row['flg_goodbye']),
      runs: _asInt(row['int_runs']),
      homerNumber: _asInt(row['cnt_homerun']),
      direction: _direction('${row['code_direction_batting'] ?? ''}'),
    );
    if (chip != null) chips.add(chip);
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
    'ERROR',
    'WALK',
    'WALK_DEAD',
    'ERROR_FIELDING',
    'INTERFERENCE_BATTING',
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
  final head = '${pinch ? '代打' : ''}$state${goodbye ? 'サヨナラ' : ''}';
  if (result == Value.CodeGameResult.HOME_RUN) {
    final kind = switch (runs) {
      >= 4 => '満塁',
      3 => '3ラン',
      2 => '2ラン',
      _ => 'ソロ',
    };
    final number = homerNumber > 0 ? '$homerNumber号' : '';
    return (text: '$head$number$kindホームラン', kind: 'hr');
  }

  if (result == Value.CodeGameResult.HIT_SINGLE || result == Value.CodeGameResult.HIT_DOUBLE || result == Value.CodeGameResult.HIT_TRIPLE) {
    final hit = switch (result) {
      'HIT2' => 'ツーベース',
      'HIT3' => 'スリーベース',
      _ => 'ヒット',
    };
    final short = switch (result) {
      'HIT2' => '${direction}2',
      'HIT3' => '${direction}3',
      _ => direction.isEmpty ? '安' : '${direction}安',
    };
    if (runs > 0) {
      final points = runs >= 2 ? '$runs点' : '';
      // 速報が「タイムリーヒット」でも、ヒットよりタイムリーを優先する。二塁打・三塁打は種類を残す。
      final body = result == Value.CodeGameResult.HIT_SINGLE ? 'タイムリー' : 'タイムリー$hit';
      return (text: '$head$points$body', kind: 'timely');
    }
    final hitKind = switch (result) {
      'HIT3' => 'triple',
      'HIT2' => 'double',
      _ => 'single',
    };
    if (state.isNotEmpty || goodbye) {
      return (text: '$head$hit', kind: hitKind);
    }
    return (text: '$head$short', kind: hitKind);
  }

  if (result == 'OUT_GROUND' || result == 'OUT_FLY' || result == 'OUT_LINE_DRIVE' || result == 'OUT_POP_UP' || result == 'OUT_DOUBLE_PLAY' || result == 'STRIKE_OUT') {
    return null;
  }

  final squeeze = result == Value.CodeGameResult.SQUEEZE || (result == Value.CodeGameResult.SACRIFICE_BUNT && runs > 0);
  final body = switch (result) {
    'WALK' => '四球',
    'WALK_DEAD' => '死球',
    'SQUEEZE' => 'スクイズ',
    'SACRIFICE_BUNT' => squeeze ? 'スクイズ' : '犠打',
    'SACRIFICE_FLY' => '犠飛',
    'ERROR' || 'ERROR_FIELDING' => direction.isEmpty ? '失策' : '${direction}失',
    'INTERFERENCE_BATTING' => '打撃妨害',
    _ => '',
  };
  if (body.isEmpty) return null;
  final kind = switch (result) {
    'WALK' => 'walk',
    'WALK_DEAD' || 'INTERFERENCE_BATTING' => 'dead',
    'ERROR' || 'ERROR_FIELDING' => 'error',
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
