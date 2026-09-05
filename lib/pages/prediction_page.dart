import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../tools/Env.dart';
import '../tools/app_logger.dart';
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

  // 個人成績の id_user → 表示名
  String _usernameForId(String idUser) => lookupField(npbPlayerStats, 'id_user', idUser, 'username');

  String _userNameFromPredictions(String idUserStr) => lookupField(predictions, 'id_user', idUserStr, 'name_user_last');

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
        logger.w('HTTP ${res.statusCode} body: ${res.body.substring(0, res.body.length.clamp(0, 400))}');
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

  // 上部: Score + News + イベント日程
  Widget _scoreNewsEventsRow() {
    final counts = computeAtariCounts(
      npbPlayerStats: npbPlayerStats,
      npbPlayerStatsActual: npbPlayerStatsActual,
      predictions: predictions,
      standings: standings,
    );
    Widget _scoreBox() {
      final name1 = _userNameFromPredictions('1');
      final name2 = _userNameFromPredictions('2');

      // 予想ブロックの列幅に合わせる: 左(順位56 + 現在 1/3) / 立石 1/3 / 江島 1/3
      // const double rankW = 56; // 予想ブロックの順位列幅
      const double vBorder = 1.0; // 縦ボーダー幅（立石/江島 列の左境界）
      final double gutters = vBorder * 2;
      // final double rem = (width - rankW - gutters).clamp(0, double.infinity);
      // final double eachW = (rem / 3).floorToDouble();
      // final double leftHeaderW = (width - gutters - (eachW * 2)).clamp(0, double.infinity);

      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black45),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  color: Colors.red,
                  alignment: Alignment.center,
                  child: const OneLineShrinkText(
                    'SCORE',
                    baseSize: 35,
                    minSize: 12,
                    weight: FontWeight.bold,
                    align: TextAlign.center,
                    color: Colors.white,
                  ),
                ),
              ),

              // 立石 列（ヘッダー+スコア）
              Container(
                width: PREDICTION_HEADER_PREDICTOR_W,
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.black45, width: vBorder)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 34,
                      color: Colors.red,
                      alignment: Alignment.center,
                      child: OneLineShrinkText(
                        name1,
                        baseSize: 18,
                        minSize: 10,
                        weight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        alignment: Alignment.center,
                        child: OneLineShrinkText(
                          '${counts['1'] ?? 0}',
                          baseSize: 45,
                          minSize: 14,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 江島 列（ヘッダー+スコア）
              Container(
                width: PREDICTION_HEADER_PREDICTOR_W,
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.black45, width: vBorder)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 34,
                      color: Colors.red,
                      alignment: Alignment.center,
                      child: OneLineShrinkText(
                        name2,
                        baseSize: 18,
                        minSize: 10,
                        weight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        alignment: Alignment.center,
                        child: OneLineShrinkText(
                          '${counts['2'] ?? 0}',
                          baseSize: 45,
                          minSize: 14,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget _newsBox() {
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

      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black45),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with embedded 'すべて既読にする'
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('News', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('未読メッセージを一覧表示', style: TextStyle(color: Colors.white, fontSize: 11)),
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
                                constraints: const BoxConstraints(minHeight: tagH),
                                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: parse(n['tag_main_color_back'], Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: OneLineShrinkText(
                                  (n['tag_main_title'] ?? '').toString(),
                                  baseSize: 12,
                                  minSize: 8,
                                  color: parse(n['tag_main_color_font'], Colors.white),
                                  align: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // サブタグ
                              Container(
                                width: tagW,
                                alignment: Alignment.center,
                                constraints: const BoxConstraints(minHeight: tagH),
                                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: parse(n['tag_sub_color_back'], Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: OneLineShrinkText(
                                  (n['tag_sub_title'] ?? '').toString(),
                                  baseSize: 12,
                                  minSize: 8,
                                  color: parse(n['tag_sub_color_font'], Colors.white),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (n['flg_read'] == true) ? Colors.grey : Colors.orange,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  (n['flg_read'] == true) ? '既読' : '未読',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
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

    Widget _eventsBox() {
      final evs = [...events];
      evs.sort((a, b) => (a['date_from_temp'] ?? '').toString().compareTo((b['date_from_temp'] ?? '').toString()));

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

      final content = Container(
        height: 120, // 必要なら調整
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black45),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('イベント日程', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
                    final maxAllowed = constraints.maxWidth - fixedCats - spacing - minDate;
                    if (titleColW > maxAllowed) titleColW = maxAllowed;
                    if (titleColW < 60) titleColW = 60;

                    double dateMaxW = constraints.maxWidth - fixedCats - spacing - titleColW;
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
                                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: parse(e['event_category_color_back'], Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: OneLineShrinkText(
                                    (e['event_category'] ?? '').toString(),
                                    baseSize: 12,
                                    minSize: 8,
                                    color: parse(e['event_category_color_font'], Colors.white),
                                    align: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // サブカテゴリ
                                Container(
                                  width: catW,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: parse(e['event_category_sub_color_back'], Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: OneLineShrinkText(
                                    (e['event_category_sub'] ?? '').toString(),
                                    baseSize: 12,
                                    minSize: 8,
                                    color: parse(e['event_category_sub_color_font'], Colors.white),
                                    align: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // タイトル（最長幅に固定）
                                SizedBox(
                                  width: titleColW,
                                  child: Builder(builder: (context) {
                                    final String title = (e['title_event'] ?? '').toString();
                                    final bool isToday = e['flg_today'] == true;
                                    final double tw = measureTextWidth(title);
                                    final double frac = (tw / titleColW).clamp(0.0, 1.0);
                                    final BoxDecoration? deco = isToday
                                        ? BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.yellowAccent.withOpacity(1.0),
                                                Colors.yellowAccent.withOpacity(1.0),
                                                Colors.yellowAccent.withOpacity(0.0),
                                              ],
                                              stops: [0.0, frac, 1.0],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                            borderRadius: BorderRadius.circular(3),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(children: [
          Expanded(
            flex: ALL_RATIO_BLOCK_W[0] + ALL_RATIO_BLOCK_W[1],
            child: _scoreBox(),
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: ALL_RATIO_BLOCK_W[2],
            child: _newsBox(),
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: ALL_RATIO_BLOCK_W[3],
            child: _eventsBox(),
          ),
        ]);
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

        // レイアウトを「リーグ×2行、各行に 予想・成績・試合情報」を配置
        return Container(
          alignment: Alignment.topCenter,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: designWidth),
              child: Padding(
                padding: EdgeInsets.only(bottom: ALL_SPACE_BLOCK, left: ALL_MARGIN_LEFT, right: ALL_MARGIN_LEFT),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ─────────────────────────────────────────────
                      // ヘッダー（タブ / News / Score / イベント）
                      // ─────────────────────────────────────────────
                      Headers.globalHeader(HEADER_GLOBAL_H, ALL_COLOR_APP, HEADER_TITLE, HEADER_PAD_VERTICAL, ALL_MARGIN_LEFT),
                      SizedBox(height: ALL_SPACE_BLOCK),
                      Tabs.tabsBar(TAB_TITLES, TAB_BAR_H, ALL_COLOR_APP, TAB_COLOR_FONT, TAB_RADIUS, ALL_MARGIN_LEFT, TAB_PAD_HORIZONTAL, TAB_PAD_VERTICAL),
                      SizedBox(height: ALL_SPACE_BLOCK),
                      Expanded(
                        flex: ALL_RATIO_BLOCK_H[0],
                        child: _scoreNewsEventsRow(),
                      ),
                      SizedBox(height: ALL_SPACE_BLOCK),
                      Expanded(
                        flex: ALL_RATIO_BLOCK_H[1],
                        child: LeagueBoardRow(
                          leagueId: 1,
                          leagueColor: const Color(0xFF0B8F3A),
                          logoAsset: 'assets/images/logo_league_central.webp',
                          leagueLabelPrefix: 'セ',
                          predictions: predictions,
                          standings: standings,
                          npbPlayerStats: npbPlayerStats,
                          npbPlayerStatsActual: npbPlayerStatsActual,
                          games: games,
                          usernameForId: _usernameForId,
                          userNameFromPredictions: _userNameFromPredictions,
                          compact: compact,
                        ),
                      ),
                      SizedBox(height: ALL_SPACE_BLOCK),
// 2行目: パ・リーグ（比率 2）
                      Expanded(
                        flex: ALL_RATIO_BLOCK_H[1],
                        child: LeagueBoardRow(
                          leagueId: 2,
                          leagueColor: const Color(0xFF4DB5E8),
                          logoAsset: 'assets/images/logo_league_pacific.png',
                          leagueLabelPrefix: 'パ',
                          predictions: predictions,
                          standings: standings,
                          npbPlayerStats: npbPlayerStats,
                          npbPlayerStatsActual: npbPlayerStatsActual,
                          games: games,
                          usernameForId: _usernameForId,
                          userNameFromPredictions: _userNameFromPredictions,
                          compact: compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
