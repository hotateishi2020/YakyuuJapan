import 'package:html/dom.dart';

import 'Value.dart';

class ParsedLiveText {
  final List<ParsedHalf> halves;
  final bool finished;

  ParsedLiveText({required this.halves, required this.finished});
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
  Value.CodeGameResult.WALK_BALL,
  Value.CodeGameResult.WALK_DEAD,
  Value.CodeGameResult.WALK_ERROR,
  Value.CodeGameResult.ERROR_FIELDING,
  Value.CodeGameResult.INTERFERENCE_BATTING,
  Value.CodeGameResult.INTERFERENCE_RUNNING,
  Value.CodeGameResult.INTERFERENCE_FIELDING,
};

class LiveText {
  static ParsedLiveText parse(Document doc) {
    final root = doc.querySelector('#text_live');
    if (root == null) {
      return ParsedLiveText(halves: [], finished: false);
    }

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
        final state = batter.querySelector('span.bb-liveText__state')?.text.trim() ?? '';
        final runners = _runners(state);

        final events = <ParsedLiveEvent>[];
        for (final summary in item.querySelectorAll('p.bb-liveText__summary')) {
          if (summary.text.contains('試合終了')) finished = true;
          events.addAll(_eventsOf(summary));
        }
        if (events.isEmpty) continue;
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

    return ParsedLiveText(halves: halves, finished: finished);
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
          event.enterName = following.isNotEmpty ? following[0] : (previous ?? '');
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
    } else if ((digits.contains('ヒット') && !digits.contains('ヒット性')) || digits.contains('安打')) {
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
    } else if (digits.contains('ファンブル') || digits.contains('失策') || digits.contains('エラー') || digits.contains('後逸') || digits.contains('落球')) {
      event.category = Value.CodeGameResultCategory.ERROR;
      event.result = Value.CodeGameResult.ERROR_FIELDING;
    } else if (digits.contains('暴投')) {
      event.category = Value.CodeGameResultCategory.ERROR;
      event.result = Value.CodeGameResult.WILD_PITCH;
    } else if (digits.contains('捕逸')) {
      event.category = Value.CodeGameResultCategory.ERROR;
      event.result = Value.CodeGameResult.PASS_BALL;
    } else if (digits.contains('打撃妨害')) {
      event.category = Value.CodeGameResultCategory.ERROR;
      event.result = Value.CodeGameResult.INTERFERENCE_BATTING;
    } else if (digits.contains('走塁妨害')) {
      event.category = Value.CodeGameResultCategory.ERROR;
      event.result = Value.CodeGameResult.INTERFERENCE_RUNNING;
    } else if (digits.contains('守備妨害')) {
      event.category = Value.CodeGameResultCategory.BATTING;
      event.result = Value.CodeGameResult.INTERFERENCE_FIELDING;
    } else if (digits.contains('盗塁死')) {
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
    if (state.contains('三死')) return 3;
    if (state.contains('二死')) return 2;
    if (state.contains('一死')) return 1;
    return 0;
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
    if (text.contains('タイムリー')) return 1;
    return 0;
  }

  static int _homerNumber(String text) {
    final match = RegExp(r'(\d+)\s*号').firstMatch(text);
    if (match == null) return 0;
    return int.tryParse(match.group(1)!) ?? 0;
  }

  static String _direction(String text) {
    const words = ['左中間', '右中間', 'レフト線', 'ライト線', 'レフト', 'ライト', 'センター', 'ファースト', 'セカンド', 'サード', 'ショート', 'ピッチャー', 'キャッチャー', '中堅'];
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
