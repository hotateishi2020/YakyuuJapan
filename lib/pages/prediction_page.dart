import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../tools/Env.dart';
import '../tools/app_logger.dart';
import '../tools/color_parse.dart';
import '../config/app_design.dart';
import '../tools/json_utils.dart';
import '../logic/atari_counts.dart';
import '../View/Headers.dart';
import '../View/Tabs.dart';
import '../View/Text.dart';
import '../View/LeagueBoardRow.dart';

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  // 左カラム
  List<Map<String, dynamic>> predictions = [];
  List<Map<String, dynamic>> standings = []; // ← フラット行（id_league/name_league入り）
  List<Map<String, dynamic>> npbPlayerStats = [];
  List<Map<String, dynamic>> npbPlayerStatsActual = [];

  // 右カラム（すべて文字列で扱う）
  List<Map<String, dynamic>> games = [];
  List<Map<String, dynamic>> events = [];
  List<Map<String, dynamic>> notifications = [];

  bool isLoading = true;
  String? error;

  bool _scoreExpanded = true;
  bool _newsExpanded = false;
  bool _eventsExpanded = false;
  // 縦型: 0=セ・リーグ, 1=パ・リーグ
  int _portraitLeagueTab = 0;
  // 縦型: 0=チーム成績, 1=個人成績
  int _portraitContentTab = 0;
  // 1: 右側のタブから入る、-1: 左側のタブから入る
  int _portraitSlideDirection = 1;

  // 個人成績の id_user → 表示名
  String _usernameForId(String idUser) =>
      lookupField(npbPlayerStats, 'id_user', idUser, 'username');

  String _userNameFromPredictions(String idUserStr) =>
      lookupField(predictions, 'id_user', idUserStr, 'name_user_last');

  Color _userBackColorForId(String idUser, {required Color fallback}) {
    final teamColor =
        lookupField(predictions, 'id_user', idUser, 'code_color', fallback: '');
    final playerColor = lookupField(
        npbPlayerStats, 'id_user', idUser, 'code_color',
        fallback: '');
    return parseColorNameOrNull(teamColor) ??
        parseColorNameOrNull(playerColor) ??
        fallback;
  }

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    try {
      final uri = Uri.parse('${Env.baseUrl()}/predictions');
      final res = await http.get(uri);

      if (res.statusCode != 200) {
        setState(() {
          error = 'HTTPエラー: ${res.statusCode}';
          isLoading = false;
        });
        logger.w(
            'HTTP ${res.statusCode} body: ${res.body.substring(0, res.body.length.clamp(0, 400))}');
        return;
      }

      final map = jsonDecode(res.body) as Map<String, dynamic>;

      final users = listMapFromJson(map['predict_team']);
      final npb = listMapFromJson(map['stats_team']);
      final statsPredict = listMapFromJson(map['predict_player']);
      final statsActual = listMapFromJson(map['stats_player']);
      final gms = listMapFromJson(map['games']);
      final evts = listMapFromJson(map['events']);
      final notifs = listMapFromJson(map['notification']);

      setState(() {
        predictions = users;
        standings = npb;
        npbPlayerStats = statsPredict; // 左
        npbPlayerStatsActual = statsActual; // 中央
        games = gms;
        events = evts;
        notifications = notifs;
        isLoading = false;
      });
    } catch (e, st) {
      logger.e('通信/解析エラー: $e\n$st');
      setState(() {
        error = '通信エラー: $e';
        isLoading = false;
      });
    }
  }

  // flg_atari の合計（予想者のみ: id_user 1/2、セ+パ合算）

  Widget _portraitTabBar({
    required List<(String label, int index)> tabs,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    Color? selectedColor,
  }) {
    final Color active = selectedColor ?? ALL_COLOR_APP;
    return SizedBox(
      height: TAB_BAR_H,
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: ALL_SPACE_BLOCK),
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(tabs[i].$2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: TAB_PAD_VERTICAL,
                      horizontal: TAB_PAD_HORIZONTAL),
                  decoration: BoxDecoration(
                    color: selectedIndex == tabs[i].$2
                        ? active
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(TAB_RADIUS),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tabs[i].$1,
                    style: TextStyle(
                      fontSize: TAB_BAR_H / 2,
                      fontWeight: selectedIndex == tabs[i].$2
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: selectedIndex == tabs[i].$2
                          ? TAB_COLOR_FONT
                          : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _portraitLeagueTabBar() {
    return _portraitTabBar(
      tabs: const [
        ('セ・リーグ', 0),
        ('パ・リーグ', 1),
      ],
      selectedIndex: _portraitLeagueTab,
      onSelected: (i) {
        if (i == _portraitLeagueTab) return;
        setState(() {
          _portraitSlideDirection = i > _portraitLeagueTab ? 1 : -1;
          _portraitLeagueTab = i;
        });
      },
      selectedColor: _portraitLeagueTab == 0
          ? const Color(0xFF0B8F3A)
          : const Color(0xFF4DB5E8),
    );
  }

  Widget _portraitContentTabBar() {
    return _portraitTabBar(
      tabs: const [
        ('チーム成績', 0),
        ('個人成績', 1),
      ],
      selectedIndex: _portraitContentTab,
      onSelected: (i) {
        if (i == _portraitContentTab) return;
        setState(() {
          _portraitSlideDirection = i > _portraitContentTab ? 1 : -1;
          _portraitContentTab = i;
        });
      },
    );
  }

  Widget _portraitCollapsibleSection({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20),
                  const SizedBox(width: 4),
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 4),
          child,
        ],
        const SizedBox(height: ALL_SPACE_BLOCK),
      ],
    );
  }

  // 上部: Score + News + イベント日程
  Widget _scoreNewsEventsRow({required bool portrait}) {
    final counts = computeAtariCounts(
      npbPlayerStats: npbPlayerStats,
      npbPlayerStatsActual: npbPlayerStatsActual,
      predictions: predictions,
      standings: standings,
    );
    Widget _scoreBox({bool hideHeader = false, bool portraitCompact = false}) {
      final name1 = _userNameFromPredictions('1');
      final name2 = _userNameFromPredictions('2');
      final score1 = '${counts['1'] ?? 0}';
      final score2 = '${counts['2'] ?? 0}';
      final color1 = _userBackColorForId('1', fallback: Colors.blue);
      final color2 = _userBackColorForId('2', fallback: Colors.red);
      const double vBorder = 1.0;
      const double cellPad = 6.0;

      Widget _nameCell(String name, Color background,
          {bool leftBorder = false}) {
        return Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: background,
              border: leftBorder
                  ? const Border(
                      left: BorderSide(color: Colors.black45, width: vBorder))
                  : null,
            ),
            alignment: Alignment.center,
            padding:
                const EdgeInsets.symmetric(horizontal: cellPad, vertical: 4),
            child: OneLineShrinkText(
              name,
              baseSize: 20,
              minSize: 10,
              weight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black45),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: portraitCompact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (!hideHeader)
                Container(
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    border: Border(
                        bottom:
                            BorderSide(color: Colors.black45, width: vBorder)),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                      horizontal: cellPad, vertical: 4),
                  child: const OneLineShrinkText(
                    'SCORE',
                    baseSize: 20,
                    minSize: 10,
                    weight: FontWeight.bold,
                    align: TextAlign.center,
                    color: Colors.white,
                  ),
                ),
              // 2行目: 立石 | 江島
              Container(
                height: portraitCompact ? 26 : 32,
                decoration: const BoxDecoration(
                  border: Border(
                      bottom:
                          BorderSide(color: Colors.black45, width: vBorder)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _nameCell(name1, color1),
                    _nameCell(name2, color2, leftBorder: true),
                  ],
                ),
              ),
              // 3行目: 数字（両列とも同じフォントサイズ）
              if (portraitCompact)
                SizedBox(
                  height: 46,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(cellPad),
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              score1,
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(
                                left: BorderSide(
                                    color: Colors.black45, width: vBorder)),
                          ),
                          padding: const EdgeInsets.all(cellPad),
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              score2,
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final double halfW = c.maxWidth / 2;
                    final double availW =
                        (halfW - cellPad * 2).clamp(0.0, double.infinity);
                    final double availH =
                        (c.maxHeight - cellPad * 2).clamp(0.0, double.infinity);
                    final double byH = availH * 0.88;
                    final double byW = availW * 0.88;
                    final double scoreSize =
                        (byH < byW ? byH : byW).clamp(16.0, 56.0);

                    Widget scoreCell(String value, {bool leftBorder = false}) {
                      return Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: leftBorder
                                ? const Border(
                                    left: BorderSide(
                                        color: Colors.black45, width: vBorder))
                                : null,
                          ),
                          padding: const EdgeInsets.all(cellPad),
                          alignment: Alignment.center,
                          child: Text(
                            value,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: scoreSize,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                        ),
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        scoreCell(score1),
                        scoreCell(score2, leftBorder: true),
                      ],
                    );
                  }),
                ),
            ],
          ),
        ),
      );
    }

    Widget _newsBox({bool hideHeader = false, double? boxHeight}) {
      Color parse(String? name, Color fallback) {
        final n = (name ?? '').toLowerCase().trim();
        const m = {
          'red': 0xFFF44336,
          'green': 0xFF4CAF50,
          'blue': 0xFF0000FF,
          'navy': 0xFF001F3F,
          'royalblue': 0xFF4169E1,
          'orange': 0xFFFF9800,
          'yellow': 0xFFFFEB3B,
          'gold': 0xFFFFD700,
          'lime': 0xFFCDDC39,
          'black': 0xFF000000,
          'gray': 0xFF9E9E9E,
          'grey': 0xFF9E9E9E,
          'crimson': 0xFFDC143C,
          'lightgreen': 0xFF8BC34A,
          'white': 0xFFFFFFFF,
        };
        if (m.containsKey(n)) return Color(m[n]!);
        return fallback;
      }

      const double tagW = 64.0;
      const double tagH = 20.0;

      final h = boxHeight ?? 120.0;
      return Container(
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black45),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hideHeader)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('News',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('未読メッセージを一覧表示',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 4),
                      for (final n in notifications)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              // メインタグ
                              Container(
                                width: tagW,
                                alignment: Alignment.center,
                                constraints:
                                    const BoxConstraints(minHeight: tagH),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 2, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: parse(n['tag_main_color_back'],
                                      Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: OneLineShrinkText(
                                  (n['tag_main_title'] ?? '').toString(),
                                  baseSize: 12,
                                  minSize: 8,
                                  color: parse(
                                      n['tag_main_color_font'], Colors.white),
                                  align: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // サブタグ
                              Container(
                                width: tagW,
                                alignment: Alignment.center,
                                constraints:
                                    const BoxConstraints(minHeight: tagH),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 2, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: parse(n['tag_sub_color_back'],
                                      Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: OneLineShrinkText(
                                  (n['tag_sub_title'] ?? '').toString(),
                                  baseSize: 12,
                                  minSize: 8,
                                  color: parse(
                                      n['tag_sub_color_font'], Colors.white),
                                  align: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // タイトル
                              Expanded(
                                child: OneLineShrinkText(
                                  (n['title'] ?? '').toString(),
                                  baseSize: 12,
                                  minSize: 8,
                                  align: TextAlign.left,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // 既読/未読ボタン
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (n['flg_read'] == true)
                                      ? Colors.grey
                                      : Colors.orange,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  (n['flg_read'] == true) ? '既読' : '未読',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget _eventsBox({bool hideHeader = false, double? boxHeight}) {
      final evs = [...events];
      evs.sort((a, b) => (a['date_from_temp'] ?? '')
          .toString()
          .compareTo((b['date_from_temp'] ?? '').toString()));

      Color parse(String? name, Color fallback) {
        final n = (name ?? '').toLowerCase().trim();
        const m = {
          'red': 0xFFF44336,
          'green': 0xFF4CAF50,
          'blue': 0xFF0000FF,
          'navy': 0xFF001F3F,
          'royalblue': 0xFF4169E1,
          'orange': 0xFFFF9800,
          'yellow': 0xFFFFEB3B,
          'gold': 0xFFFFD700,
          'lime': 0xFFCDDC39,
          'black': 0xFF000000,
          'gray': 0xFF9E9E9E,
          'grey': 0xFF9E9E9E,
          'crimson': 0xFFDC143C,
          'lightgreen': 0xFF8BC34A,
          'white': 0xFFFFFFFF,
        };
        if (m.containsKey(n)) return Color(m[n]!);
        return fallback;
      }

      const catW = 64.0; // 主・サブの列幅（同一）

      final h = boxHeight ?? 120.0;
      final content = Container(
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black45),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hideHeader)
              SizedBox(
                width: double.infinity,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('イベント日程',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    double measureTextWidth(String text) {
                      final painter = TextPainter(
                        text: TextSpan(
                            text: text,
                            style: const TextStyle(
                              fontSize: 12,
                            )),
                        maxLines: 1,
                        textDirection: TextDirection.ltr,
                      )..layout();
                      return painter.width;
                    }

                    double rawMaxTitleW = 0;
                    for (final e in evs) {
                      final t = (e['title_event'] ?? '').toString();
                      final w = measureTextWidth(t);
                      if (w > rawMaxTitleW) rawMaxTitleW = w;
                    }

                    // 固定列幅計算
                    const double spacing = 6 + 6 + 4; // cat間+title-date間
                    const double minDate = 48;
                    final double fixedCats = catW * 2;
                    double titleColW = rawMaxTitleW;
                    final maxAllowed =
                        constraints.maxWidth - fixedCats - spacing - minDate;
                    if (titleColW > maxAllowed) titleColW = maxAllowed;
                    if (titleColW < 60) titleColW = 60;

                    double dateMaxW =
                        constraints.maxWidth - fixedCats - spacing - titleColW;
                    if (dateMaxW < minDate) dateMaxW = minDate;

                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          const Divider(height: 1),
                          const SizedBox(height: 4),
                          for (final e in evs)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(children: [
                                // 主カテゴリ
                                Container(
                                  width: catW,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 2, horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: parse(e['event_category_color_back'],
                                        Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: OneLineShrinkText(
                                    (e['event_category'] ?? '').toString(),
                                    baseSize: 12,
                                    minSize: 8,
                                    color: parse(e['event_category_color_font'],
                                        Colors.white),
                                    align: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // サブカテゴリ
                                Container(
                                  width: catW,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 2, horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: parse(
                                        e['event_category_sub_color_back'],
                                        Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: OneLineShrinkText(
                                    (e['event_category_sub'] ?? '').toString(),
                                    baseSize: 12,
                                    minSize: 8,
                                    color: parse(
                                        e['event_category_sub_color_font'],
                                        Colors.white),
                                    align: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // タイトル（最長幅に固定）
                                SizedBox(
                                  width: titleColW,
                                  child: Builder(builder: (context) {
                                    final String title =
                                        (e['title_event'] ?? '').toString();
                                    final bool isToday = e['flg_today'] == true;
                                    final double tw = measureTextWidth(title);
                                    final double frac =
                                        (tw / titleColW).clamp(0.0, 1.0);
                                    final BoxDecoration? deco = isToday
                                        ? BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.yellowAccent
                                                    .withOpacity(1.0),
                                                Colors.yellowAccent
                                                    .withOpacity(1.0),
                                                Colors.yellowAccent
                                                    .withOpacity(0.0),
                                              ],
                                              stops: [0.0, frac, 1.0],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          )
                                        : null;
                                    return Container(
                                      decoration: deco,
                                      child: OneLineShrinkText(
                                        title,
                                        baseSize: 12,
                                        minSize: 8,
                                        align: TextAlign.left,
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(width: 2),
                                // 日付（左詰め・最小/最大幅内で縮小）
                                Expanded(
                                  // constraints: BoxConstraints(minWidth: minDate, maxWidth: dateMaxW),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: OneLineShrinkText(
                                      (e['txt_timing'] ?? '').toString(),
                                      baseSize: 12,
                                      minSize: 8,
                                      align: TextAlign.left,
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                        ],
                      ),
                    );
                  }, //builder
                ),
              ),
            ),
          ],
        ),
      );

      return content;
    }

    if (portrait) {
      const double panelH = 160.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _portraitCollapsibleSection(
            title: 'News',
            expanded: _newsExpanded,
            onToggle: () => setState(() => _newsExpanded = !_newsExpanded),
            child: _newsBox(hideHeader: true, boxHeight: panelH),
          ),
          _portraitCollapsibleSection(
            title: 'イベント日程',
            expanded: _eventsExpanded,
            onToggle: () => setState(() => _eventsExpanded = !_eventsExpanded),
            child: _eventsBox(hideHeader: true, boxHeight: panelH),
          ),
          _portraitCollapsibleSection(
            title: 'SCORE',
            expanded: _scoreExpanded,
            onToggle: () => setState(() => _scoreExpanded = !_scoreExpanded),
            child: _scoreBox(hideHeader: true, portraitCompact: true),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 下段 LeagueBoardRow / SeasonTable と同じ比率・隙間で幅を決める
        final double rowW = constraints.maxWidth;
        final int sideFlex = ALL_RATIO_BLOCK_W[0];
        final int bodyFlex = ALL_RATIO_BLOCK_W[2] + ALL_RATIO_BLOCK_W[3];
        const int standingsFlex = 3;
        const int personalFlex = 2;
        const double seasonGap = 4.0; // SeasonTable 内の隙間と同じ
        const double rankColsW = STANDINGS_COL_W2 * 3; // 順位・立・江

        // Expanded の丸め誤差を避けるため、余白は引き算で確定させる
        final double sideW = rowW * sideFlex / (sideFlex + bodyFlex);
        final double bodyW = rowW - sideW;
        final double standingsW = (bodyW - seasonGap) *
            standingsFlex /
            (standingsFlex + personalFlex);
        final double personalW = bodyW - seasonGap - standingsW;
        final double scoreW = sideW + rankColsW;
        final double newsW = standingsW - rankColsW;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: scoreW, child: _scoreBox()),
            SizedBox(width: newsW, child: _newsBox()),
            const SizedBox(width: seasonGap),
            SizedBox(width: personalW, child: _eventsBox()),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text(error!));

    return LayoutBuilder(
      builder: (context, constraints) {
        // フル幅表示（スケーリングなし）
        final designWidth = constraints.maxWidth;
        const double scale = 1.0;
        final compact = false;

        final isPortrait = constraints.maxHeight / constraints.maxWidth >=
            PORTRAIT_ASPECT_RATIO;
        final bool portraitShowPersonal = _portraitContentTab == 1;

        Widget centralLeagueBoard({
          required int leagueId,
          required Color leagueColor,
          required String logoAsset,
          required String leagueLabelPrefix,
        }) {
          return LeagueBoardRow(
            leagueId: leagueId,
            leagueColor: leagueColor,
            logoAsset: logoAsset,
            leagueLabelPrefix: leagueLabelPrefix,
            predictions: predictions,
            standings: standings,
            npbPlayerStats: npbPlayerStats,
            npbPlayerStatsActual: npbPlayerStatsActual,
            games: games,
            usernameForId: _usernameForId,
            userNameFromPredictions: _userNameFromPredictions,
            compact: compact,
            portraitLayout: isPortrait,
            portraitShowPersonal: portraitShowPersonal,
          );
        }

        final Widget selectedPortraitLeague = _portraitLeagueTab == 0
            ? centralLeagueBoard(
                leagueId: 1,
                leagueColor: const Color(0xFF0B8F3A),
                logoAsset: 'assets/images/logo_league_central.webp',
                leagueLabelPrefix: 'セ',
              )
            : centralLeagueBoard(
                leagueId: 2,
                leagueColor: const Color(0xFF4DB5E8),
                logoAsset: 'assets/images/logo_league_pacific.png',
                leagueLabelPrefix: 'パ',
              );

        final Widget portraitTop = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: ALL_SPACE_BLOCK),
            Tabs.tabsBar(
                TAB_TITLES,
                TAB_BAR_H,
                ALL_COLOR_APP,
                TAB_COLOR_FONT,
                TAB_RADIUS,
                ALL_MARGIN_LEFT,
                TAB_PAD_HORIZONTAL,
                TAB_PAD_VERTICAL),
            SizedBox(height: ALL_SPACE_BLOCK),
            _scoreNewsEventsRow(portrait: true),
            _portraitLeagueTabBar(),
            SizedBox(height: ALL_SPACE_BLOCK),
            _portraitContentTabBar(),
            SizedBox(height: ALL_SPACE_BLOCK),
          ],
        );

        final contentKey = ValueKey(
            '$_portraitLeagueTab-$_portraitContentTab');
        final Widget portraitBody = portraitShowPersonal
            ? SizedBox.expand(
                key: contentKey,
                child: selectedPortraitLeague,
              )
            : SingleChildScrollView(
                key: contentKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    selectedPortraitLeague,
                    SizedBox(height: ALL_SPACE_BLOCK),
                  ],
                ),
              );

        final Widget bodyContent = isPortrait
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  portraitTop,
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            for (final child in previousChildren)
                              Positioned.fill(child: child),
                            if (currentChild != null)
                              Positioned.fill(child: currentChild),
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        final isIncoming = child.key == contentKey;
                        final direction = -_portraitSlideDirection.toDouble();
                        final begin = Offset(
                          isIncoming ? direction : -direction,
                          0,
                        );
                        return SlideTransition(
                          position: Tween<Offset>(
                            begin: begin,
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        );
                      },
                      child: portraitBody,
                    ),
                  ),
                  SizedBox(height: ALL_SPACE_BLOCK),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: ALL_SPACE_BLOCK),
                  Tabs.tabsBar(
                      TAB_TITLES,
                      TAB_BAR_H,
                      ALL_COLOR_APP,
                      TAB_COLOR_FONT,
                      TAB_RADIUS,
                      ALL_MARGIN_LEFT,
                      TAB_PAD_HORIZONTAL,
                      TAB_PAD_VERTICAL),
                  SizedBox(height: ALL_SPACE_BLOCK),
                  Expanded(
                    flex: ALL_RATIO_BLOCK_H[0],
                    child: _scoreNewsEventsRow(portrait: false),
                  ),
                  SizedBox(height: ALL_SPACE_BLOCK),
                  Expanded(
                    flex: ALL_RATIO_BLOCK_H[1],
                    child: centralLeagueBoard(
                      leagueId: 1,
                      leagueColor: const Color(0xFF0B8F3A),
                      logoAsset: 'assets/images/logo_league_central.webp',
                      leagueLabelPrefix: 'セ',
                    ),
                  ),
                  SizedBox(height: ALL_SPACE_BLOCK),
                  Expanded(
                    flex: ALL_RATIO_BLOCK_H[1],
                    child: centralLeagueBoard(
                      leagueId: 2,
                      leagueColor: const Color(0xFF4DB5E8),
                      logoAsset: 'assets/images/logo_league_pacific.png',
                      leagueLabelPrefix: 'パ',
                    ),
                  ),
                ],
              );

        // レイアウトを「リーグ×2行、各行に 予想・成績・試合情報」を配置
        return Container(
          alignment: Alignment.topCenter,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: designWidth),
              child: SizedBox(
                height: constraints.maxHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Headers.globalHeader(HEADER_GLOBAL_H, ALL_COLOR_APP,
                        HEADER_TITLE, HEADER_PAD_VERTICAL, ALL_MARGIN_LEFT),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            bottom: ALL_SPACE_BLOCK,
                            left: ALL_MARGIN_LEFT,
                            right: ALL_MARGIN_LEFT),
                        child: bodyContent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
