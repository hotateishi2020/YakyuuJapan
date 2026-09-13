import 'package:flutter/material.dart';
import '../config/app_design.dart';
import '../tools/date_format.dart';
import 'Text.dart';
import 'BlinkBg.dart';
import 'GamesBoard.dart';

class SeasonTableBlock extends StatelessWidget {
  final List<Map<String, dynamic>> standings;
  final List<Map<String, dynamic>> stats;
  final List<Map<String, dynamic>> games;
  final int? onlyLeagueId; // 1: セ, 2: パ, null: 両方
  final String? gamesDateFilter; // "YYYY-MM-DD"（nullなら今日）
  final bool portraitLayout;
  final bool portraitShowPersonal;

  const SeasonTableBlock({
    super.key,
    required this.standings,
    required this.stats,
    this.games = const [],
    this.onlyLeagueId,
    this.gamesDateFilter,
    this.portraitLayout = false,
    this.portraitShowPersonal = false,
  });

  // JSONの色名をColorに変換（不明ならnull）
  Color? _parseColorName(String? name) {
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
    if (v == null) return null;
    return Color(v);
  }

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

  List<Map<String, dynamic>> _statsOf(int leagueId, {required bool pitcher}) => stats.where((e) => ((e['league_name'] ?? '').toString() == (leagueId == 1 ? 'セ・リーグ' : 'パ・リーグ')) && (e['flg_pitcher'] == pitcher)).toList();

  // タイトル→選手名(なければ ?)
  String _playerOf(List<Map<String, dynamic>> rows, String title) {
    final r = rows.firstWhere(
      (e) => (e['title'] ?? '').toString() == title,
      orElse: () => const {},
    );
    final name = (r.isNotEmpty ? (r['name_player'] ?? '') : '').toString();
    return name.isEmpty ? '?' : name;
  }

  Widget _sectionHeader(String label, Color color) {
    return Container(
      height: 26,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  // 簡易セル
  Widget _cell(String text, {Color? bg, FontWeight? weight, Color? fg, double? h}) {
    return Container(
      height: h,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: OneLineShrinkText(text, baseSize: 10, minSize: 1, weight: weight, color: fg),
    );
  }

  // 最小幅付きセル（数値列用）
  Widget _minCell(String text, double min, {Color? bg, Color? fg, FontWeight? weight}) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: min),
      child: _cell(text, bg: bg, fg: fg, weight: weight),
    );
  }

  // 順位テーブル（上:順位行、下:スタッツ要約）
  Widget _leagueTable(int leagueId) {
    final cur = _standingsOf(leagueId);
    final Color leagueColor = leagueId == 1 ? const Color(0xFF0B8F3A) : const Color(0xFF4DB5E8);
    // リーグ見出しは非表示

    // 打撃/投手タイトル（画像に近い簡易版）: stats_player の形に合わせて抽出
    const battingTitles = ['打率', '本塁打', '打点', '盗塁', '出塁率'];
    const pitchingTitles = ['防御率', '最多勝', '奪三振', 'HP', 'セーブ'];
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

    // タイトル列ごとに、クリック/ホバーで全ランキングを展開できるカラム
    Widget _statsColumn({
      required String title,
      required double width,
      required Color headerBg,
      required List<Map<String, dynamic>> rows,
      required Widget Function(Map<String, dynamic>) buildRow,
    }) {
      return _StatsColumn(
        title: title,
        width: width,
        headerBg: headerBg,
        rows: rows,
        buildRow: buildRow,
      );
    }

    Widget _bar(String label, Color color, {double h = 24, Color fg = Colors.white}) {
      return Container(
        height: h,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: color),
        child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
      );
    }

    Widget _personalStatsSheet(int leagueId, List<Map<String, dynamic>> bat, List<Map<String, dynamic>> pit, double parentWidth) {
      final leagueLabel = leagueId == 1 ? 'セ・リーグ' : 'パ・リーグ';

      List<TableRow> _rankRows(List<String> cols, List<Map<String, dynamic>> src) {
        String _normalizeTitle(String t) => t == 'ホールド' ? 'HP' : t;
        String _nameBy(String title, int rank) {
          final e = src.firstWhere((m) => (m['title']?.toString() ?? '') == _normalizeTitle(title) && (int.tryParse('${m['int_rank']}') ?? -1) == rank, orElse: () => const {});
          return (e.isNotEmpty ? (e['name_player'] ?? '') : '').toString();
        }

        final rows = <TableRow>[];
        for (int r = 1; r <= 5; r++) {
          rows.add(TableRow(children: [
            _gridCell('$r', bg: Colors.white, fg: Colors.black),
            for (final t in cols) _gridCell(_nameBy(t, r)),
          ]));
        }
        return rows;
      }

      // 1位の選手名（無ければ空文字）
      String _pick(List<Map<String, dynamic>> src, String title) {
        final v = src.firstWhere((e) => (e['title'] ?? '') == title, orElse: () => const {});
        return (v.isNotEmpty ? (v['name_player'] ?? '') : '').toString();
      }

      String _normalizeTitle(String t) => t == 'ホールド' ? 'HP' : t;
      String _nameBy(List<Map<String, dynamic>> src, String title, int rank) {
        final e = src.firstWhere((m) => (m['title']?.toString() ?? '') == _normalizeTitle(title) && (int.tryParse('${m['int_rank']}') ?? -1) == rank, orElse: () => const {});
        return (e.isNotEmpty ? (e['name_player'] ?? '') : '').toString();
      }

      final battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率'];
      final pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ'];

      // 個人成績セル: ランク/チーム/選手/数値 を1セル内に表示
      // rank は「表示行のインデックス(1..5)」。SQL順を維持したリストの rank 番目を表示する。
      Widget _entryCell(List<Map<String, dynamic>> src, String title, int rank) {
        final list = src.where((m) => (m['title']?.toString() ?? '') == _normalizeTitle(title)).toList();
        final idx = (rank - 1).clamp(0, list.isNotEmpty ? list.length - 1 : 0);
        final Map<String, dynamic> e = list.isNotEmpty && list.length >= rank ? list[idx] : const {};

        final rankText = (e.isNotEmpty ? (e['int_rank']?.toString() ?? '') : '').toString();
        final team = (e.isNotEmpty ? (e['name_team'] ?? '') : '').toString();
        final name = (e.isNotEmpty ? (e['player_name'] ?? e['name_player'] ?? '') : '').toString();
        final stat = _num(e.isNotEmpty ? e['stats'] : null);

        // colors_user: "/red/blue/" のように / 区切りで色名が入る
        // 1色なら単色背景、2色以上なら左→右のグラデーション
        BoxDecoration? _nameBgDecoration() {
          final raw = (e.isNotEmpty ? (e['colors_user'] ?? '') : '').toString();
          if (raw.isEmpty) return null;
          final parts = raw.split('/').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
          if (parts.isEmpty) return null;
          final cols = <Color>[];
          for (final p in parts) {
            final c = _parseColorName(p);
            if (c != null) cols.add(c);
          }
          if (cols.isEmpty) return null;
          if (cols.length == 1) {
            return BoxDecoration(
              color: cols.first,
              borderRadius: BorderRadius.circular(4),
            );
          }
          return BoxDecoration(
            gradient: LinearGradient(
              colors: cols,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(4),
          );
        }

        return SizedBox(
          width: parentWidth * 0.2,
          child: Container(
            height: 20,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26, width: 1),
            ),
            // padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(children: [
              Expanded(
                  flex: STATS_PLAYER_RATIO_CELL_BLOCK_W[0],
                  child: Center(
                    child: () {
                      if (rankText.trim() == '1') {
                        return const FittedBox(
                          fit: BoxFit.contain,
                          child: Text('👑',
                              style: TextStyle(
                                fontSize: 25,
                                height: 1.0,
                              )),
                        );
                      } else if (rankText.trim() == '1000') {
                        return const FittedBox(
                          fit: BoxFit.contain,
                          child: Text('-',
                              style: TextStyle(
                                fontSize: 25,
                                height: 1.0,
                              )),
                        );
                      }
                      return OneLineShrinkText(rankText.isNotEmpty ? rankText : '—', baseSize: 15, minSize: 1, fast: true);
                    }(),
                  )),
              Expanded(
                  flex: STATS_PLAYER_RATIO_CELL_BLOCK_W[1],
                  child: Container(
                    decoration: BoxDecoration(
                      color: _parseColorName(e['color_back']),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    alignment: Alignment.center,
                    child: OneLineShrinkText(team, baseSize: 12, minSize: 1, fast: true, color: _parseColorName(e['color_font'])),
                  )),
              Expanded(
                  flex: STATS_PLAYER_RATIO_CELL_BLOCK_W[2],
                  child: Container(
                    decoration: (() {
                      final d = _nameBgDecoration();
                      return d;
                    })(),
                    alignment: Alignment.center,
                    child: (() {
                      final hasBg = _nameBgDecoration() != null;
                      return OneLineShrinkText(name, baseSize: 12, minSize: 1, fast: true, color: hasBg ? Colors.white : null, weight: hasBg ? FontWeight.bold : null);
                    })(),
                  )),
              Expanded(flex: STATS_PLAYER_RATIO_CELL_BLOCK_W[3], child: OneLineShrinkText(stat, baseSize: 12, minSize: 1, fast: true)),
            ]),
          ),
        );
      }

      // 1行分（与えられた行データからそのまま描画）
      const double rowH = 16.0;
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
        final rankRaw = e['int_rank'];
        final rankText = (rankRaw?.toString() ?? '').toString();
        // JSON経由で 1000.0 になる場合もあるので数値で判定
        final int rankNum = () {
          if (rankRaw is int) return rankRaw;
          if (rankRaw is num) return rankRaw.round();
          return num.tryParse(rankText.trim())?.round() ?? -1;
        }();
        final team = (e['name_team'] ?? '').toString();
        final name = (e['player_name'] ?? e['name_player'] ?? '').toString();
        final stat = _num(e['stats']);
        final bool isNoRank = rankNum == 1000;
        const Color noRankBg = Color(0xFFC8C8C8); // 規定未到達などのグレー

        BoxDecoration? _nameBgDecorationFromRow() {
          final raw = (e['colors_user'] ?? '').toString();
          if (raw.isEmpty) return null;
          final parts = raw.split('/').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
          if (parts.isEmpty) return null;
          final cols = <Color>[];
          for (final p in parts) {
            final c = _parseColorName(p);
            if (c != null) cols.add(c);
          }
          if (cols.isEmpty) return null;
          if (cols.length == 1) {
            return BoxDecoration(
              color: cols.first,
              borderRadius: BorderRadius.circular(4),
            );
          }
          return BoxDecoration(
            gradient: LinearGradient(
              colors: cols,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(4),
          );
        }

        Widget _cellBg({required Widget child, Color? overlay}) {
          return ColoredBox(
            color: isNoRank ? (overlay ?? noRankBg) : (overlay ?? Colors.transparent),
            child: child,
          );
        }

        return SizedBox(
          width: parentWidth * 0.2,
          height: rowH,
          child: ColoredBox(
            color: isNoRank ? noRankBg : Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black26, width: 1),
              ),
              child: Row(children: [
                Expanded(
                    flex: 2,
                    child: _cellBg(
                      child: Center(
                        child: () {
                          final isOne = rankNum == 1;
                          if (isOne) {
                            return const FittedBox(
                              fit: BoxFit.contain,
                              child: Text('👑',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.0,
                                  )),
                            );
                          } else if (isNoRank) {
                            return const FittedBox(
                              fit: BoxFit.contain,
                              child: Text('-',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.0,
                                  )),
                            );
                          }
                          return OneLineShrinkText(rankText.isNotEmpty ? '$rankNum' : '—', baseSize: 10, minSize: 1, fast: true);
                        }(),
                      ),
                    )),
                Expanded(
                    flex: 2,
                    child: _cellBg(
                      // 球団カラーは従来どおり（グレー行の上に載せる）
                      overlay: _parseColorName(e['color_back']) ?? (isNoRank ? noRankBg : Colors.transparent),
                      child: Container(
                        alignment: Alignment.center,
                        child: OneLineShrinkText(team, baseSize: 10, minSize: 1, fast: true, color: _parseColorName(e['color_font'])),
                      ),
                    )),
                Expanded(
                    flex: 10,
                    child: (() {
                      final BoxDecoration? d = _nameBgDecorationFromRow();
                      final bool hasBg = d != null;
                      final bool isToday = e['flg_today'] == true;
                      final Widget txt = OneLineShrinkText(name, baseSize: 10, minSize: 1, fast: true, color: hasBg ? Colors.white : null, weight: hasBg ? FontWeight.bold : null);
                      // 予想者カラーがある場合はそれを優先。ないときだけグレー
                      if (isToday) {
                        return BlinkBg(
                          base: d ?? BoxDecoration(borderRadius: BorderRadius.circular(4), color: isNoRank ? noRankBg : null),
                          color: const Color(0xFFFFF176),
                          radius: 4,
                          duration: const Duration(milliseconds: 1000),
                          child: Align(alignment: Alignment.center, child: txt),
                        );
                      }
                      if (hasBg) {
                        return Container(
                          decoration: d,
                          alignment: Alignment.center,
                          child: txt,
                        );
                      }
                      return _cellBg(
                        child: Align(alignment: Alignment.center, child: txt),
                      );
                    })()),
                Expanded(
                  flex: 4,
                  child: _cellBg(
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
                headerBg: const Color(0xFFE57373),
                matchTitle: (m, t) => (m['title']?.toString() ?? '') == t,
              ),
            ),
          if (pit.isNotEmpty)
            Expanded(
              child: _statsTitleColumns(
                cols: pitchingCols,
                src: pit,
                headerBg: const Color(0xFF64B5F6),
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
          final double pinnedBaseW = _wChar2 * 3; // 順位・立・江
          final double parentW = lb.maxWidth.isFinite ? lb.maxWidth : (pinnedBaseW + minNameW + scrollColsW);
          final double availForName = parentW - pinnedBaseW - scrollColsW;
          final double wName = availForName > minNameW ? availForName : minNameW;
          final bool needsHScroll = (pinnedBaseW + wName + scrollColsW) > parentW + 0.5;
          const double gridBodyH = 20.0;

          Widget pinnedHeader() {
            return Row(children: [
              SizedBox(width: _wChar2, child: _gridCell('順位', h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white, weight: FontWeight.bold)),
              SizedBox(width: _wChar2, child: _gridCell('立', h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white, weight: FontWeight.bold)),
              SizedBox(width: _wChar2, child: _gridCell('江', h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white, weight: FontWeight.bold)),
              SizedBox(width: wName, child: _gridCell('チーム', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: Colors.white)),
            ]);
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

          Widget pinnedBodyRow(int i) {
            final row = cur[i];
            final int rk = int.tryParse('${row['int_rank']}') ?? (i + 1);
            final Color? teamBg = _parseColorName(row['color_back']);
            final Color? teamFg = _parseColorName(row['color_font']);
            final Color? teamBgTateishi = _parseColorName(row['team_color_back_tateishi']);
            final Color? teamFgTateishi = _parseColorName(row['team_color_font_tateishi']);
            final Color? teamBgEjima = _parseColorName(row['team_color_back_ejima']);
            final Color? teamFgEjima = _parseColorName(row['team_color_font_ejima']);
            return Row(children: [
              SizedBox(width: _wChar2, child: _gridCell('$rk', h: gridBodyH, bg: leagueColor, fg: Colors.white, weight: FontWeight.bold)),
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
              SizedBox(width: wName, child: _gridCell(_num(row['name_team']), h: gridBodyH, bg: teamBg, fg: teamFg)),
            ]);
          }

          Widget scrollBodyRow(int i) {
            final row = cur[i];
            final Color? teamBg = _parseColorName(row['color_back']);
            final Color paleBg = teamBg != null ? _paleOf(teamBg, 0.72) : Colors.white;

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
            final bool closeBehind = gameBehindVal != null && gameBehindVal <= 1.0;
            final bool hasMagic = gbText.toUpperCase().contains('M');
            final Color? fgGb = closeBehind ? Colors.blue : null;
            final FontWeight? wtGb = (closeBehind || hasMagic) ? FontWeight.bold : null;

            return Row(children: [
              SizedBox(width: _wChar2, child: _gridCell(_num(row['int_game']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar1, child: _gridCell(_num(row['int_win']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar1, child: _gridCell(_num(row['int_lose']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar1, child: _gridCell(_num(row['int_draw']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar2, child: _gridCell(_num(row['game_behind']), h: gridBodyH, bg: paleBg, fg: fgGb, weight: wtGb)),
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

          final Widget pinnedCol = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              pinnedHeader(),
              for (int i = 0; i < cur.length; i++) pinnedBodyRow(i),
            ],
          );

          final Widget scrollCol = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              scrollHeader(),
              for (int i = 0; i < cur.length; i++) scrollBodyRow(i),
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

      final Widget gamesHeader = Container(
        height: ALL_HEADER_H * 1.0,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: leagueColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: OneLineShrinkText(
          '今日  ${DateFormatUtil.jaDateWithOffset(0)}',
          baseSize: 13.0,
          minSize: 5.0,
          weight: FontWeight.bold,
          align: TextAlign.center,
          color: Colors.white,
          verticalPadding: 2,
          fast: true,
        ),
      );

      final Widget gamesBoard = GamesBoardYahooStyle(
        games: games,
        dateFilter: gamesDateFilter ?? DateFormatUtil.ymdWithOffset(0),
        horizontal: true,
      );

      // 縦型: 内容の高さだけ（余白を作らない）。横型: 残り領域いっぱいに広げる
      const double portraitGamesBodyH = 130.0;
      final Widget gamesBlock = portraitLayout
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                gamesHeader,
                SizedBox(height: portraitGamesBodyH, width: double.infinity, child: gamesBoard),
              ],
            )
          : Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  gamesHeader,
                  Expanded(child: gamesBoard),
                ],
              ),
            );

      final Widget teamPanel = Column(
        mainAxisSize: portraitLayout ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          standingsTable(),
          const SizedBox(height: 6),
          gamesBlock,
        ],
      );

      final Widget personalPanel = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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

      if (portraitLayout) {
        return portraitShowPersonal ? personalPanel : teamPanel;
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
    // 縦型のチーム成績は内容高さ。個人成績・横型は親に合わせて広げる
    if (portraitLayout && !portraitShowPersonal) {
      return content;
    }
    return SizedBox.expand(child: content);
  }
}

// 汎用: 個人成績1タイトルのカラム。ヘッダーをクリック/ホバーで全件展開。
class _StatsColumn extends StatefulWidget {
  final String title;
  final double width;
  final Color headerBg;
  final List<Map<String, dynamic>> rows; // 既に並び替え済み推奨
  final Widget Function(Map<String, dynamic>) buildRow;

  const _StatsColumn({
    super.key,
    required this.title,
    required this.width,
    required this.headerBg,
    required this.rows,
    required this.buildRow,
  });

  @override
  State<_StatsColumn> createState() => _StatsColumnState();
}

class _StatsColumnState extends State<_StatsColumn> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    const double _rowH = 13.5;
    const double _headerH = 20.0;
    final double _baseH = _headerH + _rowH * 5;

    final header = Container(
      height: _headerH,
      width: widget.width,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: widget.headerBg),
      child: OneLineShrinkText(widget.title, baseSize: 12, minSize: 6),
    );

    final firstFive = widget.rows.length <= 5 ? widget.rows : widget.rows.sublist(0, 5);
    final extras = widget.rows.length <= 5 ? const <Map<String, dynamic>>[] : widget.rows.sublist(5);

    // Revert to simple scroll version behavior at column level (no overlay expansion here).
    return SizedBox(
      width: widget.width,
      child: Column(
        children: [
          header,
          for (final r in firstFive) widget.buildRow(r),
        ],
      ),
    );
  }
}
