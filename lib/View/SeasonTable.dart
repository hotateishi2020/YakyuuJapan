import 'package:flutter/material.dart';
import '../config/app_design.dart';
import '../config/org_config.dart';
import '../tools/color_parse.dart';
import 'Text.dart';
import 'BlinkBg.dart';
import 'Border.dart';
import 'GamesBoard.dart';

enum SeasonPane { combined, games, standings }

class SeasonTableBlock extends StatelessWidget {
  final List<Map<String, dynamic>> standings;
  final List<Map<String, dynamic>> stats;
  final List<Map<String, dynamic>> games;
  final int? onlyLeagueId; // 団体内リーグ ID。null: 両方
  final String? gamesDateFilter; // "YYYY-MM-DD"（nullなら今日）
  final bool portraitLayout;
  final SeasonPane pane;
  final OrgConfig org;

  const SeasonTableBlock({
    super.key,
    required this.standings,
    required this.stats,
    this.games = const [],
    this.onlyLeagueId,
    this.gamesDateFilter,
    this.portraitLayout = false,
    this.pane = SeasonPane.combined,
    this.org = OrgConfig.npb,
  });

  Color? _parseColorName(String? name) => parseColorNameOrNull(name);

  // 元の色を白とブレンドして淡くする
  Color _paleOf(Color base, [double t = 0.88]) {
    t = t.clamp(0.0, 1.0);
    final r = (base.value >> 16) & 0xFF;
    final g = (base.value >> 8) & 0xFF;
    final b = base.value & 0xFF;
    final rr = (r + (255 - r) * t).round();
    final gg = (g + (255 - g) * t).round();
    final bb = (b + (255 - b) * t).round();
    return Color(0xFF000000 | (rr << 16) | (gg << 8) | bb);
  }

  // 文字→数値(表示用)
  String _num(dynamic v) => (v == null || '$v'.isEmpty) ? '—' : '$v';

  // リーグ別フィルタ
  List<Map<String, dynamic>> _standingsOf(int leagueId) => standings.where((e) => int.tryParse('${e['id_league']}') == leagueId).toList()..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0).compareTo(int.tryParse('${b['int_rank']}') ?? 0));

  /// MLB は東・中・西地区に分割。NPB はリーグ全体を1ブロック。
  List<({String label, List<Map<String, dynamic>> rows})> _standingSections(int leagueId) {
    final all = _standingsOf(leagueId);
    if (org.kind != OrgKind.mlb) {
      return [(label: '', rows: all)];
    }
    const areas = [
      ('EAST', '東地区'),
      ('CENTER', '中地区'),
      ('WEST', '西地区'),
    ];
    final sections = <({String label, List<Map<String, dynamic>> rows})>[];
    for (final area in areas) {
      final rows = all.where((e) => '${e['code_area'] ?? ''}'.trim().toUpperCase() == area.$1).toList()
        ..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0).compareTo(int.tryParse('${b['int_rank']}') ?? 0));
      if (rows.isNotEmpty) sections.add((label: area.$2, rows: rows));
    }
    if (sections.isEmpty && all.isNotEmpty) {
      return [(label: '', rows: all)];
    }
    return sections;
  }

  Widget _sectionHeader(String label, Color color) {
    return Container(
      height: 26,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  // 順位テーブル（上:順位行、下:スタッツ要約）
  Widget _leagueTable(int leagueId) {
    final Color leagueColor = org.leagueColor(leagueId);
    // リーグ見出しは非表示

    // 打撃/投手タイトル（画像に近い簡易版）: stats_player の形に合わせて抽出
    const battingTitles = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '盗塁成功率', '長打率', 'OPS'];
    const pitchingTitles = ['防御率', '最多勝', '奪三振', 'HP', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'QS率'];
    final leagueStats = stats.where((e) => int.tryParse('${e['id_league']}') == leagueId).toList();
    final bat = leagueStats.where((e) => battingTitles.contains(((e['title'] ?? '').toString()))).toList();
    final pit = leagueStats.where((e) => pitchingTitles.contains(((e['title'] ?? '').toString()))).toList();

    // 文字幅の目安（12pxフォントで約14px/字）
    // 文字幅の目安（12pxフォントで約14px/字）
    const double _kChar = 14.0;
    const double _wChar2 = _kChar * 2; // 2文字ぶん
    const double _wChar1 = _kChar * 1.5; // 1文字ぶん
    const double _wChar6 = _kChar * 6; // 6文字ぶん（順位表で使用中）
    const double _wChar3 = _kChar * 3; // 3文字ぶん（順位表で使用中）

    Widget _gridCell(String text, {double h = 15, Color? bg, Color? fg, FontWeight? weight, TextAlign align = TextAlign.center}) {
      return Container(
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: Colors.black26, width: 1),
        ),
        child: OneLineShrinkText(text, baseSize: 12, minSize: 6, weight: weight, color: fg, align: align),
      );
    }

    Widget _personalStatsSheet(int leagueId, List<Map<String, dynamic>> bat, List<Map<String, dynamic>> pit, double parentWidth) {
      String _normalizeTitle(String t) => t == 'ホールド' ? 'HP' : t;

      final battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '盗塁成功率', '長打率', 'OPS'];
      final pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'QS率'];

      // 1行分（与えられた行データからそのまま描画）
      const double rowH = 20.8;
      Widget _emptyEntryCell({double? height}) {
        return SizedBox(
          width: parentWidth * 0.2,
          height: height ?? rowH,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26, width: 1),
            ),
          ),
        );
      }

      Widget _entryCellFromRow(Map<String, dynamic> e) {
        return PlayerStatCell(
          row: e,
          width: parentWidth * 0.2,
          showJapanFlag: org.kind == OrgKind.mlb,
        );
      }

      Widget _statsTitleColumns({
        required List<String> cols,
        required List<Map<String, dynamic>> src,
        required Color headerBg,
        required bool Function(Map<String, dynamic> m, String title) matchTitle,
      }) {
        if (src.isEmpty) return const SizedBox.shrink();
        return LayoutBuilder(builder: (context, constraints) {
          final double h = constraints.maxHeight.isFinite ? constraints.maxHeight : 200.0;
          const double headerH = 20.0;
          return SizedBox(
            height: h,
            width: constraints.maxWidth.isFinite ? constraints.maxWidth : parentWidth,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final t in cols)
                    SizedBox(
                      width: parentWidth * 0.2,
                      height: h,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _gridCell(t, bg: headerBg, fg: Colors.white, weight: FontWeight.bold, h: headerH),
                          Expanded(
                            child: LayoutBuilder(builder: (context, bodyConstraints) {
                              // SQLの ORDER BY（成績値順など）を維持するため、ここでは再ソートしない
                              final rows = src.where((m) => matchTitle(m, t)).toList();
                              final double bodyH = bodyConstraints.maxHeight.isFinite ? bodyConstraints.maxHeight : 0;
                              final int visibleSlots = bodyH > 0 ? (bodyH / rowH).floor().clamp(0, 1000) : 0;

                              // 選手が多いときはタイトルごとに独立スクロール
                              if (rows.length > visibleSlots && visibleSlots > 0) {
                                return SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      for (final e in rows) _entryCellFromRow(e),
                                    ],
                                  ),
                                );
                              }

                              // 不足分は空セルで埋め、端数は最後の空セルで伸ばして空白をなくす
                              final int emptyFixed = (visibleSlots - rows.length).clamp(0, 1000);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final e in rows) _entryCellFromRow(e),
                                  for (var i = 0; i < emptyFixed; i++) _emptyEntryCell(),
                                  Expanded(
                                    child: _emptyEntryCell(height: double.infinity),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        });
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bat.isNotEmpty)
            Expanded(
              child: _statsTitleColumns(
                cols: battingCols,
                src: bat,
                headerBg: const Color(0xFFDC143C),
                matchTitle: (m, t) => (m['title']?.toString() ?? '') == t,
              ),
            ),
          if (pit.isNotEmpty)
            Expanded(
              child: _statsTitleColumns(
                cols: pitchingCols,
                src: pit,
                headerBg: const Color(0xFF1E88E5),
                matchTitle: (m, t) => (m['title']?.toString() ?? '') == t || (_normalizeTitle((m['title'] ?? '').toString()) == _normalizeTitle(t)),
              ),
            ),
        ],
      );
    }

    // 左: チーム順位 / 右: 個人成績（打撃・投手）
    return LayoutBuilder(builder: (context, c) {
      Widget standingsTable() {
        return LayoutBuilder(builder: (context, lb) {
          final sections = _standingSections(leagueId);
          final bool showPredictCols = sections.any((section) => section.rows.any((row) {
                final tateishi = '${row['team_name_tateishi'] ?? ''}'.trim();
                final ejima = '${row['team_name_ejima'] ?? ''}'.trim();
                return (tateishi.isNotEmpty && tateishi != '—') || (ejima.isNotEmpty && ejima != '—');
              }));
          final double minNameW = _wChar6;
          // スクロール側（試合〜防御率）の固定幅合計
          final double scrollColsW = _wChar2 + // 試合
              _wChar1 * 3 + // 勝・負・分
              _wChar2 + // 勝差
              _wChar3 + // 勝率
              _wChar2 + // 打率
              _wChar3 + // 本塁打
              _wChar2 + // 打点
              _wChar2 + // 盗塁
              _wChar3 + // 失策率
              _wChar2 * 3; // 防御率3列
          final double pinnedBaseW = showPredictCols ? _wChar2 * 3 : _wChar2; // 順位(+立・江)
          final double parentW = lb.maxWidth.isFinite ? lb.maxWidth : (pinnedBaseW + minNameW + scrollColsW);
          final double availForName = parentW - pinnedBaseW - scrollColsW;
          final double wName = availForName > minNameW ? availForName : minNameW;
          final bool needsHScroll = (pinnedBaseW + wName + scrollColsW) > parentW + 0.5;
          const double gridBodyH = 20.0;

          Widget pinnedHeader() {
            return Row(children: [
              SizedBox(width: _wChar2, child: _gridCell('順位', h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white, weight: FontWeight.bold)),
              if (showPredictCols) ...[
                SizedBox(width: _wChar2, child: _gridCell('立', h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white, weight: FontWeight.bold)),
                SizedBox(width: _wChar2, child: _gridCell('江', h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white, weight: FontWeight.bold)),
              ],
              SizedBox(width: wName, child: _gridCell('チーム', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
            ]);
          }

          Widget divisionHeader(String label, double width) {
            return SizedBox(
              width: width,
              child: _gridCell(label, h: gridBodyH, bg: const Color(0xFF37474F), fg: Colors.white, weight: FontWeight.bold, align: TextAlign.left),
            );
          }

          Widget scrollHeader() {
            return Row(children: [
              SizedBox(width: _wChar2, child: _gridCell('試合', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(width: _wChar1, child: _gridCell('勝', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(width: _wChar1, child: _gridCell('負', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(width: _wChar1, child: _gridCell('分', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(width: _wChar2, child: _gridCell('勝差', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(width: _wChar3, child: _gridCell('勝率', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(width: _wChar2, child: _gridCell('打率', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(width: _wChar3, child: _gridCell('本塁打', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(width: _wChar2, child: _gridCell('打点', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(width: _wChar2, child: _gridCell('盗塁', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(width: _wChar3, child: _gridCell('失策率', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
              SizedBox(
                width: _wChar2 * 3,
                child: Column(children: [
                  _gridCell('防御率', weight: FontWeight.bold, h: ALL_HEADER_H / 2, bg: leagueColor, fg: Colors.white),
                  Row(children: [
                    SizedBox(width: _wChar2, child: _gridCell('総合', weight: FontWeight.bold, h: ALL_HEADER_H / 2, bg: leagueColor, fg: Colors.white, align: TextAlign.center)),
                    SizedBox(width: _wChar2, child: _gridCell('先発', weight: FontWeight.bold, h: ALL_HEADER_H / 2, bg: leagueColor, fg: Colors.white, align: TextAlign.center)),
                    SizedBox(width: _wChar2, child: _gridCell('救援', weight: FontWeight.bold, h: ALL_HEADER_H / 2, bg: leagueColor, fg: Colors.white, align: TextAlign.center)),
                  ]),
                ]),
              ),
            ]);
          }

          Widget pinnedBodyRow(Map<String, dynamic> row, int divisionRank) {
            final int rk = org.kind == OrgKind.mlb
                ? divisionRank
                : (int.tryParse('${row['int_rank']}') ?? divisionRank);
            final Color? teamBg = _parseColorName(row['color_back']);
            final Color? teamFg = _parseColorName(row['color_font']);
            final Color? teamBgTateishi = _parseColorName(row['team_color_back_tateishi']);
            final Color? teamFgTateishi = _parseColorName(row['team_color_font_tateishi']);
            final Color? teamBgEjima = _parseColorName(row['team_color_back_ejima']);
            final Color? teamFgEjima = _parseColorName(row['team_color_font_ejima']);
            return Row(children: [
              SizedBox(width: _wChar2, child: _gridCell('$rk', h: gridBodyH, bg: leagueColor, fg: Colors.white, weight: FontWeight.bold)),
              if (showPredictCols) ...[
                SizedBox(
                  width: _wChar2,
                  child: _gridCell(
                    _num(row['team_name_tateishi']),
                    h: gridBodyH,
                    bg: row['flg_atari_tateishi'] == true ? Colors.yellowAccent : teamBgTateishi,
                    fg: row['flg_atari_tateishi'] == true ? Colors.blueAccent : teamFgTateishi,
                    weight: row['flg_atari_tateishi'] == true ? FontWeight.bold : null,
                  ),
                ),
                SizedBox(
                  width: _wChar2,
                  child: _gridCell(
                    _num(row['team_name_ejima']),
                    h: gridBodyH,
                    bg: row['flg_atari_ejima'] == true ? Colors.yellowAccent : teamBgEjima,
                    fg: row['flg_atari_ejima'] == true ? Colors.redAccent : teamFgEjima,
                    weight: row['flg_atari_ejima'] == true ? FontWeight.bold : null,
                  ),
                ),
              ],
              SizedBox(width: wName, child: _gridCell(_num(row['name_team']), h: gridBodyH, bg: teamBg, fg: teamFg, weight: FontWeight.bold)),
            ]);
          }

          Widget scrollBodyRow(Map<String, dynamic> row) {
            final Color? teamBg = _parseColorName(row['color_back']);
            final lotte = '${row['name_team'] ?? ''}'.contains('ロッテ');
            final Color paleBg = teamBg != null ? _paleOf(teamBg, lotte ? 0.9 : 0.72) : Colors.white;

            Color? topColor(bool cond) => cond ? const Color(0xFF32CD32) : null;
            Color? worstColor(bool cond) => cond ? Colors.red : null;

            final bool topBat = row['flg_top_num_avg_batting'] == true;
            final bool worstBat = row['flg_worst_num_avg_batting'] == true;
            final Color? fgBat = topColor(topBat) ?? worstColor(worstBat);
            final FontWeight? wtBat = (topBat || worstBat) ? FontWeight.bold : null;

            final bool topHr = row['flg_top_int_homerun'] == true;
            final bool worstHr = row['flg_worst_int_homerun'] == true;
            final Color? fgHr = topColor(topHr) ?? worstColor(worstHr);
            final FontWeight? wtHr = (topHr || worstHr) ? FontWeight.bold : null;

            final bool topRbi = row['flg_top_int_rbi'] == true;
            final bool worstRbi = row['flg_worst_int_rbi'] == true;
            final Color? fgRbi = topColor(topRbi) ?? worstColor(worstRbi);
            final FontWeight? wtRbi = (topRbi || worstRbi) ? FontWeight.bold : null;

            final bool topSb = row['flg_top_int_sh'] == true;
            final bool worstSb = row['flg_worst_int_sh'] == true;
            final Color? fgSb = topColor(topSb) ?? worstColor(worstSb);
            final FontWeight? wtSb = (topSb || worstSb) ? FontWeight.bold : null;

            final bool topFld = row['flg_top_num_avg_fielding'] == true;
            final bool worstFld = row['flg_worst_num_avg_fielding'] == true;
            final Color? fgFld = topColor(topFld) ?? worstColor(worstFld);
            final FontWeight? wtFld = (topFld || worstFld) ? FontWeight.bold : null;

            final bool topEraT = row['flg_top_num_era_total'] == true;
            final bool worstEraT = row['flg_worst_num_era_total'] == true;
            final Color? fgEraT = topColor(topEraT) ?? worstColor(worstEraT);
            final FontWeight? wtEraT = (topEraT || worstEraT) ? FontWeight.bold : null;

            final bool topEraS = row['flg_top_num_era_starter'] == true;
            final bool worstEraS = row['flg_worst_num_era_starter'] == true;
            final Color? fgEraS = topColor(topEraS) ?? worstColor(worstEraS);
            final FontWeight? wtEraS = (topEraS || worstEraS) ? FontWeight.bold : null;

            final bool topEraR = row['flg_top_num_era_relief'] == true;
            final bool worstEraR = row['flg_worst_num_era_relief'] == true;
            final Color? fgEraR = topColor(topEraR) ?? worstColor(worstEraR);
            final FontWeight? wtEraR = (topEraR || worstEraR) ? FontWeight.bold : null;

            final String gbText = '${row['game_behind']}'.trim();
            final double? gameBehindVal = double.tryParse(gbText);
            final bool closeBehind = gameBehindVal != null && gameBehindVal <= 2.0;
            final bool hasMagic = gbText.toUpperCase().contains('M');
            final bool isChampion = gbText == '優勝';
            final Color? fgGb = isChampion
                ? Colors.yellow
                : (closeBehind ? const Color.fromARGB(255, 255, 68, 196) : null);
            final Color bgGb = isChampion ? Colors.red : paleBg;
            final FontWeight? wtGb =
                (closeBehind || hasMagic || isChampion) ? FontWeight.bold : null;

            return Row(children: [
              SizedBox(width: _wChar2, child: _gridCell(_num(row['int_game']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar1, child: _gridCell(_num(row['int_win']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar1, child: _gridCell(_num(row['int_lose']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar1, child: _gridCell(_num(row['int_draw']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar2, child: _gridCell(_num(row['game_behind']), h: gridBodyH, bg: bgGb, fg: fgGb, weight: wtGb)),
              SizedBox(width: _wChar3, child: _gridCell(_num(row['pct_win']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar2, child: _gridCell(_num(row['num_avg_batting']), h: gridBodyH, bg: paleBg, fg: fgBat, weight: wtBat)),
              SizedBox(width: _wChar3, child: _gridCell(_num(row['int_homerun']), h: gridBodyH, bg: paleBg, fg: fgHr, weight: wtHr)),
              SizedBox(width: _wChar2, child: _gridCell(_num(row['int_rbi']), h: gridBodyH, bg: paleBg, fg: fgRbi, weight: wtRbi)),
              SizedBox(width: _wChar2, child: _gridCell(_num(row['int_sh']), h: gridBodyH, bg: paleBg, fg: fgSb, weight: wtSb)),
              SizedBox(width: _wChar3, child: _gridCell(_num(row['num_avg_fielding']), h: gridBodyH, bg: paleBg, fg: fgFld, weight: wtFld)),
              SizedBox(width: _wChar2, child: _gridCell(_num(row['num_era_total']), h: gridBodyH, bg: paleBg, fg: fgEraT, weight: wtEraT)),
              SizedBox(width: _wChar2, child: _gridCell(_num(row['num_era_starter']), h: gridBodyH, bg: paleBg, fg: fgEraS, weight: wtEraS)),
              SizedBox(width: _wChar2, child: _gridCell(_num(row['num_era_relief']), h: gridBodyH, bg: paleBg, fg: fgEraR, weight: wtEraR)),
            ]);
          }

          // MLB は地区ごとに「順位〜防御率」ヘッダーを繰り返す。NPB は先頭1回だけ。
          final bool headerPerSection = org.kind == OrgKind.mlb && sections.any((s) => s.label.isNotEmpty);

          final Widget pinnedCol = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!headerPerSection) pinnedHeader(),
              for (final section in sections) ...[
                if (section.label.isNotEmpty) divisionHeader(section.label, pinnedBaseW + wName),
                if (headerPerSection) pinnedHeader(),
                for (var i = 0; i < section.rows.length; i++) pinnedBodyRow(section.rows[i], i + 1),
              ],
            ],
          );

          final Widget scrollCol = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!headerPerSection) scrollHeader(),
              for (final section in sections) ...[
                if (section.label.isNotEmpty) divisionHeader('', scrollColsW),
                if (headerPerSection) scrollHeader(),
                for (final row in section.rows) scrollBodyRow(row),
              ],
            ],
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: needsHScroll
                    ? BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 3,
                            offset: const Offset(2, 0),
                          ),
                        ],
                      )
                    : const BoxDecoration(),
                child: pinnedCol,
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: scrollCol,
                ),
              ),
            ],
          );
        });
      }

      final Widget gamesSwitcher = GameDateSwitcher(
        games: games,
        playerStats: stats,
        initialDate: gamesDateFilter,
        headerColor: leagueColor,
        horizontal: true,
      );

      // 縦型は試合カードが選手人数で伸びる
      final Widget gamesBlock = portraitLayout
          ? gamesSwitcher
          : Expanded(child: gamesSwitcher);

      final Widget teamPanel = Column(
        mainAxisSize: portraitLayout ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('チーム順位', leagueColor),
          const SizedBox(height: 4),
          standingsTable(),
          const SizedBox(height: 6),
          gamesBlock,
        ],
      );

      final Widget personalPanel = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('個人成績', leagueColor),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(builder: (context, lb) {
              final double centralW = lb.maxWidth.isFinite ? lb.maxWidth : 0;
              return _personalStatsSheet(leagueId, bat, const [], centralW);
            }),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: LayoutBuilder(builder: (context, lb) {
              final double centralW = lb.maxWidth.isFinite ? lb.maxWidth : 0;
              return _personalStatsSheet(leagueId, const [], pit, centralW);
            }),
          ),
        ],
      );

      final leagueName = org.leagueName(leagueId);
      if (pane == SeasonPane.games) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader(leagueName, leagueColor),
            const SizedBox(height: 4),
            gamesBlock,
          ],
        );
      }
      if (pane == SeasonPane.standings) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader(leagueName, leagueColor),
            const SizedBox(height: 4),
            standingsTable(),
          ],
        );
      }

      if (portraitLayout) {
        // 縦スクロール時は、見出しと上位10名が見える高さに抑える。
        // 横型では従来どおり、親から与えられた高さ全体を使用する。
        const double personalSectionHeight = 20.0 + 20.8 * 10;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            gamesBlock,
            const SizedBox(height: 6),
            _sectionHeader('チーム順位', leagueColor),
            const SizedBox(height: 4),
            standingsTable(),
            const SizedBox(height: 6),
            _sectionHeader('個人成績', leagueColor),
            const SizedBox(height: 4),
            SizedBox(
              height: personalSectionHeight,
              child: LayoutBuilder(builder: (context, lb) {
                final width = lb.maxWidth.isFinite ? lb.maxWidth : 0.0;
                return _personalStatsSheet(leagueId, bat, const [], width);
              }),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: personalSectionHeight,
              child: LayoutBuilder(builder: (context, lb) {
                final width = lb.maxWidth.isFinite ? lb.maxWidth : 0.0;
                return _personalStatsSheet(leagueId, const [], pit, width);
              }),
            ),
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: teamPanel),
          const SizedBox(width: 4),
          Expanded(flex: 2, child: personalPanel),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      child: onlyLeagueId == null
          ? Column(
              children: [
                Expanded(child: _leagueTable(1)),
              ],
            )
          : _leagueTable(onlyLeagueId!),
    );
    // 縦型は内容高さ、横型は親に合わせて広げる
    if (portraitLayout) {
      return content;
    }
    return SizedBox.expand(child: content);
  }
}

const double _statRowH = 20.8;

class PlayerStatCell extends StatelessWidget {
  final Map<String, dynamic> row;
  final double? width;
  final bool showRank;
  final bool showJapanFlag;

  const PlayerStatCell({
    super.key,
    required this.row,
    this.width,
    this.showRank = true,
    this.showJapanFlag = false,
  });

  @override
  Widget build(BuildContext context) {
    final rankRaw = row['int_rank'];
    final rankText = '${rankRaw ?? ''}';
    final int rankNum = rankRaw is int
        ? rankRaw
        : rankRaw is num
            ? rankRaw.round()
            : num.tryParse(rankText.trim())?.round() ?? -1;
    final team = '${row['name_team'] ?? ''}';
    final name = '${row['player_name'] ?? row['name_player'] ?? ''}';
    final statRaw = row['stats'];
    final stat = (statRaw == null || '$statRaw'.isEmpty) ? '—' : '$statRaw';
    final isNoRank = rankNum == 1000;
    const noRankBg = Color(0xFFC8C8C8);
    bool isTrue(dynamic value) {
      if (value == true) return true;
      if (value is num) return value != 0;
      final text = '$value'.trim().toLowerCase();
      return text == 'true' || text == 't' || text == '1';
    }

    final isJapan = showJapanFlag && isTrue(row['flg_japan']);
    const japanBg = Color(0xFFF5C6CE); // 薄いクリムゾンレッド
    final countryEmoji = '${row['emoji_country'] ?? ''}'.trim();
    final marks = [
      if (isJapan) (countryEmoji.isNotEmpty ? countryEmoji : '🇯🇵'),
      if (isTrue(row['flg_rookie'])) '🔰',
      if (isTrue(row['flg_career_this_year'])) '✨',
      if (isTrue(row['flg_under21'])) '🌱',
      if (isTrue(row['flg_age35'])) '🍁',
    ];
    final paren = name.indexOf('(');
    final label = paren >= 0 ? name.substring(0, paren) : name;
    final suffix = paren >= 0 ? name.substring(paren) : '';

    BoxDecoration? nameBg() {
      final raw = '${row['colors_user'] ?? ''}';
      final parts = raw.split('/').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
      final cols = [for (final part in parts) if (parseColorNameOrNull(part) != null) parseColorNameOrNull(part)!];
      if (cols.isEmpty) {
        if (isJapan) return BoxDecoration(color: japanBg, borderRadius: BorderRadius.circular(4));
        return null;
      }
      if (cols.length == 1) return BoxDecoration(color: cols.first, borderRadius: BorderRadius.circular(4));
      return BoxDecoration(
        gradient: LinearGradient(colors: cols, begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(4),
      );
    }

    Widget cellBg({required Widget child, Color? overlay}) {
      return ColoredBox(
        color: isNoRank ? (overlay ?? noRankBg) : (overlay ?? Colors.transparent),
        child: child,
      );
    }

    final decoration = nameBg();
    final hasBg = decoration != null;
    final hasPredictColor = '${row['colors_user'] ?? ''}'.split('/').any((s) => s.trim().isNotEmpty);
    final nameColor = hasPredictColor ? Colors.white : (isJapan ? const Color(0xFF8B0000) : null);
    final nameWeight = (hasBg || isJapan) ? FontWeight.bold : null;
    final nameLine = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: OneLineShrinkText(label.isEmpty ? '—' : label, baseSize: 10, minSize: 1, fast: true, color: nameColor, weight: nameWeight, align: TextAlign.center),
        ),
        for (final mark in marks) Text(mark, style: TextStyle(fontSize: 10, height: 1.0, color: nameColor)),
        if (suffix.isNotEmpty)
          Flexible(
            fit: FlexFit.loose,
            child: OneLineShrinkText(suffix, baseSize: 10, minSize: 1, fast: true, color: nameColor, weight: nameWeight, align: TextAlign.center),
          ),
      ],
    );
    final isToday = row['flg_today'] == true || row['flg_today'] == 'true' || row['flg_today'] == 't';
    final Widget nameWidget;
    if (hasBg) {
      // 予想色を常に残し、今日登板は枠だけ点滅させる（黄オーバーレイで赤が消えないようにする）
      final colored = Container(decoration: decoration, alignment: Alignment.center, child: nameLine);
      nameWidget = isToday
          ? BlinkBorder(
              color: const Color(0xFFFF9800),
              radius: 4,
              width: 2,
              duration: const Duration(milliseconds: 700),
              baseBgColor: Colors.transparent,
              fillUseColor: true,
              child: colored,
            )
          : colored;
    } else if (isToday) {
      nameWidget = BlinkBg(
        base: BoxDecoration(borderRadius: BorderRadius.circular(4), color: isNoRank ? noRankBg : null),
        color: const Color(0xFFFFF176),
        radius: 4,
        duration: const Duration(milliseconds: 700),
        child: Align(alignment: Alignment.center, child: nameLine),
      );
    } else {
      nameWidget = cellBg(child: Align(alignment: Alignment.center, child: nameLine));
    }

    return SizedBox(
      width: width,
      height: _statRowH,
      child: ColoredBox(
        color: isNoRank ? noRankBg : (isJapan && !hasPredictColor ? japanBg : Colors.transparent),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black26, width: 1)),
          child: Row(children: [
            if (showRank)
              Expanded(
                flex: 2,
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: rankNum == 1
                        ? const FittedBox(fit: BoxFit.contain, child: Text('👑', style: TextStyle(fontSize: 12, height: 1.0)))
                        : isNoRank
                            ? const FittedBox(
                                fit: BoxFit.contain,
                                child: Text('-', style: TextStyle(fontSize: 12, height: 1.0, color: Colors.white)),
                              )
                            : OneLineShrinkText(
                                rankText.isNotEmpty ? '$rankNum' : '—',
                                baseSize: 10,
                                minSize: 1,
                                fast: true,
                                color: Colors.white,
                              ),
                  ),
                ),
              ),
            Expanded(
              flex: 2,
              child: cellBg(
                overlay: parseColorNameOrNull('${row['color_back'] ?? ''}') ?? (isNoRank ? noRankBg : Colors.transparent),
                child: Align(
                  alignment: Alignment.center,
                  child: OneLineShrinkText(team, baseSize: 10, minSize: 1, fast: true, color: parseColorNameOrNull('${row['color_font'] ?? ''}')),
                ),
              ),
            ),
            Expanded(flex: 10, child: nameWidget),
            Expanded(
              flex: 4,
              child: cellBg(
                child: Align(
                  alignment: Alignment.center,
                  child: OneLineShrinkText(stat, baseSize: 10, minSize: 1, fast: true),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 項目ごとの個人成績。タイトルを縦に並べ、左が第1リーグ、右が第2リーグ。
class BothLeaguePersonalStats extends StatelessWidget {
  final List<Map<String, dynamic>> stats;
  final bool pitcher;
  final OrgConfig org;

  const BothLeaguePersonalStats({
    super.key,
    required this.stats,
    required this.pitcher,
    this.org = OrgConfig.npb,
  });

  static const _pitchingTitles = {'防御率', '最多勝', '奪三振', 'HP', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'QS率'};

  bool _isPitcher(Map<String, dynamic> row) {
    final value = row['flg_pitcher'];
    if (value is bool) return value;
    final text = '$value'.trim().toLowerCase();
    if (text == 'true' || text == 't' || text == '1') return true;
    if (text == 'false' || text == 'f' || text == '0') return false;
    return _pitchingTitles.contains('${row['title'] ?? ''}'.trim());
  }

  @override
  Widget build(BuildContext context) {
    final rows = stats.where((row) => _isPitcher(row) == pitcher).toList();
    final titles = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      final title = '${row['title'] ?? ''}'.trim();
      if (title.isEmpty || !seen.add(title)) continue;
      titles.add(title);
    }
    if (titles.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }

    List<Map<String, dynamic>> side(int leagueId, String title) {
      return rows.where((row) => (int.tryParse('${row['id_league']}') ?? 0) == leagueId && '${row['title'] ?? ''}'.trim() == title).take(10).toList();
    }

    return ListView(
      children: [
        for (final title in titles) ...[
          Container(
            height: 26,
            alignment: Alignment.center,
            color: pitcher ? const Color(0xFF1E88E5) : const Color(0xFFDC143C),
            child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 22,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    color: org.leagues[0].color,
                    child: Text(org.leagues[0].name.replaceAll('・リーグ', ''), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    color: org.leagues[1].color,
                    child: Text(org.leagues[1].name.replaceAll('・リーグ', ''), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          for (var i = 0; i < 10; i++)
            if (i < side(org.leagues[0].id, title).length || i < side(org.leagues[1].id, title).length)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: i < side(org.leagues[0].id, title).length
                        ? PlayerStatCell(
                            row: side(org.leagues[0].id, title)[i],
                            showRank: true,
                            showJapanFlag: org.kind == OrgKind.mlb,
                          )
                        : const SizedBox(height: _statRowH),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: i < side(org.leagues[1].id, title).length
                        ? PlayerStatCell(
                            row: side(org.leagues[1].id, title)[i],
                            showRank: true,
                            showJapanFlag: org.kind == OrgKind.mlb,
                          )
                        : const SizedBox(height: _statRowH),
                  ),
                ],
              ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

