import 'package:html/dom.dart';

import '../tools/StringTool.dart';
import 'LiveText.dart';
import 'PlayerName.dart';
import 'Value.dart';

/// 出場成績の1打席。打順・イニング・結果はここが正本。
class BoxPlate {
  final int teamId;
  final bool bottom;
  final int order;
  final String name;
  final String position;
  final int inning;
  final String label;
  final String result;
  String direction;
  final double totalBases;
  final int seq;

  int outs = 0;
  bool runnerFirst = false;
  bool runnerSecond = false;
  bool runnerThird = false;
  int runs = 0;
  int homerNumber = 0;
  String stateScore = '';
  bool goodbye = false;
  int scoreHome = 0;
  int scoreAway = 0;
  int pitcherId = 0;
  bool matched = false;

  BoxPlate({
    required this.teamId,
    required this.bottom,
    required this.order,
    required this.name,
    required this.position,
    required this.inning,
    required this.label,
    required this.result,
    required this.direction,
    required this.totalBases,
    required this.seq,
  });
}

/// テキスト速報側の、出場成績に無い出来事。
class LiveExtra {
  final String result;
  final String category;
  final String exitName;
  final String enterName;
  final String positionFrom;
  final String positionTo;
  final bool pitcherChange;

  const LiveExtra({
    required this.result,
    required this.category,
    this.exitName = '',
    this.enterName = '',
    this.positionFrom = '',
    this.positionTo = '',
    this.pitcherChange = false,
  });
}

/// テキスト速報の1打席。打撃結果は出場成績へ写し、それ以外は extras として残す。
class LivePlateNote {
  final int inning;
  final bool bottom;
  final int teamId;
  final String batterName;
  final int battingOrder;
  final int outs;
  final bool runnerFirst;
  final bool runnerSecond;
  final bool runnerThird;
  final String battingResult;
  final int runs;
  final int homerNumber;
  final String stateScore;
  final bool goodbye;
  final String direction;
  final int scoreHome;
  final int scoreAway;
  final int pitcherId;
  final List<LiveExtra> extras;

  const LivePlateNote({
    required this.inning,
    required this.bottom,
    required this.teamId,
    required this.batterName,
    required this.battingOrder,
    required this.outs,
    required this.runnerFirst,
    required this.runnerSecond,
    required this.runnerThird,
    required this.battingResult,
    required this.runs,
    required this.homerNumber,
    required this.stateScore,
    required this.goodbye,
    required this.direction,
    required this.scoreHome,
    required this.scoreAway,
    required this.pitcherId,
    required this.extras,
  });
}

class PlacedExtra {
  final LiveExtra extra;
  final int teamId;
  final bool bottom;
  final int inning;
  final int order;
  final String batterName;
  final int outs;
  final bool runnerFirst;
  final bool runnerSecond;
  final bool runnerThird;
  final int scoreHome;
  final int scoreAway;
  final int pitcherId;

  const PlacedExtra({
    required this.extra,
    required this.teamId,
    required this.bottom,
    required this.inning,
    required this.order,
    required this.batterName,
    required this.outs,
    required this.runnerFirst,
    required this.runnerSecond,
    required this.runnerThird,
    required this.scoreHome,
    required this.scoreAway,
    required this.pitcherId,
  });
}

class _BoxPlay {
  final String result;
  final String direction;
  final double totalBases;

  const _BoxPlay(this.result, this.direction, this.totalBases);
}

/// 出場成績の打者表。先発の守備位置で打順を進め、位置の無い行はその枠の途中出場。
/// MLB はチームごとに `table.bb-statsTable` が分かれる。NPB は1表で合計行で切り替わる。
List<({int teamId, bool bottom, List<Element> rows, bool switchOnTh})> batterStatsGroups(
  Document doc,
  int idTeamAway,
  int idTeamHome,
) {
  final tables = doc.querySelectorAll('#async-gameBatterStats table.bb-statsTable');
  if (tables.length >= 2) {
    return [
      for (var i = 0; i < 2; i++)
        (
          teamId: i == 0 ? idTeamAway : idTeamHome,
          bottom: i == 1,
          rows: tables[i].querySelectorAll('tbody tr'),
          switchOnTh: false,
        ),
    ];
  }
  return [
    (
      teamId: idTeamAway,
      bottom: false,
      rows: doc.querySelectorAll('#async-gameBatterStats tbody tr'),
      switchOnTh: true,
    ),
  ];
}

/// Yahoo 出場成績の打順。`(三)` は先発枠。同じ守備記号の2人目の `(三)` は代守で先発と同じ打順。
class BoxBattingSlot {
  final int order;
  final bool originalStarter;
  const BoxBattingSlot(this.order, this.originalStarter);
}

class BoxBattingOrderTracker {
  int _order = 0;
  final Map<String, int> _firstPos = {};

  void reset() {
    _order = 0;
    _firstPos.clear();
  }

  BoxBattingSlot take(String badge) {
    if (!_isStarterSlot(badge)) {
      return BoxBattingSlot(_order, false);
    }
    final pos = _badgePosition(badge);
    final existing = pos.isEmpty ? null : _firstPos[pos];
    if (existing != null) {
      return BoxBattingSlot(existing, false);
    }
    if (_order < 9) {
      _order++;
      if (pos.isNotEmpty) _firstPos[pos] = _order;
    }
    return BoxBattingSlot(_order, true);
  }
}

List<BoxPlate> parseBoxPlates(Document doc, int idTeamAway, int idTeamHome) {
  final plates = <BoxPlate>[];
  var seq = 0;
  for (final group in batterStatsGroups(doc, idTeamAway, idTeamHome)) {
    var teamId = group.teamId;
    var bottom = group.bottom;
    var switched = false;
    final tracker = BoxBattingOrderTracker();
    var order = 0;
    for (final row in group.rows) {
      if (row.querySelector('th') != null) {
        if (group.switchOnTh && !switched) {
          teamId = idTeamHome;
          bottom = true;
          switched = true;
          tracker.reset();
          order = 0;
        }
        continue;
      }
      final tds = row.querySelectorAll('td');
      if (tds.length < 2) continue;
      final badge = tds.first.text;
      final position = _badgePosition(badge);
      final name = StringTool.noSpace(tds[1].text);
      if (name.isEmpty) continue;
      // (右) は先発枠。(三) が先発の三塁と同じ記号なら守備変更の代守で、打順は進めない。
      // 「三」「走左」「一右」は括弧なしの途中出場で直前の枠。
      final slot = tracker.take(badge);
      order = slot.order;
      if (order < 1) continue;
      var inning = 0;
      for (final cell in row.querySelectorAll('td.bb-statsTable__data--inning')) {
        inning++;
        final details = cell.querySelectorAll('.bb-statsTable__dataDetail');
        final labels = details.isEmpty ? [cell.text.trim()] : [for (final detail in details) detail.text.trim()];
        for (final label in labels) {
          if (label.isEmpty) continue;
          final play = classifyBoxPlay(label);
          if (play == null) continue;
          plates.add(BoxPlate(
            teamId: teamId,
            bottom: bottom,
            order: order,
            name: name,
            position: position,
            inning: inning,
            label: label,
            result: play.result,
            direction: play.direction,
            totalBases: play.totalBases,
            seq: seq++,
          ));
        }
      }
    }
  }
  return plates;
}

class BoxStarter {
  final int teamId;
  final int order;
  final String name;
  final String position;

  const BoxStarter({
    required this.teamId,
    required this.order,
    required this.name,
    required this.position,
  });
}

/// 出場成績の先発9人。まだ打席が無くても打順と守備位置を返す。
List<BoxStarter> parseBoxStarters(Document doc, int idTeamAway, int idTeamHome) {
  final starters = <BoxStarter>[];
  for (final group in batterStatsGroups(doc, idTeamAway, idTeamHome)) {
    var teamId = group.teamId;
    var switched = false;
    final tracker = BoxBattingOrderTracker();
    for (final row in group.rows) {
      if (row.querySelector('th') != null) {
        if (group.switchOnTh && !switched) {
          teamId = idTeamHome;
          switched = true;
          tracker.reset();
        }
        continue;
      }
      final tds = row.querySelectorAll('td');
      if (tds.length < 2) continue;
      final name = StringTool.noSpace(tds[1].text);
      if (name.isEmpty) continue;
      final slot = tracker.take(tds.first.text);
      if (!slot.originalStarter || slot.order < 1 || slot.order > 9) continue;
      starters.add(BoxStarter(
        teamId: teamId,
        order: slot.order,
        name: name,
        position: _badgePosition(tds.first.text),
      ));
    }
  }
  return starters;
}

bool isBoxStarterSlot(String raw) => _isStarterSlot(raw);

String boxBadgePosition(String raw) => _badgePosition(raw);

/// 出場成績の略記（遊ゴロ、左２、空三振、故意四）を結果コードにする。
_BoxPlay? classifyBoxPlay(String raw) {
  final text = raw.replaceAll(RegExp(r'\s+'), '');
  if (text.isEmpty) return null;
  final r = Value.CodeGameResult;
  final direction = _boxDirection(text);
  if (text.contains('打妨') || text.contains('打撃妨害')) return _BoxPlay(r.INTERFERENCE_BATTING, '', 0);
  if (text.contains('野選')) return _BoxPlay(r.FIELDERS_CHOICE, direction, 0);
  if (text.contains('三振')) return _BoxPlay(r.STRIKE_OUT, '', 0);
  if (text.contains('振逃') || text.contains('振り逃げ')) return _BoxPlay(r.DROPPED_THIRD, '', 0);
  if (text.contains('四球') || text.contains('故意四') || text.contains('敬遠')) return _BoxPlay(r.WALK_BALL, '', 0);
  if (text.contains('死球')) return _BoxPlay(r.WALK_DEAD, '', 0);
  if (text.contains('併')) return _BoxPlay(r.OUT_DOUBLE_PLAY, direction, 0);
  if (text.contains('犠打') || text.contains('バント')) return _BoxPlay(r.SACRIFICE_BUNT, direction, 0);
  if (text.contains('犠飛') || text.contains('犠野')) return _BoxPlay(r.SACRIFICE_FLY, direction, 0);
  if (text.contains('邪')) return _BoxPlay(r.OUT_POP_UP, direction, 0);
  if (text.contains('直') || text.contains('ライナー')) return _BoxPlay(r.OUT_LINE_DRIVE, direction, 0);
  if (text.contains('本')) return _BoxPlay(r.HOME_RUN, direction, 4);
  if (text.endsWith('３') || text.endsWith('3') || text.contains('三塁打')) return _BoxPlay(r.HIT_TRIPLE, direction, 3);
  if (text.endsWith('２') || text.endsWith('2') || text.contains('二塁打')) return _BoxPlay(r.HIT_DOUBLE, direction, 2);
  if (text.contains('安')) return _BoxPlay(r.HIT_SINGLE, direction, 1);
  if (text.contains('失') || text.contains('エラー')) return _BoxPlay(r.ERROR_FIELDING, direction, 0);
  if (text.contains('ゴ')) return _BoxPlay(r.OUT_GROUND, direction, 0);
  if (text.contains('飛')) return _BoxPlay(r.OUT_FLY, direction, 0);
  return null;
}

/// テキスト速報の打撃結果を、同じ打者の出場成績の打席へ写す。
/// 合わない速報の打席は作らない。盗塁や交代だけを別行で返す。
List<PlacedExtra> attachLiveNotes(List<BoxPlate> plates, List<LivePlateNote> notes) {
  final extras = <PlacedExtra>[];
  for (final note in notes) {
    BoxPlate? plate;
    if (note.battingResult.isNotEmpty) {
      plate = _takePlate(plates, note);
      if (plate != null) {
        plate.outs = note.outs;
        plate.runnerFirst = note.runnerFirst;
        plate.runnerSecond = note.runnerSecond;
        plate.runnerThird = note.runnerThird;
        plate.runs = note.runs;
        plate.homerNumber = note.homerNumber;
        plate.stateScore = note.stateScore;
        plate.goodbye = note.goodbye;
        plate.scoreHome = note.scoreHome;
        plate.scoreAway = note.scoreAway;
        plate.pitcherId = note.pitcherId;
        if (plate.direction.isEmpty && note.direction.isNotEmpty) plate.direction = note.direction;
      }
    }
    final situation = plate;
    for (final extra in note.extras) {
      extras.add(PlacedExtra(
        extra: extra,
        teamId: note.teamId,
        bottom: note.bottom,
        inning: note.inning,
        order: situation?.order ?? (note.battingOrder >= 1 && note.battingOrder <= 9 ? note.battingOrder : 0),
        batterName: note.batterName,
        outs: situation?.outs ?? note.outs,
        runnerFirst: situation?.runnerFirst ?? note.runnerFirst,
        runnerSecond: situation?.runnerSecond ?? note.runnerSecond,
        runnerThird: situation?.runnerThird ?? note.runnerThird,
        scoreHome: situation?.scoreHome ?? note.scoreHome,
        scoreAway: situation?.scoreAway ?? note.scoreAway,
        pitcherId: situation?.pitcherId ?? note.pitcherId,
      ));
    }
  }
  return extras;
}

BoxPlate? _takePlate(List<BoxPlate> plates, LivePlateNote note) {
  BoxPlate? fallback;
  for (final plate in plates) {
    if (plate.matched || plate.teamId != note.teamId || plate.result != note.battingResult) continue;
    if (!_sameBatter(plate.name, note.batterName)) continue;
    if (plate.inning == note.inning) {
      plate.matched = true;
      return plate;
    }
    fallback ??= plate;
  }
  if (fallback != null) fallback.matched = true;
  return fallback;
}

int _orderDistance(int order, int start) {
  if (order < 1 || order > 9) return 30;
  return (order - start + 9) % 9;
}

/// 出場成績の seq は打者表の並びなので、イニング内は前の回の続きの打順で見る。
List<BoxPlate> platesInPlayOrder(List<BoxPlate> plates) {
  final halves = <({int inning, bool bottom, List<BoxPlate> plates})>[];
  for (final plate in plates) {
    final found = halves.where((half) => half.inning == plate.inning && half.bottom == plate.bottom);
    if (found.isEmpty) {
      halves.add((inning: plate.inning, bottom: plate.bottom, plates: [plate]));
    } else {
      found.first.plates.add(plate);
    }
  }
  halves.sort((a, b) {
    final byInning = a.inning.compareTo(b.inning);
    if (byInning != 0) return byInning;
    return (a.bottom ? 1 : 0).compareTo(b.bottom ? 1 : 0);
  });
  var startAway = 1;
  var startHome = 1;
  final ordered = <BoxPlate>[];
  for (final half in halves) {
    final start = half.bottom ? startHome : startAway;
    half.plates.sort((a, b) {
      final byDist = _orderDistance(a.order, start).compareTo(_orderDistance(b.order, start));
      if (byDist != 0) return byDist;
      return a.seq.compareTo(b.seq);
    });
    ordered.addAll(half.plates);
    final last = half.plates.last.order;
    if (last >= 1 && last <= 9) {
      final next = last == 9 ? 1 : last + 1;
      if (half.bottom) {
        startHome = next;
      } else {
        startAway = next;
      }
    }
  }
  return ordered;
}

/// 速報が付いていない本塁打でも、直前の出塁から打点と先制などを補う。
void applyBoxPlateScoring(List<BoxPlate> plates) {
  if (plates.isEmpty) return;
  final ordered = platesInPlayOrder(plates);
  var first = false;
  var second = false;
  var third = false;
  var inning = 0;
  var bottom = false;
  var scoreHome = 0;
  var scoreAway = 0;
  final r = Value.CodeGameResult;
  for (final plate in ordered) {
    if (plate.inning != inning || plate.bottom != bottom) {
      first = false;
      second = false;
      third = false;
      inning = plate.inning;
      bottom = plate.bottom;
    }
    if (!plate.matched) {
      plate.runnerFirst = first;
      plate.runnerSecond = second;
      plate.runnerThird = third;
      plate.scoreHome = scoreHome;
      plate.scoreAway = scoreAway;
    }
    if (plate.result == r.HOME_RUN) {
      final fromRunners = 1 + (plate.runnerFirst ? 1 : 0) + (plate.runnerSecond ? 1 : 0) + (plate.runnerThird ? 1 : 0);
      if (plate.runs < fromRunners) plate.runs = fromRunners;
    }
    if (plate.runs > 0 && plate.stateScore.isEmpty) {
      final afterHome = plate.bottom ? scoreHome + plate.runs : scoreHome;
      final afterAway = plate.bottom ? scoreAway : scoreAway + plate.runs;
      plate.stateScore = scoreStateFromTransition(
        bottom: plate.bottom,
        beforeHome: scoreHome,
        beforeAway: scoreAway,
        afterHome: afterHome,
        afterAway: afterAway,
      );
    }
    if (plate.runs > 0) {
      if (plate.bottom) {
        scoreHome += plate.runs;
      } else {
        scoreAway += plate.runs;
      }
    }
    if (plate.result == r.HOME_RUN) {
      first = false;
      second = false;
      third = false;
    } else if (plate.result == r.HIT_DOUBLE) {
      third = first || second;
      second = true;
      first = false;
    } else if (plate.result == r.HIT_TRIPLE) {
      first = false;
      second = false;
      third = true;
    } else if (plate.result == r.OUT_DOUBLE_PLAY) {
      first = false;
      second = false;
      third = false;
    } else if (plate.result == r.SACRIFICE_FLY) {
      third = false;
    } else if (plate.result == r.HIT_SINGLE ||
        plate.result == r.WALK_BALL ||
        plate.result == r.WALK_DEAD ||
        plate.result == r.ERROR_FIELDING ||
        plate.result == r.INTERFERENCE_BATTING ||
        plate.result == r.FIELDERS_CHOICE ||
        plate.result == r.DROPPED_THIRD) {
      third = second;
      second = first;
      first = true;
    }
  }
}

bool _sameBatter(String boxName, String liveName) {
  final box = StringTool.noSpace(boxName);
  final live = StringTool.noSpace(liveName);
  if (box.isEmpty || live.isEmpty) return false;
  if (box == live || box.startsWith(live) || live.startsWith(box)) return true;
  return playerNameMatches(query: live, nameFull: box) ||
      playerNameMatches(query: box, nameFull: live);
}

const _positionMarks = {'投', '捕', '一', '二', '三', '遊', '左', '中', '右', '指'};

bool _isStarterSlot(String raw) {
  final trimmed = raw.trim();
  final wrapped = (trimmed.startsWith('(') || trimmed.startsWith('（')) && (trimmed.endsWith(')') || trimmed.endsWith('）'));
  if (!wrapped) return false;
  final text = trimmed.replaceAll(RegExp(r'[（）()\s]'), '');
  return text.isNotEmpty && text.split('').every(_positionMarks.contains);
}

/// Yahoo の出場成績バッジから守備位置を取る。
/// `(右一)` / `(中左)` は先発位置→途中移籍なので先頭の守備記号を使う（末尾だと一塁が二重になる）。
String _badgePosition(String raw) {
  final text = raw.replaceAll(RegExp(r'[（）()\s]'), '');
  for (var i = 0; i < text.length; i++) {
    if (_positionMarks.contains(text[i])) return text[i];
  }
  return '';
}

String _boxDirection(String text) {
  if (text.isEmpty) return '';
  final head = text.substring(0, 1);
  final p = Value.CodePosition;
  return switch (head) {
    '左' => p.LF,
    '中' => p.CF,
    '右' => p.RF,
    '遊' => p.SS,
    '投' => p.P,
    '捕' => p.C,
    '一' => p.FIRST,
    '二' => p.SECOND,
    '三' => p.THIRD,
    _ => '',
  };
}
