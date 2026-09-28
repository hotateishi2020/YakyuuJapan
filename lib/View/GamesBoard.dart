import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../tools/color_parse.dart';
import '../tools/date_format.dart';
import 'Text.dart';
import 'Border.dart';

String gameDateOnly(dynamic value) {
  final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch('${value ?? ''}');
  return match?.group(0) ?? '${value ?? ''}'.trim();
}

int _gameInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value'.trim()) ?? 0;
}

String gameMatchupKey(Map<String, dynamic> game) {
  final idGame = game['id_game'] ?? game['id'];
  final idText = '${idGame ?? ''}'.trim();
  if (idText.isNotEmpty && idText != 'null' && idText != '0') {
    return 'id:$idText';
  }
  final date = gameDateOnly(game['date_game']);
  final homeName = '${game['name_team_home'] ?? ''}'.trim();
  final awayName = '${game['name_team_away'] ?? ''}'.trim();
  if (homeName.isNotEmpty && awayName.isNotEmpty) {
    return '$date|$homeName|$awayName';
  }
  return '$date|${_gameInt(game['id_team_home'])}|${_gameInt(game['id_team_away'])}';
}

bool gameHasStarted(Map<String, dynamic> game) {
  final state = '${game['state'] ?? ''}'.trim();
  if (state.isNotEmpty) return true;
  final home = int.tryParse('${game['score_home']}') ?? -1;
  final away = int.tryParse('${game['score_away']}') ?? -1;
  return home >= 0 && away >= 0;
}

List<Map<String, dynamic>> expandGameRows(Map<String, dynamic> game) {
  final raw = game['summaries'];
  var summaries = const <Map<String, dynamic>>[];
  if (raw is List) {
    summaries = [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  } else if (raw is String) {
    final text = raw.trim();
    if (text.isNotEmpty && text != 'null') {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          summaries = [
            for (final item in decoded)
              if (item is Map) Map<String, dynamic>.from(item),
          ];
        }
      } catch (_) {}
    }
  }
  if (summaries.isEmpty) return [Map<String, dynamic>.from(game)..remove('summaries')];
  final base = Map<String, dynamic>.from(game)..remove('summaries');
  return [
    for (final summary in summaries) ({...base, ...summary}..remove('summaries')),
  ];
}

List<List<Map<String, dynamic>>> groupGamesByMatchup(List<Map<String, dynamic>> games) {
  final order = <String>[];
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final game in games) {
    for (final row in expandGameRows(game)) {
      final key = gameMatchupKey(row);
      if (!groups.containsKey(key)) {
        order.add(key);
        groups[key] = [];
      }
      groups[key]!.add(row);
    }
  }
  return [for (final key in order) groups[key]!];
}

List<Map<String, dynamic>> normalizeGames(List<Map<String, dynamic>> games) {
  return [
    for (final rows in groupGamesByMatchup(games))
      {
        ...rows.first,
        'summaries': rows,
      },
  ];
}

class GameDateSwitcher extends StatefulWidget {
  final List<Map<String, dynamic>> games;
  final Color headerColor;
  final String? initialDate;
  final bool horizontal;

  const GameDateSwitcher({
    super.key,
    required this.games,
    required this.headerColor,
    this.initialDate,
    this.horizontal = true,
  });

  @override
  State<GameDateSwitcher> createState() => _GameDateSwitcherState();
}

class _GameDateSwitcherState extends State<GameDateSwitcher> {
  late DateTime _baseDate;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _baseDate = DateTime.tryParse(widget.initialDate ?? '') ?? DateTime.now();
    _baseDate = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
  }

  DateTime get _selectedDate => _baseDate.add(Duration(days: _offset));

  String _jaDate(DateTime date) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return '${date.year}年${date.month.toString().padLeft(2, '0')}月'
        '${date.day.toString().padLeft(2, '0')}日'
        '(${weekdays[date.weekday - 1]})';
  }

  String _dayLabel() {
    if (_offset == -1) return '昨日';
    if (_offset == 0) return '今日';
    if (_offset == 1) return '明日';
    if (_offset < 0) return '${-_offset}日前';
    return '$_offset日後';
  }

  void _move(int by) {
    setState(() => _offset += by);
  }

  Widget _dateButton(String label, int by) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _move(by),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = _selectedDate;
    final date = DateFormatUtil.ymd(selectedDate);
    final dayGames = normalizeGames(
      widget.games.where((game) => gameDateOnly(game['date_game']) == date).toList(),
    );
    final header = Container(
      height: 33,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.headerColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _dateButton('前の日', -1),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _offset = 0),
                child: Center(
                  child: OneLineShrinkText(
                    '${_dayLabel()}  ${_jaDate(selectedDate)}',
                    baseSize: 13,
                    minSize: 7,
                    weight: FontWeight.bold,
                    color: Colors.white,
                    verticalPadding: 2,
                  ),
                ),
              ),
            ),
          ),
          _dateButton('次の日', 1),
        ],
      ),
    );
    final board = GamesBoardYahooStyle(
      key: ValueKey('games-$date-${dayGames.map(gameMatchupKey).join('|')}'),
      games: dayGames,
      dateFilter: date,
      horizontal: widget.horizontal,
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxHeight.isFinite) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 4),
            Expanded(child: board),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 4),
          board,
        ],
      );
    });
  }
}

class GamesBoardYahooStyle extends StatelessWidget {
  final List<Map<String, dynamic>> games;
  final String? dateFilter; // "YYYY-MM-DD"
  /// true のとき試合カードを横並び表示（リーグ内の1日分向け）
  final bool horizontal;

  const GamesBoardYahooStyle({
    super.key,
    required this.games,
    this.dateFilter,
    this.horizontal = false,
  });

  int _toInt(dynamic v) {
    if (v == null) return 0;
    final s = v.toString().trim();
    return int.tryParse(s) ?? 0;
  }

  String _sectionOf(Map<String, dynamic> g) {
    final h = _toInt(g['id_league_home']);
    final a = _toInt(g['id_league_away']);
    if (h == 1 && a == 1) return 'セ・リーグ';
    if (h == 2 && a == 2) return 'パ・リーグ';
    return '交流戦';
  }

  List<List<Map<String, dynamic>>> _groupGames(List<Map<String, dynamic>> src) {
    return groupGamesByMatchup(src);
  }

  @override
  Widget build(BuildContext context) {
    final src = (dateFilter == null || dateFilter!.isEmpty) ? games : games.where((g) => gameDateOnly(g['date_game']) == dateFilter).toList();
    final grouped = _groupGames(normalizeGames(src));

    if (horizontal) {
      if (grouped.isEmpty) {
        return const SizedBox(
          height: 40,
          child: Center(child: Text('試合はありません', style: TextStyle(fontSize: 12))),
        );
      }
      return LayoutBuilder(builder: (context, constraints) {
        final started = grouped.any((rows) => gameHasStarted(rows.first));
        final heights = [for (final rows in grouped) _TableGameCard(rows).intrinsicHeight];
        if (started) {
          final needed = heights.fold<double>(0, (sum, h) => sum + h) + 2 * math.max(0, grouped.length - 1);
          final canFit = constraints.maxHeight.isFinite && constraints.maxHeight + 0.5 >= needed;
          Widget column({required bool expand}) {
            return Column(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < grouped.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  expand
                      ? Expanded(
                          flex: math.max(1, heights[i].round()),
                          child: _TableGameCard(grouped[i]),
                        )
                      : SizedBox(height: heights[i], child: _TableGameCard(grouped[i])),
                ],
              ],
            );
          }

          if (canFit) return column(expand: true);
          if (!constraints.maxHeight.isFinite) return column(expand: false);
          return SingleChildScrollView(child: column(expand: false));
        }

        final neededH = heights.reduce(math.max);
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < grouped.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(child: _TableGameCard(grouped[i])),
            ],
          ],
        );
        if (!constraints.maxHeight.isFinite) {
          return SizedBox(height: neededH, child: row);
        }
        if (constraints.maxHeight + 0.5 >= neededH) return row;
        return SingleChildScrollView(child: SizedBox(height: neededH, child: row));
      });
    }

    final bySec = <String, List<List<Map<String, dynamic>>>>{};
    for (final rows in grouped) {
      final sec = _sectionOf(rows.first);
      bySec.putIfAbsent(sec, () => []).add(rows);
    }

    if (bySec.isEmpty) {
      return const Center(child: Text('試合はありません', style: TextStyle(fontSize: 12)));
    }

    return LayoutBuilder(builder: (context, c) {
      final bySecKeys = bySec.keys.toSet();
      final order = ['セ・リーグ', 'パ・リーグ'].where((k) => bySecKeys.contains(k)).toList();

      Widget threeRows(List<List<Map<String, dynamic>>> list) {
        final g0 = list.isNotEmpty ? list[0] : null;
        final g1 = list.length > 1 ? list[1] : null;
        final g2 = list.length > 2 ? list[2] : null;

        Widget slot(List<Map<String, dynamic>>? g) {
          if (g == null) return const SizedBox();
          return LayoutBuilder(builder: (context, cc) {
            final double hAvail = cc.maxHeight.isFinite ? cc.maxHeight : 0.0;
            const double minCardH = 110.0; // これ以下なら内部スクロール
            if (hAvail <= 0 || hAvail >= minCardH) {
              return _TableGameCard(g);
            }
            return SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: SizedBox(height: minCardH, child: _TableGameCard(g)),
            );
          });
        }

        // 元の3分割構成を維持。足りないときだけ各枠内をスクロール
        return Column(
          children: [
            Expanded(child: slot(g0)),
            const SizedBox(height: 2),
            Expanded(child: slot(g1)),
            const SizedBox(height: 2),
            Expanded(child: slot(g2)),
          ],
        );
      }

      return Column(
        children: [
          for (final sec in order) Expanded(child: threeRows(bySec[sec]!)),
        ],
      );
    });
  }
}

class _LeagueHeader extends StatelessWidget {
  final String label;
  const _LeagueHeader(this.label);

  Color get _color => label == 'セ・リーグ'
      ? const Color(0xFF19A974)
      : label == 'パ・リーグ'
          ? const Color(0xFF2CB1BC)
          : const Color(0xFF6C63FF);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}

class _TableGameCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _TableGameCard(this.rows);

  Map<String, dynamic> get game => rows.first;

  static const _lineColor = Color(0xFF333333);
  static const _labelColor = Color(0xFF5A5A5A);
  static const _minPlayerNameSize = 8.0;
  static const _minPlayerStatSize = 8.0;
  static const _minHeaderH = 22.0;
  static const _minTeamRowH = 28.0;
  static const _playerRowH = 18.0;

  String _text(String key) => game[key]?.toString() ?? '';
  int _int(String key) => int.tryParse('${game[key]}') ?? -1;

  bool _isPitcher(Map<String, dynamic> row) {
    final value = row['flg_pitcher'];
    if (value is bool) return value;
    final text = '$value'.trim().toLowerCase();
    return text == 'true' || text == 't' || text == '1';
  }

  String _batterMark(Map<String, dynamic> row) {
    final homers = int.tryParse('${row['int_homerun'] ?? ''}') ?? 0;
    if (homers > 0) return 'HR';
    final batting = '${row['txt_batting'] ?? ''}';
    if (RegExp(r'\d+HR').hasMatch(batting)) return 'HR';
    return '';
  }

  String _resultMark(dynamic code) {
    final text = '${code ?? ''}'.trim().toUpperCase();
    return switch (text) {
      'WIN' || '勝' => '勝',
      'LOSE' || '負' => '負',
      'SAVE' || 'S' => 'S',
      'HOLD' || 'H' => 'H',
      _ => '',
    };
  }

  Color _pale(Color? color) {
    final base = color ?? const Color(0xFFE0E0E0);
    const mix = 0.58;
    final value = base.toARGB32();
    final r = (value >> 16) & 0xFF;
    final g = (value >> 8) & 0xFF;
    final b = value & 0xFF;
    return Color.fromARGB(
      255,
      (r + (255 - r) * mix).round(),
      (g + (255 - g) * mix).round(),
      (b + (255 - b) * mix).round(),
    );
  }

  String _statOf(Map<String, dynamic> row, {required bool pitcher}) {
    final raw = '${row[pitcher ? 'txt_pitching' : 'txt_batting'] ?? ''}'.trim();
    if (raw.isEmpty || raw == 'null') return '';
    return raw;
  }

  String _homerunTotalLabel(Map<String, dynamic> row) {
    final raw = '${row['txt_homerun_total'] ?? ''}'.trim();
    if (raw.isEmpty || raw == 'null') return '';
    final labels = <String>[];
    for (final part in raw.split(RegExp(r'[,、]\s*'))) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final digits = RegExp(r'\d+').firstMatch(text);
      if (digits == null) continue;
      labels.add('${digits.group(0)}号');
    }
    return labels.join(',');
  }

  List<({String name, String colors, String mark, String stat, String hrTotal})> _players({
    required bool home,
    required bool pitcher,
  }) {
    final teamId = _int(home ? 'id_team_home' : 'id_team_away');
    final starterName = _text(home ? 'name_pitcher_home' : 'name_pitcher_away');
    final starterColors = _text(home ? 'colors_pitcher_home' : 'colors_pitcher_away');
    final result = <({String name, String colors, String mark, String stat, String hrTotal})>[];

    void add(String name, String playerColors, String mark, [String stat = '', String hrTotal = '']) {
      if (name.trim().isEmpty) return;
      final index = result.indexWhere((player) => player.name == name);
      if (index < 0) {
        result.add((name: name, colors: playerColors, mark: mark, stat: stat, hrTotal: hrTotal));
        return;
      }
      final current = result[index];
      result[index] = (
        name: current.name,
        colors: current.colors.isNotEmpty ? current.colors : playerColors,
        mark: current.mark.isNotEmpty ? current.mark : mark,
        stat: current.stat.isNotEmpty ? current.stat : stat,
        hrTotal: current.hrTotal.isNotEmpty ? current.hrTotal : hrTotal,
      );
    }

    for (final row in rows) {
      final name = '${row['name_full_summary'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final summaryTeam = int.tryParse('${row['id_team_summary']}') ?? -1;
      if (summaryTeam != teamId) continue;
      if (_isPitcher(row) != pitcher) continue;
      final colors = '${row['colors_summary'] ?? ''}'.trim();
      final mark = pitcher ? _resultMark(row['code_result_pitcher']) : _batterMark(row);
      add(
        name,
        colors.isNotEmpty ? colors : (name == starterName ? starterColors : ''),
        mark,
        _statOf(row, pitcher: pitcher),
        _homerunTotalLabel(row),
      );
    }

    if (result.isNotEmpty) return result;

    if (pitcher) {
      add(starterName, starterColors, '');
      if (_int('id_team_pitcher_win') == teamId) {
        add(_text('name_pitcher_win'), '', '勝');
      }
      if (_int('id_team_pitcher_lose') == teamId) {
        add(_text('name_pitcher_lose'), '', '負');
      }
      if (_int('id_team_pitcher_save') == teamId) {
        add(_text('name_pitcher_save'), '', 'S');
      }
    } else {
      add(_text(home ? 'name_homerun_home' : 'name_homerun_away'), '', 'HR');
    }
    return result;
  }

  double get intrinsicHeight {
    final homePitchers = _players(home: true, pitcher: true);
    final awayPitchers = _players(home: false, pitcher: true);
    final homeBatters = _players(home: true, pitcher: false);
    final awayBatters = _players(home: false, pitcher: false);
    final pitcherN = math.max(1, math.max(homePitchers.length, awayPitchers.length));
    final batterN = math.max(1, math.max(homeBatters.length, awayBatters.length));
    const sectionPad = 2.0;
    const chrome = 8.0;
    final inProgress = '${game['state'] ?? ''}'.contains('回');
    return _minHeaderH + _minTeamRowH + pitcherN * _playerRowH + batterN * _playerRowH + sectionPad * 2 + chrome + (inProgress ? 6.0 : 0.0);
  }

  Widget _cell({
    required Widget child,
    Color? color,
    bool right = true,
    bool bottom = true,
    AlignmentGeometry alignment = Alignment.center,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
  }) {
    return Container(
      clipBehavior: Clip.hardEdge,
      alignment: alignment,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border(
          right: right ? const BorderSide(color: _lineColor) : BorderSide.none,
          bottom: bottom ? const BorderSide(color: _lineColor) : BorderSide.none,
        ),
      ),
      child: child,
    );
  }

  Widget _textCell(
    String text, {
    required double size,
    Color? color,
    Color? textColor,
    FontWeight? weight,
    bool right = true,
    bool bottom = true,
    TextAlign align = TextAlign.center,
    double minSize = 9,
  }) {
    return _cell(
      color: color,
      right: right,
      bottom: bottom,
      child: OneLineShrinkText(
        text,
        baseSize: size,
        minSize: minSize,
        color: textColor ?? Colors.black87,
        weight: weight,
        align: align,
      ),
    );
  }

  double _textWidth(
    String text,
    double fontSize, {
    FontWeight weight = FontWeight.normal,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text.isEmpty ? '—' : text,
        style: TextStyle(fontSize: fontSize, fontWeight: weight, height: 1.1),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    return painter.width;
  }

  double _nameColumnWidth(
    Iterable<({String name, String colors, String mark, String stat, String hrTotal})> players,
    double fontSize,
    BuildContext context,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    var width = 0.0;
    for (final player in players) {
      // _pitcherNameBox の左右 padding 2+2。成績のために名前幅を削らない。
      final w = _textWidth(player.name, fontSize, weight: FontWeight.bold, textScaler: scaler) + 4;
      if (w > width) width = w;
    }
    return width.ceilToDouble();
  }

  Widget _pitcherCell(
    List<({String name, String colors, String mark, String stat, String hrTotal})> pitchers, {
    required Color color,
    required double size,
    required bool right,
    bool bottom = true,
    double nameColW = 0,
    bool centerNames = false,
  }) {
    final nameSize = size < _minPlayerNameSize ? _minPlayerNameSize : size;
    final statSize = (nameSize * 0.92).clamp(_minPlayerStatSize, 12.0);
    final rowH = _playerRowH;
    final badgeWidth = (nameSize + 2).clamp(9.0, 16.0);

    return _cell(
      color: color,
      right: right,
      bottom: bottom,
      alignment: centerNames ? Alignment.center : Alignment.topLeft,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: pitchers.isEmpty
          ? const SizedBox.expand()
          : LayoutBuilder(builder: (context, constraints) {
              final maxH = constraints.maxHeight;
              final fitRowH = maxH.isFinite && pitchers.isNotEmpty ? math.min(rowH, maxH / pitchers.length) : rowH;
              final cellW = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
              final scaler = MediaQuery.textScalerOf(context);
              final nameStatGap = 2.0 + _textWidth(' ', nameSize, textScaler: scaler);

              if (!constraints.maxWidth.isFinite || constraints.maxWidth < 1) {
                return const SizedBox.expand();
              }

              if (centerNames) {
                return SizedBox(
                  width: cellW,
                  height: maxH.isFinite ? maxH : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final pitcher in pitchers)
                        SizedBox(
                          height: fitRowH,
                          width: cellW,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (pitcher.mark.isNotEmpty) ...[
                                SizedBox(
                                  width: badgeWidth,
                                  child: _resultBadge(pitcher.mark, nameSize),
                                ),
                                const SizedBox(width: 0.5),
                              ],
                              _pitcherNameBox(
                                name: pitcher.name,
                                colorsRaw: pitcher.colors,
                                baseSize: nameSize,
                                minSize: _minPlayerNameSize,
                                alignLeft: false,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              }

              final reservedNameW = nameColW > 0 ? nameColW : _nameColumnWidth(pitchers, nameSize, context);
              final leadingW = badgeWidth + 0.5;
              // 名前幅は成績のために削らない。セル自体が名前より狭いときだけクリップする。
              final maxNameBox = math.max(0.0, cellW - leadingW);
              final nameBoxW = reservedNameW.clamp(0.0, maxNameBox).toDouble();
              final restW = math.max(0.0, cellW - leadingW - nameBoxW);
              final hasAnyStats = pitchers.any((p) => p.stat.isNotEmpty || p.hrTotal.isNotEmpty);
              final gapW = hasAnyStats && restW > nameStatGap ? nameStatGap : 0.0;
              final statsViewportW = hasAnyStats ? math.max(0.0, restW - gapW) : 0.0;

              Widget statLine(({String name, String colors, String mark, String stat, String hrTotal}) pitcher) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pitcher.stat.isNotEmpty)
                      Text(
                        pitcher.stat,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: statSize,
                          color: Colors.black87,
                          height: 1.1,
                        ),
                      ),
                    if (pitcher.hrTotal.isNotEmpty) ...[
                      if (pitcher.stat.isNotEmpty) const SizedBox(width: 2),
                      Text(
                        pitcher.hrTotal,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: statSize,
                          color: Colors.black87,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                );
              }

              return SizedBox(
                width: cellW,
                height: maxH.isFinite ? maxH : null,
                child: ClipRect(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: leadingW + nameBoxW,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final pitcher in pitchers)
                              SizedBox(
                                height: fitRowH,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: badgeWidth,
                                      child: pitcher.mark.isEmpty ? const SizedBox() : _resultBadge(pitcher.mark, nameSize),
                                    ),
                                    const SizedBox(width: 0.5),
                                    ClipRect(
                                      child: SizedBox(
                                        width: nameBoxW,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: _pitcherNameBox(
                                            name: pitcher.name,
                                            colorsRaw: pitcher.colors,
                                            baseSize: nameSize,
                                            minSize: _minPlayerNameSize,
                                            alignLeft: true,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (statsViewportW > 0) ...[
                        if (gapW > 0) SizedBox(width: gapW),
                        SizedBox(
                          width: statsViewportW,
                          height: maxH.isFinite ? maxH : fitRowH * pitchers.length,
                          child: ClipRect(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              primary: false,
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final pitcher in pitchers)
                                    SizedBox(
                                      height: fitRowH,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: statLine(pitcher),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
    );
  }

  Widget _resultBadge(String mark, double fontSize) {
    final isHr = mark == 'HR';
    final color = switch (mark) {
      '勝' => Colors.red,
      '負' => Colors.blue,
      'H' => Colors.green.shade700,
      'HR' => const Color(0xFFFF5FA2),
      _ => Colors.amber.shade700,
    };
    final diameter = (fontSize + 2).clamp(9.0, 16.0);
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(isHr ? diameter * 0.18 : diameter * 0.08),
        child: FittedBox(
          fit: BoxFit.contain,
          child: Text(
            mark,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight.isFinite ? constraints.maxHeight : intrinsicHeight;
      final headerSize = (height * 0.10).clamp(10.0, 14.0);
      final teamSize = (height * 0.11).clamp(11.0, 16.0);
      final stateSize = (height * 0.09).clamp(9.0, 12.0);
      final scoreSize = (height * 0.13).clamp(12.0, 18.0);
      final detailSize = (height * 0.07).clamp(_minPlayerNameSize, 10.0);
      final labelSize = (height * 0.10).clamp(10.0, 14.0);

      final homeBg = parseColorNameOrNull(_text('color_back_home'));
      final awayBg = parseColorNameOrNull(_text('color_back_away'));
      final homeFg = parseColorNameOrNull(_text('color_font_home')) ?? Colors.black87;
      final awayFg = parseColorNameOrNull(_text('color_font_away')) ?? Colors.black87;
      final homePale = _pale(homeBg);
      final awayPale = _pale(awayBg);

      final scoreHome = _int('score_home');
      final scoreAway = _int('score_away');
      final score = scoreHome >= 0 && scoreAway >= 0 ? '$scoreHome - $scoreAway' : 'vs';
      final state = _text('state');
      final header = [
        if (_text('time_game').isNotEmpty) _text('time_game'),
        if (_text('name_stadium').isNotEmpty) _text('name_stadium'),
      ].join(' ');
      final homePitchers = _players(home: true, pitcher: true);
      final awayPitchers = _players(home: false, pitcher: true);
      final homeBatters = _players(home: true, pitcher: false);
      final awayBatters = _players(home: false, pitcher: false);
      final homeNameColW = _nameColumnWidth([...homePitchers, ...homeBatters], detailSize, context);
      final awayNameColW = _nameColumnWidth([...awayPitchers, ...awayBatters], detailSize, context);
      final pitcherN = math.max(1, math.max(homePitchers.length, awayPitchers.length));
      final batterN = math.max(1, math.max(homeBatters.length, awayBatters.length));
      final started = gameHasStarted(game);
      final midFlex = started ? 1 : 3;

      final content = Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _lineColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _minHeaderH,
              child: _textCell(
                header.isEmpty ? '　' : header,
                size: headerSize,
                minSize: 9,
                color: homeBg ?? const Color(0xFFF4D03F),
                textColor: homeFg,
                weight: FontWeight.bold,
                right: false,
                align: TextAlign.left,
              ),
            ),
            SizedBox(
              height: _minTeamRowH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _textCell(
                      _text('name_team_home'),
                      size: teamSize,
                      minSize: 9,
                      color: homeBg,
                      textColor: homeFg,
                      weight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    flex: midFlex,
                    child: _cell(
                      color: Colors.white,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (state.isNotEmpty)
                              Text(
                                state,
                                style: TextStyle(
                                  fontSize: stateSize,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                            if (state.isNotEmpty) const SizedBox(height: 3),
                            Text(
                              score,
                              style: TextStyle(
                                fontSize: scoreSize,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: _textCell(
                      _text('name_team_away'),
                      size: teamSize,
                      minSize: 9,
                      color: awayBg,
                      textColor: awayFg,
                      weight: FontWeight.bold,
                      right: false,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: pitcherN,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _pitcherCell(
                      homePitchers,
                      color: homePale,
                      size: detailSize,
                      right: true,
                      nameColW: homeNameColW,
                      centerNames: !started,
                    ),
                  ),
                  Expanded(
                    flex: midFlex,
                    child: _textCell(
                      '投手',
                      size: labelSize,
                      minSize: 9,
                      color: _labelColor,
                      textColor: Colors.white,
                      weight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: _pitcherCell(
                      awayPitchers,
                      color: awayPale,
                      size: detailSize,
                      right: false,
                      nameColW: awayNameColW,
                      centerNames: !started,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: batterN,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _pitcherCell(
                      homeBatters,
                      color: homePale,
                      size: detailSize,
                      right: true,
                      bottom: false,
                      nameColW: homeNameColW,
                      centerNames: !started,
                    ),
                  ),
                  Expanded(
                    flex: midFlex,
                    child: _textCell(
                      '打者',
                      size: labelSize,
                      minSize: 9,
                      color: _labelColor,
                      textColor: Colors.white,
                      weight: FontWeight.bold,
                      bottom: false,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: _pitcherCell(
                      awayBatters,
                      color: awayPale,
                      size: detailSize,
                      right: false,
                      bottom: false,
                      nameColW: awayNameColW,
                      centerNames: !started,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      final sized = SizedBox(
        height: height,
        width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
        child: content,
      );

      if (state.contains('回')) {
        return BlinkBorder(
          color: Colors.amber,
          radius: 4,
          width: 3,
          duration: const Duration(milliseconds: 900),
          baseBgColor: Colors.transparent,
          fillUseColor: false,
          child: sized,
        );
      }
      return sized;
    });
  }
}

class _GameCard extends StatelessWidget {
  final Map<String, dynamic> g;
  const _GameCard(this.g);

  String get _home => g['name_team_home']?.toString() ?? '';
  String get _away => g['name_team_away']?.toString() ?? '';
  String get _stadium => g['name_stadium']?.toString() ?? '';
  String get _time => g['time_game']?.toString() ?? '';
  String get _win => g['name_pitcher_win']?.toString() ?? '';
  String get _lose => g['name_pitcher_lose']?.toString() ?? '';
  String get _save => g['name_pitcher_save']?.toString() ?? '';
  String get _pHome => g['name_pitcher_home']?.toString() ?? '';
  String get _pAway => g['name_pitcher_away']?.toString() ?? '';
  String get _cPitchHome => g['colors_pitcher_home']?.toString() ?? '';
  String get _cPitchAway => g['colors_pitcher_away']?.toString() ?? '';
  String get _sHome => g['score_home']?.toString() ?? '';
  String get _sAway => g['score_away']?.toString() ?? '';
  String get _stateTxt => g['state']?.toString() ?? '';

  int get _idTeamHome => int.tryParse('${g['id_team_home']}') ?? -1;
  int get _idTeamAway => int.tryParse('${g['id_team_away']}') ?? -1;
  int? get _idTeamPitchWin => g['id_team_pitcher_win'] == null ? null : int.tryParse('${g['id_team_pitcher_win']}');
  int? get _idTeamPitchLose => g['id_team_pitcher_lose'] == null ? null : int.tryParse('${g['id_team_pitcher_lose']}');
  int? get _idTeamPitchSave => g['id_team_pitcher_save'] == null ? null : int.tryParse('${g['id_team_pitcher_save']}');

  int _parseScore(String s) => int.tryParse(s.trim()) ?? -1;

  bool get _showScore {
    final h = _parseScore(_sHome);
    final a = _parseScore(_sAway);
    if (h < 0 || a < 0) return false; // どちらかが -1 なら非表示
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight.isFinite ? c.maxHeight : 120.0;
      final vPad = (h * 0.04).clamp(2.0, 8.0);
      final gap = (h * 0.03).clamp(2.0, 8.0);
      final baseSmall = (h * 0.10).clamp(9.0, 13.0);
      final baseMid = (h * 0.12).clamp(10.0, 15.0);
      final baseBig = (h * 0.14).clamp(11.0, 16.0);

      // チーム名セル用の色（試合JSONから）
      Color? _parseColor(String? name) {
        final n = (name ?? '').trim().toLowerCase();
        if (n.isEmpty) return null;
        const m = {
          'red': 0xFFF44336,
          'orange': 0xFFFF9800,
          'yellow': 0xFFFFEB3B,
          'green': 0xFF4CAF50,
          'lightgreen': 0xFF8BC34A,
          'blue': 0xFF0000FF,
          'royalblue': 0xFF4169E1,
          'mediumblue': 0xFF0000CD,
          'midnightblue': 0xFF191970,
          'darkblue': 0xFF00008B,
          'dodgerblue': 0xFF1E90FF,
          'navy': 0xFF001F3F,
          'crimson': 0xFFDC143C,
          'gold': 0xFFFFD700,
          'lime': 0xFFCDDC39,
          'gray': 0xFF9E9E9E,
          'grey': 0xFF9E9E9E,
          'black': 0xFF000000,
          'white': 0xFFFFFFFF,
        };
        final v = m[n];
        return v == null ? null : Color(v);
      }

      final Color? homeNameBg = _parseColor(g['color_back_home']?.toString());
      final Color? awayNameBg = _parseColor(g['color_back_away']?.toString());
      final Color? homeNameFg = _parseColor(g['color_font_home']?.toString());
      final Color? awayNameFg = _parseColor(g['color_font_away']?.toString());

      // チーム名チップの最小高さ（文字数が多くても高さを維持）
      final double nameChipH = (baseMid + 6).clamp(18.0, 24.0);

      // チーム名セルの横幅（カード幅の約2/5）
      final double teamNameW = (c.maxWidth.isFinite ? c.maxWidth : 300.0) * 6.0;

      // カード背景: ホーム/アウェイ色で二分割グラデーション
      Color? _teamColor(String? name) {
        final n = (name ?? '').trim().toLowerCase();
        if (n.isEmpty) return null;
        const m = {
          'red': 0xFFF44336,
          'orange': 0xFFFF9800,
          'yellow': 0xFFFFEB3B,
          'green': 0xFF4CAF50,
          'lightgreen': 0xFF8BC34A,
          'blue': 0xFF0000FF,
          'royalblue': 0xFF4169E1,
          'mediumblue': 0xFF0000CD,
          'midnightblue': 0xFF191970,
          'darkblue': 0xFF00008B,
          'dodgerblue': 0xFF1E90FF,
          'navy': 0xFF001F3F,
          'crimson': 0xFFDC143C,
          'gold': 0xFFFFD700,
          'lime': 0xFFCDDC39,
          'gray': 0xFF9E9E9E,
          'grey': 0xFF9E9E9E,
          'black': 0xFF000000,
          'white': 0xFFFFFFFF,
        };
        final v = m[n];
        return v == null ? null : Color(v);
      }

      final Color? homeBg = _teamColor(g['color_back_home']?.toString());
      final Color? awayBg = _teamColor(g['color_back_away']?.toString());
      // チーム名エリアまでは各色でべた塗り、その先からグラデーション
      final double cardW = c.maxWidth.isFinite ? c.maxWidth : 300.0;
      final double teamNameFracW = cardW * 2.0 / 5.0; // 既存チップ幅相当
      final double frac = (teamNameFracW / cardW).clamp(0.05, 0.45);
      const double eps = 0.04; // 適度なブレンド幅
      final double fracSolid = (frac - 0.02).clamp(0.03, 0.45); // ベタ領域を少しだけ短く

      final BoxDecoration? cardDecoration = (homeBg != null && awayBg != null)
          ? (() {
              // 10段階の緩やかなグラデーション（左右対称）
              const int steps = 10; // 左右それぞれの段数
              const double epsSolid = 0.01; // べた領域の終端を明示
              final List<Color> gColors = [];
              final List<double> gStops = [];

              // 左: 0.0 〜 frac はホーム色をべた塗り
              gColors.add(homeBg.withOpacity(1));
              gStops.add(0.0);
              gColors.add(homeBg.withOpacity(1));
              gStops.add((fracSolid - epsSolid).clamp(0.0, 0.49));

              // 左: frac → 0.5 まで徐々に透明へ
              for (int i = 1; i <= steps; i++) {
                final double t = i / steps; // 0→1
                final double pos = fracSolid + (0.5 - fracSolid) * t; // 左ベタ終端→中央
                final double opacity = (1.0 - t); // 1→0 線形
                gColors.add(homeBg.withOpacity(opacity));
                gStops.add(pos.clamp(0.0, 0.5));
              }

              // 中央透明
              gColors.add(Colors.transparent);
              gStops.add(0.5);
              gColors.add(Colors.transparent);
              gStops.add(0.5);

              // 右: 0.5 → (1-frac) で徐々に色を濃く
              for (int i = 1; i <= steps; i++) {
                final double t = i / steps; // 0→1
                final double pos = 0.5 + (0.5 - fracSolid) * t; // 0.5→(1-fracSolid)
                final double opacity = t; // 中央から外側へ行くほど濃く
                gColors.add(awayBg.withOpacity(opacity));
                gStops.add(pos.clamp(0.5, 1.0));
              }

              // 右: (1-frac) 〜 1.0 はアウェイ色をべた塗り
              gColors.add(awayBg.withOpacity(1));
              gStops.add((1.0 - fracSolid + epsSolid).clamp(0.51, 1.0));
              gColors.add(awayBg.withOpacity(1));
              gStops.add(1.0);

              return BoxDecoration(
                gradient: LinearGradient(
                  colors: gColors,
                  stops: gStops,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(6),
              );
            })()
          : (homeBg != null || awayBg != null)
              ? (() {
                  final base = (homeBg ?? awayBg)!;
                  const int steps = 10;
                  const double epsSolid = 0.01;
                  final List<Color> gColors = [];
                  final List<double> gStops = [];

                  // 左べた
                  gColors.add(base.withOpacity(1));
                  gStops.add(0.0);
                  gColors.add(base.withOpacity(1));
                  gStops.add((fracSolid - epsSolid).clamp(0.0, 0.49));

                  // 左→中央
                  for (int i = 1; i <= steps; i++) {
                    final double t = i / steps;
                    final double pos = fracSolid + (0.5 - fracSolid) * t;
                    final double opacity = (1.0 - t);
                    gColors.add(base.withOpacity(opacity));
                    gStops.add(pos.clamp(0.0, 0.5));
                  }

                  // 中央透明
                  gColors.add(Colors.transparent);
                  gStops.add(0.5);
                  gColors.add(Colors.transparent);
                  gStops.add(1.0);

                  return BoxDecoration(
                    gradient: LinearGradient(
                      colors: gColors,
                      stops: gStops,
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  );
                })()
              : null;

      // 球場名の表示幅はホーム側のベタ塗り領域（cardW * fracSolid）に合わせる
      final double stadiumW = (cardW * (fracSolid - 0.01)).clamp(40.0, cardW);

      // 先発投手の下のスペースの 11 分の 5 を 1 行の高さに
      final double nameChipH2 = (baseMid + 6).clamp(18.0, 24.0);
      final double _belowPitcherSpace = nameChipH2; // 近似: 同等の高さを確保
      final double _rowH = (_belowPitcherSpace * 5.0 / 11.0).clamp(14.0, 28.0);
      final double badgeD = (_rowH * 0.92).clamp(12.0, 24.0);
      final double rowFont = (_rowH * 0.52).clamp(9.0, 16.0);

      // 勝敗・S用の丸バッジ（中央表示）: 行フォントに合わせる
      Widget _badge(String label, Color bg, double d) {
        return Container(
          width: d,
          height: d,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: Colors.white, fontSize: rowFont)),
        );
      }

      final bool inProgress = _stateTxt.contains('回');
      final inner = Container(
        decoration: cardDecoration,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 上段: 球場（左上：ホーム色）／ 時刻（右上：アウェイ色）
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: stadiumW,
                    child: Container(
                      margin: const EdgeInsets.only(left: 2, top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: homeNameBg,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: OneLineShrinkText(
                        _stadium,
                        baseSize: baseSmall,
                        minSize: 7,
                        color: homeNameFg ?? Colors.black87,
                        align: TextAlign.left,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: awayNameBg,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: OneLineShrinkText(
                          _time.isNotEmpty ? _time : (_showScore ? '試合終了' : ''),
                          baseSize: baseSmall,
                          minSize: 7,
                          weight: FontWeight.bold,
                          color: awayNameFg ?? Colors.black87,
                          align: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),

              // 中段: ホーム / スコアorvs / ビジター
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                              width: teamNameW,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: null,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                constraints: BoxConstraints(minHeight: nameChipH2),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                alignment: Alignment.center,
                                width: double.infinity,
                                child: OneLineShrinkText(_home, baseSize: baseMid, minSize: 8, weight: FontWeight.w600, color: homeNameFg ?? Colors.black87, align: TextAlign.center),
                              )),
                          if (_pHome.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: gap * 0.3),
                              child: _pitcherNameBox(
                                name: _pHome,
                                colorsRaw: _cPitchHome,
                                baseSize: baseSmall,
                                alignLeft: true,
                                overrideTextColor: _cPitchHome.trim().isEmpty ? (homeNameFg ?? Colors.black87) : null,
                                overrideWeight: _cPitchHome.trim().isEmpty ? FontWeight.w600 : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_stateTxt.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: OneLineShrinkText(
                              _stateTxt,
                              baseSize: baseSmall,
                              minSize: 7,
                              color: Colors.black,
                              shadows: [Shadow(color: Colors.white.withOpacity(0.85), blurRadius: 2, offset: Offset(0, 1))],
                              align: TextAlign.center,
                            ),
                          ),
                        Center(
                          child: OneLineShrinkText(
                            _showScore ? '$_sHome  -  $_sAway' : 'vs',
                            baseSize: baseBig,
                            minSize: 9,
                            weight: FontWeight.bold,
                            color: Colors.black,
                            shadows: [Shadow(color: Colors.white.withOpacity(0.85), blurRadius: 2, offset: Offset(0, 1))],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                              width: teamNameW,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: null,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                constraints: BoxConstraints(minHeight: nameChipH2),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                alignment: Alignment.center,
                                width: double.infinity,
                                child: OneLineShrinkText(_away, baseSize: baseMid, minSize: 8, weight: FontWeight.w600, color: awayNameFg ?? Colors.black87, align: TextAlign.center),
                              )),
                          if (_pAway.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: gap * 0.3),
                              child: _pitcherNameBox(
                                name: _pAway,
                                colorsRaw: _cPitchAway,
                                baseSize: baseSmall,
                                alignLeft: false,
                                overrideTextColor: _cPitchAway.trim().isEmpty ? (awayNameFg ?? Colors.black87) : null,
                                overrideWeight: _cPitchAway.trim().isEmpty ? FontWeight.w600 : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: gap),

              // 下段: 勝敗S投手（各サイドの先発投手行の下に表示）
              if (_win.isNotEmpty || _lose.isNotEmpty || _save.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左側（ホーム）
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_win.isNotEmpty && _idTeamPitchWin == _idTeamHome)
                            SizedBox(
                              height: _rowH,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _badge('勝', Colors.red, badgeD),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: OneLineShrinkText(_win, baseSize: 15, minSize: 15, color: homeNameFg ?? Colors.black87, align: TextAlign.left),
                                  ),
                                ],
                              ),
                            ),
                          if (_lose.isNotEmpty && _idTeamPitchLose == _idTeamHome)
                            SizedBox(
                              height: _rowH,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _badge('負', Colors.blue, badgeD),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: OneLineShrinkText(_lose, baseSize: 15, minSize: 15, color: homeNameFg ?? Colors.black87, align: TextAlign.left),
                                  ),
                                ],
                              ),
                            ),
                          if (_save.isNotEmpty && _idTeamPitchSave == _idTeamHome)
                            SizedBox(
                              height: _rowH,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _badge('S', Colors.amber, badgeD),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: OneLineShrinkText(_save, baseSize: 15, minSize: 7, color: homeNameFg ?? Colors.black87, align: TextAlign.left),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 中央スペーサ（スコア列の幅ぶん）
                    SizedBox(width: 72),
                    // 右側（ビジター）
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_win.isNotEmpty && _idTeamPitchWin == _idTeamAway)
                            SizedBox(
                              height: _rowH,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _badge('勝', Colors.red, badgeD),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: OneLineShrinkText(_win, baseSize: baseSmall + 2, minSize: 7, color: awayNameFg ?? Colors.black87, align: TextAlign.right),
                                  ),
                                ],
                              ),
                            ),
                          if (_lose.isNotEmpty && _idTeamPitchLose == _idTeamAway)
                            SizedBox(
                              height: _rowH,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _badge('負', Colors.blue, badgeD),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: OneLineShrinkText(_lose, baseSize: baseSmall + 2, minSize: 7, color: awayNameFg ?? Colors.black87, align: TextAlign.right),
                                  ),
                                ],
                              ),
                            ),
                          if (_save.isNotEmpty && _idTeamPitchSave == _idTeamAway)
                            SizedBox(
                              height: _rowH,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _badge('S', Colors.amber, badgeD),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: OneLineShrinkText(_save, baseSize: baseSmall + 2, minSize: 7, color: awayNameFg ?? Colors.black87, align: TextAlign.right),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );

      final card = Card(
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: inProgress
            ? BlinkBorder(
                color: Colors.amber,
                radius: 6,
                width: 4,
                duration: const Duration(milliseconds: 900),
                baseBgColor: Colors.transparent,
                fillUseColor: false,
                child: inner,
              )
            : inner,
      );
      return card;
    });
  }
}

// 先発投手名の背景色を colors_user 形式で適用（/red/blue/ → グラデ）
Widget _pitcherNameBox({
  required String name,
  required String colorsRaw,
  required double baseSize,
  required bool alignLeft,
  double minSize = 9,
  Color? overrideTextColor,
  FontWeight? overrideWeight,
}) {
  return _PitcherNameBox(
    name: name,
    colorsRaw: colorsRaw,
    baseSize: baseSize,
    minSize: minSize,
    alignLeft: alignLeft,
    overrideTextColor: overrideTextColor,
    overrideWeight: overrideWeight,
  );
}

class _PitcherNameBox extends StatefulWidget {
  final String name;
  final String colorsRaw;
  final double baseSize;
  final double minSize;
  final bool alignLeft;
  final Color? overrideTextColor;
  final FontWeight? overrideWeight;

  const _PitcherNameBox({
    super.key,
    required this.name,
    required this.colorsRaw,
    required this.baseSize,
    required this.minSize,
    required this.alignLeft,
    this.overrideTextColor,
    this.overrideWeight,
  });

  @override
  State<_PitcherNameBox> createState() => _PitcherNameBoxState();
}

class _PitcherNameBoxState extends State<_PitcherNameBox> with SingleTickerProviderStateMixin {
  BoxDecoration? deco;
  Color? firstBlinkColor;
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  Color? _colorFrom(String? name) => parseColorNameOrNull(name);

  @override
  void initState() {
    super.initState();
    // 解析: 背景装飾と点滅カラー
    final parts = widget.colorsRaw.split('/').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      final cols = <Color>[];
      for (final p in parts) {
        final c = _colorFrom(p);
        if (c != null) {
          cols.add(c);
          firstBlinkColor ??= c;
        }
      }
      if (cols.isNotEmpty) {
        if (cols.length == 1) {
          deco = BoxDecoration(color: cols.first, borderRadius: BorderRadius.circular(4));
        } else {
          final List<Color> gColors = [];
          final List<double> gStops = [];
          if (cols.length == 2) {
            gColors.addAll([cols[0], cols[0], cols[1], cols[1]]);
            gStops.addAll([0.0, 0.46, 0.54, 1.0]);
          } else {
            const double eps = 0.04;
            gColors.add(cols.first);
            gStops.add(0.0);
            for (int i = 0; i < cols.length - 1; i++) {
              final double pos = (i + 1) / (cols.length - 1);
              final double left = (pos - eps).clamp(0.0, 1.0);
              final double right = (pos + eps).clamp(0.0, 1.0);
              gColors.add(cols[i]);
              gStops.add(left);
              gColors.add(cols[i + 1]);
              gStops.add(right);
            }
            gColors.add(cols.last);
            gStops.add(1.0);
          }
          deco = BoxDecoration(
            gradient: LinearGradient(
              colors: gColors,
              stops: gStops,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(4),
          );
        }
      }
    }

    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasColor = deco != null;
    final textColor = hasColor ? Colors.white : (widget.overrideTextColor ?? Colors.black87);
    final weight = widget.overrideWeight ?? (hasColor ? FontWeight.bold : FontWeight.normal);

    final alignment = widget.alignLeft ? Alignment.centerLeft : Alignment.center;
    return Align(
      alignment: alignment,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: deco,
        child: Stack(
          alignment: alignment,
          clipBehavior: Clip.hardEdge,
          children: [
            if (firstBlinkColor != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _t,
                    builder: (context, _) {
                      final alpha = (0.12 + 0.23 * _t.value).clamp(0.0, 1.0);
                      return ColoredBox(
                        color: firstBlinkColor!.withValues(alpha: alpha),
                      );
                    },
                  ),
                ),
              ),
            Text(
              widget.name.isNotEmpty ? widget.name : '—',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                fontSize: widget.baseSize < widget.minSize ? widget.minSize : widget.baseSize,
                fontWeight: weight,
                color: textColor,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
