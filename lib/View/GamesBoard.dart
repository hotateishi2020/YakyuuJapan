import 'package:flutter/material.dart';
import '../tools/color_parse.dart';
import '../tools/date_format.dart';
import 'Text.dart';
import 'Border.dart';

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
  static const int _todayPage = 10000;

  late final PageController _controller;
  late DateTime _baseDate;
  int _page = _todayPage;

  @override
  void initState() {
    super.initState();
    _baseDate = DateTime.tryParse(widget.initialDate ?? '') ?? DateTime.now();
    _baseDate = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DateTime _dateForPage(int page) => _baseDate.add(Duration(days: page - _todayPage));

  String _jaDate(DateTime date) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return '${date.year}年${date.month.toString().padLeft(2, '0')}月'
        '${date.day.toString().padLeft(2, '0')}日'
        '(${weekdays[date.weekday - 1]})';
  }

  String _dayLabel(int page) {
    final offset = page - _todayPage;
    if (offset == -1) return '昨日';
    if (offset == 0) return '今日';
    if (offset == 1) return '明日';
    if (offset < 0) return '${-offset}日前';
    return '$offset日後';
  }

  Future<void> _showPage(int page) async {
    if (_page == page || !_controller.hasClients) return;
    await _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _dateButton(String label, int offset) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showPage(_page + offset),
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
    final selectedDate = _dateForPage(_page);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
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
                    onTap: () => _showPage(_todayPage),
                    child: Center(
                      child: OneLineShrinkText(
                        '${_dayLabel(_page)}  ${_jaDate(selectedDate)}',
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
        ),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, page) {
              return GamesBoardYahooStyle(
                games: widget.games,
                dateFilter: DateFormatUtil.ymd(_dateForPage(page)),
                horizontal: widget.horizontal,
              );
            },
          ),
        ),
      ],
    );
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

  @override
  Widget build(BuildContext context) {
    final src = (dateFilter == null || dateFilter!.isEmpty) ? games : games.where((g) => (g['date_game']?.toString() ?? '') == dateFilter).toList();

    if (horizontal) {
      if (src.isEmpty) {
        return const SizedBox(
          height: 40,
          child: Center(child: Text('試合はありません', style: TextStyle(fontSize: 12))),
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < src.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(child: _TableGameCard(src[i])),
          ],
        ],
      );
    }

    final bySec = <String, List<Map<String, dynamic>>>{};
    for (final g in src) {
      final sec = _sectionOf(g);
      bySec.putIfAbsent(sec, () => []).add(g);
    }

    if (bySec.isEmpty) {
      return const Center(child: Text('試合はありません', style: TextStyle(fontSize: 12)));
    }

    return LayoutBuilder(builder: (context, c) {
      final bySecKeys = bySec.keys.toSet();
      final order = ['セ・リーグ', 'パ・リーグ'].where((k) => bySecKeys.contains(k)).toList();

      Widget threeRows(List<Map<String, dynamic>> list) {
        final g0 = list.isNotEmpty ? list[0] : null;
        final g1 = list.length > 1 ? list[1] : null;
        final g2 = list.length > 2 ? list[2] : null;

        Widget slot(Map<String, dynamic>? g) {
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
  final Map<String, dynamic> game;

  const _TableGameCard(this.game);

  static const _lineColor = Color(0xFF333333);
  static const _labelColor = Color(0xFF5A5A5A);

  String _text(String key) => game[key]?.toString() ?? '';
  int _int(String key) => int.tryParse('${game[key]}') ?? -1;

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

  List<({String name, String colors, String mark})> _pitchers(bool home) {
    final starter = _text(home ? 'name_pitcher_home' : 'name_pitcher_away');
    final colors = _text(home ? 'colors_pitcher_home' : 'colors_pitcher_away');
    final teamId = _int(home ? 'id_team_home' : 'id_team_away');
    final result = <({String name, String colors, String mark})>[];

    void add(String name, String playerColors, String mark) {
      if (name.trim().isEmpty) return;
      final index = result.indexWhere((pitcher) => pitcher.name == name);
      if (index < 0) {
        result.add((name: name, colors: playerColors, mark: mark));
        return;
      }
      final current = result[index];
      result[index] = (
        name: current.name,
        colors: current.colors.isNotEmpty ? current.colors : playerColors,
        mark: current.mark.isNotEmpty ? current.mark : mark,
      );
    }

    add(starter, colors, '');
    if (_int('id_team_pitcher_win') == teamId) {
      add(_text('name_pitcher_win'), '', '勝');
    }
    if (_int('id_team_pitcher_lose') == teamId) {
      add(_text('name_pitcher_lose'), '', '負');
    }
    if (_int('id_team_pitcher_save') == teamId) {
      add(_text('name_pitcher_save'), '', 'S');
    }
    return result;
  }

  Widget _cell({
    required Widget child,
    Color? color,
    bool right = true,
    bool bottom = true,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
  }) {
    return Container(
      clipBehavior: Clip.hardEdge,
      alignment: Alignment.center,
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
  }) {
    return _cell(
      color: color,
      right: right,
      bottom: bottom,
      child: OneLineShrinkText(
        text,
        baseSize: size,
        minSize: 7,
        color: textColor ?? Colors.black87,
        weight: weight,
        align: align,
      ),
    );
  }

  Widget _pitcherCell(
    List<({String name, String colors, String mark})> pitchers, {
    required Color color,
    required double size,
    required bool right,
  }) {
    return _cell(
      color: color,
      right: right,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: pitchers.isEmpty
          ? const SizedBox.expand()
          : LayoutBuilder(builder: (context, constraints) {
              final hasResultMark = pitchers.any((pitcher) => pitcher.mark.isNotEmpty);
              final badgeWidth = hasResultMark ? (size + 2).clamp(9.0, 16.0) : 0.0;
              final gap = hasResultMark ? 0.5 : 0.0;

              double nameWidth(String name, bool highlighted) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: name,
                    style: TextStyle(
                      fontSize: size,
                      fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                )..layout();
                return painter.width + 4;
              }

              final availableNameWidth = (constraints.maxWidth - badgeWidth - gap).clamp(1.0, double.infinity);
              final measuredWidths = pitchers.map((pitcher) => nameWidth(pitcher.name, pitcher.colors.isNotEmpty)).toList();
              final widestName = measuredWidths.reduce((current, width) => current > width ? current : width);
              final nameColumnWidth = widestName.clamp(1.0, availableNameWidth);
              final groupWidth = badgeWidth + gap + nameColumnWidth;

              return Column(
                children: [
                  for (int i = 0; i < pitchers.length; i++)
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          width: groupWidth,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (hasResultMark) ...[
                                SizedBox(
                                  width: badgeWidth,
                                  child: pitchers[i].mark.isEmpty ? const SizedBox() : _resultBadge(pitchers[i].mark, size),
                                ),
                                SizedBox(width: gap),
                              ],
                              Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: measuredWidths[i].clamp(1.0, nameColumnWidth),
                                  child: _pitcherNameBox(
                                    name: pitchers[i].name,
                                    colorsRaw: pitchers[i].colors,
                                    baseSize: size,
                                    alignLeft: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }),
    );
  }

  Widget _resultBadge(String mark, double fontSize) {
    final color = switch (mark) {
      '勝' => Colors.red,
      '負' => Colors.blue,
      _ => Colors.amber.shade700,
    };
    final diameter = (fontSize + 2).clamp(9.0, 16.0);
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          mark,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 140.0;
      final headerSize = (height * 0.10).clamp(8.0, 14.0);
      final teamSize = (height * 0.11).clamp(9.0, 16.0);
      final stateSize = (height * 0.09).clamp(7.0, 12.0);
      final scoreSize = (height * 0.13).clamp(10.0, 18.0);
      final detailSize = (height * 0.09).clamp(8.0, 13.0);
      final labelSize = (height * 0.10).clamp(8.0, 14.0);

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
            Expanded(
              flex: 2,
              child: _textCell(
                header.isEmpty ? '　' : header,
                size: headerSize,
                color: homeBg ?? const Color(0xFFF4D03F),
                textColor: homeFg,
                weight: FontWeight.bold,
                right: false,
                align: TextAlign.left,
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _textCell(
                      _text('name_team_home'),
                      size: teamSize,
                      color: homeBg,
                      textColor: homeFg,
                      weight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    flex: 3,
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
              flex: 3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _pitcherCell(
                      _pitchers(true),
                      color: homePale,
                      size: detailSize,
                      right: true,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _textCell(
                      '投手',
                      size: labelSize,
                      color: _labelColor,
                      textColor: Colors.white,
                      weight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: _pitcherCell(
                      _pitchers(false),
                      color: awayPale,
                      size: detailSize,
                      right: false,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _textCell(
                      _text('name_homerun_home'),
                      size: detailSize,
                      color: homePale,
                      bottom: false,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _textCell(
                      '打者',
                      size: labelSize,
                      color: _labelColor,
                      textColor: Colors.white,
                      weight: FontWeight.bold,
                      bottom: false,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: _textCell(
                      _text('name_homerun_away'),
                      size: detailSize,
                      color: awayPale,
                      right: false,
                      bottom: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      if (state.contains('回')) {
        return BlinkBorder(
          color: Colors.amber,
          radius: 4,
          width: 3,
          duration: const Duration(milliseconds: 900),
          baseBgColor: Colors.transparent,
          fillUseColor: false,
          child: content,
        );
      }
      return content;
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
  Color? overrideTextColor,
  FontWeight? overrideWeight,
}) {
  return _PitcherNameBox(
    name: name,
    colorsRaw: colorsRaw,
    baseSize: baseSize,
    alignLeft: alignLeft,
    overrideTextColor: overrideTextColor,
    overrideWeight: overrideWeight,
  );
}

class _PitcherNameBox extends StatefulWidget {
  final String name;
  final String colorsRaw;
  final double baseSize;
  final bool alignLeft;
  final Color? overrideTextColor;
  final FontWeight? overrideWeight;

  const _PitcherNameBox({
    super.key,
    required this.name,
    required this.colorsRaw,
    required this.baseSize,
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

    return LayoutBuilder(builder: (context, constraints) {
      return Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth.isFinite ? constraints.maxWidth : 120,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: deco,
              child: Stack(
                alignment: Alignment.center,
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
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.name.isNotEmpty ? widget.name : '—',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: widget.baseSize,
                        fontWeight: weight,
                        color: textColor,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
