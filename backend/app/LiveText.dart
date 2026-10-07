import 'package:html/dom.dart';

import 'Value.dart';

class ParsedLiveText {
  final List<ParsedHalf> halves;
  final bool finished;

  /// 先攻は false、後攻は true。名前は空白なしの苗字、値は守備位置の1文字。
  final Map<bool, Map<String, String>> positions;

  ParsedLiveText({required this.halves, required this.finished, this.positions = const {}});
}

class ParsedHalf {
  final int inning;
  final bool bottom;
  final List<ParsedPlate> plates;

  ParsedHalf({required this.inning, required this.bottom, required this.plates});
}

class ParsedPlate {
  final int battingOrder;
  final String batterName;
  final int outs;
  final bool runnerFirst;
  final bool runnerSecond;
  final bool runnerThird;
  final List<ParsedLiveEvent> events;

  ParsedPlate({
    required this.battingOrder,
    required this.batterName,
    required this.outs,
    required this.runnerFirst,
    required this.runnerSecond,
    required this.runnerThird,
    required this.events,
  });
}

class ParsedLiveEvent {
  String category = '';
  String result = '';
  double totalBases = 0;
  int linguisticRuns = 0;
  bool timely = false;
  int homerNumber = 0;
  String stateScore = '';
  bool goodbye = false;
  String direction = '';
  String exitName = '';
  String enterName = '';
  String positionFrom = '';
  String positionTo = '';
  bool pitcherChange = false;
  String scoreLeftName = '';
  String scoreRightName = '';
  int? scoreLeft;
  int? scoreRight;
}

/// 得点の前後から、速報本文に書かれていない「先制・同点・逆転・勝ち越し」を補う。
String scoreStateFromTransition({
  required bool bottom,
  required int beforeHome,
  required int beforeAway,
  required int afterHome,
  required int afterAway,
}) {
  final beforeBatting = bottom ? beforeHome : beforeAway;
  final beforeFielding = bottom ? beforeAway : beforeHome;
  final afterBatting = bottom ? afterHome : afterAway;
  final afterFielding = bottom ? afterAway : afterHome;
  final beforeDiff = beforeBatting - beforeFielding;
  final afterDiff = afterBatting - afterFielding;

  if (afterDiff == 0 && beforeDiff != 0) return Value.CodeStateScore.TIE;
  if (afterDiff > 0 && beforeDiff < 0) return Value.CodeStateScore.REVERSE;
  if (afterDiff > 0 && beforeDiff == 0) {
    return beforeHome == 0 && beforeAway == 0 ? Value.CodeStateScore.FIRST : Value.CodeStateScore.GO_AHEAD;
  }
  return '';
}

/// 速報本文の「ツーラン」・走者・スコア差のうち、いちばん大きい打点を採用する。
/// スコア差だけだと走者なしソロに落ちることがある。
int preferredLiveRuns({
  required String result,
  required int linguisticRuns,
  required bool runnerFirst,
  required bool runnerSecond,
  required bool runnerThird,
  int scoreDelta = 0,
}) {
  var runs = scoreDelta > 0 ? scoreDelta : 0;
  if (linguisticRuns > runs) runs = linguisticRuns;
  if (result == Value.CodeGameResult.HOME_RUN) {
    final fromRunners = 1 + (runnerFirst ? 1 : 0) + (runnerSecond ? 1 : 0) + (runnerThird ? 1 : 0);
    if (fromRunners > runs) runs = fromRunners;
  }
  return runs;
}

String richerStateScore(String current, String incoming) {
  if (current == Value.CodeStateScore.FIRST) return current;
  if (incoming.isNotEmpty) return incoming;
  return current;
}

int halfOrd(int inning, bool bottom) => inning * 2 + (bottom ? 1 : 0);

/// 出場成績の打席数が増えた最初の半回から書き直す。それより前は残す。
int resumeHalfOrd({
  required Map<int, int> storedCounts,
  required Map<int, int> boxCounts,
}) {
  if (storedCounts.isEmpty) return 0;
  final ords = boxCounts.keys.toList()..sort();
  for (final ord in ords) {
    if ((storedCounts[ord] ?? 0) < (boxCounts[ord] ?? 0)) return ord;
  }
  return ords.isEmpty ? 0 : ords.last;
}

final Set<String> livePlateFinishedResults = {
  Value.CodeGameResult.HIT_SINGLE,
  Value.CodeGameResult.HIT_DOUBLE,
  Value.CodeGameResult.HIT_TRIPLE,
  Value.CodeGameResult.HOME_RUN,
  Value.CodeGameResult.OUT_FLY,
  Value.CodeGameResult.OUT_GROUND,
  Value.CodeGameResult.OUT_POP_UP,
  Value.CodeGameResult.OUT_DOUBLE_PLAY,
  Value.CodeGameResult.OUT_LINE_DRIVE,
  Value.CodeGameResult.SACRIFICE_BUNT,
  Value.CodeGameResult.SACRIFICE_FLY,
  Value.CodeGameResult.SQUEEZE,
  Value.CodeGameResult.STRIKE_OUT,
  Value.CodeGameResult.DROPPED_THIRD,
  Value.CodeGameResult.WALK_BALL,
  Value.CodeGameResult.WALK_DEAD,
  Value.CodeGameResult.WALK_ERROR,
  Value.CodeGameResult.ERROR_FIELDING,
  Value.CodeGameResult.INTERFERENCE_BATTING,
  Value.CodeGameResult.INTERFERENCE_RUNNING,
  Value.CodeGameResult.INTERFERENCE_FIELDING,
};

class StoredLivePlate {
  final int order;
  final int batter;
  final int outs;
  final bool runnerFirst;
  final bool runnerSecond;
  final bool runnerThird;

  const StoredLivePlate({
    required this.order,
    required this.batter,
    required this.outs,
    required this.runnerFirst,
    required this.runnerSecond,
    required this.runnerThird,
  });
}

/// すでに保存した打席と突き合わせ、速報側にだけある打席の位置を返す。
List<int> unmatchedLivePlates({
  required List<ParsedPlate> plates,
  required List<StoredLivePlate> stored,
  required int Function(String batterName) batterIdOf,
}) {
  final used = <int>{};
  final missing = <int>[];
  for (var i = 0; i < plates.length; i++) {
    final plate = plates[i];
    final batterId = batterIdOf(plate.batterName);
    var found = -1;
    for (var s = 0; s < stored.length; s++) {
      if (used.contains(s)) continue;
      final row = stored[s];
      if (plate.battingOrder != 0 && row.order != 0 && plate.battingOrder != row.order) continue;
      if (batterId != 0 && row.batter != 0 && batterId != row.batter) continue;
      if (plate.battingOrder == 0 && batterId == 0) continue;
      if (row.outs != plate.outs) continue;
      if (row.runnerFirst != plate.runnerFirst || row.runnerSecond != plate.runnerSecond || row.runnerThird != plate.runnerThird) continue;
      found = s;
      break;
    }
    if (found >= 0) {
      used.add(found);
    } else {
      missing.add(i);
    }
  }
  return missing;
}

class LiveText {
  static ParsedLiveText parse(Document doc) {
    final root = doc.querySelector('#text_live');
    if (root == null) {
      return ParsedLiveText(halves: [], finished: false);
    }
    final positions = _starterPositions(root);

    final halves = <ParsedHalf>[];
    var finished = false;
    for (final section in root.querySelectorAll('section.bb-liveText')) {
      final title = section.querySelector('.bb-liveText__inning')?.text.trim() ?? '';
      final heading = RegExp(r'(\d+)回(表|裏)').firstMatch(title);
      if (heading == null) {
        if (section.text.contains('試合終了')) finished = true;
        continue;
      }

      final plates = <ParsedPlate>[];
      for (final item in section.querySelectorAll('li.bb-liveText__item')) {
        if (item.text.contains('試合終了')) finished = true;
        final batter = item.querySelector('p.bb-liveText__batter');
        if (batter == null) continue;
        final batterName = batter.querySelector('a.bb-liveText__player')?.text.trim() ?? '';
        if (batterName.isEmpty) continue;

        final orderText = batter.querySelector('span.bb-liveText__order')?.text.trim() ?? '';
        final orderMatch = RegExp(r'(\d+)').firstMatch(orderText);
        final state = _normalizeLiveState(
            batter.querySelector('span.bb-liveText__state')?.text.trim() ?? '');
        final runners = _runners(state);

        final events = <ParsedLiveEvent>[];
        for (final summary in item.querySelectorAll('p.bb-liveText__summary')) {
          if (summary.text.contains('試合終了')) finished = true;
          events.addAll(_eventsOf(summary));
        }
        if (events.isEmpty) continue;
        for (final event in events) {
          final timelyHit = event.timely &&
              (event.result == Value.CodeGameResult.HIT_SINGLE ||
                  event.result == Value.CodeGameResult.HIT_DOUBLE ||
                  event.result == Value.CodeGameResult.HIT_TRIPLE);
          // 二三塁からのタイムリーは本文に「2点」が無くても2打点（MLBサヨナラなど）。
          if (timelyHit && event.linguisticRuns <= 1 && runners.$2 && runners.$3 && !RegExp(r'\d+\s*点').hasMatch(_digits(item.text))) {
            event.linguisticRuns = 2;
          }
        }
        final homerNumber = _homerNumber(_digits(item.text));
        if (homerNumber > 0) {
          for (final event in events) {
            if (event.result == Value.CodeGameResult.HOME_RUN && event.homerNumber == 0) {
              event.homerNumber = homerNumber;
            }
          }
        }

        plates.add(ParsedPlate(
          battingOrder: orderMatch == null ? 0 : int.parse(orderMatch.group(1)!),
          batterName: batterName,
          outs: _outs(state),
          runnerFirst: runners.$1,
          runnerSecond: runners.$2,
          runnerThird: runners.$3,
          events: events,
        ));
      }

      halves.add(ParsedHalf(
        inning: int.parse(heading.group(1)!),
        bottom: heading.group(2) == '裏',
        plates: plates,
      ));
    }

    return ParsedLiveText(halves: _withoutExtraPlates(_inPlayOrder(halves)), finished: finished, positions: positions);
  }

  /// Yahoo MLB のテキスト速報は新しいイニング・打席が先に来る。打席数の整合は古い順で見る。
  static List<ParsedHalf> _inPlayOrder(List<ParsedHalf> halves) {
    final sorted = [...halves]..sort((a, b) {
      final byInning = a.inning.compareTo(b.inning);
      if (byInning != 0) return byInning;
      return (a.bottom ? 1 : 0).compareTo(b.bottom ? 1 : 0);
    });
    return [
      for (final half in sorted)
        ParsedHalf(inning: half.inning, bottom: half.bottom, plates: _inPlateOrder(half.plates)),
    ];
  }

  static List<ParsedPlate> _inPlateOrder(List<ParsedPlate> plates) {
    if (plates.length < 2 || !_platesNewestFirst(plates)) return plates;
    return plates.reversed.toList();
  }

  static bool _platesNewestFirst(List<ParsedPlate> plates) {
    if (plates.last.outs < plates.first.outs) return true;
    if (plates.last.outs > plates.first.outs) return false;
    var forward = 0;
    var backward = 0;
    for (var i = 0; i < plates.length - 1; i++) {
      final from = plates[i].battingOrder;
      final to = plates[i + 1].battingOrder;
      if (from < 1 || from > 9 || to < 1 || to > 9 || from == to) continue;
      final step = (to - from + 9) % 9;
      if (step <= 4) {
        forward++;
      } else {
        backward++;
      }
    }
    return backward > forward;
  }

  static Map<bool, Map<String, String>> _starterPositions(Element root) {
    final away = <String, String>{};
    final home = <String, String>{};
    final text = root.text.replaceAll(RegExp(r'\s+'), ' ');
    final marker = text.indexOf('先攻');
    if (marker < 0) return {false: away, true: home};
    final rest = text.substring(marker);
    final homeAt = rest.indexOf('後攻');
    void fill(String chunk, Map<String, String> into) {
      for (final match in RegExp(r'(\d+)番:\s*(\S+?)\s*[（(]([^)）]+)[)）]').allMatches(chunk)) {
        final name = match.group(2)!.replaceAll(' ', '');
        final pos = _shortDefense(match.group(3)!);
        if (name.isNotEmpty && pos.isNotEmpty) into[name] = pos;
      }
    }

    fill(homeAt < 0 ? rest : rest.substring(0, homeAt), away);
    if (homeAt >= 0) fill(rest.substring(homeAt), home);
    return {false: away, true: home};
  }

  static String _shortDefense(String raw) {
    final text = raw.trim();
    const named = {'投手': '投', '捕手': '捕', '一塁': '一', '二塁': '二', '三塁': '三', '遊撃': '遊', '左翼': '左', '中堅': '中', '右翼': '右', '指名': '指'};
    for (final entry in named.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    const short = {'投', '捕', '一', '二', '三', '遊', '左', '中', '右', '指'};
    if (short.contains(text)) return text;
    return '';
  }

  static bool _safetyBuntHit(String text) {
    if (!text.contains('セーフティ')) return false;
    if (text.contains('アウト') || text.contains('失敗')) return false;
    return text.contains('セーフ') || text.contains('ヒット') || text.contains('安打');
  }

  static bool _countsAsPlate(ParsedPlate plate) {
    return plate.events.any((event) => livePlateFinishedResults.contains(event.result));
  }

  /// 同じ打順のあとに打つ打者は、前の打順より打席が多くならない。
  /// 代打は打順表示がなくても、その枠の次の打席として数える。
  /// 速報の取り直しで同じ打席がもう一度入っても、後ろの枠だけ増えないように捨てる。
  static List<ParsedHalf> _withoutExtraPlates(List<ParsedHalf> halves) {
    final counts = <bool, Map<int, int>>{false: {}, true: {}};
    final nextSlot = <bool, int>{false: 1, true: 1};
    final keptHalves = <ParsedHalf>[];
    for (final half in halves) {
      final count = counts[half.bottom]!;
      final kept = <ParsedPlate>[];
      for (final plate in half.plates) {
        if (!_countsAsPlate(plate)) {
          kept.add(plate);
          continue;
        }
        final shown = plate.battingOrder;
        final order = shown >= 1 && shown <= 9 ? shown : nextSlot[half.bottom]!;
        final next = (count[order] ?? 0) + 1;
        var ahead = true;
        for (var earlier = 1; earlier < order; earlier++) {
          if ((count[earlier] ?? 0) < next) {
            ahead = false;
            break;
          }
        }
        if (!ahead) continue;
        count[order] = next;
        nextSlot[half.bottom] = order == 9 ? 1 : order + 1;
        kept.add(plate);
      }
      keptHalves.add(ParsedHalf(inning: half.inning, bottom: half.bottom, plates: kept));
    }
    return keptHalves;
  }

  static List<ParsedLiveEvent> _eventsOf(Element summary) {
    final text = summary.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final changing = summary.classes.contains('bb-liveText__summary--change') ||
        RegExp(r'投手交代|守備交代|守備固め|守備変更|代打|代走|退場').hasMatch(text);
    if (changing) {
      return _changeEvents(summary);
    }
    final batting = _battingEvent(text, summary);
    if (batting == null) return const [];
    return [batting];
  }

  static List<ParsedLiveEvent> _changeEvents(Element summary) {
    final tokens = <_Tok>[];
    for (final node in summary.nodes) {
      if (node is! Element) continue;
      if (node.localName == 'a') {
        final name = node.text.trim();
        if (name.isNotEmpty) tokens.add(_Tok.player(name));
        continue;
      }
      tokens.addAll(_splitKeywords(node.text));
    }

    final events = <ParsedLiveEvent>[];
    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      if (!token.keyword) {
        i++;
        continue;
      }
      final nextKeyword = _nextKeyword(tokens, i + 1);
      final following = _playersBetween(tokens, i + 1, nextKeyword);
      final previous = _previousPlayer(tokens, i);
      final betweenText = _textBetween(tokens, i + 1, following.isEmpty ? nextKeyword : _indexOfPlayer(tokens, i + 1, following.first));
      final afterPlayer = following.isEmpty ? '' : _textBetween(tokens, _indexOfPlayer(tokens, i + 1, following.first) + 1, nextKeyword);

      final event = ParsedLiveEvent();
      switch (token.text) {
        case '投手交代':
          event.category = Value.CodeGameResultCategory.CHANGE_PLAYER;
          event.result = Value.CodeGameResult.CHANGE_PITCHER;
          event.pitcherChange = true;
          if (following.length >= 2) {
            event.exitName = following[0];
            event.enterName = following[1];
          } else if (previous != null && following.isNotEmpty) {
            event.exitName = previous;
            event.enterName = following[0];
          } else if (following.isNotEmpty) {
            event.enterName = following[0];
          }
          break;
        case '代打':
          event.category = Value.CodeGameResultCategory.CHANGE_PLAYER;
          event.result = Value.CodeGameResult.PINCH_HITTER;
          event.exitName = previous ?? (following.length >= 2 ? following[0] : '');
          event.enterName = previous != null ? (following.isNotEmpty ? following[0] : '') : (following.length >= 2 ? following[1] : '');
          break;
        case '代走':
          event.category = Value.CodeGameResultCategory.CHANGE_PLAYER;
          event.result = Value.CodeGameResult.PINCH_RUNNER;
          event.exitName = previous ?? (following.length >= 2 ? following[0] : '');
          event.enterName = previous != null ? (following.isNotEmpty ? following[0] : '') : (following.length >= 2 ? following[1] : '');
          break;
        case '守備交代':
        case '守備固め':
          event.category = Value.CodeGameResultCategory.CHANGE_PLAYER;
          event.result = Value.CodeGameResult.PINCH_FIELDER;
          if (following.length >= 2) {
            event.exitName = following[0];
            event.enterName = following[1];
          } else if (previous != null && following.isNotEmpty) {
            event.exitName = previous;
            event.enterName = following[0];
          } else if (following.isNotEmpty) {
            event.enterName = following[0];
          } else if (previous != null) {
            event.enterName = previous;
          }
          event.positionTo = _position(betweenText).isNotEmpty ? _position(betweenText) : _position(afterPlayer);
          break;
        case '守備変更':
          event.category = Value.CodeGameResultCategory.CHANGE_POSITION;
          event.result = Value.CodeGameResult.CHANGE_POSITION;
          event.enterName = following.isNotEmpty ? following[0] : (previous ?? '');
          event.exitName = event.enterName;
          final move = _move(afterPlayer.isNotEmpty ? afterPlayer : betweenText);
          event.positionFrom = move.$1;
          event.positionTo = move.$2;
          break;
        case '退場':
          event.category = Value.CodeGameResultCategory.EXIT;
          event.result = Value.CodeGameResult.EXIT;
          event.exitName = previous ?? (following.isNotEmpty ? following[0] : '');
          break;
        default:
          i++;
          continue;
      }
      if (event.enterName.isNotEmpty || event.exitName.isNotEmpty || event.result == Value.CodeGameResult.EXIT) {
        events.add(event);
      }
      i = nextKeyword;
    }
    return events;
  }

  static ParsedLiveEvent? _battingEvent(String text, Element summary) {
    if (text.isEmpty || text.contains('試合終了') || text.contains('スターティング') || text.contains('先発ピッチャー')) {
      return null;
    }
    if (text.contains('リクエスト') || text.contains('リプレー') || text.contains('判定変わらず') || text.contains('判定覆る')) {
      return null;
    }
    if (text.contains('帰塁') && !text.contains('アウト') && !text.contains('タッチ')) {
      return null;
    }

    final event = ParsedLiveEvent();
    final digits = _digits(text);
    if (digits.contains('タッチアウト') || (digits.contains('けん制') && digits.contains('アウト'))) {
      event.category = Value.CodeGameResultCategory.RUNNING_BASE;
      event.result = Value.CodeGameResult.RUN_DEAD;
    } else if (digits.contains('本塁打') || digits.contains('ホームラン')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.HOME_RUN;
      event.totalBases = 4;
    } else if (digits.contains('三塁打') || digits.contains('スリーベース')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.HIT_TRIPLE;
      event.totalBases = 3;
    } else if (digits.contains('二塁打') || digits.contains('ツーベース')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.HIT_DOUBLE;
      event.totalBases = 2;
    } else if ((digits.contains('ヒット') && !digits.contains('ヒット性')) ||
        digits.contains('安打') ||
        digits.contains('適時打') ||
        digits.contains('適時') ||
        _safetyBuntHit(digits)) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.HIT_SINGLE;
      event.totalBases = 1;
    } else if (digits.contains('四球') || digits.contains('フォアボール') || digits.contains('敬遠')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.WALK_BALL;
    } else if (digits.contains('死球')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.WALK_DEAD;
    } else if (digits.contains('ダブルプレー') || digits.contains('併殺')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.OUT_DOUBLE_PLAY;
    } else if (digits.contains('スクイズ')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.SQUEEZE;
    } else if (digits.contains('送りバント') || digits.contains('犠打') || digits.contains('犠牲バント') || digits.contains('バントを決め') || digits.contains('バントを成功')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.SACRIFICE_BUNT;
    } else if (digits.contains('犠飛') || digits.contains('犠牲フライ')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.SACRIFICE_FLY;
    } else if (digits.contains('振り逃げ')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.DROPPED_THIRD;
    } else if (digits.contains('三振')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.STRIKE_OUT;
    } else if (digits.contains('ライナー')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.OUT_LINE_DRIVE;
    } else if (digits.contains('ポップ') || digits.contains('小飛')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.OUT_POP_UP;
    } else if (digits.contains('フライ') || digits.contains('飛球')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.OUT_FLY;
    } else if (digits.contains('ゴロ')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.OUT_GROUND;
    } else if (digits.contains('悪送球') || digits.contains('ファンブル') || digits.contains('失策') || digits.contains('エラー') || digits.contains('後逸') || digits.contains('落球')) {
      event.category = Value.CodeGameResultCategory.ERROR;
      event.result = Value.CodeGameResult.ERROR_FIELDING;
    } else if (digits.contains('暴投')) {
      event.category = Value.CodeGameResultCategory.ERROR;
      event.result = Value.CodeGameResult.WILD_PITCH;
    } else if (digits.contains('捕逸')) {
      event.category = Value.CodeGameResultCategory.ERROR;
      event.result = Value.CodeGameResult.PASS_BALL;
    } else if (digits.contains('野選')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.FIELDERS_CHOICE;
    } else if (digits.contains('打妨') || digits.contains('打撃妨害')) {
      event.category = Value.CodeGameResultCategory.ERROR;
      event.result = Value.CodeGameResult.INTERFERENCE_BATTING;
    } else if (digits.contains('走塁妨害')) {
      event.category = Value.CodeGameResultCategory.ERROR;
      event.result = Value.CodeGameResult.INTERFERENCE_RUNNING;
    } else if (digits.contains('守備妨害')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.INTERFERENCE_FIELDING;
    } else if (digits.contains('盗塁死') || (digits.contains('盗塁') && (digits.contains('アウト') || digits.contains('失敗') || digits.contains('刺さ')))) {
      event.category = Value.CodeGameResultCategory.RUNNING_BASE;
      event.result = Value.CodeGameResult.STEAL_BASE_OUT;
    } else if (digits.contains('盗塁')) {
      event.category = Value.CodeGameResultCategory.RUNNING_BASE;
      event.result = Value.CodeGameResult.STEAL_BASE_SAFE;
    } else if (digits.contains('走塁死')) {
      event.category = Value.CodeGameResultCategory.RUNNING_BASE;
      event.result = Value.CodeGameResult.RUN_DEAD;
    } else {
      return null;
    }

    event.direction = _direction(digits);
    event.goodbye = digits.contains('サヨナラ') && !digits.contains('場面');
    event.stateScore = _stateScore(digits);
    event.homerNumber = _homerNumber(digits);
    event.timely = digits.contains('タイムリー') || digits.contains('適時');
    if (event.result == Value.CodeGameResult.STEAL_BASE_SAFE || event.result == Value.CodeGameResult.STEAL_BASE_OUT) {
      event.enterName = _runnerName(summary, digits);
    }
    event.linguisticRuns = _linguisticRuns(digits, event.result);
    final score = RegExp(r'(\S+)\s+(\d+)\s*[-－]\s*(\d+)\s+(\S+)').firstMatch(digits);
    if (score != null) {
      event.scoreLeftName = score.group(1)!;
      event.scoreLeft = int.parse(score.group(2)!);
      event.scoreRight = int.parse(score.group(3)!);
      event.scoreRightName = score.group(4)!;
    }
    return event;
  }

  static int _outs(String state) {
    final normalized = _normalizeLiveState(state);
    if (normalized.contains('三死') || normalized.contains('3アウト')) return 3;
    if (normalized.contains('二死') || normalized.contains('2アウト')) return 2;
    if (normalized.contains('一死') || normalized.contains('1アウト')) return 1;
    return 0;
  }

  /// MLB 速報は「走者2,3塁」「走者1塁」と算用数字で書く。
  static String _normalizeLiveState(String state) {
    var text = state;
    const numerals = {'1': '一', '2': '二', '3': '三'};
    text = text.replaceAllMapped(RegExp(r'走者\s*([123])\s*,\s*([123])塁'), (match) {
      return '${numerals[match.group(1)]}${numerals[match.group(2)]}塁';
    });
    text = text.replaceAllMapped(RegExp(r'走者\s*([123])塁'), (match) {
      return '${numerals[match.group(1)]}塁';
    });
    text = text.replaceAllMapped(RegExp(r'(^|[^一二三])([123])塁'), (match) {
      return '${match.group(1)}${numerals[match.group(2)]}塁';
    });
    return text;
  }

  static (bool, bool, bool) _runners(String state) {
    if (state.contains('満塁') || state.contains('一二三塁')) {
      return (true, true, true);
    }
    if (state.contains('一二塁')) return (true, true, false);
    if (state.contains('一三塁')) return (true, false, true);
    if (state.contains('二三塁')) return (false, true, true);
    return (state.contains('一塁'), state.contains('二塁'), state.contains('三塁'));
  }

  static String _stateScore(String text) {
    final situational = text.contains('場面') || text.contains('出れば') || text.contains('チャンス') || text.contains('一打');
    if (situational) return '';
    if (text.contains('決勝')) return Value.CodeStateScore.DECISIVE;
    if (text.contains('勝ち越し')) return Value.CodeStateScore.GO_AHEAD;
    if (text.contains('逆転')) return Value.CodeStateScore.REVERSE;
    if (text.contains('同点')) return Value.CodeStateScore.TIE;
    if (text.contains('先制')) return Value.CodeStateScore.FIRST;
    return '';
  }

  static int _linguisticRuns(String text, String result) {
    if (text.contains('満塁') && result == Value.CodeGameResult.HOME_RUN) return 4;
    if (text.contains('グランドスラム')) return 4;
    if (text.contains('3ラン')) return 3;
    if (text.contains('2ラン') || text.contains('ツーラン')) return 2;
    if (text.contains('ソロ')) return 1;
    if (result == Value.CodeGameResult.HOME_RUN) return 1;
    final points = RegExp(r'(\d+)\s*点').firstMatch(text);
    if (points != null) return int.parse(points.group(1)!);
    if (text.contains('タイムリー') || text.contains('適時')) return 1;
    return 0;
  }

  static int _homerNumber(String text) {
    final match = RegExp(r'(\d+)\s*号').firstMatch(text);
    if (match == null) return 0;
    return int.tryParse(match.group(1)!) ?? 0;
  }

  static String _direction(String text) {
    final mark = RegExp(r'[（(]([遊一二三投捕左右中])[）)]').firstMatch(text);
    if (mark != null) {
      final code = _position(switch (mark.group(1)) {
        '遊' => '遊撃',
        '一' => '一塁',
        '二' => '二塁',
        '三' => '三塁',
        '投' => '投手',
        '捕' => '捕手',
        '左' => 'レフト',
        '右' => 'ライト',
        '中' => 'センター',
        _ => '',
      });
      if (code.isNotEmpty) return code;
    }
    const words = [
      '左中間',
      '右中間',
      'レフト線',
      'ライト線',
      'レフト前',
      'ライト前',
      'センター前',
      '中前',
      '左前',
      '右前',
      'レフト',
      'ライト',
      'センター',
      'ファースト',
      'セカンド',
      'サード',
      'ショート',
      'ピッチャー',
      'キャッチャー',
      '中堅',
      '左翼',
      '右翼',
      '左翼線',
      '右翼線',
    ];
    for (final word in words) {
      if (text.contains(word)) {
        final code = _position(word);
        return code.isEmpty ? word : code;
      }
    }
    return '';
  }

  static String _position(String text) {
    const words = [
      'ピッチャー',
      'キャッチャー',
      'ファースト',
      'セカンド',
      'ショート',
      'サード',
      'レフト',
      'ライト',
      'センター',
      '指名打者',
      '一塁',
      '二塁',
      '三塁',
      '遊撃',
      '中堅',
      '左翼',
      '右翼',
      '捕手',
      '投手',
    ];
    for (final word in words) {
      if (!text.contains(word)) continue;
      switch (word) {
        case 'ピッチャー':
        case '投手':
          return Value.CodePosition.P;
        case 'キャッチャー':
        case '捕手':
          return Value.CodePosition.C;
        case 'ファースト':
        case '一塁':
          return Value.CodePosition.FIRST;
        case 'セカンド':
        case '二塁':
          return Value.CodePosition.SECOND;
        case 'サード':
        case '三塁':
          return Value.CodePosition.THIRD;
        case 'ショート':
        case '遊撃':
          return Value.CodePosition.SS;
        case 'レフト':
        case '左翼':
          return Value.CodePosition.LF;
        case 'ライト':
        case '右翼':
          return Value.CodePosition.RF;
        case 'センター':
        case '中堅':
          return Value.CodePosition.CF;
        case '指名打者':
          return Value.CodePosition.DH;
      }
    }
    return '';
  }

  static (String, String) _move(String text) {
    final arrow = text.indexOf('→');
    if (arrow < 0) return ('', _position(text));
    return (_position(text.substring(0, arrow)), _position(text.substring(arrow + 1)));
  }

  static String _runnerName(Element summary, String text) {
    final link = summary.querySelector('a')?.text.trim() ?? '';
    if (link.isNotEmpty) return link;
    return RegExp(r'([A-Za-z一-龥ぁ-んァ-ヶ]{2,12})が').firstMatch(text)?.group(1)?.trim() ?? '';
  }

  static String _digits(String text) {
    const full = '０１２３４５６７８９';
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final index = full.indexOf(char);
      buffer.write(index >= 0 ? '$index' : char);
    }
    return buffer.toString();
  }

  static List<_Tok> _splitKeywords(String raw) {
    final text = raw.replaceAll(RegExp(r'\s+'), ' ');
    if (text.trim().isEmpty) return const [];
    final pattern = RegExp(r'投手交代|守備交代|守備固め|守備変更|代打|代走|退場');
    final tokens = <_Tok>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        final plain = text.substring(cursor, match.start).trim();
        if (plain.isNotEmpty) tokens.add(_Tok.text(plain));
      }
      tokens.add(_Tok.keyword(match.group(0)!));
      cursor = match.end;
    }
    if (cursor < text.length) {
      final plain = text.substring(cursor).trim();
      if (plain.isNotEmpty) tokens.add(_Tok.text(plain));
    }
    return tokens;
  }

  static int _nextKeyword(List<_Tok> tokens, int from) {
    for (var i = from; i < tokens.length; i++) {
      if (tokens[i].keyword) return i;
    }
    return tokens.length;
  }

  static String? _previousPlayer(List<_Tok> tokens, int keywordIndex) {
    for (var i = keywordIndex - 1; i >= 0; i--) {
      if (tokens[i].keyword) return null;
      if (tokens[i].player != null) return tokens[i].player;
    }
    return null;
  }

  static List<String> _playersBetween(List<_Tok> tokens, int from, int until) {
    final names = <String>[];
    for (var i = from; i < until && i < tokens.length; i++) {
      final name = tokens[i].player;
      if (name != null) names.add(name);
    }
    return names;
  }

  static int _indexOfPlayer(List<_Tok> tokens, int from, String name) {
    for (var i = from; i < tokens.length; i++) {
      if (tokens[i].player == name) return i;
    }
    return tokens.length;
  }

  static String _textBetween(List<_Tok> tokens, int from, int until) {
    final buffer = StringBuffer();
    for (var i = from; i < until && i < tokens.length; i++) {
      if (tokens[i].player != null || tokens[i].keyword) continue;
      buffer.write(tokens[i].text);
    }
    return buffer.toString();
  }

  /// 一球速報の球速表記を km/h に揃える。取れなければ null。
  static int? kmhFromSpeedText(String raw) {
    final km = RegExp(r'(\d{2,3})\s*km(?:\s*/\s*h)?', caseSensitive: false).firstMatch(raw);
    if (km != null) {
      final n = int.parse(km.group(1)!);
      if (n >= 80 && n <= 200) return n;
    }
    final mph = RegExp(r'(\d{2,3})\s*(?:mph|マイル)', caseSensitive: false).firstMatch(raw);
    if (mph != null) {
      final n = int.parse(mph.group(1)!);
      if (n >= 50 && n <= 120) return (n * 1.60934).round();
    }
    return null;
  }

  static String scorePitcherName(Document doc) {
    final gm = doc.querySelector('#gm_rslt a')?.text.trim() ?? '';
    if (gm.isNotEmpty) return gm;
    return doc.querySelector('.nm a')?.text.trim() ?? '';
  }

  /// 一打席の一球速報ページから、その投手の当該打席での最速（km/h）。
  static ({String pitcher, int kmh})? maxKmhOnScorePage(Document doc) {
    var max = 0;
    for (final td in doc.querySelectorAll('td.bb-splitsTable__data--speed')) {
      final kmh = kmhFromSpeedText(td.text);
      if (kmh != null && kmh > max) max = kmh;
    }
    if (max <= 0) {
      for (final match in RegExp(r'(\d{2,3})\s*(?:km(?:\s*/\s*h)?|mph|マイル)', caseSensitive: false).allMatches(doc.body?.text ?? '')) {
        final kmh = kmhFromSpeedText(match.group(0)!);
        if (kmh != null && kmh > max) max = kmh;
      }
    }
    final pitcher = scorePitcherName(doc);
    if (pitcher.isEmpty || max <= 0) return null;
    return (pitcher: pitcher, kmh: max);
  }

  static String? nextScoreIndex(Document doc) {
    final a = doc.querySelector('dd.next a');
    if (a == null) return null;
    final idx = (a.attributes['index'] ?? '').trim();
    if (idx.isNotEmpty) return idx;
    return RegExp(r'index=(\d+)').firstMatch(a.attributes['href'] ?? '')?.group(1);
  }

  static Set<String> scorePlateIndexes(Document doc) {
    final out = <String>{};
    for (final a in doc.querySelectorAll('a[href*="index="], a[index]')) {
      final raw = (a.attributes['index'] ?? '').trim();
      final href = a.attributes['href'] ?? '';
      final idx = raw.isNotEmpty ? raw : (RegExp(r'index=(\d{7})').firstMatch(href)?.group(1) ?? '');
      if (idx.length != 7 || idx.endsWith('0000')) continue;
      out.add(idx);
    }
    return out;
  }
}

class _Tok {
  final bool keyword;
  final String text;
  final String? player;

  _Tok.text(this.text)
      : keyword = false,
        player = null;

  _Tok.keyword(this.text)
      : keyword = true,
        player = null;

  _Tok.player(String name)
      : keyword = false,
        text = '',
        player = name;
}
