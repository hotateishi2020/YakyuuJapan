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
      title: 'Flutter + Neon',
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
  List<Map<String, dynamic>> standings = [];
  List<Map<String, dynamic>> npbPlayerStats = [];

  // 右カラム（すべて文字列で扱う）
  List<Map<String, dynamic>> games = [];

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
      final response =
          await http.get(Uri.parse('${Env.baseUrl()}/predictions'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final users = (data['users'] as List).cast<Map<String, dynamic>>();
        final npb = (data['npbstandings'] as List).cast<Map<String, dynamic>>();
        final stats =
            (data['npbPlayerStats'] as List).cast<Map<String, dynamic>>();
        final gms = (data['games'] as List).cast<Map<String, dynamic>>();

        setState(() {
          predictions = users;
          standings = npb;
          npbPlayerStats = stats;
          games = gms;
          isLoading = false;
        });

        // 初期表示での自動縮小を確実化
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {});
        });
      } else {
        setState(() {
          error = 'HTTPエラー: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      logger.e('通信エラー: $e');
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

  // games を date_game でフィルタ
  List<Map<String, dynamic>> _filterGamesByOffset(int offset) {
    final ymd = _ymdWithOffset(offset);
    return games
        .where((g) => (g['date_game']?.toString() ?? '') == ymd)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text(error!));

    return LayoutBuilder(
      builder: (context, constraints) {
        // デザイン幅基準のスケーリング
        const designWidth = 1200.0;
        const minScale = 0.75;
        final width = constraints.maxWidth;
        final rawScale = width / designWidth;
        final scale = rawScale.clamp(minScale, 1.0);
        final compact = rawScale < minScale;

        final left = _UnifiedGrid(
          predictions: predictions,
          standings: standings,
          npbPlayerStats: npbPlayerStats,
          usernameForId: _usernameForId,
          userNameFromPredictions: _userNameFromPredictions,
          compact: compact,
        );

        final right = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DaySwitcher(
              selectedOffset: _selectedDayOffset,
              onChanged: (o) => setState(() => _selectedDayOffset = o),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: GamesBoardYahooStyle(
                games: games,
                // 既存のフィルタがあればここで "YYYY-MM-DD" を渡す
                dateFilter: _ymdWithOffset(_selectedDayOffset),
              ),
            ),
          ],
        );

        return Container(
          alignment: Alignment.topCenter,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints.tightFor(width: designWidth),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    const VerticalDivider(width: 8, thickness: 0.5),
                    Expanded(child: right),
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
class OneLineShrinkText extends StatelessWidget {
  final String text;
  final double baseSize;
  final double minSize;
  final FontWeight? weight;
  final TextAlign align;

  const OneLineShrinkText(
    this.text, {
    super.key,
    this.baseSize = 12,
    this.minSize = 6,
    this.weight,
    this.align = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
      double fontSize = baseSize;

      if (maxW > 0 && text.isNotEmpty) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(fontSize: baseSize, fontWeight: weight),
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final textW = painter.size.width;
        if (textW > 0) {
          final scale = (maxW / textW).clamp(minSize / baseSize, 1.0);
          fontSize = baseSize * scale;
        }
      }

      return Text(
        text.isNotEmpty ? text : '—',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        textAlign: align,
        style: TextStyle(fontSize: fontSize, fontWeight: weight),
      );
    });
  }
}

/// 右ペイン：スコア状況（JSONはすべて文字列で扱う）
/// ─────────────────────────────────────────────
/// Yahoo!風の試合ボード（セ／パ／交流戦 でセクション分け）
/// すべて文字列のJSONを想定
/// games の要素キー:
///   date_game, time_game, name_team_home, name_team_away,
///   name_pitcher_home, name_pitcher_away, name_pitcher_win, name_pitcher_lose,
///   name_stadium, score_home, score_away, id_league_home, id_league_away
/// ─────────────────────────────────────────────
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
      final w = c.maxWidth;
      final cross = w >= 1000 ? 3 : (w >= 700 ? 2 : 1);
      final order =
          ['セ・リーグ', 'パ・リーグ', '交流戦'].where(bySec.keys.toSet().contains).toList();

      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final sec in order) ...[
            _LeagueHeader(sec),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bySec[sec]!.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cross,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 6.4, // ← 3.2 から上げて高さを約半分へ
              ),
              itemBuilder: (context, i) => _GameCard(bySec[sec]![i]),
            ),
            const SizedBox(height: 12),
          ],
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
  String get _date => g['date_game']?.toString() ?? '';
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
    // どちらかが -1 なら非表示
    if (h < 0 || a < 0) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 上段: 会場（左）／ 時刻/ステータス（右）
            Row(
              children: [
                // 左：時刻（なければ試合状況）
                Text(
                  _time.isNotEmpty ? _time : (_showScore ? '試合終了' : ''),
                  style: TextStyle(
                    fontSize: 11, // 少し小さく
                    color: _showScore ? Colors.purple : Colors.black54,
                    fontWeight:
                        _showScore ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 6),
                // 右：球場（広がる）
                Expanded(
                  child: Text(
                    _stadium,
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // 中段: 左(ホーム: チーム名＋先発) / 中央(スコア or vs) / 右(ビジター: チーム名＋先発)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_home,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        if (_pHome.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(_pHome,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black87)),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Center(
                    child: Text(
                      _showScore ? '$_sHome  -  $_sAway' : 'vs',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_away,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        if (_pAway.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(_pAway,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black87)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // 下段: 勝敗投手（あれば）
            if (_win.isNotEmpty || _lose.isNotEmpty)
              Row(
                children: [
                  if (_win.isNotEmpty)
                    Text('(勝)$_win',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black87)),
                  if (_win.isNotEmpty && _lose.isNotEmpty)
                    const SizedBox(width: 8),
                  if (_lose.isNotEmpty)
                    Text('(敗)$_lose',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black87)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// 左ペイン：統合グリッド（セ左・パ右）
// ────────────────────────────────────────────────────────────────
class _UnifiedGrid extends StatelessWidget {
  final List<Map<String, dynamic>> predictions;
  final List<Map<String, dynamic>> standings;
  final List<Map<String, dynamic>> npbPlayerStats;
  final String Function(String idUser) usernameForId;
  final String Function(String idUser) userNameFromPredictions;
  final bool compact;

  const _UnifiedGrid({
    super.key,
    required this.predictions,
    required this.standings,
    required this.npbPlayerStats,
    required this.usernameForId,
    required this.userNameFromPredictions,
    required this.compact,
  });

  Widget headerCell(String text, {FontWeight weight = FontWeight.bold}) {
    return Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SizedBox(
        width: double.infinity,
        child:
            OneLineShrinkText(text, baseSize: 12, minSize: 6, weight: weight),
      ),
    );
  }

  Widget cell(String text, {bool highlight = false}) {
    return Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        color: highlight ? Colors.yellow[200] : null,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OneLineShrinkText(text, baseSize: 12, minSize: 6),
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

  List<Widget> _buildLeagueColumn(String leagueName) {
    // 現在順位
    final lg = standings.firstWhere(
      (e) => (e['league'] ?? '').toString() == leagueName,
      orElse: () => const {},
    );
    final curMap = <int, String>{};
    if (lg.isNotEmpty) {
      final teams = (lg['teams'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final t in teams) {
        final r = int.tryParse('${t['rank']}') ?? 0;
        curMap[r] = (t['team'] ?? '').toString();
      }
    }

    // 予想
    final predMap = <String, Map<int, List<String>>>{};
    for (final p in predictions) {
      final leagueId = p['id_league'];
      final ln = (leagueId == 1)
          ? 'セ・リーグ'
          : (leagueId == 2 ? 'パ・リーグ' : '${leagueId ?? ''}');
      if (ln != leagueName) continue;

      final idUser = '${p['id_user']}';
      final rank = p['int_rank'] is int
          ? p['int_rank'] as int
          : int.tryParse('${p['int_rank']}') ?? 0;
      final team = (p['name_team_short'] ?? p['team'] ?? '').toString();

      predMap.putIfAbsent(idUser, () => {});
      predMap[idUser]!.putIfAbsent(rank, () => []);
      if (team.isNotEmpty) predMap[idUser]![rank]!.add(team);
    }

    // 個人タイトル
    final statMap = <String, List<Map<String, dynamic>>>{};
    for (final r in npbPlayerStats) {
      if ((r['league_name'] ?? '').toString() != leagueName) continue;
      final idStatStr =
          (r['id_stats'] == null) ? 'unknown' : '${r['id_stats']}';
      final title = (r['title'] ?? '不明').toString();
      final key = '$idStatStr|$title';
      statMap.putIfAbsent(key, () => []).add(r);
    }

    final widgets = <Widget>[];

    // 見出し
    widgets.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            leagueName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
      ),
    );

    // チーム順位（4列：順位 / id=1 / 現在 / id=2）
    widgets.add(
      Row(
        children: [
          const Expanded(
              flex: 2,
              child: Center(child: OneLineShrinkText('順位', baseSize: 12))),
          Expanded(
              flex: 2,
              child: Center(
                  child: OneLineShrinkText(userNameFromPredictions('1'),
                      baseSize: 12, weight: FontWeight.bold))),
          const Expanded(
              flex: 2,
              child: Center(
                  child: OneLineShrinkText('現在',
                      baseSize: 12, weight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Center(
                  child: OneLineShrinkText(userNameFromPredictions('2'),
                      baseSize: 12, weight: FontWeight.bold))),
        ],
      ),
    );
    widgets.add(const Divider(height: 8, thickness: 0.5));

    final maxRank =
        curMap.keys.isEmpty ? 0 : curMap.keys.reduce((a, b) => a > b ? a : b);
    final lastRank = compact ? (maxRank.clamp(0, 5)) : maxRank; // コンパクト時は上位5

    for (int rk = 1; rk <= lastRank; rk++) {
      final nowTeam = curMap[rk] ?? '';
      String txtFor(String uid) => _joinDedup(predMap[uid]?[rk]);

      final txt1 = txtFor('1');
      final txt2 = txtFor('2');
      final hi1 = (txt1 != '—' &&
          nowTeam.isNotEmpty &&
          txt1.split(', ').contains(nowTeam));
      final hi2 = (txt2 != '—' &&
          nowTeam.isNotEmpty &&
          txt2.split(', ').contains(nowTeam));

      widgets.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                flex: 2, child: headerCell('$rk', weight: FontWeight.w600)),
            Expanded(flex: 2, child: cell(txt1, highlight: hi1)),
            Expanded(flex: 2, child: cell(nowTeam)),
            Expanded(flex: 2, child: cell(txt2, highlight: hi2)),
          ],
        ),
      );
    }

    widgets.add(const SizedBox(height: 4));
    widgets.add(const Divider(height: 8, thickness: 0.5));

    // 個人タイトル（4列：スタッツ / id=1 / id=0 / id=2）
    widgets.add(
      Row(
        children: [
          const Expanded(
              flex: 2,
              child: Center(child: OneLineShrinkText('スタッツ', baseSize: 12))),
          Expanded(
              flex: 2,
              child: Center(
                  child: OneLineShrinkText(usernameForId('1'),
                      baseSize: 12, weight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Center(
                  child: OneLineShrinkText(usernameForId('0'),
                      baseSize: 12, weight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Center(
                  child: OneLineShrinkText(usernameForId('2'),
                      baseSize: 12, weight: FontWeight.bold))),
        ],
      ),
    );
    widgets.add(const Divider(height: 8, thickness: 0.5));

    final statEntries = statMap.entries.toList()
      ..sort((a, b) => a.key.split('|').last.compareTo(b.key.split('|').last));
    final visibleStats =
        compact ? (statEntries.length.clamp(0, 6)) : statEntries.length;

    for (int i = 0; i < visibleStats; i++) {
      final entry = statEntries[i];
      final title = entry.key.split('|').last;
      final rows = entry.value;

      final user1Rows = rows.where((e) => '${e['id_user']}' == '1');
      final user0Rows = rows.where((e) => '${e['id_user']}' == '0');
      final user2Rows = rows.where((e) => '${e['id_user']}' == '2');

      final txt1 =
          _joinDedup(user1Rows.map((e) => (e['player_name'] ?? '').toString()));
      final txt0 =
          _joinDedup(user0Rows.map((e) => (e['player_name'] ?? '').toString()));
      final txt2 =
          _joinDedup(user2Rows.map((e) => (e['player_name'] ?? '').toString()));

      final hi1 = user1Rows.any((e) => e['flg_atari'] == true);
      final hi0 = user0Rows.any((e) => e['flg_atari'] == true);
      final hi2 = user2Rows.any((e) => e['flg_atari'] == true);

      widgets.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: headerCell(title)),
            Expanded(flex: 2, child: cell(txt1, highlight: hi1)),
            Expanded(flex: 2, child: cell(txt0, highlight: hi0)),
            Expanded(flex: 2, child: cell(txt2, highlight: hi2)),
          ],
        ),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.all(4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildLeagueColumn('セ・リーグ'),
                ),
              ),
              const VerticalDivider(width: 8, thickness: 0.5),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildLeagueColumn('パ・リーグ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
