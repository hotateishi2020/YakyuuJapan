import 'package:flutter/material.dart';
import '../config/app_design.dart';
import '../config/org_config.dart';
import '../logic/show_user_predictions.dart';
import '../tools/browser_cookie.dart';
import '../tools/color_parse.dart';
import 'Text.dart';
import 'BlinkBg.dart';
import 'Border.dart';
import 'GamesBoard.dart';

enum SeasonPane { combined, games, standings }

enum PersonalStatsLayout { segment, scroll }

const personalStatsLayoutCookie = 'koko_personal_stats_layout';

/// 個人成績の選手名は姓名の間の空白を入れない。
String compactPersonalStatName(String name) {
  return name.replaceAll(RegExp(r'[\s\u3000]+'), '');
}

String _stealStatsWithRate(String steals, String rate) {
  final count = steals.trim();
  var shown = rate.trim();
  if (shown.isEmpty) return count;
  if (!shown.contains('%') && !shown.contains('％')) shown = '$shown%';
  if (count.contains('（') || count.contains('(')) return count;
  return '$count（$shown）';
}

List<Map<String, dynamic>> _mergeStealSuccessRate(List<Map<String, dynamic>> rows) {
  String playerKey(Map<String, dynamic> row) {
    final id = '${row['id_player'] ?? ''}'.trim();
    if (id.isNotEmpty && id != 'null' && id != '0') return 'id:$id';
    return 'name:${row['player_name'] ?? row['name_player'] ?? ''}';
  }

  final rates = <String, String>{};
  for (final row in rows) {
    if ('${row['title'] ?? ''}'.trim() != '盗塁成功率') continue;
    final value = '${row['stats'] ?? ''}'.trim();
    if (value.isNotEmpty && value != 'null' && value != '—') rates[playerKey(row)] = value;
  }
  return [
    for (final row in rows)
      if ('${row['title'] ?? ''}'.trim() != '盗塁成功率')
        if ('${row['title'] ?? ''}'.trim() == '盗塁' && rates[playerKey(row)]?.isNotEmpty == true)
          {
            ...row,
            'stats': _stealStatsWithRate('${row['stats'] ?? '—'}', rates[playerKey(row)]!),
          }
        else
          row,
  ];
}

PersonalStatsLayout readPersonalStatsLayout() {
  final raw = readBrowserCookie(personalStatsLayoutCookie);
  if (raw == 'scroll') return PersonalStatsLayout.scroll;
  return PersonalStatsLayout.segment;
}

void writePersonalStatsLayout(PersonalStatsLayout layout) {
  writeBrowserCookie(personalStatsLayoutCookie, layout == PersonalStatsLayout.scroll ? 'scroll' : 'segment');
}

/// MLB ワイルドカード表は 9/1〜翌開幕までに出す。過去年は常に出す。
bool showMlbWildcardStandings({int? seasonYear, DateTime? now}) {
  final today = now ?? DateTime.now();
  final year = seasonYear ?? today.year;
  if (year != today.year) return true;
  if (today.month >= 9) return true;
  if (today.month <= 3) return true;
  return false;
}

class SeasonTableBlock extends StatelessWidget {
  final List<Map<String, dynamic>> standings;
  final List<Map<String, dynamic>> stats;
  final List<Map<String, dynamic>> games;
  final int? onlyLeagueId; // 団体内リーグ ID。null: 両方
  final String? gamesDateFilter; // "YYYY-MM-DD"（nullなら今日）
  final bool portraitLayout;
  final SeasonPane pane;
  final OrgConfig org;
  final PersonalStatsLayout personalStatsLayout;
  final ValueChanged<PersonalStatsLayout>? onPersonalStatsLayoutChanged;
  final bool loadingStandings;
  final bool loadingStats;
  final bool loadingGames;
  final int seasonYear;
  final Future<void> Function(DateTime date)? onNeedGameDate;
  final bool Function(DateTime date)? shouldLoadGameDate;
  final String? loadingGameDate;
  final int gameDateOffset;
  final ValueChanged<int>? onGameDateOffsetChanged;

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
    this.personalStatsLayout = PersonalStatsLayout.segment,
    this.onPersonalStatsLayoutChanged,
    this.loadingStandings = false,
    this.loadingStats = false,
    this.loadingGames = false,
    this.seasonYear = 0,
    this.onNeedGameDate,
    this.shouldLoadGameDate,
    this.loadingGameDate,
    this.gameDateOffset = 0,
    this.onGameDateOffsetChanged,
  });

  Widget _sectionLoading({double height = 120}) {
    return SizedBox(
      height: height,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

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

  int get _seasonYear => seasonYear > 0 ? seasonYear : DateTime.now().year;

  bool get _showMlbWildcard => showMlbWildcardStandings(seasonYear: _seasonYear);

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
      final rows = all.where((e) => '${e['code_area'] ?? ''}'.trim().toUpperCase() == area.$1).toList()..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0).compareTo(int.tryParse('${b['int_rank']}') ?? 0));
      if (rows.isNotEmpty) sections.add((label: area.$2, rows: rows));
    }
    if (sections.isNotEmpty) {
      double pct(Map<String, dynamic> row) {
        final wins = int.tryParse('${row['int_win']}') ?? 0;
        final losses = int.tryParse('${row['int_lose']}') ?? 0;
        return wins + losses == 0 ? 0 : wins / (wins + losses);
      }

      final divisionWinners = {
        for (final section in sections)
          if (section.rows.isNotEmpty) int.tryParse('${section.rows.first['id_team']}') ?? 0,
      };
      final wild = [
        for (final row in all)
          if (!divisionWinners.contains(int.tryParse('${row['id_team']}') ?? 0)) Map<String, dynamic>.from(row),
      ]..sort((a, b) {
          final byPct = pct(b).compareTo(pct(a));
          if (byPct != 0) return byPct;
          return (int.tryParse('${b['int_win']}') ?? 0).compareTo(int.tryParse('${a['int_win']}') ?? 0);
        });
      if (wild.isNotEmpty) {
        final leaderWins = int.tryParse('${wild.first['int_win']}') ?? 0;
        final leaderLosses = int.tryParse('${wild.first['int_lose']}') ?? 0;
        for (var i = 0; i < wild.length; i++) {
          final wins = int.tryParse('${wild[i]['int_win']}') ?? 0;
          final losses = int.tryParse('${wild[i]['int_lose']}') ?? 0;
          final behind = ((leaderWins - wins) + (losses - leaderLosses)) / 2;
          wild[i]['int_rank'] = i + 1;
          wild[i]['game_behind'] = i == 0 ? '0' : (behind == behind.roundToDouble() ? '${behind.round()}' : behind.toStringAsFixed(1));
        }
        if (_showMlbWildcard) {
          sections.add((label: 'ワイルドカード順位', rows: wild));
        }
      }
    }
    if (sections.isEmpty && all.isNotEmpty) {
      return [(label: '', rows: all)];
    }
    return sections;
  }

  Widget _sectionHeader(String label, Color color) {
    return Container(
      height: 32,
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
    const battingTitles = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
    const pitchingTitles = ['防御率', '最多勝', '奪三振', 'HP', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'QS率'];
    final leagueStats = stats.where((e) => int.tryParse('${e['id_league']}') == leagueId).toList();
    final bat = _mergeStealSuccessRate(
      leagueStats.where((e) => battingTitles.contains(((e['title'] ?? '').toString())) || '${e['title'] ?? ''}' == '盗塁成功率').toList(),
    );
    final pit = leagueStats.where((e) => pitchingTitles.contains(((e['title'] ?? '').toString()))).toList();

    // 文字幅の目安（12pxフォントで約14px/字）
    // 文字幅の目安（12pxフォントで約14px/字）
    const double _kChar = 14.0;
    const double _wChar2 = _kChar * 2; // 2文字ぶん
    const double _wChar1 = _kChar * 1.5; // 1文字ぶん
    const double _wChar6 = _kChar * 6; // 6文字ぶん（順位表で使用中）
    const double _wChar3 = _kChar * 3; // 3文字ぶん（順位表で使用中）

    bool _isTrue(dynamic value) {
      if (value == true) return true;
      if (value is num) return value != 0;
      final s = '$value'.trim().toLowerCase();
      return s == 'true' || s == 't' || s == '1';
    }

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

    Widget _teamNameCell(String text, {required double h, Color? bg, Color? fg, bool showJapan = false}) {
      return Container(
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: Colors.black26, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: OneLineShrinkText(text, baseSize: 12, minSize: 6, weight: FontWeight.bold, color: fg, align: TextAlign.center),
              ),
              if (showJapan)
                const Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Text('🇯🇵', style: TextStyle(fontSize: 11, height: 1)),
                ),
            ],
          ),
        ),
      );
    }

    Widget _personalStatsSheet(List<Map<String, dynamic>> bat, List<Map<String, dynamic>> pit) {
      // 画素の多い横長画面は、打者上段・投手下段の全スタッツグリッド（元仕様）。
      if (!portraitLayout) {
        return DualBandLeaguePersonalStats(
          batting: bat,
          pitching: pit,
          showJapanFlag: org.kind == OrgKind.mlb,
        );
      }
      return LeaguePersonalStatsHost(
        batting: bat,
        pitching: pit,
        showJapanFlag: org.kind == OrgKind.mlb,
        layout: personalStatsLayout,
        onLayoutChanged: onPersonalStatsLayoutChanged,
      );
    }

    // 左: チーム順位 / 右: 個人成績（打撃・投手）
    return LayoutBuilder(builder: (context, c) {
      Widget standingsTable() {
        return LayoutBuilder(builder: (context, lb) {
          final sections = _standingSections(leagueId);
          final bool showPredictCols = ShowUserPredictions.of(context) &&
              sections.any((section) => section.rows.any((row) {
                    final tateishi = '${row['team_name_tateishi'] ?? ''}'.trim();
                    final ejima = '${row['team_name_ejima'] ?? ''}'.trim();
                    return (tateishi.isNotEmpty && tateishi != '—') || (ejima.isNotEmpty && ejima != '—');
                  }));
          // MLB は「ホワイトソックス」等が入るのでチーム名列を広めに取る。
          final double minNameW = org.kind == OrgKind.mlb ? _kChar * 9 : _wChar6;
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
            final int rk = org.kind == OrgKind.mlb ? divisionRank : (int.tryParse('${row['int_rank']}') ?? divisionRank);
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
              SizedBox(
                width: wName,
                child: _teamNameCell(
                  _num(row['name_team']),
                  h: gridBodyH,
                  bg: teamBg,
                  fg: teamFg,
                  showJapan: org.kind == OrgKind.mlb && _isTrue(row['flg_japan']),
                ),
              ),
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
            final bool isChampion = gbText == '優勝' || gbText.toUpperCase() == 'W';
            final Color? fgGb = isChampion ? Colors.yellow : (closeBehind ? const Color.fromARGB(255, 255, 68, 196) : null);
            final Color bgGb = isChampion ? Colors.red : paleBg;
            final FontWeight? wtGb = (closeBehind || hasMagic || isChampion) ? FontWeight.bold : null;
            final gbDisplay = isChampion && org.kind == OrgKind.mlb ? 'W' : _num(row['game_behind']);

            return Row(children: [
              SizedBox(width: _wChar2, child: _gridCell(_num(row['int_game']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar1, child: _gridCell(_num(row['int_win']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar1, child: _gridCell(_num(row['int_lose']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar1, child: _gridCell(_num(row['int_draw']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: _wChar2, child: _gridCell(gbDisplay, h: gridBodyH, bg: bgGb, fg: fgGb, weight: wtGb)),
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

          Widget divisionBanner(String label) {
            return SizedBox(
              width: double.infinity,
              child: _gridCell(label, h: gridBodyH, bg: const Color(0xFF37474F), fg: Colors.white, weight: FontWeight.bold, align: TextAlign.left),
            );
          }

          Widget sectionTable(({String label, List<Map<String, dynamic>> rows}) section) {
            final Widget pinned = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pinnedHeader(),
                for (var i = 0; i < section.rows.length; i++) pinnedBodyRow(section.rows[i], i + 1),
              ],
            );
            final Widget scroll = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                scrollHeader(),
                for (final row in section.rows) scrollBodyRow(row),
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
                  child: pinned,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: scroll,
                  ),
                ),
              ],
            );
          }

          if (!headerPerSection) {
            return sections.isEmpty ? const SizedBox.shrink() : sectionTable(sections.first);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) SizedBox(height: sections[i].label == 'ワイルドカード順位' ? 20 : 12),
                if (sections[i].label.isNotEmpty) divisionBanner(sections[i].label),
                sectionTable(sections[i]),
              ],
            ],
          );
        });
      }

      final Widget gamesSwitcher = loadingGames
          ? _sectionLoading(height: portraitLayout ? 160 : 220)
          : GameDateSwitcher(
              key: ValueKey('gds-${org.kind.name}-$onlyLeagueId-$gamesDateFilter'),
              games: games,
              playerStats: stats,
              initialDate: gamesDateFilter,
              headerColor: leagueColor,
              horizontal: true,
              onNeedGameDate: onNeedGameDate,
              shouldLoadGameDate: shouldLoadGameDate,
              loadingGameDate: loadingGameDate,
              dateOffset: gameDateOffset,
              onDateOffsetChanged: onGameDateOffsetChanged,
            );

      // 縦型は試合カードが選手人数で伸びる
      final Widget gamesBlock = portraitLayout ? gamesSwitcher : Expanded(child: gamesSwitcher);

      final Widget standingsBody = loadingStandings ? _sectionLoading(height: 140) : standingsTable();
      final Widget personalBody = loadingStats ? _sectionLoading(height: 180) : _personalStatsSheet(bat, pit);

      final Widget teamPanel = Column(
        mainAxisSize: portraitLayout ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('チーム順位', leagueColor),
          const SizedBox(height: 6),
          standingsBody,
          const SizedBox(height: 12),
          gamesBlock,
        ],
      );

      final Widget personalPanel = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('個人成績', leagueColor),
          const SizedBox(height: 6),
          Expanded(child: personalBody),
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
            standingsBody,
          ],
        );
      }

      if (portraitLayout) {
        // 縦スクロール時は、見出しと上位10名が見える高さに抑える。
        // Picker +（Segment二段 or 打者投手タブ）+ 上位10名。
        const double personalSectionHeight = 32.0 + 130.0 + 20.8 * 10;
        final Widget personalSection = personalStatsLayout == PersonalStatsLayout.scroll
            ? personalBody
            : SizedBox(
                height: personalSectionHeight,
                child: personalBody,
              );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            gamesBlock,
            const SizedBox(height: 16),
            _sectionHeader('チーム順位', leagueColor),
            const SizedBox(height: 6),
            standingsBody,
            const SizedBox(height: 16),
            _sectionHeader('個人成績', leagueColor),
            const SizedBox(height: 6),
            personalSection,
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: teamPanel),
          const SizedBox(width: 12),
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
const int _statsScrollVisibleRows = 10;
const double _statsScrollBodyH = _statRowH * _statsScrollVisibleRows;

/// MLB 個人成績の短縮チーム名列（半角3文字 + 余白）
const double _mlbTeamAbbrevColW = 34.0;

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

    final showUserPredictions = ShowUserPredictions.of(context);
    final isJapan = showJapanFlag && isTrue(row['flg_japan']);
    const japanBg = Color(0xFFF5C6CE); // 薄いクリムゾンレッド
    final countryEmoji = '${row['emoji_country'] ?? ''}'.trim();
    final marks = [
      if (isJapan) (countryEmoji.isNotEmpty ? countryEmoji : '🇯🇵'),
      if (isTrue(row['flg_rookie'])) '🔰',
      if (isTrue(row['flg_career_this_year'])) '✨',
      if (isTrue(row['flg_under21'])) '🌱',
      if (isTrue(row['flg_age35'])) '🍁',
      if (isTrue(row['flg_retired'])) '💐',
    ];
    final compacted = compactPersonalStatName(name);
    final paren = compacted.indexOf('(');
    final label = paren >= 0 ? compacted.substring(0, paren) : compacted;
    final suffix = paren >= 0 ? compacted.substring(paren) : '';

    BoxDecoration? nameBg() {
      final raw = showUserPredictions ? '${row['colors_user'] ?? ''}' : '';
      final parts = raw.split('/').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
      final cols = [
        for (final part in parts)
          if (parseColorNameOrNull(part) != null) parseColorNameOrNull(part)!
      ];
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
    final hasPredictColor = showUserPredictions && '${row['colors_user'] ?? ''}'.split('/').any((s) => s.trim().isNotEmpty);
    final nameColor = hasPredictColor ? Colors.white : (isJapan ? Colors.black : null);
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
                  color: const Color(0xFF424242),
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
            // MLB略称（NYY 等）: 半角3文字 + 余白。NPB は従来どおり flex。
            if (showJapanFlag)
              SizedBox(
                width: _mlbTeamAbbrevColW,
                child: cellBg(
                  overlay: parseColorNameOrNull('${row['color_back'] ?? ''}') ?? (isNoRank ? noRankBg : Colors.transparent),
                  child: Align(
                    alignment: Alignment.center,
                    child: OneLineShrinkText(team, baseSize: 10, minSize: 1, fast: true, color: parseColorNameOrNull('${row['color_font'] ?? ''}')),
                  ),
                ),
              )
            else
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

const _statsBattingFallback = Color(0xFFF12C51);
const _statsPitchingFallback = Color(0xFF1A1AFF);

/// 打撃：左の黄→橙→右の赤ピンク（横方向）
const _statsBattingGradDecoration = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFFEBF100),
      Color(0xFFF8941D),
      Color(0xFFF12C51),
    ],
    stops: [0.0, 0.5, 1.0],
  ),
);

/// 投手：左上の深い青→右下のシアン（添付イメージ）
const _statsPitchingGradDecoration = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1A1AFF),
      Color(0xFF2E31FF),
      Color(0xFF0090FF),
      Color(0xFF00E5FF),
    ],
    stops: [0.0, 0.32, 0.68, 1.0],
  ),
);

/// 打撃／投手グラデ背景（タブ・タイトルヘッダー・Segment 共通）。
Widget _statsGradBackground({required bool batting, double opacity = 1.0}) {
  final fill = DecoratedBox(
    decoration: batting ? _statsBattingGradDecoration : _statsPitchingGradDecoration,
  );
  return Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: batting ? _statsBattingFallback : _statsPitchingFallback),
      Opacity(opacity: opacity.clamp(0.0, 1.0), child: fill),
    ],
  );
}

Widget _statsGradHeader({
  required bool batting,
  required Widget child,
  double height = 20,
  BorderRadius? borderRadius,
}) {
  return SizedBox(
    height: height,
    child: ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _statsGradBackground(batting: batting),
          Center(child: child),
        ],
      ),
    ),
  );
}

String _normalizePersonalTitle(String t) => t == 'ホールド' ? 'HP' : t;

bool _personalRowIsPitcher(Map<String, dynamic> row) {
  const pitchingTitles = {'防御率', '最多勝', '奪三振', 'HP', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'QS率'};
  final value = row['flg_pitcher'];
  if (value is bool) return value;
  final text = '$value'.trim().toLowerCase();
  if (text == 'true' || text == 't' || text == '1') return true;
  if (text == 'false' || text == 'f' || text == '0') return false;
  return pitchingTitles.contains('${row['title'] ?? ''}'.trim());
}

List<String> _titlesInOrder(List<Map<String, dynamic>> rows, List<String> preferred) {
  final present = <String>{};
  for (final row in rows) {
    final title = _normalizePersonalTitle('${row['title'] ?? ''}'.trim());
    if (title.isNotEmpty) present.add(title);
  }
  final ordered = <String>[];
  for (final title in preferred) {
    final key = _normalizePersonalTitle(title);
    if (present.remove(key)) ordered.add(title);
  }
  ordered.addAll(present);
  return ordered;
}

Widget _verticalStatLabel(String text, {required Color color, required FontWeight weight, double fontSize = 10}) {
  final chars = text.characters.toList();
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final ch in chars)
        Text(
          (ch == 'ー' || ch == '―' || ch == 'ｰ' || ch == '−') ? '｜' : ch,
          style: TextStyle(
            color: color,
            fontWeight: weight,
            fontSize: fontSize,
            height: 1.05,
          ),
        ),
    ],
  );
}

double _statsSegmentHeightFor(List<String> labels) {
  if (labels.isEmpty) return 0;
  final maxChars = labels.fold<int>(1, (m, label) => label.characters.length > m ? label.characters.length : m);
  return (maxChars * 11.0 + 10).clamp(36.0, 72.0);
}

/// グラデーション背景。選択中は原色、非選択は暗く。モヤ重ねなし。
class StatsSegmentControl extends StatelessWidget {
  final List<String> labels;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  final String? backgroundAsset;
  final Decoration? backgroundDecoration;
  final Color fallbackColor;
  final Color foreground;
  final double? height;

  const StatsSegmentControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    required this.fallbackColor,
    this.backgroundAsset,
    this.backgroundDecoration,
    this.foreground = Colors.white,
    this.height,
  });

  Widget _backgroundFill({required bool selected}) {
    final fill = backgroundDecoration != null
        ? DecoratedBox(decoration: backgroundDecoration!)
        : backgroundAsset != null
            ? Image.asset(
                backgroundAsset!,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            : const SizedBox.shrink();
    if (selected) return fill;
    const saturation = 0.22;
    const inv = 1 - saturation;
    const r = 0.2126 * inv;
    const g = 0.7152 * inv;
    const b = 0.0722 * inv;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        r + saturation, g, b, 0, 0,
        r, g + saturation, b, 0, 0,
        r, g, b + saturation, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: Opacity(opacity: 0.55, child: fill),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final barH = height ?? _statsSegmentHeightFor(labels);
    return SizedBox(
      height: barH,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) Container(width: 1, color: foreground.withValues(alpha: 0.85)),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelected(i),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: fallbackColor),
                        _backgroundFill(selected: selectedIndex == i),
                        if (selectedIndex == i)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        Center(
                          child: _verticalStatLabel(
                            labels[i],
                            color: foreground,
                            weight: selectedIndex == i ? FontWeight.w900 : FontWeight.w600,
                            fontSize: labels.length > 9 ? 9 : 10,
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
  }
}

/// 上段＝打者・下段＝投手の二段 Segment を持つ個人成績パネル。
class _DualStatsSegmentBars extends StatelessWidget {
  final List<String> battingTitles;
  final List<String> pitchingTitles;
  final bool battingSelected;
  final int titleIndex;
  final ValueChanged<({bool batting, int index})> onSelected;

  const _DualStatsSegmentBars({
    required this.battingTitles,
    required this.pitchingTitles,
    required this.battingSelected,
    required this.titleIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // 打者・投手で文字数が違っても、二段の高さを揃える。
    final sharedH = [
      _statsSegmentHeightFor(battingTitles),
      _statsSegmentHeightFor(pitchingTitles),
    ].fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (battingTitles.isNotEmpty)
          StatsSegmentControl(
            labels: battingTitles,
            selectedIndex: battingSelected ? titleIndex : null,
            backgroundDecoration: _statsBattingGradDecoration,
            fallbackColor: _statsBattingFallback,
            height: sharedH,
            onSelected: (i) => onSelected((batting: true, index: i)),
          ),
        if (battingTitles.isNotEmpty && pitchingTitles.isNotEmpty) const SizedBox(height: 4),
        if (pitchingTitles.isNotEmpty)
          StatsSegmentControl(
            labels: pitchingTitles,
            selectedIndex: battingSelected ? null : titleIndex,
            backgroundDecoration: _statsPitchingGradDecoration,
            fallbackColor: _statsPitchingFallback,
            height: sharedH,
            onSelected: (i) => onSelected((batting: false, index: i)),
          ),
      ],
    );
  }
}

/// 個人成績の「セグメント表示 / スクロール表示」Picker。
class PersonalStatsLayoutPicker extends StatelessWidget {
  final PersonalStatsLayout layout;
  final ValueChanged<PersonalStatsLayout> onChanged;

  const PersonalStatsLayoutPicker({
    super.key,
    required this.layout,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold);
    final label = layout == PersonalStatsLayout.segment ? 'セグメント表示' : 'スクロール表示';
    return SizedBox(
      height: TAB_BAR_H,
      child: Material(
        color: Colors.black,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Colors.black),
          borderRadius: BorderRadius.circular(TAB_RADIUS),
        ),
        child: PopupMenuButton<PersonalStatsLayout>(
          padding: EdgeInsets.zero,
          tooltip: '',
          color: Colors.black,
          initialValue: layout,
          position: PopupMenuPosition.under,
          onSelected: onChanged,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: PersonalStatsLayout.segment,
              child: Center(child: Text('セグメント表示', textAlign: TextAlign.center, style: style)),
            ),
            PopupMenuItem(
              value: PersonalStatsLayout.scroll,
              child: Center(child: Text('スクロール表示', textAlign: TextAlign.center, style: style)),
            ),
          ],
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, textAlign: TextAlign.center, style: style),
              const Positioned(
                right: 2,
                child: Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _batterPitcherTabBar({
  required int selectedIndex,
  required ValueChanged<int> onSelected,
}) {
  const tabs = [('打者', 0), ('投手', 1)];
  return SizedBox(
    height: TAB_BAR_H,
    child: Row(
      children: [
        for (var i = 0; i < tabs.length; i++) ...[
          if (i > 0) const SizedBox(width: ALL_SPACE_BLOCK),
          Expanded(
            child: GestureDetector(
              onTap: () => onSelected(tabs[i].$2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TAB_RADIUS),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 選択中はグラデをそのまま、非選択は薄いグレーのみ（選択エフェクトなし）
                    if (selectedIndex == tabs[i].$2) _statsGradBackground(batting: tabs[i].$2 == 0) else ColoredBox(color: Colors.grey.shade300),
                    Center(
                      child: Text(
                        tabs[i].$1,
                        style: TextStyle(
                          fontSize: TAB_BAR_H / 2,
                          fontWeight: selectedIndex == tabs[i].$2 ? FontWeight.bold : FontWeight.normal,
                          color: selectedIndex == tabs[i].$2 ? Colors.white : Colors.black87,
                        ),
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
  );
}

/// 1リーグ分。Picker でセグメント／スクロールを切り替える。
class LeaguePersonalStatsHost extends StatefulWidget {
  final List<Map<String, dynamic>> batting;
  final List<Map<String, dynamic>> pitching;
  final bool showJapanFlag;
  final PersonalStatsLayout layout;
  final ValueChanged<PersonalStatsLayout>? onLayoutChanged;

  const LeaguePersonalStatsHost({
    super.key,
    required this.batting,
    required this.pitching,
    this.showJapanFlag = false,
    this.layout = PersonalStatsLayout.segment,
    this.onLayoutChanged,
  });

  @override
  State<LeaguePersonalStatsHost> createState() => _LeaguePersonalStatsHostState();
}

class _LeaguePersonalStatsHostState extends State<LeaguePersonalStatsHost> {
  int _batterPitcherTab = 0;

  void _setLayout(PersonalStatsLayout value) {
    if (value == widget.layout) return;
    writePersonalStatsLayout(value);
    widget.onLayoutChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final battingSelected = _batterPitcherTab == 0;
    final picker = PersonalStatsLayoutPicker(
      layout: widget.layout,
      onChanged: _setLayout,
    );
    if (widget.layout == PersonalStatsLayout.scroll) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          picker,
          const SizedBox(height: 4),
          _batterPitcherTabBar(
            selectedIndex: _batterPitcherTab,
            onSelected: (i) {
              if (i == _batterPitcherTab) return;
              setState(() => _batterPitcherTab = i);
            },
          ),
          const SizedBox(height: 4),
          ScrollLeaguePersonalStats(
            rows: battingSelected ? widget.batting : widget.pitching,
            batting: battingSelected,
            showJapanFlag: widget.showJapanFlag,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        picker,
        const SizedBox(height: 4),
        Expanded(
          child: SegmentedLeaguePersonalStats(
            batting: widget.batting,
            pitching: widget.pitching,
            showJapanFlag: widget.showJapanFlag,
          ),
        ),
      ],
    );
  }
}

/// スクロール表示（1リーグ）。タイトルを横スクロールし、各列は10位まで見える高さで縦スクロール。
class ScrollLeaguePersonalStats extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final bool batting;
  final bool showJapanFlag;

  const ScrollLeaguePersonalStats({
    super.key,
    required this.rows,
    required this.batting,
    this.showJapanFlag = false,
  });

  static const _battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
  static const _pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'QS率'];

  @override
  Widget build(BuildContext context) {
    final cols = batting ? _battingCols : _pitchingCols;
    final titles = _titlesInOrder(rows, cols);
    if (titles.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      const headerH = 28.0;
      if (titles.isEmpty) {
        return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final title in titles) ...[
            DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: Colors.black26, width: 1)),
              child: _statsGradHeader(
                batting: batting,
                height: headerH,
                child: OneLineShrinkText(
                  title,
                  baseSize: 12,
                  minSize: 6,
                  weight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            Builder(builder: (context) {
              final matched = rows.where((m) {
                final t = '${m['title'] ?? ''}'.trim();
                return t == title || _normalizePersonalTitle(t) == _normalizePersonalTitle(title);
              }).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in matched)
                    PlayerStatCell(
                      row: row,
                      showJapanFlag: showJapanFlag,
                    ),
                ],
              );
            }),
            const SizedBox(height: 8),
          ],
        ],
      );
    });
  }
}

/// 横長画面用。上段＝全打撃スタッツ、下段＝全投手スタッツのグリッド（打者／投手切替なし）。
class DualBandLeaguePersonalStats extends StatelessWidget {
  final List<Map<String, dynamic>> batting;
  final List<Map<String, dynamic>> pitching;
  final bool showJapanFlag;

  const DualBandLeaguePersonalStats({
    super.key,
    required this.batting,
    required this.pitching,
    this.showJapanFlag = false,
  });

  @override
  Widget build(BuildContext context) {
    if (batting.isEmpty && pitching.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (batting.isNotEmpty)
          Expanded(
            child: _FillScrollLeaguePersonalStats(
              rows: batting,
              batting: true,
              showJapanFlag: showJapanFlag,
            ),
          ),
        if (batting.isNotEmpty && pitching.isNotEmpty) const SizedBox(height: 4),
        if (pitching.isNotEmpty)
          Expanded(
            child: _FillScrollLeaguePersonalStats(
              rows: pitching,
              batting: false,
              showJapanFlag: showJapanFlag,
            ),
          ),
      ],
    );
  }
}

/// 与えられた高さいっぱいにスタッツ列を敷き、溢れた選手は列内スクロール。
class _FillScrollLeaguePersonalStats extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final bool batting;
  final bool showJapanFlag;

  const _FillScrollLeaguePersonalStats({
    required this.rows,
    required this.batting,
    this.showJapanFlag = false,
  });

  static const _battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
  static const _pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'QS率'];

  @override
  Widget build(BuildContext context) {
    final cols = batting ? _battingCols : _pitchingCols;
    final titles = _titlesInOrder(rows, cols);
    if (titles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final parentW = constraints.maxWidth.isFinite && constraints.maxWidth > 0 ? constraints.maxWidth : 300.0;
      final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 200.0;
      const headerH = 28.0;
      final colW = parentW * 0.2;
      return SizedBox(
        height: h,
        width: parentW,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final title in titles)
                SizedBox(
                  width: colW,
                  height: h,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(border: Border.all(color: Colors.black26, width: 1)),
                        child: _statsGradHeader(
                          batting: batting,
                          height: headerH,
                          child: OneLineShrinkText(
                            title,
                            baseSize: 12,
                            minSize: 6,
                            weight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Builder(builder: (context) {
                          final matched = rows.where((m) {
                            final t = '${m['title'] ?? ''}'.trim();
                            return t == title || _normalizePersonalTitle(t) == _normalizePersonalTitle(title);
                          }).toList();
                          return LayoutBuilder(builder: (context, bodyConstraints) {
                            final bodyH = bodyConstraints.maxHeight.isFinite ? bodyConstraints.maxHeight : 0.0;
                            final visibleSlots = bodyH > 0 ? (bodyH / _statRowH).floor().clamp(0, 1000) : 0;
                            if (matched.length > visibleSlots && visibleSlots > 0) {
                              return SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (final row in matched)
                                      PlayerStatCell(
                                        row: row,
                                        width: colW,
                                        showJapanFlag: showJapanFlag,
                                      ),
                                  ],
                                ),
                              );
                            }
                            final emptyFixed = (visibleSlots - matched.length).clamp(0, 1000);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final row in matched)
                                  PlayerStatCell(
                                    row: row,
                                    width: colW,
                                    showJapanFlag: showJapanFlag,
                                  ),
                                for (var i = 0; i < emptyFixed; i++)
                                  SizedBox(
                                    width: colW,
                                    height: _statRowH,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.black26, width: 1),
                                      ),
                                    ),
                                  ),
                                const Expanded(
                                  child: SizedBox.expand(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(color: Colors.black26),
                                          right: BorderSide(color: Colors.black26),
                                          bottom: BorderSide(color: Colors.black26),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          });
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
}

/// 横長・項目ごと表示。左右に各リーグの打撃上段／投手下段グリッド。
class DualBandBothLeaguePersonalStats extends StatelessWidget {
  final List<Map<String, dynamic>> stats;
  final OrgConfig org;

  const DualBandBothLeaguePersonalStats({
    super.key,
    required this.stats,
    this.org = OrgConfig.npb,
  });

  @override
  Widget build(BuildContext context) {
    Widget side(int leagueId, Color color, String name) {
      final leagueRows = stats.where((row) => (int.tryParse('${row['id_league']}') ?? 0) == leagueId).toList();
      final bat = leagueRows.where((row) => !_personalRowIsPitcher(row)).toList();
      final pit = leagueRows.where(_personalRowIsPitcher).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: ColoredBox(
              color: color,
              child: Center(
                child: Text(
                  name.replaceAll('・リーグ', ''),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: DualBandLeaguePersonalStats(
              batting: bat,
              pitching: pit,
              showJapanFlag: org.kind == OrgKind.mlb,
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: side(org.leagues[0].id, org.leagues[0].color, org.leagues[0].name)),
        const SizedBox(width: 4),
        Expanded(child: side(org.leagues[1].id, org.leagues[1].color, org.leagues[1].name)),
      ],
    );
  }
}

/// スクロール表示（両リーグ）。タイトルごとに10位まで見える高さで、それ以下は縦スクロール。
class ScrollBothLeaguePersonalStats extends StatelessWidget {
  final List<Map<String, dynamic>> stats;
  final bool pitcher;
  final OrgConfig org;

  const ScrollBothLeaguePersonalStats({
    super.key,
    required this.stats,
    required this.pitcher,
    this.org = OrgConfig.npb,
  });

  @override
  Widget build(BuildContext context) {
    final rows = stats.where((row) => _personalRowIsPitcher(row) == pitcher).toList();
    final preferred = pitcher ? const ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'QS率'] : const ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
    final titles = _titlesInOrder(rows, preferred);
    if (titles.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }

    List<Map<String, dynamic>> side(int leagueId, String title) {
      return rows.where((row) {
        if ((int.tryParse('${row['id_league']}') ?? 0) != leagueId) return false;
        final t = '${row['title'] ?? ''}'.trim();
        return t == title || _normalizePersonalTitle(t) == _normalizePersonalTitle(title);
      }).toList();
    }

    return ListView(
      children: [
        for (final title in titles) ...[
          _statsGradHeader(
            batting: !pitcher,
            height: 26,
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
                    child: Text(
                      org.leagues[0].name.replaceAll('・リーグ', ''),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    color: org.leagues[1].color,
                    child: Text(
                      org.leagues[1].name.replaceAll('・リーグ', ''),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Builder(builder: (context) {
            final left = side(org.leagues[0].id, title);
            final right = side(org.leagues[1].id, title);
            final rowCount = left.length > right.length ? left.length : right.length;
            return SizedBox(
              height: _statsScrollBodyH,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < rowCount; i++)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: i < left.length
                                ? PlayerStatCell(
                                    row: left[i],
                                    showRank: true,
                                    showJapanFlag: org.kind == OrgKind.mlb,
                                  )
                                : const SizedBox(height: _statRowH),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: i < right.length
                                ? PlayerStatCell(
                                    row: right[i],
                                    showRank: true,
                                    showJapanFlag: org.kind == OrgKind.mlb,
                                  )
                                : const SizedBox(height: _statRowH),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// 1リーグ分の個人成績。打者／投手タイトルを二段 Segment で切り替える。
class SegmentedLeaguePersonalStats extends StatefulWidget {
  final List<Map<String, dynamic>> batting;
  final List<Map<String, dynamic>> pitching;
  final bool showJapanFlag;

  const SegmentedLeaguePersonalStats({
    super.key,
    required this.batting,
    required this.pitching,
    this.showJapanFlag = false,
  });

  @override
  State<SegmentedLeaguePersonalStats> createState() => _SegmentedLeaguePersonalStatsState();
}

class _SegmentedLeaguePersonalStatsState extends State<SegmentedLeaguePersonalStats> {
  static const _battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
  static const _pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'QS率'];

  bool _battingSelected = true;
  int _titleIndex = 0;

  @override
  void didUpdateWidget(covariant SegmentedLeaguePersonalStats oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.batting != widget.batting || oldWidget.pitching != widget.pitching) {
      _battingSelected = widget.batting.isNotEmpty;
      _titleIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final batTitles = _titlesInOrder(widget.batting, _battingCols);
    final pitTitles = _titlesInOrder(widget.pitching, _pitchingCols);
    if (batTitles.isEmpty && pitTitles.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }
    final battingSelected = batTitles.isEmpty ? false : (pitTitles.isEmpty ? true : _battingSelected);
    final titles = battingSelected ? batTitles : pitTitles;
    final index = titles.isEmpty ? 0 : _titleIndex.clamp(0, titles.length - 1);
    final title = titles.isEmpty ? '' : titles[index];
    final src = battingSelected ? widget.batting : widget.pitching;
    final rows = src.where((m) {
      final t = '${m['title'] ?? ''}';
      return t == title || _normalizePersonalTitle(t) == _normalizePersonalTitle(title);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DualStatsSegmentBars(
          battingTitles: batTitles,
          pitchingTitles: pitTitles,
          battingSelected: battingSelected,
          titleIndex: index,
          onSelected: (sel) => setState(() {
            _battingSelected = sel.batting;
            _titleIndex = sel.index;
          }),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => PlayerStatCell(
              row: rows[i],
              showRank: true,
              showJapanFlag: widget.showJapanFlag,
            ),
          ),
        ),
      ],
    );
  }
}

/// 項目ごとの個人成績。Picker でセグメント／スクロールを切り替える。
class BothLeaguePersonalStats extends StatefulWidget {
  final List<Map<String, dynamic>> stats;
  final OrgConfig org;
  final PersonalStatsLayout layout;
  final ValueChanged<PersonalStatsLayout>? onLayoutChanged;

  const BothLeaguePersonalStats({
    super.key,
    required this.stats,
    this.org = OrgConfig.npb,
    this.layout = PersonalStatsLayout.segment,
    this.onLayoutChanged,
  });

  @override
  State<BothLeaguePersonalStats> createState() => _BothLeaguePersonalStatsState();
}

class _BothLeaguePersonalStatsState extends State<BothLeaguePersonalStats> {
  static const _battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
  static const _pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'QS率'];

  bool _battingSelected = true;
  int _titleIndex = 0;
  int _batterPitcherTab = 0;

  @override
  void didUpdateWidget(covariant BothLeaguePersonalStats oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats != widget.stats) {
      _titleIndex = 0;
    }
  }

  void _setLayout(PersonalStatsLayout value) {
    if (value == widget.layout) return;
    writePersonalStatsLayout(value);
    widget.onLayoutChanged?.call(value);
  }

  Widget _segmentBody() {
    final battingRows = widget.stats.where((row) => !_personalRowIsPitcher(row)).toList();
    final pitchingRows = widget.stats.where(_personalRowIsPitcher).toList();
    final batTitles = _titlesInOrder(battingRows, _battingCols);
    final pitTitles = _titlesInOrder(pitchingRows, _pitchingCols);
    if (batTitles.isEmpty && pitTitles.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }

    final battingSelected = batTitles.isEmpty ? false : (pitTitles.isEmpty ? true : _battingSelected);
    final titles = battingSelected ? batTitles : pitTitles;
    final index = titles.isEmpty ? 0 : _titleIndex.clamp(0, titles.length - 1);
    final title = titles.isEmpty ? '' : titles[index];
    final rows = battingSelected ? battingRows : pitchingRows;
    final org = widget.org;

    List<Map<String, dynamic>> side(int leagueId) {
      return rows.where((row) {
        if ((int.tryParse('${row['id_league']}') ?? 0) != leagueId) return false;
        final t = '${row['title'] ?? ''}'.trim();
        return t == title || _normalizePersonalTitle(t) == _normalizePersonalTitle(title);
      }).toList();
    }

    final left = side(org.leagues[0].id);
    final right = side(org.leagues[1].id);
    final rowCount = left.length > right.length ? left.length : right.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DualStatsSegmentBars(
          battingTitles: batTitles,
          pitchingTitles: pitTitles,
          battingSelected: battingSelected,
          titleIndex: index,
          onSelected: (sel) => setState(() {
            _battingSelected = sel.batting;
            _titleIndex = sel.index;
          }),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 22,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  color: org.leagues[0].color,
                  child: Text(
                    org.leagues[0].name.replaceAll('・リーグ', ''),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  color: org.leagues[1].color,
                  child: Text(
                    org.leagues[1].name.replaceAll('・リーグ', ''),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: ListView.builder(
            itemCount: rowCount,
            itemBuilder: (context, i) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: i < left.length
                      ? PlayerStatCell(
                          row: left[i],
                          showRank: true,
                          showJapanFlag: org.kind == OrgKind.mlb,
                        )
                      : const SizedBox(height: _statRowH),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: i < right.length
                      ? PlayerStatCell(
                          row: right[i],
                          showRank: true,
                          showJapanFlag: org.kind == OrgKind.mlb,
                        )
                      : const SizedBox(height: _statRowH),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scrollBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _batterPitcherTabBar(
          selectedIndex: _batterPitcherTab,
          onSelected: (i) {
            if (i == _batterPitcherTab) return;
            setState(() => _batterPitcherTab = i);
          },
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ScrollBothLeaguePersonalStats(
            stats: widget.stats,
            pitcher: _batterPitcherTab == 1,
            org: widget.org,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PersonalStatsLayoutPicker(
          layout: widget.layout,
          onChanged: _setLayout,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: widget.layout == PersonalStatsLayout.segment ? _segmentBody() : _scrollBody(),
        ),
      ],
    );
  }
}
