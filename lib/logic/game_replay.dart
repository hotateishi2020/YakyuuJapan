int _n(dynamic v, [int fallback = 0]) => int.tryParse('$v') ?? fallback;
bool _b(dynamic v) => v == true || v == 1 || v == 'true';
String _s(dynamic v) => v == null ? '' : '$v'.trim();
String replayPosition(dynamic v) =>
    const {
      'P': '投',
      'PITCHER': '投',
      'C': '捕',
      'CATCHER': '捕',
      'FIRST': '一',
      '1B': '一',
      'SECOND': '二',
      '2B': '二',
      'THIRD': '三',
      '3B': '三',
      'SHORT': '遊',
      'SHORTSTOP': '遊',
      'SS': '遊',
      'LEFT': '左',
      'LF': '左',
      'CENTER': '中',
      'CF': '中',
      'RIGHT': '右',
      'RF': '右',
      'DH': '指'
    }[_s(v)] ??
    _s(v);
const replayChanges = {
  'CHANGE_PITCHER',
  'PINCH_HITTER',
  'PINCH_RUNNER',
  'PINCH_FIELDER',
  'CHANGE_POSITION',
  'EXIT'
};
const replayRunning = {
  'STEAL_BASE_SAFE',
  'STEAL_BASE_OUT',
  'WILD_PITCH',
  'PASS_BALL',
  'ERROR_RUNNING'
};

class ReplayFrame {
  final int inning, outs, bases;
  final bool bottom, after;
  final int? homeScore, awayScore;
  final String batter, nextBatter, label;
  final Map<String, String> defense;
  final String result, direction;
  final int beforeBases, runsScored;
  const ReplayFrame(
      {this.result = '',
      this.direction = '',
      this.beforeBases = -1,
      this.runsScored = 0,
      required this.inning,
      required this.bottom,
      required this.after,
      required this.outs,
      required this.bases,
      required this.homeScore,
      required this.awayScore,
      required this.batter,
      required this.nextBatter,
      required this.label,
      required this.defense});
}

/// Each row is a recorded pre-event snapshot. The following row supplies the
/// resulting bases/score; never invent a runner's identity or path from an RBI.
List<ReplayFrame> buildGameReplay(
    Map<String, dynamic> game, List<Map<String, dynamic>> source) {
  final rows = source.where((r) => _n(r['int_inning']) > 0).toList()
    ..sort((a, b) {
      final half = (_n(a['int_inning']) * 2 + (_b(a['flg_bottom']) ? 1 : 0))
          .compareTo(_n(b['int_inning']) * 2 + (_b(b['flg_bottom']) ? 1 : 0));
      return half != 0 ? half : _n(a['id']).compareTo(_n(b['id']));
    });
  final field = <bool, Map<String, String>>{true: {}, false: {}};
  for (final slot in (game['lineup'] as List? ?? []).whereType<Map>()) {
    final players = (slot['players'] as List? ?? []).whereType<Map>();
    if (players.isEmpty) continue;
    final first = players.first;
    final pos = replayPosition(first['pos']);
    if (pos.isEmpty || pos == '指') continue;
    field['${slot['id_team']}' == '${game['id_team_home']}']![pos] =
        _s(first['name']);
  }
  for (final home in [true, false]) {
    final pitcher = _s(game['name_pitcher_${home ? 'home' : 'away'}']);
    if (pitcher.isNotEmpty) field[home]!['投'] = pitcher;
  }
  int? score(Map<String, dynamic> row, String side) =>
      int.tryParse('${row['int_score_$side']}');
  int bases(Map<String, dynamic> row) {
    if (!['first', 'second', 'third']
        .every((s) => row.containsKey('flg_runner_$s'))) {
      return -1;
    }
    return (_b(row['flg_runner_first']) ? 1 : 0) |
        (_b(row['flg_runner_second']) ? 2 : 0) |
        (_b(row['flg_runner_third']) ? 4 : 0);
  }

  final frames = <ReplayFrame>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i], bottom = _b(rows[i]['flg_bottom']);
    final code = _s(row['code_result']), inning = _n(row['int_inning']);
    final defense = field[!bottom]!;
    final pitcher = _s(row['name_pitcher']);
    if (pitcher.isNotEmpty) defense['投'] = pitcher;
    final batter = _s(row['name_full']);
    String next = '';
    for (final later in rows.skip(i + 1)) {
      if (_b(later['flg_bottom']) != bottom) continue;
      if (replayChanges.contains(_s(later['code_result'])) ||
          replayRunning.contains(_s(later['code_result']))) {
        continue;
      }
      if (_n(later['int_batting_order']) ==
          _n(row['int_batting_order']) % 9 + 1) {
        next = _s(later['name_full']);
        break;
      }
    }
    ReplayFrame frame(
            {required bool after,
            required String label,
            required int base,
            required int outs,
            int? h,
            int? a}) =>
        ReplayFrame(
            result: code,
            direction: _s(row['code_direction_batting']),
            beforeBases: bases(row),
            runsScored: after
                ? ((bottom ? h : a) ?? 0) -
                    (score(row, bottom ? 'home' : 'away') ?? 0)
                : 0,
            inning: inning,
            bottom: bottom,
            after: after,
            outs: outs,
            bases: base,
            homeScore: h,
            awayScore: a,
            batter: batter,
            nextBatter: next,
            label: label,
            defense: Map.unmodifiable({...defense}));
    frames.add(frame(
        after: false,
        label: replayChanges.contains(code)
            ? '選手交代前'
            : replayRunning.contains(code)
                ? '進塁記録前'
                : '打席開始',
        base: bases(row),
        outs: _n(row['cnt_out'], -1),
        h: score(row, 'home'),
        a: score(row, 'away')));
    final entered = _s(row['name_enter']), exited = _s(row['name_exit']);
    if (code == 'CHANGE_PITCHER' && entered.isNotEmpty) defense['投'] = entered;
    if (code == 'PINCH_FIELDER' || code == 'CHANGE_POSITION') {
      final to = replayPosition(row['code_position_to']);
      final from = replayPosition(row['code_position_from']);
      if (from.isNotEmpty && defense[from] == entered) defense.remove(from);
      if (entered.isNotEmpty) defense.removeWhere((k, v) => v == entered);
      if (exited.isNotEmpty) defense.removeWhere((k, v) => v == exited);
      if (to.isNotEmpty && entered.isNotEmpty) defense[to] = entered;
    }
    final nextRow = i + 1 < rows.length ? rows[i + 1] : null;
    final sameHalf = nextRow != null &&
        _n(nextRow['int_inning']) == inning &&
        _b(nextRow['flg_bottom']) == bottom;
    final finished = _s(game['state']).contains('終了');
    frames.add(frame(
        after: true,
        label: _s(row['label']).isEmpty ? code : _s(row['label']),
        base: sameHalf
            ? bases(nextRow)
            : nextRow != null
                ? 0
                : -1,
        outs: sameHalf
            ? _n(nextRow['cnt_out'], -1)
            : nextRow != null
                ? 3
                : -1,
        h: nextRow != null
            ? score(nextRow, 'home')
            : finished
                ? int.tryParse('${game['score_home']}')
                : null,
        a: nextRow != null
            ? score(nextRow, 'away')
            : finished
                ? int.tryParse('${game['score_away']}')
                : null));
  }
  return frames;
}
