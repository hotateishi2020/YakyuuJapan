import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'tools/Env.dart';
import 'View/Headers.dart';
import 'View/Tabs.dart';
import 'View/Text.dart';
import 'View/Grid.dart';
import 'View/Border.dart';

final logger = Logger();

//デザイン設定
//全体
final ALL_MARGIN_LEFT = 8.0; //左端のマージン
final ALL_RATIO_BLOCK_H = [3, 11]; //上部ブロック : リーグの高さの比率
final ALL_RATIO_BLOCK_W = [5, 50, 75, 75]; //リーグのサイドヘッダー : 予想ブロック : 成績ブロック : 試合ブロックの比率 = [1, 50, 50]; //リーグのサイドヘッダー : 予想ブロック : 成績ブロックの比率
final ALL_COLOR_APP = Colors.orange.shade200; //アプリの色
final ALL_SPACE_BLOCK = 5.0;
final ALL_CELL_RADIUS_MARGIN = 2.0;
double ALL_WIDTH = 0;

//最上部ヘッダー
final HEADER_GLOBAL_H = 26.0; //最上部ヘッダーの高さ
final HEADER_PAD_VERTICAL = 5.0; //最上部ヘッダーのパディング
final HEADER_TITLE = "Yakyuu! Japan"; //最上部ヘッダーのタイトル

//タブバー
final TAB_BAR_H = 26.0; //タブバーの高さ
final TAB_PAD_HORIZONTAL = 15.0; //タブの水平マージン
final TAB_PAD_VERTICAL = 2.0; //タブの垂直マージン
final TAB_RADIUS = 16.0; //タブの角の丸み
final TAB_TITLES = ['侍', 'MLB', 'NPB', '2軍', '独立', '社会人', '大学', '高校']; //タブのタイトル
final TAB_COLOR_FONT = Colors.white; //タブの文字色

//リーグサイドヘッダー
final LEAGUE_SIDEHEADER_W = 23;

//予想ブロック
final PREDICTION_HEADER_PREDICTOR_W_PCT = 0.06;
final PREDICTION_HEADER_STANDINGS_W = 56;
final PREDICTION_HEADER_PREDICTOR_W = ALL_WIDTH * PREDICTION_HEADER_PREDICTOR_W_PCT;
final PREDICTION_BLOCK_W = LEAGUE_SIDEHEADER_W + PREDICTION_HEADER_STANDINGS_W + ((ALL_WIDTH * PREDICTION_HEADER_PREDICTOR_W_PCT) * 3);

//個人成績
final STATS_PLAYER_RATIO_CELL_BLOCK_W = [1, 1, 5, 2];

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    ALL_WIDTH = MediaQuery.of(context).size.width;
    return MaterialApp(
      title: 'Yakyuu! Japan',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: SafeArea(child: PredictionPage()),
      ),
    );
  }
}

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

  // -1: 昨日 / 0: 今日 / +1: 明日（将来拡張用）
  int _selectedDayOffset = 0;

  // 個人成績の id_user → 表示名
  String _usernameForId(String idUser) {
    final m = npbPlayerStats.firstWhere(
      (e) => '${e['id_user']}' == idUser,
      orElse: () => const {},
    );
    return (m.isNotEmpty ? (m['username'] ?? '—') : '—').toString();
  }

  // チーム順位の id_user → 予想者名
  String _userNameFromPredictions(String idUserStr) {
    final m = predictions.firstWhere(
      (e) => '${e['id_user']}' == idUserStr,
      orElse: () => const {},
    );
    return (m.isNotEmpty ? (m['name_user_last'] ?? '—') : '—').toString();
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
        logger.w('HTTP ${res.statusCode} body: ${res.body.substring(0, res.body.length.clamp(0, 400))}');
        return;
      }

      final map = jsonDecode(res.body) as Map<String, dynamic>;

      // null安全に取り出すヘルパ
      List<Map<String, dynamic>> _listMap(dynamic v) {
        final raw = (v as List?) ?? const [];
        // JSONの各要素がMap<String,dynamic>であることを保証
        return raw.map((e) => (e as Map).map((k, v) => MapEntry('$k', v))).cast<Map<String, dynamic>>().toList();
      }

      // After（stats_playerを使う）
      final users = _listMap(map['predict_team']);
      final npb = _listMap(map['stats_team']);
      final statsPredict = _listMap(map['predict_player']); // 左ブロック（予想）
      final statsActual = _listMap(map['stats_player']); // 中央ブロック（実績）
      final gms = _listMap(map['games']);
      final evts = _listMap(map['events']);
      final notifs = _listMap(map['notification']);

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

  // yyyy-MM-dd 文字列
  String _ymdWithOffset(int offset) {
    final d = DateTime.now().add(Duration(days: offset));
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  // yyyy-MM-dd フォーマット
  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  // 日本語: YYYY年MM月DD日(曜日)
  String _jaDateWithOffset(int offset) {
    final d = DateTime.now().add(Duration(days: offset));
    const youbi = ['月', '火', '水', '木', '金', '土', '日'];
    final wd = youbi[(d.weekday - 1).clamp(0, 6)];
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y年$m月$dd日($wd)';
  }

  // games に含まれる日付の中で最新日を起点にする（なければ今日）
  String _anchorYmdFromGames() {
    DateTime? maxD;
    for (final g in games) {
      final s = (g['date_game']?.toString() ?? '').trim();
      if (s.isEmpty) continue;
      final dt = DateTime.tryParse(s);
      if (dt == null) continue;
      if (maxD == null || dt.isAfter(maxD!)) maxD = dt;
    }
    return maxD == null ? _ymdWithOffset(0) : _ymd(maxD!);
  }

  // flg_atari の合計（予想者のみ: id_user 1/2、セ+パ合算）
  Map<String, int> _atariCounts() {
    final counts = <String, int>{'1': 0, '2': 0};

    // 個人成績（予想・実績）の的中
    void addFromPlayer(List<Map<String, dynamic>> src) {
      for (final r in src) {
        final id = '${r['id_user'] ?? ''}';
        if (!counts.containsKey(id)) continue; // 1 or 2 のみ
        if (r['flg_atari'] == true) counts[id] = (counts[id] ?? 0) + 1;
      }
    }

    addFromPlayer(npbPlayerStats);
    addFromPlayer(npbPlayerStatsActual);

    // チーム順位の的中（現在と予想の一致）
    bool _teamHit(Map<String, dynamic>? pred, List<Map<String, dynamic>> curGroup) {
      if (pred == null || pred.isEmpty || curGroup.isEmpty) return false;
      final int prdId = int.tryParse('${pred['id_team']}') ?? -1;
      final String prdName = (pred['name_team_short']?.toString() ?? pred['name_team']?.toString() ?? '').trim();
      for (final cur in curGroup) {
        final int curId = int.tryParse('${cur['id_team']}') ?? -1;
        final String curName = (cur['name_team']?.toString() ?? '').trim();
        if ((prdId >= 0 && curId >= 0 && prdId == curId) || (prdName.isNotEmpty && curName == prdName)) {
          return true;
        }
      }
      return false;
    }

    for (final leagueId in [1, 2]) {
      final curRows = standings.where((e) => int.tryParse('${e['id_league']}') == leagueId).toList();
      final pred1 = predictions.where((e) => '${e['id_user']}' == '1' && (int.tryParse('${e['id_league']}') ?? 0) == leagueId).toList();
      final pred2 = predictions.where((e) => '${e['id_user']}' == '2' && (int.tryParse('${e['id_league']}') ?? 0) == leagueId).toList();
      for (int rk = 1; rk <= 6; rk++) {
        final curGroup = curRows.where((e) => int.tryParse('${e['int_rank']}') == rk).toList();
        final p1 = pred1.firstWhere((e) => int.tryParse('${e['int_rank']}') == rk, orElse: () => {});
        final p2 = pred2.firstWhere((e) => int.tryParse('${e['int_rank']}') == rk, orElse: () => {});
        if (_teamHit(p1.isNotEmpty ? p1 : null, curGroup)) counts['1'] = (counts['1'] ?? 0) + 1;
        if (_teamHit(p2.isNotEmpty ? p2 : null, curGroup)) counts['2'] = (counts['2'] ?? 0) + 1;
      }
    }

    return counts;
  }

  // 上部: Score + News + イベント日程
  Widget _scoreNewsEventsRow() {
    final counts = _atariCounts();
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
                                      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
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

  Widget _scoreNumber(int n) {
    return Container(
      width: 64,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black45),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$n', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
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
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // サイドヘッダー（リーグ名）
                            Expanded(
                              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Expanded(
                                    flex: ALL_RATIO_BLOCK_W[0],
                                    child: Container(
                                      // width: 36,
                                      margin: const EdgeInsets.only(right: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0B8F3A),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4, bottom: 4),
                                              child: Image.asset(
                                                'assets/images/logo_league_central.webp',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) => const SizedBox(height: 20),
                                              ),
                                            ),
                                            const Text('セ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            const Text('・', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            const Text('リ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            const Text('|', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            const Text('グ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    )),
                                Expanded(
                                  flex: ALL_RATIO_BLOCK_W[1],
                                  child: UnifiedGrid(
                                    predictions: predictions,
                                    standings: standings,
                                    npbPlayerStats: npbPlayerStats,
                                    usernameForId: _usernameForId,
                                    userNameFromPredictions: _userNameFromPredictions,
                                    compact: compact,
                                    onlyLeagueId: 1,
                                  ),
                                ),
                                // const VerticalDivider(width: 8, thickness: 0.0),
                                SizedBox(width: ALL_SPACE_BLOCK),
                                Expanded(
                                  flex: ALL_RATIO_BLOCK_W[2],
                                  child: SeasonTableBlock(
                                    standings: standings,
                                    stats: npbPlayerStatsActual,
                                    onlyLeagueId: 1,
                                  ),
                                ),
                                SizedBox(width: ALL_SPACE_BLOCK),
                                Expanded(
                                  flex: ALL_RATIO_BLOCK_W[3],
                                  child: Row(children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            alignment: Alignment.center,
                                            margin: const EdgeInsets.symmetric(horizontal: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0B8F3A),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text('昨日  ${_jaDateWithOffset(-1)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 340,
                                            child: GamesBoardYahooStyle(
                                              games: games.where((g) => (int.tryParse('${g['id_league_home']}') ?? 0) == 1 && (int.tryParse('${g['id_league_away']}') ?? 0) == 1).toList(),
                                              dateFilter: _ymdWithOffset(-1),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    SizedBox(
                                      width: 1,
                                      child: Container(
                                        color: Colors.black26,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            alignment: Alignment.center,
                                            margin: const EdgeInsets.symmetric(horizontal: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0B8F3A),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text('今日  ${_jaDateWithOffset(0)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 340,
                                            child: GamesBoardYahooStyle(
                                              games: games.where((g) => (int.tryParse('${g['id_league_home']}') ?? 0) == 1 && (int.tryParse('${g['id_league_away']}') ?? 0) == 1).toList(),
                                              dateFilter: _ymdWithOffset(0),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    SizedBox(
                                      width: 1,
                                      child: Container(
                                        color: Colors.black26,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            alignment: Alignment.center,
                                            margin: const EdgeInsets.symmetric(horizontal: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0B8F3A),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text('明日  ${_jaDateWithOffset(1)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 340,
                                            child: GamesBoardYahooStyle(
                                              games: games.where((g) => (int.tryParse('${g['id_league_home']}') ?? 0) == 1 && (int.tryParse('${g['id_league_away']}') ?? 0) == 1).toList(),
                                              dateFilter: _ymdWithOffset(1),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ]),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: ALL_SPACE_BLOCK),
                      // 2行目: パ・リーグ（比率 2）
                      Expanded(
                        flex: ALL_RATIO_BLOCK_H[1],
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // サイドヘッダー（リーグ名）
                            Container(
                              width: 36,
                              margin: const EdgeInsets.only(left: 0, right: 0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4DB5E8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                                      child: Image.asset(
                                        'assets/images/logo_league_pacific.png',
                                        width: 22,
                                        height: 22,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const SizedBox(height: 22),
                                      ),
                                    ),
                                    const Text('パ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const Text('・', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const Text('リ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const Text('|', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const Text('グ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Expanded(
                                  flex: 2,
                                  child: UnifiedGrid(
                                    predictions: predictions,
                                    standings: standings,
                                    npbPlayerStats: npbPlayerStats,
                                    usernameForId: _usernameForId,
                                    userNameFromPredictions: _userNameFromPredictions,
                                    compact: compact,
                                    onlyLeagueId: 2,
                                  ),
                                ),
                                const VerticalDivider(width: 8, thickness: 0.5),
                                Expanded(
                                  flex: 3,
                                  child: SeasonTableBlock(
                                    standings: standings,
                                    stats: npbPlayerStatsActual,
                                    onlyLeagueId: 2,
                                  ),
                                ),
                                const VerticalDivider(width: 8, thickness: 0.5),
                                Expanded(
                                  flex: 3,
                                  child: Row(children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            alignment: Alignment.center,
                                            margin: const EdgeInsets.symmetric(horizontal: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4DB5E8),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text('昨日  ${_jaDateWithOffset(-1)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 340,
                                            child: GamesBoardYahooStyle(
                                              games: games.where((g) => (int.tryParse('${g['id_league_home']}') ?? 0) == 2 && (int.tryParse('${g['id_league_away']}') ?? 0) == 2).toList(),
                                              dateFilter: _ymdWithOffset(-1),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    SizedBox(
                                      width: 1,
                                      child: Container(
                                        color: Colors.black26,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            alignment: Alignment.center,
                                            margin: const EdgeInsets.symmetric(horizontal: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4DB5E8),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text('今日  ${_jaDateWithOffset(0)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 340,
                                            child: GamesBoardYahooStyle(
                                              games: games.where((g) => (int.tryParse('${g['id_league_home']}') ?? 0) == 2 && (int.tryParse('${g['id_league_away']}') ?? 0) == 2).toList(),
                                              dateFilter: _ymdWithOffset(0),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            alignment: Alignment.center,
                                            margin: const EdgeInsets.symmetric(horizontal: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4DB5E8),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text('明日  ${_jaDateWithOffset(1)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 340,
                                            child: GamesBoardYahooStyle(
                                              games: games.where((g) => (int.tryParse('${g['id_league_home']}') ?? 0) == 2 && (int.tryParse('${g['id_league_away']}') ?? 0) == 2).toList(),
                                              dateFilter: _ymdWithOffset(1),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ]),
                                ),
                              ]),
                            ),
                          ],
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

/// 昨日 / 今日 / 明日 切替
class _DaySwitcher extends StatelessWidget {
  final int selectedOffset; // -1, 0, +1
  final ValueChanged<int> onChanged;

  const _DaySwitcher({
    super.key,
    required this.selectedOffset,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, int value) {
      final selected = selectedOffset == value;
      return Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 6),
            side: BorderSide(
              color: selected ? Colors.deepPurple : Colors.grey.shade300,
              width: selected ? 1.5 : 1,
            ),
            backgroundColor: selected ? Colors.deepPurple.withOpacity(0.06) : null,
          ),
          onPressed: () => onChanged(value),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Colors.deepPurple : null,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn('昨日', -1),
        const SizedBox(width: 6),
        btn('今日', 0),
        const SizedBox(width: 6),
        btn('明日', 1),
      ],
    );
  }
}

/// セル幅に合わせて1行自動縮小（省略記号なし）

/// 右ペイン：スコア状況（JSONはすべて文字列で扱う）
class GamesBoardYahooStyle extends StatelessWidget {
  final List<Map<String, dynamic>> games;
  final String? dateFilter; // "YYYY-MM-DD"

  const GamesBoardYahooStyle({
    super.key,
    required this.games,
    this.dateFilter,
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
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(child: g0 != null ? _GameCard(g0) : const SizedBox()),
              const SizedBox(height: 2),
              Expanded(child: g1 != null ? _GameCard(g1) : const SizedBox()),
              const SizedBox(height: 2),
              Expanded(child: g2 != null ? _GameCard(g2) : const SizedBox()),
            ],
          ),
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
      final double teamNameW = (c.maxWidth.isFinite ? c.maxWidth : 300.0) * 2.0 / 5.0;

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
      final double badgeD = (_rowH * 0.82).clamp(12.0, 24.0);
      final double rowFont = (_rowH * 0.52).clamp(9.0, 16.0);

      // 勝敗・S用の丸バッジ（中央表示）: 行フォントに合わせる
      Widget _badge(String label, Color bg, double d) {
        return Container(
          width: d,
          height: d,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: rowFont)),
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
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: OneLineShrinkText(_win, baseSize: baseSmall + 2, minSize: 7, color: homeNameFg ?? Colors.black87, align: TextAlign.left),
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
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: OneLineShrinkText(_lose, baseSize: baseSmall + 2, minSize: 7, color: homeNameFg ?? Colors.black87, align: TextAlign.left),
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
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: OneLineShrinkText(_save, baseSize: baseSmall + 2, minSize: 7, color: homeNameFg ?? Colors.black87, align: TextAlign.left),
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

  Color? _colorFrom(String? name) {
    final raw = (name ?? '').trim();
    if (raw.isEmpty) return null;
    final n = raw.toLowerCase();
    // hex (#RRGGBB or #AARRGGBB or 0xAARRGGBB)
    String hex = n;
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.startsWith('0x')) hex = hex.substring(2);
    if (RegExp(r'^[0-9a-f]{6} ?$', caseSensitive: false).hasMatch(hex)) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    if (RegExp(r'^[0-9a-f]{8} ?$', caseSensitive: false).hasMatch(hex)) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(v);
    }
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

    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          // 背景（固定: 単色 or グラデ）
          if (deco != null)
            Positioned.fill(
              child: Container(decoration: deco),
            ),
          // 点滅オーバーレイ（背景の上、テキストの下）
          if (firstBlinkColor != null)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _t,
                builder: (context, _) {
                  final double bgAlpha = (0.12 + 0.23 * _t.value).clamp(0.0, 1.0).toDouble();
                  return Container(
                    decoration: BoxDecoration(
                      color: firstBlinkColor!.withOpacity(bgAlpha),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                },
              ),
            ),
          // テキスト
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            alignment: Alignment.center,
            child: OneLineShrinkText(
              widget.name,
              baseSize: widget.baseSize,
              minSize: 7,
              color: textColor,
              weight: weight,
              align: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// 背景のみをやさしく点滅させる（テキストは前面で固定）
class _BlinkBg extends StatefulWidget {
  final Widget child;
  final BoxDecoration base;
  final Color color; // 点滅色（上に重ねる色）
  final double radius;
  final Duration duration;

  const _BlinkBg({
    super.key,
    required this.child,
    required this.base,
    required this.color,
    this.radius = 4,
    this.duration = const Duration(milliseconds: 1000),
  });

  @override
  State<_BlinkBg> createState() => _BlinkBgState();
}

class _BlinkBgState extends State<_BlinkBg> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final double a = (0.12 + 0.23 * _t.value).clamp(0.0, 1.0);
        return Stack(children: [
          // ベース背景（単色/グラデ）
          Positioned.fill(child: Container(decoration: widget.base)),
          // 点滅オーバーレイ
          Positioned.fill(
              child: Container(
                  decoration: BoxDecoration(
            color: widget.color.withOpacity(a),
            borderRadius: BorderRadius.circular(widget.radius),
          ))),
          // 子（テキストなど）
          child!,
        ]);
      },
      child: widget.child,
    );
  }
}

class SeasonTableBlock extends StatelessWidget {
  final List<Map<String, dynamic>> standings;
  final List<Map<String, dynamic>> stats;
  final int? onlyLeagueId; // 1: セ, 2: パ, null: 両方

  const SeasonTableBlock({
    super.key,
    required this.standings,
    required this.stats,
    this.onlyLeagueId,
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
      // rank は「表示行のインデックス(1..5)」。同順位がある場合も
      // タイトルごとに int_rank 昇順で並べた上位5件から rank 番目を表示する。
      Widget _entryCell(List<Map<String, dynamic>> src, String title, int rank) {
        final list = src.where((m) => (m['title']?.toString() ?? '') == _normalizeTitle(title)).toList()..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 1 << 30).compareTo(int.tryParse('${b['int_rank']}') ?? 1 << 30));
        final idx = (rank - 1).clamp(0, list.isNotEmpty ? list.length - 1 : 0);
        final Map<String, dynamic> e = list.isNotEmpty && list.length >= rank ? list[idx] : const {};

        final rankText = (e.isNotEmpty ? (e['int_rank']?.toString() ?? '') : '').toString();
        final team = (e.isNotEmpty ? (e['name_team'] ?? '') : '').toString();
        final name = (e.isNotEmpty ? (e['name_player'] ?? '') : '').toString();
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
                      final isOne = rankText.trim() == '1';
                      if (isOne) {
                        return const FittedBox(
                          fit: BoxFit.contain,
                          child: Text('👑',
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
      Widget _entryCellFromRow(Map<String, dynamic> e) {
        final rankText = (e['int_rank']?.toString() ?? '').toString();
        final team = (e['name_team'] ?? '').toString();
        final name = (e['name_player'] ?? '').toString();
        final stat = _num(e['stats']);

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

        return SizedBox(
          width: parentWidth * 0.2,
          child: Container(
            height: 17.5,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26, width: 1),
            ),
            // padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(children: [
              Expanded(
                  flex: 2,
                  child: Center(
                    child: () {
                      final isOne = rankText.trim() == '1';
                      if (isOne) {
                        return const FittedBox(
                          fit: BoxFit.contain,
                          child: Text('👑',
                              style: TextStyle(
                                fontSize: 20,
                                height: 1.0,
                              )),
                        );
                      }
                      return OneLineShrinkText(rankText.isNotEmpty ? rankText : '—', baseSize: 12, minSize: 1, fast: true);
                    }(),
                  )),
              Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _parseColorName(e['color_back']),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    alignment: Alignment.center,
                    child: OneLineShrinkText(team, baseSize: 12, minSize: 1, fast: true, color: _parseColorName(e['color_font'])),
                  )),
              Expanded(
                  flex: 10,
                  child: (() {
                    final BoxDecoration? d = _nameBgDecorationFromRow();
                    final bool hasBg = d != null;
                    final bool isToday = e['flg_today'] == true;
                    final Widget txt = OneLineShrinkText(name, baseSize: 12, minSize: 1, fast: true, color: hasBg ? Colors.white : null, weight: hasBg ? FontWeight.bold : null);
                    if (isToday) {
                      return _BlinkBg(
                        base: d ?? BoxDecoration(borderRadius: BorderRadius.circular(4)),
                        color: const Color(0xFFFFF176),
                        radius: 4,
                        duration: const Duration(milliseconds: 1000),
                        child: Align(alignment: Alignment.center, child: txt),
                      );
                    }
                    return Container(
                      decoration: d,
                      alignment: Alignment.center,
                      child: txt,
                    );
                  }())),
              Expanded(flex: 4, child: OneLineShrinkText(stat, baseSize: 12, minSize: 1, fast: true)),
            ]),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 個人成績 見出しは非表示
          // 緑: リーグ名（非表示）
          // 打撃（見出し+本文を同一スクロールで横スクロール）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in battingCols)
                SizedBox(
                  width: parentWidth * 0.2,
                  child: Column(children: [
                    _gridCell(t, bg: const Color(0xFFE57373), fg: Colors.white, weight: FontWeight.bold, h: 20),
                    SizedBox(
                      height: 17.5 * 5,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final e in (bat.where((m) => (m['title']?.toString() ?? '') == t).toList()..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 1 << 30).compareTo(int.tryParse('${b['int_rank']}') ?? 1 << 30)))) _entryCellFromRow(e),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
          // 投手（見出し+本文を同一スクロールで横スクロール）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in pitchingCols)
                SizedBox(
                  width: parentWidth * 0.2,
                  child: Column(children: [
                    _gridCell(t, bg: const Color(0xFF64B5F6), fg: Colors.white, weight: FontWeight.bold, h: 20),
                    SizedBox(
                      height: 17.5 * 5,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final e in (pit.where((m) => (m['title']?.toString() ?? '') == t || (_normalizeTitle((m['title'] ?? '').toString()) == _normalizeTitle(t))).toList()..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 1 << 30).compareTo(int.tryParse('${b['int_rank']}') ?? 1 << 30)))) _entryCellFromRow(e),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ],
      );
    }

    // スクロール分離: チーム順位は専用の横スクロール、個人成績は別
    final double _standingsWidth = _wChar2 + _wChar6 + _wChar3 * 14; // 列数: 試合/勝/負/分/勝差/勝率/打率/本塁打/打点/盗塁/防御率(総合/先発/救援)/守備率
    final hStatsTeamHeader = 33.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // リーグ見出し（非表示）

        // チーム順位（親幅に合わせ可変／不足時のみ横スクロール）
        LayoutBuilder(builder: (context, lb) {
          final double minNameW = _wChar6; // チーム名の最小幅
          final double fixed = _wChar2 + // 順位
              _wChar2 + // 試合
              _wChar1 +
              _wChar1 +
              _wChar1 + // 勝/負/分
              _wChar2 + // 勝差
              _wChar3 + // 勝率
              _wChar2 + // 打率
              _wChar3 + // 本塁打
              _wChar2 + // 打点
              _wChar2 + // 盗塁
              _wChar3 + // 失策率
              _wChar2 * 3; // 防御率(総合/先発/救援)
          final double parentW = lb.maxWidth.isFinite ? lb.maxWidth : _standingsWidth;
          final double tableW = (fixed + minNameW) > parentW ? (fixed + minNameW) : parentW;
          final double wName = tableW - fixed;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー（非防御率は縦結合、防御率のみ二段）
                  Row(children: [
                    SizedBox(width: _wChar2, child: _gridCell('順位', h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white, weight: FontWeight.bold)),
                    SizedBox(width: wName, child: _gridCell('チーム', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),
                    SizedBox(width: _wChar2, child: _gridCell('試合', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),
                    SizedBox(width: _wChar1, child: _gridCell('勝', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),
                    SizedBox(width: _wChar1, child: _gridCell('負', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),
                    SizedBox(width: _wChar1, child: _gridCell('分', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),
                    SizedBox(width: _wChar2, child: _gridCell('勝差', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),
                    SizedBox(width: _wChar3, child: _gridCell('勝率', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),
                    SizedBox(width: _wChar2, child: _gridCell('打率', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),
                    SizedBox(width: _wChar3, child: _gridCell('本塁打', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),
                    SizedBox(width: _wChar2, child: _gridCell('打点', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),
                    SizedBox(width: _wChar2, child: _gridCell('盗塁', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),

                    SizedBox(width: _wChar3, child: _gridCell('失策率', weight: FontWeight.bold, h: hStatsTeamHeader, bg: leagueColor, fg: Colors.white)),

                    // 防御率ブロック（上: 見出し、下: 総合/先発/救援）
                    SizedBox(
                      width: _wChar2 * 3,
                      child: Column(children: [
                        _gridCell('防御率', weight: FontWeight.bold, h: hStatsTeamHeader / 2, bg: leagueColor, fg: Colors.white),
                        Row(children: [
                          SizedBox(width: _wChar2, child: _gridCell('総合', weight: FontWeight.bold, h: hStatsTeamHeader / 2, bg: leagueColor, fg: Colors.white, align: TextAlign.center)),
                          SizedBox(width: _wChar2, child: _gridCell('先発', weight: FontWeight.bold, h: hStatsTeamHeader / 2, bg: leagueColor, fg: Colors.white, align: TextAlign.center)),
                          SizedBox(width: _wChar2, child: _gridCell('救援', weight: FontWeight.bold, h: hStatsTeamHeader / 2, bg: leagueColor, fg: Colors.white, align: TextAlign.center)),
                        ]),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 0),

                  // 本文 1..6
                  for (int rk = 1; rk <= 6; rk++)
                    () {
                      final row = cur.firstWhere((e) => int.tryParse('${e['int_rank']}') == rk, orElse: () => const {});
                      final Color? teamBg = _parseColorName(row['color_back']);
                      final Color? teamFg = _parseColorName(row['color_font']);
                      // 右側（チーム名より右）のセル背景は縞模様（奇数: 白 / 偶数: 薄いベージュ）
                      final Color? paleBg = (rk % 2 == 0) ? const Color(0xFFEAD9B9) : Colors.white;

                      // トップ/ワースト強調色
                      Color? _topColor(bool cond) => cond ? const Color(0xFF32CD32) : null; // limegreen
                      Color? _worstColor(bool cond) => cond ? Colors.red : null;

                      // 指標ごとのフラグ判定
                      final bool topBat = row['flg_top_num_avg_batting'] == true;
                      final bool worstBat = row['flg_worst_num_avg_batting'] == true;
                      final Color? fgBat = _topColor(topBat) ?? _worstColor(worstBat);
                      final FontWeight? wtBat = (topBat || worstBat) ? FontWeight.bold : null;

                      final bool topHr = row['flg_top_int_homerun'] == true;
                      final bool worstHr = row['flg_worst_int_homerun'] == true;
                      final Color? fgHr = _topColor(topHr) ?? _worstColor(worstHr);
                      final FontWeight? wtHr = (topHr || worstHr) ? FontWeight.bold : null;

                      final bool topRbi = row['flg_top_int_rbi'] == true;
                      final bool worstRbi = row['flg_worst_int_rbi'] == true;
                      final Color? fgRbi = _topColor(topRbi) ?? _worstColor(worstRbi);
                      final FontWeight? wtRbi = (topRbi || worstRbi) ? FontWeight.bold : null;

                      final bool topSb = row['flg_top_int_sh'] == true;
                      final bool worstSb = row['flg_worst_int_sh'] == true;
                      final Color? fgSb = _topColor(topSb) ?? _worstColor(worstSb);
                      final FontWeight? wtSb = (topSb || worstSb) ? FontWeight.bold : null;

                      final bool topFld = row['flg_top_num_avg_fielding'] == true;
                      final bool worstFld = row['flg_worst_num_avg_fielding'] == true;
                      final Color? fgFld = _topColor(topFld) ?? _worstColor(worstFld);
                      final FontWeight? wtFld = (topFld || worstFld) ? FontWeight.bold : null;

                      final bool topEraT = row['flg_top_num_era_total'] == true;
                      final bool worstEraT = row['flg_worst_num_era_total'] == true;
                      final Color? fgEraT = _topColor(topEraT) ?? _worstColor(worstEraT);
                      final FontWeight? wtEraT = (topEraT || worstEraT) ? FontWeight.bold : null;

                      final bool topEraS = row['flg_top_num_era_starter'] == true;
                      final bool worstEraS = row['flg_worst_num_era_starter'] == true;
                      final Color? fgEraS = _topColor(topEraS) ?? _worstColor(worstEraS);
                      final FontWeight? wtEraS = (topEraS || worstEraS) ? FontWeight.bold : null;

                      final bool topEraR = row['flg_top_num_era_relief'] == true;
                      final bool worstEraR = row['flg_worst_num_era_relief'] == true;
                      final Color? fgEraR = _topColor(topEraR) ?? _worstColor(worstEraR);
                      final FontWeight? wtEraR = (topEraR || worstEraR) ? FontWeight.bold : null;

                      const double _gridBodyH = 20.0;
                      return Row(children: [
                        SizedBox(width: _wChar2, child: _gridCell('$rk', h: _gridBodyH, bg: leagueColor, fg: Colors.white, weight: FontWeight.bold)),
                        SizedBox(width: wName, child: _gridCell(_num(row['name_team']), h: _gridBodyH, bg: teamBg, fg: teamFg)),
                        SizedBox(width: _wChar2, child: _gridCell(_num(row['int_game']), h: _gridBodyH, bg: paleBg)),
                        SizedBox(width: _wChar1, child: _gridCell(_num(row['int_win']), h: _gridBodyH, bg: paleBg)),
                        SizedBox(width: _wChar1, child: _gridCell(_num(row['int_lose']), h: _gridBodyH, bg: paleBg)),
                        SizedBox(width: _wChar1, child: _gridCell(_num(row['int_draw']), h: _gridBodyH, bg: paleBg)),
                        SizedBox(width: _wChar2, child: _gridCell(_num(row['game_behind']), h: _gridBodyH, bg: paleBg)),
                        SizedBox(width: _wChar3, child: _gridCell(_num(row['pct_win']), h: _gridBodyH, bg: paleBg)),
                        SizedBox(width: _wChar2, child: _gridCell(_num(row['num_avg_batting']), h: _gridBodyH, bg: paleBg, fg: fgBat, weight: wtBat)),
                        SizedBox(width: _wChar3, child: _gridCell(_num(row['int_homerun']), h: _gridBodyH, bg: paleBg, fg: fgHr, weight: wtHr)),
                        SizedBox(width: _wChar2, child: _gridCell(_num(row['int_rbi']), h: _gridBodyH, bg: paleBg, fg: fgRbi, weight: wtRbi)),
                        SizedBox(width: _wChar2, child: _gridCell(_num(row['int_sh']), h: _gridBodyH, bg: paleBg, fg: fgSb, weight: wtSb)),
                        SizedBox(width: _wChar3, child: _gridCell(_num(row['num_avg_fielding']), h: _gridBodyH, bg: paleBg, fg: fgFld, weight: wtFld)),
                        SizedBox(width: _wChar2, child: _gridCell(_num(row['num_era_total']), h: _gridBodyH, bg: paleBg, fg: fgEraT, weight: wtEraT)),
                        SizedBox(width: _wChar2, child: _gridCell(_num(row['num_era_starter']), h: _gridBodyH, bg: paleBg, fg: fgEraS, weight: wtEraS)),
                        SizedBox(width: _wChar2, child: _gridCell(_num(row['num_era_relief']), h: _gridBodyH, bg: paleBg, fg: fgEraR, weight: wtEraR)),
                      ]);
                    }(),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 2),

        // 個人成績（独立: 内部で横スクロールを制御）
        LayoutBuilder(builder: (context, lb) {
          final double centralW = lb.maxWidth.isFinite ? lb.maxWidth : 0;
          return _personalStatsSheet(leagueId, bat, pit, centralW);
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              children: onlyLeagueId == null
                  ? [
                      _leagueTable(1), // セ
                      // _leagueTable(2), // パ
                    ]
                  : [
                      _leagueTable(onlyLeagueId!),
                    ],
            ),
          ),
        ),
      ),
    );
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
