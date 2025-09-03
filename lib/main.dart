import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'tools/Env.dart';

final logger = Logger();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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
        logger.w(
            'HTTP ${res.statusCode} body: ${res.body.substring(0, res.body.length.clamp(0, 400))}');
        return;
      }

      final map = jsonDecode(res.body) as Map<String, dynamic>;

      // null安全に取り出すヘルパ
      List<Map<String, dynamic>> _listMap(dynamic v) {
        final raw = (v as List?) ?? const [];
        // JSONの各要素がMap<String,dynamic>であることを保証
        return raw
            .map((e) => (e as Map).map((k, v) => MapEntry('$k', v)))
            .cast<Map<String, dynamic>>()
            .toList();
      }

      // After（stats_playerを使う）
      final users = _listMap(map['predict_team']);
      final npb = _listMap(map['stats_team']);
      final statsPredict = _listMap(map['predict_player']); // 左ブロック（予想）
      final statsActual = _listMap(map['stats_player']); // 中央ブロック（実績）
      final gms = _listMap(map['games']);
      final evts = _listMap(map['events']);

      setState(() {
        predictions = users;
        standings = npb;
        npbPlayerStats = statsPredict; // 左
        npbPlayerStatsActual = statsActual; // 中央
        games = gms;
        events = evts;
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
    bool _teamHit(
        Map<String, dynamic>? pred, List<Map<String, dynamic>> curGroup) {
      if (pred == null || pred.isEmpty || curGroup.isEmpty) return false;
      final int prdId = int.tryParse('${pred['id_team']}') ?? -1;
      final String prdName = (pred['name_team_short']?.toString() ??
              pred['name_team']?.toString() ??
              '')
          .trim();
      for (final cur in curGroup) {
        final int curId = int.tryParse('${cur['id_team']}') ?? -1;
        final String curName = (cur['name_team']?.toString() ?? '').trim();
        if ((prdId >= 0 && curId >= 0 && prdId == curId) ||
            (prdName.isNotEmpty && curName == prdName)) {
          return true;
        }
      }
      return false;
    }

    for (final leagueId in [1, 2]) {
      final curRows = standings
          .where((e) => int.tryParse('${e['id_league']}') == leagueId)
          .toList();
      final pred1 = predictions
          .where((e) =>
              '${e['id_user']}' == '1' &&
              (int.tryParse('${e['id_league']}') ?? 0) == leagueId)
          .toList();
      final pred2 = predictions
          .where((e) =>
              '${e['id_user']}' == '2' &&
              (int.tryParse('${e['id_league']}') ?? 0) == leagueId)
          .toList();
      for (int rk = 1; rk <= 6; rk++) {
        final curGroup = curRows
            .where((e) => int.tryParse('${e['int_rank']}') == rk)
            .toList();
        final p1 = pred1.firstWhere(
            (e) => int.tryParse('${e['int_rank']}') == rk,
            orElse: () => {});
        final p2 = pred2.firstWhere(
            (e) => int.tryParse('${e['int_rank']}') == rk,
            orElse: () => {});
        if (_teamHit(p1.isNotEmpty ? p1 : null, curGroup))
          counts['1'] = (counts['1'] ?? 0) + 1;
        if (_teamHit(p2.isNotEmpty ? p2 : null, curGroup))
          counts['2'] = (counts['2'] ?? 0) + 1;
      }
    }

    return counts;
  }

  // 画面上部: 全体ヘッダー
  Widget _globalHeader() {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: Colors.orange.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 8),
      child: const Text('Yakyuu! Japan',
          style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  // 画面切替タブ（ダミー表示）
  Widget _tabsBar() {
    final tabs = ['侍', 'MLB', 'NPB', '2軍', '独立', '社会人', '大学/高校'];
    return SizedBox(
      height: 28,
      child: Row(children: [
        for (final t in tabs) ...[
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.orange.shade300,
                borderRadius: BorderRadius.circular(4)),
            child: Text(t, style: const TextStyle(fontSize: 12)),
          ),
        ]
      ]),
    );
  }

  // 上部: Score + News + イベント日程
  Widget _scoreNewsEventsRow() {
    final counts = _atariCounts();
    Widget _scoreBox(double width) {
      final name1 = _userNameFromPredictions('1');
      final name2 = _userNameFromPredictions('2');

      // 予想ブロックの列幅に合わせる: 左(順位56 + 現在 1/3) / 立石 1/3 / 江島 1/3
      const double rankW = 56; // 予想ブロックの順位列幅
      const double vBorder = 1.0; // 縦ボーダー幅（立石/江島 列の左境界）
      final double gutters = vBorder * 2;
      final double rem = (width - rankW - gutters).clamp(0, double.infinity);
      final double eachW = (rem / 3).floorToDouble();
      final double leftHeaderW =
          (width - gutters - (eachW * 2)).clamp(0, double.infinity);

      return SizedBox(
        width: width,
        height: 120,
        child: ClipRRect(
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
                // 左: SCORE（順位+現在の幅に合わせる）
                Container(
                  width: leftHeaderW,
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

                // 立石 列（ヘッダー+スコア）
                Container(
                  width: eachW,
                  decoration: const BoxDecoration(
                    border: Border(
                        left:
                            BorderSide(color: Colors.black45, width: vBorder)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 36,
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
                  width: eachW,
                  decoration: const BoxDecoration(
                    border: Border(
                        left:
                            BorderSide(color: Colors.black45, width: vBorder)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 36,
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
        ),
      );
    }

    Widget _newsBox() {
      return Expanded(
        child: Container(
          height: 120,
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black45),
              borderRadius: BorderRadius.circular(4)),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: double.infinity,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('News',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: const [
                        Divider(height: 1),
                        SizedBox(height: 4),
                        Text('・News ------------------------------',
                            style: TextStyle(fontSize: 12)),
                        Text('・News ------------------------------',
                            style: TextStyle(fontSize: 12)),
                        Text('・News ------------------------------',
                            style: TextStyle(fontSize: 12)),
                        Text('・News ------------------------------',
                            style: TextStyle(fontSize: 12)),
                        Text('・News ------------------------------',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget _eventsBox({double? width}) {
      final evs = [...events];
      evs.sort((a, b) => (a['date_from_temp'] ?? '')
          .toString()
          .compareTo((b['date_from_temp'] ?? '').toString()));

      Color parse(String? name, Color fallback) {
        final n = (name ?? '').toLowerCase().trim();
        const m = {
          'red': 0xFFF44336,
          'green': 0xFF4CAF50,
          'blue': 0xFF2196F3,
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
                                  child: OneLineShrinkText(
                                    (e['title_event'] ?? '').toString(),
                                    baseSize: 12,
                                    minSize: 8,
                                    align: TextAlign.left,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                // 日付（左詰め・最小/最大幅内で縮小）
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                      minWidth: minDate, maxWidth: dateMaxW),
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
                  },
                ),
              ),
            ),
          ],
        ),
      );

      return width != null
          ? SizedBox(width: width, child: content)
          : Expanded(child: content);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalW = constraints.maxWidth;
        const double gamesFraction = 3 / 8;
        const double predFraction = 2 / 8;
        final double eventsW = totalW * gamesFraction;
        final double scoreW = totalW * predFraction;
        return Row(children: [
          _scoreBox(scoreW),
          const SizedBox(width: 8),
          _newsBox(),
          const SizedBox(width: 8),
          _eventsBox(width: eventsW),
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
      child: Text('$n',
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
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
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ─────────────────────────────────────────────
                      // ヘッダー（タブ / News / Score / イベント）
                      // ─────────────────────────────────────────────
                      _globalHeader(),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _tabsBar(),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        flex: 6,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _scoreNewsEventsRow(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 1行目: セ・リーグ（比率 2）
                      Expanded(
                        flex: 17,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // サイドヘッダー（リーグ名）
                            Container(
                              width: 36,
                              margin: const EdgeInsets.only(left: 4, right: 0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7CB342),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('セ',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    Text('・',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    Text('リ',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    Text('|',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    Text('グ',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _UnifiedGrid(
                                        predictions: predictions,
                                        standings: standings,
                                        npbPlayerStats: npbPlayerStats,
                                        usernameForId: _usernameForId,
                                        userNameFromPredictions:
                                            _userNameFromPredictions,
                                        compact: compact,
                                        onlyLeagueId: 1,
                                      ),
                                    ),
                                    const VerticalDivider(
                                        width: 8, thickness: 0.5),
                                    Expanded(
                                      flex: 3,
                                      child: SeasonTableBlock(
                                        standings: standings,
                                        stats: npbPlayerStatsActual,
                                        onlyLeagueId: 1,
                                      ),
                                    ),
                                    const VerticalDivider(
                                        width: 8, thickness: 0.5),
                                    Expanded(
                                      flex: 3,
                                      child: Row(children: [
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              const Text('昨日',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                height: 320,
                                                child: GamesBoardYahooStyle(
                                                  games: games
                                                      .where((g) =>
                                                          (int.tryParse(
                                                                      '${g['id_league_home']}') ??
                                                                  0) ==
                                                              1 &&
                                                          (int.tryParse(
                                                                      '${g['id_league_away']}') ??
                                                                  0) ==
                                                              1)
                                                      .toList(),
                                                  dateFilter:
                                                      _ymdWithOffset(-1),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              const Text('今日',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                height: 320,
                                                child: GamesBoardYahooStyle(
                                                  games: games
                                                      .where((g) =>
                                                          (int.tryParse(
                                                                      '${g['id_league_home']}') ??
                                                                  0) ==
                                                              1 &&
                                                          (int.tryParse(
                                                                      '${g['id_league_away']}') ??
                                                                  0) ==
                                                              1)
                                                      .toList(),
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              const Text('明日',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                height: 320,
                                                child: GamesBoardYahooStyle(
                                                  games: games
                                                      .where((g) =>
                                                          (int.tryParse(
                                                                      '${g['id_league_home']}') ??
                                                                  0) ==
                                                              1 &&
                                                          (int.tryParse(
                                                                      '${g['id_league_away']}') ??
                                                                  0) ==
                                                              1)
                                                      .toList(),
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
                      const SizedBox(height: 8),
                      // 2行目: パ・リーグ（比率 2）
                      Expanded(
                        flex: 17,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // サイドヘッダー（リーグ名）
                            Container(
                              width: 36,
                              margin: const EdgeInsets.only(left: 4, right: 0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2CB1BC),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('パ',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    Text('・',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    Text('リ',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    Text('|',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    Text('グ',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _UnifiedGrid(
                                        predictions: predictions,
                                        standings: standings,
                                        npbPlayerStats: npbPlayerStats,
                                        usernameForId: _usernameForId,
                                        userNameFromPredictions:
                                            _userNameFromPredictions,
                                        compact: compact,
                                        onlyLeagueId: 2,
                                      ),
                                    ),
                                    const VerticalDivider(
                                        width: 8, thickness: 0.5),
                                    Expanded(
                                      flex: 3,
                                      child: SeasonTableBlock(
                                        standings: standings,
                                        stats: npbPlayerStatsActual,
                                        onlyLeagueId: 2,
                                      ),
                                    ),
                                    const VerticalDivider(
                                        width: 8, thickness: 0.5),
                                    Expanded(
                                      flex: 3,
                                      child: Row(children: [
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              const Text('昨日',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                height: 320,
                                                child: GamesBoardYahooStyle(
                                                  games: games
                                                      .where((g) =>
                                                          (int.tryParse(
                                                                      '${g['id_league_home']}') ??
                                                                  0) ==
                                                              2 &&
                                                          (int.tryParse(
                                                                      '${g['id_league_away']}') ??
                                                                  0) ==
                                                              2)
                                                      .toList(),
                                                  dateFilter:
                                                      _ymdWithOffset(-1),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              const Text('今日',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                height: 320,
                                                child: GamesBoardYahooStyle(
                                                  games: games
                                                      .where((g) =>
                                                          (int.tryParse(
                                                                      '${g['id_league_home']}') ??
                                                                  0) ==
                                                              2 &&
                                                          (int.tryParse(
                                                                      '${g['id_league_away']}') ??
                                                                  0) ==
                                                              2)
                                                      .toList(),
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              const Text('明日',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                height: 320,
                                                child: GamesBoardYahooStyle(
                                                  games: games
                                                      .where((g) =>
                                                          (int.tryParse(
                                                                      '${g['id_league_home']}') ??
                                                                  0) ==
                                                              2 &&
                                                          (int.tryParse(
                                                                      '${g['id_league_away']}') ??
                                                                  0) ==
                                                              2)
                                                      .toList(),
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
            backgroundColor:
                selected ? Colors.deepPurple.withOpacity(0.06) : null,
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

// After
class OneLineShrinkText extends StatelessWidget {
  final String text;
  final double baseSize;
  final double minSize;
  final FontWeight? weight;
  final TextAlign align;
  final Color? color;
  final double verticalPadding;
  final bool fast; // if true, use FittedBox(BoxFit.scaleDown)

  const OneLineShrinkText(
    this.text, {
    super.key,
    this.baseSize = 12,
    this.minSize = 6,
    this.weight,
    this.align = TextAlign.center,
    this.color,
    this.verticalPadding = 0,
    this.fast = true,
  });

  Alignment _toAlignment(TextAlign a) {
    switch (a) {
      case TextAlign.left:
      case TextAlign.start:
        return Alignment.centerLeft;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.center:
      default:
        return Alignment.center;
    }
  }

  bool _fits(String t, double size, double maxW, double maxH) {
    final tp = TextPainter(
      text: TextSpan(
          text: t, style: TextStyle(fontSize: size, fontWeight: weight)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW.isFinite && maxW > 0 ? maxW : double.infinity);
    final w = tp.size.width;
    final h = tp.size.height;
    final okW = !(maxW.isFinite && maxW > 0) || w <= maxW + 0.5;
    final okH = !(maxH.isFinite && maxH > 0) || h <= maxH + 0.5;
    return okW && okH;
  }

  @override
  Widget build(BuildContext context) {
    if (fast) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding * 0.5),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: _toAlignment(align),
          child: Text(
            text.isNotEmpty ? text : '—',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: align,
            style:
                TextStyle(fontSize: baseSize, fontWeight: weight, color: color),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth;
      final maxH = constraints.maxHeight.isFinite
          ? (constraints.maxHeight - verticalPadding)
              .clamp(0.0, constraints.maxHeight)
          : constraints.maxHeight;

      double lo = minSize;
      double hi = baseSize;
      double chosen = baseSize;

      if ((maxW.isFinite && maxW > 0) || (maxH.isFinite && maxH > 0)) {
        for (int i = 0; i < 12; i++) {
          final mid = (lo + hi) / 2;
          if (_fits(text, mid, maxW, maxH)) {
            chosen = mid;
            lo = mid;
          } else {
            hi = mid;
          }
        }
      }

      return Text(
        text.isNotEmpty ? text : '—',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        textAlign: align,
        style: TextStyle(fontSize: chosen, fontWeight: weight, color: color),
      );
    });
  }
}

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
    print(dateFilter);
    final src = (dateFilter == null || dateFilter!.isEmpty)
        ? games
        : games
            .where((g) => (g['date_game']?.toString() ?? '') == dateFilter)
            .toList();

    final bySec = <String, List<Map<String, dynamic>>>{};
    for (final g in src) {
      final sec = _sectionOf(g);
      bySec.putIfAbsent(sec, () => []).add(g);
    }

    if (bySec.isEmpty) {
      return const Center(
          child: Text('試合はありません', style: TextStyle(fontSize: 12)));
    }

    return LayoutBuilder(builder: (context, c) {
      final bySecKeys = bySec.keys.toSet();
      final order =
          ['セ・リーグ', 'パ・リーグ'].where((k) => bySecKeys.contains(k)).toList();

      Widget threeRows(List<Map<String, dynamic>> list) {
        final g0 = list.isNotEmpty ? list[0] : null;
        final g1 = list.length > 1 ? list[1] : null;
        final g2 = list.length > 2 ? list[2] : null;
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(child: g0 != null ? _GameCard(g0) : const SizedBox()),
              const SizedBox(height: 8),
              Expanded(child: g1 != null ? _GameCard(g1) : const SizedBox()),
              const SizedBox(height: 8),
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
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
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
  String get _pHome => g['name_pitcher_home']?.toString() ?? '';
  String get _pAway => g['name_pitcher_away']?.toString() ?? '';
  String get _sHome => g['score_home']?.toString() ?? '';
  String get _sAway => g['score_away']?.toString() ?? '';

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

      return Card(
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, vPad, 8, vPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 上段: 時刻（左）／ 球場（右）
              Row(
                children: [
                  OneLineShrinkText(
                    _time.isNotEmpty ? _time : (_showScore ? '試合終了' : ''),
                    baseSize: baseSmall,
                    minSize: 7,
                    weight: _showScore ? FontWeight.w600 : FontWeight.normal,
                    color: _showScore ? Colors.purple : Colors.black54,
                    align: TextAlign.left,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OneLineShrinkText(
                      _stadium,
                      baseSize: baseSmall,
                      minSize: 7,
                      color: Colors.black87,
                      align: TextAlign.left,
                    ),
                  ),
                ],
              ),
              SizedBox(height: gap),

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
                          OneLineShrinkText(_home,
                              baseSize: baseMid,
                              minSize: 8,
                              weight: FontWeight.w600,
                              align: TextAlign.left),
                          if (_pHome.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: gap * 0.3),
                              child: OneLineShrinkText(_pHome,
                                  baseSize: baseSmall,
                                  minSize: 7,
                                  color: Colors.black87,
                                  align: TextAlign.left),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Center(
                      child: OneLineShrinkText(
                        _showScore ? '$_sHome  -  $_sAway' : 'vs',
                        baseSize: baseBig,
                        minSize: 9,
                        weight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          OneLineShrinkText(_away,
                              baseSize: baseMid,
                              minSize: 8,
                              weight: FontWeight.w600,
                              align: TextAlign.right),
                          if (_pAway.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: gap * 0.3),
                              child: OneLineShrinkText(_pAway,
                                  baseSize: baseSmall,
                                  minSize: 7,
                                  color: Colors.black87,
                                  align: TextAlign.right),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: gap),

              // 下段: 勝敗投手（あれば）
              if (_win.isNotEmpty || _lose.isNotEmpty)
                Row(
                  children: [
                    if (_win.isNotEmpty)
                      Expanded(
                        child: OneLineShrinkText('(勝)$_win',
                            baseSize: baseSmall,
                            minSize: 7,
                            color: Colors.black87,
                            align: TextAlign.left),
                      ),
                    if (_win.isNotEmpty && _lose.isNotEmpty)
                      const SizedBox(width: 8),
                    if (_lose.isNotEmpty)
                      Expanded(
                        child: OneLineShrinkText('(敗)$_lose',
                            baseSize: baseSmall,
                            minSize: 7,
                            color: Colors.black87,
                            align: TextAlign.right),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    });
  }
}

// ────────────────────────────────────────────────────────────────
// 左ペイン：統合グリッド（セ左・パ右）
// ────────────────────────────────────────────────────────────────
class _UnifiedGrid extends StatelessWidget {
  final List<Map<String, dynamic>> predictions;
  final List<Map<String, dynamic>> standings; // ← フラット
  final List<Map<String, dynamic>> npbPlayerStats;
  final String Function(String idUser) usernameForId;
  final String Function(String idUser) userNameFromPredictions;
  final bool compact;
  final int? onlyLeagueId; // 1: セ, 2: パ, null: 両方

  _UnifiedGrid({
    super.key,
    required this.predictions,
    required this.standings,
    required this.npbPlayerStats,
    required this.usernameForId,
    required this.userNameFromPredictions,
    required this.compact,
    this.onlyLeagueId,
  });

// After
  Widget headerCell(String text,
      {FontWeight weight = FontWeight.bold, Color? bgColor, Color? fgColor}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(1, 0, 1, 0),
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OneLineShrinkText(text,
            baseSize: 12,
            minSize: 6,
            weight: weight,
            color: fgColor,
            verticalPadding: 2,
            fast: true),
      ),
    );
  }

  Widget cell(String text, {bool highlight = false, Color? bgColor}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(1, 0, 1, 0),
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
      decoration: BoxDecoration(
        color: bgColor ?? (highlight ? Colors.yellow[200] : null),
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OneLineShrinkText(text,
            baseSize: 12, minSize: 6, verticalPadding: 2, fast: true),
      ),
    );
  }

  String _joinDedup(Iterable<String>? xs) {
    if (xs == null) return '—';
    final seen = <String>{};
    final out = <String>[];
    for (final s in xs) {
      if (s.isEmpty) continue;
      if (seen.add(s)) out.add(s);
    }
    return out.isEmpty ? '—' : out.join(', ');
  }

  List<Widget> _buildLeagueColumn(int leagueId) {
    // リーグ色（予想ブロック内サイドヘッダー用）
    final Color leagueColor =
        leagueId == 1 ? const Color(0xFF7CB342) : const Color(0xFF2CB1BC);
    // standingsから対象リーグを抽出
    final currentRows = standings.where((e) {
      final id = int.tryParse('${e['id_league']}') ?? 0;
      return id == leagueId;
    }).toList()
      ..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0)
          .compareTo(int.tryParse('${b['int_rank']}') ?? 0));

    // predictionsから対象リーグを抽出
    final pred1 = predictions
        .where((e) =>
            '${e['id_user']}' == '1' &&
            (int.tryParse('${e['id_league']}') ?? 0) == leagueId)
        .toList()
      ..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0)
          .compareTo(int.tryParse('${b['int_rank']}') ?? 0));

    final pred2 = predictions
        .where((e) =>
            '${e['id_user']}' == '2' &&
            (int.tryParse('${e['id_league']}') ?? 0) == leagueId)
        .toList()
      ..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0)
          .compareTo(int.tryParse('${b['int_rank']}') ?? 0));

    final widgets = <Widget>[];
    final rankHeader = <Widget>[];
    final rankRows = <Widget>[];

    // サイドヘッダー(26) + ギャップ(6) + 順位セル(56) と見かけ幅を揃える
    const double _sideHeaderW = 26;
    const double _sideGap = 0; // サイドヘッダーと右列の余白なし
    const double _rankCellW = 56;
    final double _rankHeaderW = _sideHeaderW + _sideGap + _rankCellW;

    rankHeader.add(Row(children: [
      const SizedBox(width: 4),
      SizedBox(
        width: _rankHeaderW,
        child:
            headerCell('シーズン予想', bgColor: leagueColor, fgColor: Colors.white),
      ),
      Expanded(
          flex: 2,
          child: headerCell('現在', bgColor: leagueColor, fgColor: Colors.white)),
      Expanded(
          flex: 2,
          child: headerCell(userNameFromPredictions('1'),
              bgColor: leagueColor, fgColor: Colors.white)), // 立石
      Expanded(
          flex: 2,
          child: headerCell(userNameFromPredictions('2'),
              bgColor: leagueColor, fgColor: Colors.white)), // 江島
    ]));
    // 余白や区切り線を入れず、直後のチーム順位ブロックに密着させる

    bool _isHit(
        Map<String, dynamic>? pred, List<Map<String, dynamic>> curGroup) {
      if (pred == null || curGroup.isEmpty) return false;

      // 予想側の id_team / name
      final int prdId = int.tryParse('${pred['id_team']}') ?? -1;
      final String prdName = (pred['name_team_short']?.toString() ??
              pred['name_team']?.toString() ??
              '')
          .trim();

      for (final cur in curGroup) {
        final int curId = int.tryParse('${cur['id_team']}') ?? -1;
        final String curName = (cur['name_team']?.toString() ?? '').trim();

        if ((prdId >= 0 && curId >= 0 && prdId == curId) ||
            (prdName.isNotEmpty && curName == prdName)) {
          return true;
        }
      }
      return false;
    }

    for (var rk = 1; rk <= 6; rk++) {
      // 現在の順位グループ（同じ int_rank のチームを全部）
      final curGroup = currentRows
          .where((e) => int.tryParse('${e['int_rank']}') == rk)
          .toList();

      // 予想側
      final p1 = pred1.firstWhere((e) => int.tryParse('${e['int_rank']}') == rk,
          orElse: () => {});
      final p2 = pred2.firstWhere((e) => int.tryParse('${e['int_rank']}') == rk,
          orElse: () => {});

      // 表示テキスト
      final curTeamText = curGroup.isNotEmpty
          ? curGroup.map((e) => e['name_team']?.toString() ?? '').join(', ')
          : '—';
      final txt1 =
          p1.isNotEmpty ? (p1['name_team_short']?.toString() ?? '—') : '—';
      final txt2 =
          p2.isNotEmpty ? (p2['name_team_short']?.toString() ?? '—') : '—';

      // ハイライト判定（予想チームが現在の順位グループに含まれているか）
      final hi1 = _isHit(p1.isNotEmpty ? p1 : null, curGroup);
      final hi2 = _isHit(p2.isNotEmpty ? p2 : null, curGroup);

      rankRows.add(Row(
        children: [
          const SizedBox(width: 0),
          SizedBox(
              width: _rankCellW,
              child: headerCell('$rk',
                  bgColor: leagueColor, fgColor: Colors.white)),
          Expanded(
              flex: 2,
              child: cell(curTeamText,
                  bgColor: const Color(0xFFF0E68C))), // 現在を #f0e68c
          Expanded(flex: 2, child: cell(txt1, highlight: hi1)), // 立石
          Expanded(flex: 2, child: cell(txt2, highlight: hi2)), // 江島
        ],
      ));
    }
    // まずヘッダー（順位・現在・立石・江島）を追加
    widgets.addAll(rankHeader);
    // サイドヘッダー付き（チーム順位）: 1位〜6位の高さに合わせる
    widgets.add(IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: double.infinity,
            margin: const EdgeInsets.only(left: 4, right: 0),
            decoration: BoxDecoration(
              color: leagueColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('チ',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('|',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('ム',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('順',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('位',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: rankRows,
            ),
          ),
        ],
      ),
    ));
    // チーム順位と個人タイトルの間に 2px の余白
    widgets.add(const SizedBox(height: 2));

    // ───────────────────────────────
    // 個人タイトル表示 (statMap)
    // ───────────────────────────────
    final statMap = <String, List<Map<String, dynamic>>>{};
    for (final r in npbPlayerStats) {
      final ln = (r['league_name'] ?? '').toString();
      final target = (leagueId == 1) ? 'セ・リーグ' : 'パ・リーグ';
      if (ln != target) continue;

      final idStatStr =
          (r['id_stats'] == null) ? 'unknown' : '${r['id_stats']}';
      final title = (r['title'] ?? '不明').toString();
      final key = '$idStatStr|$title';
      statMap.putIfAbsent(key, () => []).add(r);
    }

    // スタッツのヘッダー行（「スタッツ 現在 立石 江島」）は非表示のまま
    final statsSection = <Widget>[];

    int _idxOf(Map<String, dynamic> r) {
      final v = r['int_index'] ?? r['id_stats']; // 保険で id_stats も参照
      return int.tryParse('$v') ?? 1 << 30;
    }

    int _minIdx(List<Map<String, dynamic>> rows) => rows.isEmpty
        ? (1 << 30)
        : rows.map(_idxOf).reduce((a, b) => a < b ? a : b);

    final statEntries = statMap.entries.toList()
      ..sort((a, b) {
        final ia = _minIdx(a.value);
        final ib = _minIdx(b.value);
        if (ia != ib) return ia.compareTo(ib);
        return a.key
            .split('|')
            .last
            .compareTo(b.key.split('|').last); // 同順位は名称で
      });

    for (final entry in statEntries) {
      final title = entry.key.split('|').last;
      final rows2 = entry.value;

      final user1Rows = rows2.where((e) => '${e['id_user']}' == '1');
      final user0Rows = rows2.where((e) => '${e['id_user']}' == '0');
      final user2Rows = rows2.where((e) => '${e['id_user']}' == '2');

      final txt1 =
          _joinDedup(user1Rows.map((e) => '${e['player_name'] ?? ''}'));
      final txt0 =
          _joinDedup(user0Rows.map((e) => '${e['player_name'] ?? ''}'));
      final txt2 =
          _joinDedup(user2Rows.map((e) => '${e['player_name'] ?? ''}'));

      final hi1 = user1Rows.any((e) => e['flg_atari'] == true);
      final hi0 = user0Rows.any((e) => e['flg_atari'] == true);
      final hi2 = user2Rows.any((e) => e['flg_atari'] == true);

// After
      final isPitcher = rows2.any((e) => e['flg_pitcher'] == true);
      final titleBg = isPitcher
          ? const Color(0xFF64B5F6)
          : const Color(0xFFEF9A9A); // 少し濃い青/赤

      statsSection.add(Row(
        children: [
          SizedBox(
            width: 56, // 4文字ぶんの目安
            child: headerCell(title, bgColor: titleBg),
          ),
          Expanded(
              flex: 2,
              child: cell(txt0,
                  bgColor: const Color(0xFFF0E68C), highlight: hi0)), // 現在
          Expanded(flex: 2, child: cell(txt1, highlight: hi1)), // 立石
          Expanded(flex: 2, child: cell(txt2, highlight: hi2)), // 江島
        ],
      ));
    }
    // サイドヘッダー付き（個人タイトル）: 打率〜セーブまでの高さに合わせる（右余白なし）
    widgets.add(IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: double.infinity,
            margin: const EdgeInsets.only(left: 4, right: 0),
            decoration: BoxDecoration(
              color: leagueColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('個',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('人',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('タ',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('イ',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('ト',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('ル',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: statsSection,
            ),
          ),
        ],
      ),
    ));

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: onlyLeagueId == null
                  ? [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _buildLeagueColumn(1),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _buildLeagueColumn(2),
                      ),
                    ]
                  : [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _buildLeagueColumn(onlyLeagueId!),
                      ),
                    ],
            ),
          ),
        ),
      ),
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

  // 文字→数値(表示用)
  String _num(dynamic v) => (v == null || '$v'.isEmpty) ? '—' : '$v';

  // リーグ別フィルタ
  List<Map<String, dynamic>> _standingsOf(int leagueId) => standings
      .where((e) => int.tryParse('${e['id_league']}') == leagueId)
      .toList()
    ..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0)
        .compareTo(int.tryParse('${b['int_rank']}') ?? 0));

  List<Map<String, dynamic>> _statsOf(int leagueId, {required bool pitcher}) =>
      stats
          .where((e) =>
              ((e['league_name'] ?? '').toString() ==
                  (leagueId == 1 ? 'セ・リーグ' : 'パ・リーグ')) &&
              (e['flg_pitcher'] == pitcher))
          .toList();

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
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  // 簡易セル
  Widget _cell(String text,
      {Color? bg, FontWeight? weight, Color? fg, double? h}) {
    return Container(
      height: h,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: OneLineShrinkText(text,
          baseSize: 12, minSize: 6, weight: weight, color: fg),
    );
  }

  // 最小幅付きセル（数値列用）
  Widget _minCell(String text, double min,
      {Color? bg, Color? fg, FontWeight? weight}) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: min),
      child: _cell(text, bg: bg, fg: fg, weight: weight),
    );
  }

  // 順位テーブル（上:順位行、下:スタッツ要約）
  Widget _leagueTable(int leagueId) {
    final cur = _standingsOf(leagueId);
    // リーグ見出しは非表示

    // 打撃/投手タイトル（画像に近い簡易版）: stats_player の形に合わせて抽出
    const battingTitles = ['打率', '本塁打', '打点', '盗塁', '出塁率'];
    const pitchingTitles = ['防御率', '最多勝', '奪三振', 'HP', 'セーブ'];
    final leagueStats = stats
        .where((e) => int.tryParse('${e['id_league']}') == leagueId)
        .toList();
    final bat = leagueStats
        .where((e) => battingTitles.contains(((e['title'] ?? '').toString())))
        .toList();
    final pit = leagueStats
        .where((e) => pitchingTitles.contains(((e['title'] ?? '').toString())))
        .toList();

    // 文字幅の目安（12pxフォントで約14px/字）
    // 文字幅の目安（12pxフォントで約14px/字）
    const double _kChar = 14.0;
    const double _wRank = _kChar * 2; // 2文字ぶん
    const double _wTeam = _kChar * 7; // 7文字ぶん（順位表で使用中）
    const double _wNum = _kChar * 3; // 3文字ぶん（順位表で使用中）
    const double _wStat = _kChar * 18; // 個人成績の各タイトル列幅

    Widget _gridCell(String text,
        {double h = 28, Color? bg, Color? fg, FontWeight? weight}) {
      return Container(
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: Colors.black26, width: 1),
        ),
        child: OneLineShrinkText(text,
            baseSize: 12, minSize: 6, weight: weight, color: fg),
      );
    }

    Widget _bar(String label, Color color,
        {double h = 26, Color fg = Colors.white}) {
      return Container(
        height: h,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: color),
        child: Text(label,
            style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
      );
    }

    Widget _personalStatsSheet(int leagueId, List<Map<String, dynamic>> bat,
        List<Map<String, dynamic>> pit) {
      final leagueLabel = leagueId == 1 ? 'セ・リーグ' : 'パ・リーグ';

      List<TableRow> _rankRows(
          List<String> cols, List<Map<String, dynamic>> src) {
        String _normalizeTitle(String t) => t == 'ホールド' ? 'HP' : t;
        String _nameBy(String title, int rank) {
          final e = src.firstWhere(
              (m) =>
                  (m['title']?.toString() ?? '') == _normalizeTitle(title) &&
                  (int.tryParse('${m['int_rank']}') ?? -1) == rank,
              orElse: () => const {});
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
        final v = src.firstWhere((e) => (e['title'] ?? '') == title,
            orElse: () => const {});
        return (v.isNotEmpty ? (v['name_player'] ?? '') : '').toString();
      }

      String _normalizeTitle(String t) => t == 'ホールド' ? 'HP' : t;
      String _nameBy(List<Map<String, dynamic>> src, String title, int rank) {
        final e = src.firstWhere(
            (m) =>
                (m['title']?.toString() ?? '') == _normalizeTitle(title) &&
                (int.tryParse('${m['int_rank']}') ?? -1) == rank,
            orElse: () => const {});
        return (e.isNotEmpty ? (e['name_player'] ?? '') : '').toString();
      }

      final battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率'];
      final pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ'];

      // 個人成績セル: ランク/チーム/選手/数値 を1セル内に表示
      Widget _entryCell(
          List<Map<String, dynamic>> src, String title, int rank) {
        final e = src.firstWhere(
            (m) =>
                (m['title']?.toString() ?? '') == _normalizeTitle(title) &&
                (int.tryParse('${m['int_rank']}') ?? -1) == rank,
            orElse: () => const {});
        final team = (e.isNotEmpty ? (e['name_team'] ?? '') : '').toString();
        final name = (e.isNotEmpty ? (e['name_player'] ?? '') : '').toString();
        final stat = _num(e.isNotEmpty ? e['stats'] : null);

        const double _segRank = _kChar * 2;
        const double _segTeam = _kChar * 2;
        const double _segStat = _kChar * 4;

        return SizedBox(
          width: _wStat,
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26, width: 1),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(children: [
              SizedBox(
                  width: _segRank,
                  child: OneLineShrinkText('$rank', baseSize: 12, minSize: 6)),
              SizedBox(
                  width: _segTeam,
                  child: OneLineShrinkText(team, baseSize: 12, minSize: 6)),
              Expanded(
                  child: OneLineShrinkText(name, baseSize: 12, minSize: 6)),
              SizedBox(
                  width: _segStat,
                  child: OneLineShrinkText(stat, baseSize: 12, minSize: 6)),
            ]),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 個人成績 見出しは非表示
          // 緑: リーグ名（非表示）
          // 赤: 打撃 見出し（横スクロール）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in battingCols)
                SizedBox(
                    width: _wStat,
                    child: _gridCell(t, bg: const Color(0xFFE57373), h: 30)),
            ]),
          ),
          // 打撃 本文（ランク/チーム/選手/数値）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(children: [
              for (int r = 1; r <= 5; r++)
                Row(children: [
                  for (final t in battingCols) _entryCell(bat, t, r),
                ]),
            ]),
          ),
          const SizedBox(height: 8),
          // 青: 投手 見出し（横スクロール）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in pitchingCols)
                SizedBox(
                    width: _wStat,
                    child: _gridCell(t, bg: const Color(0xFF64B5F6), h: 30)),
            ]),
          ),
          // 投手 本文（ランク/チーム/選手/数値）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(children: [
              for (int r = 1; r <= 5; r++)
                Row(children: [
                  for (final t in pitchingCols) _entryCell(pit, t, r),
                ]),
            ]),
          ),
        ],
      );
    }

    // スクロール分離: チーム順位は専用の横スクロール、個人成績は別
    final double _standingsWidth = _wRank +
        _wTeam +
        _wNum * 14; // 列数: 試合/勝/負/分/勝差/勝率/打率/本塁打/打点/盗塁/防御率(総合/先発/救援)/守備率
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // リーグ見出し（非表示）

        // チーム順位（独立横スクロール）
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _standingsWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー（非防御率は縦結合、防御率のみ二段）
                Row(children: [
                  SizedBox(
                      width: _wRank,
                      child: _cell('順位',
                          h: 44,
                          bg: Colors.black,
                          fg: Colors.white,
                          weight: FontWeight.bold)),
                  SizedBox(
                      width: _wTeam,
                      child: _cell('チーム', weight: FontWeight.bold, h: 44)),
                  SizedBox(
                      width: _wNum,
                      child: _cell('試合', weight: FontWeight.bold, h: 44)),
                  SizedBox(
                      width: _wNum,
                      child: _cell('勝', weight: FontWeight.bold, h: 44)),
                  SizedBox(
                      width: _wNum,
                      child: _cell('負', weight: FontWeight.bold, h: 44)),
                  SizedBox(
                      width: _wNum,
                      child: _cell('分', weight: FontWeight.bold, h: 44)),
                  SizedBox(
                      width: _wNum,
                      child: _cell('勝差', weight: FontWeight.bold, h: 44)),
                  SizedBox(
                      width: _wNum,
                      child: _cell('勝率', weight: FontWeight.bold, h: 44)),
                  SizedBox(
                      width: _wNum,
                      child: _cell('打率', weight: FontWeight.bold, h: 44)),
                  SizedBox(
                      width: _wNum,
                      child: _cell('本塁打', weight: FontWeight.bold, h: 44)),
                  SizedBox(
                      width: _wNum,
                      child: _cell('打点', weight: FontWeight.bold, h: 44)),
                  SizedBox(
                      width: _wNum,
                      child: _cell('盗塁', weight: FontWeight.bold, h: 44)),

                  SizedBox(
                      width: _wNum,
                      child: _cell('守備率', weight: FontWeight.bold, h: 44)),

                  // 防御率ブロック（上: 見出し、下: 総合/先発/救援）
                  SizedBox(
                    width: _wNum * 3,
                    child: Column(children: [
                      _cell('防御率', weight: FontWeight.bold, h: 22),
                      Row(children: [
                        SizedBox(
                            width: _wNum,
                            child: _cell('総合', weight: FontWeight.bold, h: 22)),
                        SizedBox(
                            width: _wNum,
                            child: _cell('先発', weight: FontWeight.bold, h: 22)),
                        SizedBox(
                            width: _wNum,
                            child: _cell('救援', weight: FontWeight.bold, h: 22)),
                      ]),
                    ]),
                  ),
                ]),
                const SizedBox(height: 4),

                // 本文 1..6
                for (int rk = 1; rk <= 6; rk++)
                  Row(children: [
                    SizedBox(
                        width: _wRank,
                        child:
                            _cell('$rk', bg: Colors.black, fg: Colors.white)),
                    SizedBox(
                        width: _wTeam,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['name_team']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['int_game']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['int_win']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['int_lose']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['int_draw']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['game_behind']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['win_rate']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['num_avg_batting']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['int_homerun']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['int_rbi']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['int_sh']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['num_avg_fielding']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['num_era_total']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['num_era_starter']))),
                    SizedBox(
                        width: _wNum,
                        child: _cell(_num(cur.firstWhere(
                            (e) => int.tryParse('${e['int_rank']}') == rk,
                            orElse: () => const {})['num_era_relief']))),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 個人成績（独立: 内部で横スクロールを制御）
        _personalStatsSheet(leagueId, bat, pit),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          child: Column(
            children: onlyLeagueId == null
                ? [
                    _leagueTable(1), // セ
                    const SizedBox(height: 16),
                    _leagueTable(2), // パ
                  ]
                : [
                    _leagueTable(onlyLeagueId!),
                  ],
          ),
        ),
      ),
    );
  }
}
