import 'package:flutter/material.dart';
import 'Text.dart';
import 'Border.dart';

class UnifiedGrid extends StatelessWidget {
  final List<Map<String, dynamic>> predictions;
  final List<Map<String, dynamic>> standings; // ← フラット
  final List<Map<String, dynamic>> npbPlayerStats;
  final String Function(String idUser) usernameForId;
  final String Function(String idUser) userNameFromPredictions;
  final bool compact;
  final int? onlyLeagueId; // 1: セ, 2: パ, null: 両方
  double? w_col_predictor;

  UnifiedGrid({
    super.key,
    required this.predictions,
    required this.standings,
    required this.npbPlayerStats,
    required this.usernameForId,
    required this.userNameFromPredictions,
    required this.compact,
    this.onlyLeagueId,
    this.w_col_predictor,
  });

// After
  Widget headerCell(String text, {FontWeight weight = FontWeight.bold, Color? bgColor, Color? fgColor}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 4),
      constraints: const BoxConstraints(minHeight: 21.5),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OneLineShrinkText(text, baseSize: 12, minSize: 1, weight: weight, color: fgColor, verticalPadding: 0, fast: true),
      ),
    );
  }

  Widget cell(String text, {bool highlight = false, Color? bgColor, Color? borderColor}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 4),
      constraints: const BoxConstraints(minHeight: 21.5),
      decoration: BoxDecoration(
        color: bgColor ?? (highlight ? Colors.yellow[200] : null),
        border: Border.all(color: borderColor ?? Colors.grey.shade300),
        borderRadius: BorderRadius.circular(3),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OneLineShrinkText(text, baseSize: 12, minSize: 5, verticalPadding: 0, fast: true),
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
    Color? _parseColorNameLocal(String? name) {
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

    // リーグ色（予想ブロック内サイドヘッダー用）
    final Color leagueColor = leagueId == 1 ? const Color(0xFF0B8F3A) : const Color(0xFF4DB5E8);
    // standingsから対象リーグを抽出
    final currentRows = standings.where((e) {
      final id = int.tryParse('${e['id_league']}') ?? 0;
      return id == leagueId;
    }).toList()
      ..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0).compareTo(int.tryParse('${b['int_rank']}') ?? 0));

    // predictionsから対象リーグを抽出
    final pred1 = predictions.where((e) => '${e['id_user']}' == '1' && (int.tryParse('${e['id_league']}') ?? 0) == leagueId).toList()..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0).compareTo(int.tryParse('${b['int_rank']}') ?? 0));

    final pred2 = predictions.where((e) => '${e['id_user']}' == '2' && (int.tryParse('${e['id_league']}') ?? 0) == leagueId).toList()..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0).compareTo(int.tryParse('${b['int_rank']}') ?? 0));

    final widgets = <Widget>[];
    final rankHeader = <Widget>[];
    final rankRows = <Widget>[];

    // サイドヘッダー(26) + ギャップ(6) + 順位セル(56) と見かけ幅を揃える
    const double _sideHeaderW = 23;
    const double _sideGap = 0; // サイドヘッダーと右列の余白なし
    const double _rankCellW = 56;
    final double _rankHeaderW = _sideHeaderW + _sideGap + _rankCellW;

    rankHeader.add(Row(children: [
      Expanded(
        child: headerCell('シーズン予想', bgColor: leagueColor, fgColor: Colors.white),
      ),
      SizedBox(
        width: w_col_predictor,
        child: headerCell('現在', bgColor: leagueColor, fgColor: Colors.white),
      ),
      SizedBox(
        width: w_col_predictor,
        child: headerCell('立石', bgColor: leagueColor, fgColor: Colors.white),
      ),
      SizedBox(
        width: w_col_predictor,
        child: headerCell('江島', bgColor: leagueColor, fgColor: Colors.white),
      ),
      // Expanded(flex: 1, child: headerCell('現在', bgColor: leagueColor, fgColor: Colors.white)),
      // Expanded(flex: 1, child: headerCell(userNameFromPredictions('1'), bgColor: leagueColor, fgColor: Colors.white)), // 立石
      // Expanded(flex: 1, child: headerCell(userNameFromPredictions('2'), bgColor: leagueColor, fgColor: Colors.white)), // 江島
    ]));
    // 余白や区切り線を入れず、直後のチーム順位ブロックに密着させる

    bool _isHit(Map<String, dynamic>? pred, List<Map<String, dynamic>> curGroup) {
      if (pred == null || curGroup.isEmpty) return false;

      // 予想側の id_team / name
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

    for (var rk = 1; rk <= 6; rk++) {
      // 現在の順位グループ（同じ int_rank のチームを全部）
      final curGroup = currentRows.where((e) => int.tryParse('${e['int_rank']}') == rk).toList();

      // 予想側
      final p1 = pred1.firstWhere((e) => int.tryParse('${e['int_rank']}') == rk, orElse: () => {});
      final p2 = pred2.firstWhere((e) => int.tryParse('${e['int_rank']}') == rk, orElse: () => {});

      // 表示テキスト
      final curTeamText = curGroup.isNotEmpty ? curGroup.map((e) => e['name_team']?.toString() ?? '').join(', ') : '—';
      final txt1 = p1.isNotEmpty ? (p1['name_team_short']?.toString() ?? '—') : '—';
      final txt2 = p2.isNotEmpty ? (p2['name_team_short']?.toString() ?? '—') : '—';

      // ハイライト判定（予想チームが現在の順位グループに含まれているか）
      final hi1 = _isHit(p1.isNotEmpty ? p1 : null, curGroup);
      final hi2 = _isHit(p2.isNotEmpty ? p2 : null, curGroup);

      rankRows.add(Row(
        children: [
          SizedBox(width: _rankCellW, child: headerCell('$rk', bgColor: leagueColor, fgColor: Colors.white)),
          SizedBox(
            width: w_col_predictor!,
            child: cell(curTeamText, bgColor: const Color(0xFFF0E68C)),
          ),
          SizedBox(
            width: w_col_predictor!,
            child: cell(txt1, highlight: hi1),
          ),
          SizedBox(
            width: w_col_predictor!,
            child: cell(txt2, highlight: hi2),
          ),
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
          Expanded(
            child: Container(
              height: double.infinity,
              margin: const EdgeInsets.only(left: 0, right: 0),
              decoration: BoxDecoration(
                color: leagueColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text('チ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('|', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('ム', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('順', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('位', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
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

      final idStatStr = (r['id_stats'] == null) ? 'unknown' : '${r['id_stats']}';
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

    int _minIdx(List<Map<String, dynamic>> rows) => rows.isEmpty ? (1 << 30) : rows.map(_idxOf).reduce((a, b) => a < b ? a : b);

    final statEntries = statMap.entries.toList()
      ..sort((a, b) {
        final ia = _minIdx(a.value);
        final ib = _minIdx(b.value);
        if (ia != ib) return ia.compareTo(ib);
        return a.key.split('|').last.compareTo(b.key.split('|').last); // 同順位は名称で
      });

    for (final entry in statEntries) {
      final title = entry.key.split('|').last;
      final rows2 = entry.value;

      final user1Rows = rows2.where((e) => '${e['id_user']}' == '1');
      final user0Rows = rows2.where((e) => '${e['id_user']}' == '0');
      final user2Rows = rows2.where((e) => '${e['id_user']}' == '2');

      final txt1 = _joinDedup(user1Rows.map((e) => '${e['player_name'] ?? ''}'));
      final txt0 = _joinDedup(user0Rows.map((e) => '${e['player_name'] ?? ''}'));
      final txt2 = _joinDedup(user2Rows.map((e) => '${e['player_name'] ?? ''}'));

      final hi1 = user1Rows.any((e) => e['flg_atari'] == true);
      final hi0 = user0Rows.any((e) => e['flg_atari'] == true);
      final hi2 = user2Rows.any((e) => e['flg_atari'] == true);

// After
      final isPitcher = rows2.any((e) => e['flg_pitcher'] == true);
      final titleBg = isPitcher ? const Color(0xFF64B5F6) : const Color(0xFFEF9A9A); // 少し濃い青/赤

      // 点滅枠色（color_today）
      Color? c0 = _parseColorNameLocal(user0Rows.map((e) => '${e['color_today'] ?? ''}').firstWhere((s) => s.trim().isNotEmpty, orElse: () => ''));
      Color? c1 = _parseColorNameLocal(user1Rows.map((e) => '${e['color_today'] ?? ''}').firstWhere((s) => s.trim().isNotEmpty, orElse: () => ''));
      Color? c2 = _parseColorNameLocal(user2Rows.map((e) => '${e['color_today'] ?? ''}').firstWhere((s) => s.trim().isNotEmpty, orElse: () => ''));

      final Color _baseBg0 = const Color(0xFFF0E68C);
      final w0 = cell(txt0, bgColor: _baseBg0, highlight: hi0, borderColor: c0 != null ? Colors.transparent : null);
      final w1 = cell(txt1, highlight: hi1, borderColor: c1 != null ? Colors.transparent : null);
      final w2 = cell(txt2, highlight: hi2, borderColor: c2 != null ? Colors.transparent : null);

      statsSection.add(Row(
        children: [
          SizedBox(
            width: 56, // 4文字ぶんの目安
            child: headerCell(title, bgColor: titleBg, fgColor: Colors.white),
          ),
          SizedBox(
            width: w_col_predictor!,
            child: c0 != null ? BlinkBorder(color: c0, radius: 3, width: 2, duration: const Duration(milliseconds: 1000), baseBgColor: _baseBg0, fillUseColor: true, child: w0) : w0,
          ),
          SizedBox(
            width: w_col_predictor!,
            child: c1 != null ? BlinkBorder(color: c1, radius: 3, width: 2, duration: const Duration(milliseconds: 1000), baseBgColor: Colors.transparent, fillUseColor: true, child: w1) : w1,
          ),
          SizedBox(
            width: w_col_predictor!,
            child: c2 != null ? BlinkBorder(color: c2, radius: 3, width: 2, duration: const Duration(milliseconds: 1000), baseBgColor: Colors.transparent, fillUseColor: true, child: w2) : w2,
          ),
        ],
      ));
    }
    // サイドヘッダー付き（個人タイトル）: 打率〜セーブまでの高さに合わせる（右余白なし）
    widgets.add(IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: 23,
              height: double.infinity,
              margin: const EdgeInsets.only(left: 0, right: 0),
              decoration: BoxDecoration(
                color: leagueColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text('個', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('人', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('タ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('イ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('ト', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('ル', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
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
    w_col_predictor = MediaQuery.of(context).size.width * 0.06;
    return SizedBox.expand(
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
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
                      const Divider(height: 0.5),
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
