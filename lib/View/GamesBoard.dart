import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../tools/color_parse.dart';
import '../tools/date_format.dart';
import 'Text.dart';
import 'Border.dart';
import 'BlinkBg.dart';

/// Phone portrait and other narrow windows stack the two teams' stats.
const stackedTeamsMaxWidth = 600.0;

String gameDateOnly(dynamic value) {
  final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch('${value ?? ''}');
  return match?.group(0) ?? '${value ?? ''}'.trim();
}

int _gameInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value'.trim()) ?? 0;
}

String gameMatchupKey(Map<String, dynamic> game) {
  final idGame = game['id_game'] ?? game['id'];
  final idText = '${idGame ?? ''}'.trim();
  if (idText.isNotEmpty && idText != 'null' && idText != '0') {
    return 'id:$idText';
  }
  final date = gameDateOnly(game['date_game']);
  final homeName = '${game['name_team_home'] ?? ''}'.trim();
  final awayName = '${game['name_team_away'] ?? ''}'.trim();
  if (homeName.isNotEmpty && awayName.isNotEmpty) {
    return '$date|$homeName|$awayName';
  }
  return '$date|${_gameInt(game['id_team_home'])}|${_gameInt(game['id_team_away'])}';
}

/// 12球団の球団アイコン。試合情報のチーム名の下と、トーナメント表に出す。
String? teamLogoAsset(String name) {
  const logos = <String, String>{
    'ジャイアンツ': 'backend/assets/images/team_g.png',
    '巨人': 'backend/assets/images/team_g.png',
    'タイガース': 'backend/assets/images/team_t.png',
    '阪神': 'backend/assets/images/team_t.png',
    'ドラゴンズ': 'backend/assets/images/team_d.png',
    '中日': 'backend/assets/images/team_d.png',
    'スワローズ': 'backend/assets/images/team_s.png',
    'ヤクルト': 'backend/assets/images/team_s.png',
    'ベイスターズ': 'backend/assets/images/team_db.png',
    'DeNA': 'backend/assets/images/team_db.png',
    '横浜': 'backend/assets/images/team_db.png',
    'カープ': 'backend/assets/images/team_c.png',
    '広島': 'backend/assets/images/team_c.png',
    'ホークス': 'backend/assets/images/team_h.png',
    'ソフトバンク': 'backend/assets/images/team_h.png',
    'ライオンズ': 'backend/assets/images/team_l.png',
    '西武': 'backend/assets/images/team_l.png',
    'ファイターズ': 'backend/assets/images/team_f.png',
    '北海道日本ハム': 'backend/assets/images/team_f.png',
    '日本ハム': 'backend/assets/images/team_f.png',
    'バファローズ': 'backend/assets/images/team_bs.png',
    'オリックス': 'backend/assets/images/team_bs.png',
    'イーグルス': 'backend/assets/images/team_e.png',
    '楽天': 'backend/assets/images/team_e.png',
    'マリーンズ': 'backend/assets/images/team_m.png',
    'ロッテ': 'backend/assets/images/team_m.png',
  };
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  final keys = logos.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    if (trimmed.contains(key)) return logos[key];
  }
  return null;
}

/// MLB 球団の略称。画像アセットが無いときのロゴ代わりに使う。
String? mlbTeamAbbrev(String name) {
  const map = <String, String>{
    'フィリーズ': 'PHI',
    'ブレーブス': 'ATL',
    'メッツ': 'NYM',
    'ナショナルズ': 'WSH',
    'マーリンズ': 'MIA',
    'ブリュワーズ': 'MIL',
    'ブルワーズ': 'MIL',
    'カージナルス': 'STL',
    'カブス': 'CHC',
    'レッズ': 'CIN',
    'パイレーツ': 'PIT',
    'ドジャース': 'LAD',
    'ダイヤモンドバックス': 'AZ',
    'Dバックス': 'AZ',
    'パドレス': 'SD',
    'ジャイアンツ': 'SF',
    'ロッキーズ': 'COL',
    'ヤンキース': 'NYY',
    'オリオールズ': 'BAL',
    'レッドソックス': 'BOS',
    'Rソックス': 'BOS',
    'レイズ': 'TB',
    'ブルージェイズ': 'TOR',
    'ガーディアンズ': 'CLE',
    'ロイヤルズ': 'KC',
    'ツインズ': 'MIN',
    'タイガース': 'DET',
    'ホワイトソックス': 'CWS',
    'Wソックス': 'CWS',
    'アストロズ': 'HOU',
    'マリナーズ': 'SEA',
    'レンジャーズ': 'TEX',
    'アスレチックス': 'ATH',
    'エンゼルス': 'LAA',
  };
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  if (RegExp(r'^[A-Z]{2,3}$').hasMatch(trimmed)) return trimmed;
  final keys = map.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    if (trimmed.contains(key)) return map[key];
  }
  return null;
}

const _mlbAbbrevCodes = {
  'PHI',
  'ATL',
  'NYM',
  'WSH',
  'MIA',
  'MIL',
  'STL',
  'CHC',
  'CIN',
  'PIT',
  'LAD',
  'AZ',
  'SD',
  'SF',
  'COL',
  'NYY',
  'BAL',
  'BOS',
  'TB',
  'TOR',
  'CLE',
  'KC',
  'MIN',
  'DET',
  'CWS',
  'HOU',
  'SEA',
  'TEX',
  'ATH',
  'LAA',
};

/// ESPN CDN の MLB ロゴ URL。表示は画像を使い、略称テキストは出さない。
String? mlbTeamLogoUrl({String? abbrev, String? name}) {
  var code = (abbrev ?? '').trim().toUpperCase();
  if (code.isEmpty || !_mlbAbbrevCodes.contains(code)) {
    code = mlbTeamAbbrev(name ?? '') ?? '';
  }
  if (code.isEmpty) return null;
  const espn = <String, String>{
    'AZ': 'ari',
    'CWS': 'chw',
    'ATH': 'ath',
  };
  final slug = espn[code] ?? code.toLowerCase();
  return 'https://a.espncdn.com/i/teamlogos/mlb/500/$slug.png';
}

/// NPB はアセット画像、MLB はロゴ URL。略称テキストは出さない。
/// `abbrev` が MLB 略称のときだけネットワークロゴを優先（巨人など NPB と名前が被る球団対策）。
({String? asset, String? networkUrl}) teamLogoVisual(String name, {String? abbrev}) {
  final code = (abbrev ?? '').trim().toUpperCase();
  if (code.isNotEmpty && _mlbAbbrevCodes.contains(code)) {
    final url = mlbTeamLogoUrl(abbrev: code);
    if (url != null) return (asset: null, networkUrl: url);
  }
  final asset = teamLogoAsset(name);
  if (asset != null) return (asset: asset, networkUrl: null);
  final url = mlbTeamLogoUrl(name: name);
  if (url != null) return (asset: null, networkUrl: url);
  return (asset: null, networkUrl: null);
}

String _compactPlayerName(String name) {
  final cut = name.split(RegExp(r'[（(]')).first;
  return cut.replaceAll(RegExp(r'\s+'), '');
}

/// 個人成績のリーグ順位。21位以下と、表に無い選手は出さない。
int? pitcherLeagueRank({
  required List<Map<String, dynamic>> stats,
  required String name,
  required int leagueId,
  required Iterable<String> titles,
}) {
  final wanted = _compactPlayerName(name);
  if (wanted.isEmpty || leagueId <= 0) return null;
  final titleSet = titles.toSet();
  int? best;
  for (final row in stats) {
    if ((int.tryParse('${row['id_league']}') ?? 0) != leagueId) continue;
    if (!titleSet.contains('${row['title'] ?? ''}'.trim())) continue;
    final rank = int.tryParse('${row['int_rank']}') ?? 0;
    if (rank < 1 || rank > 20) continue;
    if (_compactPlayerName('${row['name_player'] ?? ''}') != wanted) continue;
    if (best == null || rank < best) best = rank;
  }
  return best;
}

bool gameHasStarted(Map<String, dynamic> game) {
  final state = '${game['state'] ?? ''}'.trim();
  if (state.isNotEmpty) return true;
  final home = int.tryParse('${game['score_home']}') ?? -1;
  final away = int.tryParse('${game['score_away']}') ?? -1;
  return home >= 0 && away >= 0;
}

bool _isOrgPairGame(Map<String, dynamic> game, Set<int> leagueIds) {
  final home = _gameInt(game['id_league_home']);
  final away = _gameInt(game['id_league_away']);
  return leagueIds.contains(home) && leagueIds.contains(away);
}

Map<String, String> _todaysOrgStates(List<Map<String, dynamic>> games, String today, Set<int> leagueIds) {
  final states = <String, String>{};
  for (final game in games) {
    if (gameDateOnly(game['date_game']) != today) continue;
    if (!_isOrgPairGame(game, leagueIds)) continue;
    states[gameMatchupKey(game)] = '${game['state'] ?? ''}'.trim();
  }
  return states;
}

/// 当日の対象リーグ全試合が「試合終了」または「試合中止」。試合が1件もない日は false。
bool orgGamesAreSettled(List<Map<String, dynamic>> games, String today, Set<int> leagueIds) {
  final states = _todaysOrgStates(games, today, leagueIds);
  if (states.isEmpty) return false;
  return states.values.every((state) => state == '試合終了' || state == '試合中止');
}

/// 当日の対象リーグ全試合が「試合終了」。中止が残っている日は false。
bool orgGamesAllFinished(List<Map<String, dynamic>> games, String today, Set<int> leagueIds) {
  final states = _todaysOrgStates(games, today, leagueIds);
  if (states.isEmpty) return false;
  return states.values.every((state) => state == '試合終了');
}

/// 互換: セ・パ向け。
bool centralPacificGamesAreSettled(List<Map<String, dynamic>> games, String today) => orgGamesAreSettled(games, today, const {1, 2});

bool centralPacificGamesAllFinished(List<Map<String, dynamic>> games, String today) => orgGamesAllFinished(games, today, const {1, 2});

List<Map<String, dynamic>> expandGameRows(Map<String, dynamic> game) {
  final raw = game['summaries'];
  var summaries = const <Map<String, dynamic>>[];
  if (raw is List) {
    summaries = [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  } else if (raw is String) {
    final text = raw.trim();
    if (text.isNotEmpty && text != 'null') {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          summaries = [
            for (final item in decoded)
              if (item is Map) Map<String, dynamic>.from(item),
          ];
        }
      } catch (_) {}
    }
  }
  if (summaries.isEmpty) return [Map<String, dynamic>.from(game)..remove('summaries')];
  final base = Map<String, dynamic>.from(game)..remove('summaries');
  return [
    for (final summary in summaries) ({...base, ...summary}..remove('summaries')),
  ];
}

List<List<Map<String, dynamic>>> groupGamesByMatchup(List<Map<String, dynamic>> games) {
  final order = <String>[];
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final game in games) {
    for (final row in expandGameRows(game)) {
      final key = gameMatchupKey(row);
      if (!groups.containsKey(key)) {
        order.add(key);
        groups[key] = [];
      }
      groups[key]!.add(row);
    }
  }
  return [for (final key in order) groups[key]!];
}

List<Map<String, dynamic>> normalizeGames(List<Map<String, dynamic>> games) {
  return [
    for (final rows in groupGamesByMatchup(games))
      {
        ...rows.first,
        'summaries': rows,
      },
  ];
}

/// 日ヘッダー下の横長「活躍選手のみ表示 / 出場選手全表示」Picker。
Widget rosterModePicker({
  required bool allBatters,
  required ValueChanged<bool> onChanged,
}) {
  return SizedBox(
    height: 30,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFECEFF1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black26),
      ),
      child: Row(
        children: [
          for (final entry in const [(false, '活躍選手のみ表示'), (true, '出場選手全表示')])
            Expanded(
              child: Material(
                color: allBatters == entry.$1 ? const Color(0xFF37474F) : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                child: InkWell(
                  onTap: () => onChanged(entry.$1),
                  borderRadius: BorderRadius.circular(3),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        entry.$2,
                        style: TextStyle(
                          color: allBatters == entry.$1 ? Colors.white : Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class GameDateSwitcher extends StatefulWidget {
  final List<Map<String, dynamic>> games;
  final List<Map<String, dynamic>> playerStats;
  final Color headerColor;
  final String? initialDate;
  final bool horizontal;

  const GameDateSwitcher({
    super.key,
    required this.games,
    this.playerStats = const [],
    required this.headerColor,
    this.initialDate,
    this.horizontal = true,
  });

  @override
  State<GameDateSwitcher> createState() => _GameDateSwitcherState();
}

class _GameDateSwitcherState extends State<GameDateSwitcher> {
  late DateTime _baseDate;
  int _offset = 0;
  bool _allBatters = false;

  @override
  void initState() {
    super.initState();
    _baseDate = DateTime.tryParse(widget.initialDate ?? '') ?? DateTime.now();
    _baseDate = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
    // 初回フレームはウェブフォントの幅が足りず、選手名が切れることがある。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  DateTime get _selectedDate => _baseDate.add(Duration(days: _offset));

  String _jaDate(DateTime date) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return '${date.year}年${date.month.toString().padLeft(2, '0')}月'
        '${date.day.toString().padLeft(2, '0')}日'
        '(${weekdays[date.weekday - 1]})';
  }

  String _dayLabel() {
    if (_offset == -1) return '昨日';
    if (_offset == 0) return '今日の試合';
    if (_offset == 1) return '明日';
    if (_offset < 0) return '${-_offset}日前';
    return '$_offset日後';
  }

  void _move(int by) {
    setState(() => _offset += by);
  }

  Widget _dateButton(String label, int by) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Material(
        color: const Color(0xFF263238),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: () => _move(by),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = _selectedDate;
    final date = DateFormatUtil.ymd(selectedDate);
    final dayGames = normalizeGames(
      widget.games.where((game) => gameDateOnly(game['date_game']) == date).toList(),
    );
    final header = Container(
      height: 42,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.headerColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _dateButton('<< 前の日', -1),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _offset = 0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _dayLabel(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      OneLineShrinkText(
                        '（${_jaDate(selectedDate)}）',
                        baseSize: 11,
                        minSize: 8,
                        weight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _dateButton('次の日 >>', 1),
        ],
      ),
    );
    final board = GamesBoardYahooStyle(
      key: ValueKey('games-$date-${dayGames.map(gameMatchupKey).join('|')}'),
      games: dayGames,
      playerStats: widget.playerStats,
      dateFilter: date,
      horizontal: widget.horizontal,
      allBatters: _allBatters,
    );
    final picker = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: rosterModePicker(
        allBatters: _allBatters,
        onChanged: (value) {
          if (value == _allBatters) return;
          setState(() => _allBatters = value);
        },
      ),
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxHeight.isFinite) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            picker,
            const SizedBox(height: 4),
            Expanded(child: board),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          picker,
          const SizedBox(height: 4),
          board,
        ],
      );
    });
  }
}

/// 項目ごとの試合情報。日付ヘッダーは一つで、団体内の2リーグを縦に並べる。
class BothLeagueGameDay extends StatefulWidget {
  final List<Map<String, dynamic>> games;
  final List<Map<String, dynamic>> playerStats;
  final String? initialDate;
  final List<Widget> leading;
  final List<({int id, String name, Color color})> leagues;

  const BothLeagueGameDay({
    super.key,
    required this.games,
    this.playerStats = const [],
    this.initialDate,
    this.leading = const [],
    this.leagues = const [
      (id: 1, name: 'セ・リーグ', color: Color(0xFF0E8E2D)),
      (id: 2, name: 'パ・リーグ', color: Color(0xFF01B1EA)),
    ],
  });

  @override
  State<BothLeagueGameDay> createState() => _BothLeagueGameDayState();
}

class _BothLeagueGameDayState extends State<BothLeagueGameDay> {
  late DateTime _baseDate;
  int _offset = 0;
  bool _allBatters = false;

  @override
  void initState() {
    super.initState();
    _baseDate = DateTime.tryParse(widget.initialDate ?? '') ?? DateTime.now();
    _baseDate = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
  }

  DateTime get _selectedDate => _baseDate.add(Duration(days: _offset));

  String _jaDate(DateTime date) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return '${date.year}年${date.month.toString().padLeft(2, '0')}月'
        '${date.day.toString().padLeft(2, '0')}日'
        '(${weekdays[date.weekday - 1]})';
  }

  String _dayLabel() {
    if (_offset == -1) return '昨日';
    if (_offset == 0) return '今日の試合';
    if (_offset == 1) return '明日';
    if (_offset < 0) return '${-_offset}日前';
    return '$_offset日後';
  }

  List<Map<String, dynamic>> _leagueGames(List<Map<String, dynamic>> dayGames, int leagueId) {
    return dayGames.where((game) {
      final home = int.tryParse('${game['id_league_home']}') ?? 0;
      final away = int.tryParse('${game['id_league_away']}') ?? 0;
      return home == leagueId && away == leagueId;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = _selectedDate;
    final date = DateFormatUtil.ymd(selectedDate);
    final dayGames = normalizeGames(
      widget.games.where((game) => gameDateOnly(game['date_game']) == date).toList(),
    );
    Widget dateButton(String label, int by) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Material(
          color: const Color(0xFF263238),
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: () => setState(() => _offset += by),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Center(
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      );
    }

    final header = Container(
      height: 42,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF37474F),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          dateButton('<< 前の日', -1),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _offset = 0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_dayLabel(), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, height: 1.1)),
                      OneLineShrinkText('（${_jaDate(selectedDate)}）', baseSize: 11, minSize: 8, weight: FontWeight.bold, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ),
          dateButton('次の日 >>', 1),
        ],
      ),
    );

    Widget leagueBlock(String label, Color color, int leagueId) {
      final leagueGames = _leagueGames(dayGames, leagueId);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 28,
            alignment: Alignment.center,
            color: color,
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(height: 4),
          GamesBoardYahooStyle(
            key: ValueKey('both-$leagueId-$date-${leagueGames.map(gameMatchupKey).join('|')}'),
            games: leagueGames,
            playerStats: widget.playerStats,
            dateFilter: date,
            horizontal: true,
            allBatters: _allBatters,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              ...widget.leading,
              header,
              const SizedBox(height: 4),
              rosterModePicker(
                allBatters: _allBatters,
                onChanged: (value) {
                  if (value == _allBatters) return;
                  setState(() => _allBatters = value);
                },
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < widget.leagues.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                leagueBlock(widget.leagues[i].name, widget.leagues[i].color, widget.leagues[i].id),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class GamesBoardYahooStyle extends StatefulWidget {
  final List<Map<String, dynamic>> games;
  final List<Map<String, dynamic>> playerStats;
  final String? dateFilter; // "YYYY-MM-DD"
  /// true のとき試合カードを横並び表示（リーグ内の1日分向け）
  final bool horizontal;
  /// 日単位の「全員」表示。null のときは内部状態＋上部Picker。
  final bool? allBatters;
  final ValueChanged<bool>? onAllBatters;

  const GamesBoardYahooStyle({
    super.key,
    required this.games,
    this.playerStats = const [],
    this.dateFilter,
    this.horizontal = false,
    this.allBatters,
    this.onAllBatters,
  });

  @override
  State<GamesBoardYahooStyle> createState() => _GamesBoardYahooStyleState();
}

class _GamesBoardYahooStyleState extends State<GamesBoardYahooStyle> {
  bool _localAllBatters = false;

  List<Map<String, dynamic>> get games => widget.games;
  String? get dateFilter => widget.dateFilter;
  bool get horizontal => widget.horizontal;
  bool get _allBatters => widget.allBatters ?? _localAllBatters;

  void _setAllBatters(bool value) {
    if (widget.onAllBatters != null) {
      widget.onAllBatters!(value);
      return;
    }
    if (value == _localAllBatters) return;
    setState(() => _localAllBatters = value);
  }

  _TableGameCard _card(List<Map<String, dynamic>> rows) {
    return _TableGameCard(
      rows,
      playerStats: widget.playerStats,
      allBatters: _allBatters,
    );
  }

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

  List<List<Map<String, dynamic>>> _groupGames(List<Map<String, dynamic>> src) {
    return groupGamesByMatchup(src);
  }

  Widget _wrapWithLocalPicker(Widget board) {
    if (widget.allBatters != null) return board;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rosterModePicker(allBatters: _allBatters, onChanged: _setAllBatters),
        const SizedBox(height: 4),
        Expanded(child: board),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final src = (dateFilter == null || dateFilter!.isEmpty) ? games : games.where((g) => gameDateOnly(g['date_game']) == dateFilter).toList();
    final grouped = _groupGames(normalizeGames(src));

    if (horizontal) {
      if (grouped.isEmpty) {
        final empty = const SizedBox(
          height: 40,
          child: Center(child: Text('試合はありません', style: TextStyle(fontSize: 12))),
        );
        if (widget.allBatters != null) return empty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rosterModePicker(allBatters: _allBatters, onChanged: _setAllBatters),
            const SizedBox(height: 4),
            empty,
          ],
        );
      }
      return _wrapWithLocalPicker(LayoutBuilder(builder: (context, constraints) {
        final started = grouped.any((rows) => gameHasStarted(rows.first));
        final stackedTeams = MediaQuery.sizeOf(context).width < stackedTeamsMaxWidth;
        final heights = [for (final rows in grouped) _card(rows).intrinsicHeight(stackedTeams: stackedTeams)];
        if (started) {
          final needed = heights.fold<double>(0, (sum, h) => sum + h) + 2 * math.max(0, grouped.length - 1);
          final canFit = constraints.maxHeight.isFinite && constraints.maxHeight + 0.5 >= needed;
          Widget column({required bool expand}) {
            return Column(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < grouped.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  expand
                      ? Expanded(
                          flex: math.max(1, heights[i].round()),
                          child: _card(grouped[i]),
                        )
                      : SizedBox(height: heights[i], child: _card(grouped[i])),
                ],
              ],
            );
          }

          if (canFit) return column(expand: true);
          if (!constraints.maxHeight.isFinite) return column(expand: false);
          return SingleChildScrollView(child: column(expand: false));
        }

        final neededH = heights.reduce(math.max);
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < grouped.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(child: _card(grouped[i])),
            ],
          ],
        );
        if (!constraints.maxHeight.isFinite) {
          return SizedBox(height: neededH, child: row);
        }
        if (constraints.maxHeight + 0.5 >= neededH) return row;
        return SingleChildScrollView(child: SizedBox(height: neededH, child: row));
      }));
    }

    final bySec = <String, List<List<Map<String, dynamic>>>>{};
    for (final rows in grouped) {
      final sec = _sectionOf(rows.first);
      bySec.putIfAbsent(sec, () => []).add(rows);
    }

    if (bySec.isEmpty) {
      final empty = const Center(child: Text('試合はありません', style: TextStyle(fontSize: 12)));
      return widget.allBatters != null
          ? empty
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                rosterModePicker(allBatters: _allBatters, onChanged: _setAllBatters),
                const SizedBox(height: 4),
                Expanded(child: empty),
              ],
            );
    }

    return _wrapWithLocalPicker(LayoutBuilder(builder: (context, c) {
      final bySecKeys = bySec.keys.toSet();
      final order = ['セ・リーグ', 'パ・リーグ'].where((k) => bySecKeys.contains(k)).toList();

      Widget threeRows(List<List<Map<String, dynamic>>> list) {
        final g0 = list.isNotEmpty ? list[0] : null;
        final g1 = list.length > 1 ? list[1] : null;
        final g2 = list.length > 2 ? list[2] : null;

        Widget slot(List<Map<String, dynamic>>? g) {
          if (g == null) return const SizedBox();
          return LayoutBuilder(builder: (context, cc) {
            final double hAvail = cc.maxHeight.isFinite ? cc.maxHeight : 0.0;
            const double minCardH = 110.0; // これ以下なら内部スクロール
            if (hAvail <= 0 || hAvail >= minCardH) {
              return _card(g);
            }
            return SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: SizedBox(height: minCardH, child: _card(g)),
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
    }));
  }
}

typedef _PlayerLine = ({String name, String role, String colors, String mark, String stat, String hrTotal, String predict, String plays, String achieve, String tone, String chips, int rbi});

typedef _LineupSlot = ({int order, List<_PlayerLine> players});

class _TableGameCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> playerStats;
  final bool allBatters;

  const _TableGameCard(this.rows, {this.playerStats = const [], this.allBatters = false});

  Map<String, dynamic> get game => rows.first;

  static const _lineColor = Color(0xFF333333);
  static const _labelColor = Color(0xFF5A5A5A);
  static const _minPlayerNameSize = 8.0;
  static const _minPlayerStatSize = 8.0;
  static const _minHeaderH = 22.0;
  static const _minTeamRowH = 46.0;
  static const _playerRowH = 18.0;
  static const _lineScoreH = 42.0;
  static const _seasonGap = 6.0;
  static const _seasonLineH = 16.0;

  String _text(String key) => game[key]?.toString() ?? '';

  String _seasonLine(bool home) {
    return _seasonParts(home).join(' ');
  }

  List<String> _seasonParts(bool home) {
    if (gameHasStarted(game)) return const [];
    final raw = _text(home ? 'txt_season_pitcher_home' : 'txt_season_pitcher_away').trim();
    if (raw.isEmpty || raw == 'null') return const [];
    return raw.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).map(_qualifyingLabel).toList();
  }

  String _qualifyingLabel(String part) {
    if (part.startsWith('規定到達率') || !part.startsWith('規定')) return part;
    return '規定到達率${part.substring(2)}';
  }

  ({String label, String value}) _seasonStat(String part) {
    if (part.startsWith('規定到達率')) {
      return (label: '規定到達率', value: part.substring('規定到達率'.length));
    }
    final strikeouts = RegExp(r'^(\d+)奪三振$').firstMatch(part);
    if (strikeouts != null) return (label: '奪三振', value: strikeouts.group(1)!);
    if (RegExp(r'^\d+勝\d+敗$').hasMatch(part)) return (label: '勝敗', value: part);
    if (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(part)) return (label: '防御率', value: part);
    return (label: part, value: '');
  }

  int _seasonMarkRow(String label, int rows) {
    if (rows <= 0) return 0;
    final t = label.replaceAll(RegExp(r'\s+'), '');
    if (t.contains('規定')) return rows - 1;
    // titles_pitcher は短縮名（防/勝/奪）で来ることもある
    if (t.contains('奪三振') || t == '奪') return math.min(2, rows - 1);
    if (t.contains('防御') || t == '防') return math.min(1, rows - 1);
    return 0;
  }

  List<List<Color>> _seasonChipColors(String predict, int rows) {
    final colors = List.generate(rows, (_) => <Color>[]);
    if (rows <= 0) return colors;
    for (final part in predict.split(',')) {
      if (part.isEmpty) continue;
      final bar = part.indexOf('|');
      final label = (bar < 0 ? part : part.substring(0, bar)).trim();
      final color = parseColorNameOrNull(bar < 0 ? '' : part.substring(bar + 1));
      if (color == null) continue;
      final row = colors[_seasonMarkRow(label, rows)];
      if (!row.contains(color)) row.add(color);
    }
    return colors;
  }

  Widget _seasonNameChip(String label, double fontSize, double? width, List<Color> colors) {
    final average = colors.isEmpty ? 0.0 : colors.map((color) => color.computeLuminance()).reduce((a, b) => a + b) / colors.length;
    final ink = colors.isEmpty || average <= 0.55 ? Colors.white : Colors.black87;
    final decoration = colors.length >= 2
        ? BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(2),
          )
        : BoxDecoration(
            color: colors.isEmpty ? Colors.black : colors.first,
            borderRadius: BorderRadius.circular(2),
          );
    return Container(
      width: width,
      padding: width == null ? const EdgeInsets.symmetric(horizontal: 4) : null,
      margin: const EdgeInsets.symmetric(vertical: 1),
      alignment: Alignment.center,
      decoration: decoration,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: TextStyle(color: ink, fontSize: fontSize, fontWeight: FontWeight.bold, height: 1),
      ),
    );
  }

  double? _qualifyingPercent(List<({String label, String value})> lines) {
    for (final line in lines) {
      if (line.label != '規定到達率') continue;
      return double.tryParse(line.value.replaceAll('%', '').trim());
    }
    return null;
  }

  String _seasonRankNote(String label, List<({String label, String value})> lines, String pitcherName) {
    if (label == '規定到達率' || label.isEmpty) return '';
    final titles = switch (label) {
      '勝敗' => const ['最多勝', '勝利'],
      '防御率' => const ['防御率'],
      '奪三振' => const ['奪三振'],
      _ => const <String>[],
    };
    if (titles.isEmpty) return '';
    if (label == '防御率') {
      final rate = _qualifyingPercent(lines);
      if (rate == null || rate < 100) return '';
    }
    final compact = _compactPlayerName(pitcherName);
    final home = _compactPlayerName(_text('name_pitcher_home'));
    final away = _compactPlayerName(_text('name_pitcher_away'));
    final leagueId = compact == home
        ? (int.tryParse('${game['id_league_home']}') ?? 0)
        : compact == away
            ? (int.tryParse('${game['id_league_away']}') ?? 0)
            : 0;
    final rank = pitcherLeagueRank(stats: playerStats, name: pitcherName, leagueId: leagueId, titles: titles);
    if (rank == null) return '';
    return '（リーグ$rank位）';
  }

  Widget _seasonStatTable(String stat, String predict, double fontSize, {required String pitcherName}) {
    final lines = stat.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).map(_seasonStat).toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    final colors = _seasonChipColors(predict, lines.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines.length; i++)
          SizedBox(
            height: _seasonLineH,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _seasonNameChip(lines[i].label, fontSize, null, colors[i]),
                const SizedBox(width: 3),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: lines[i].value),
                      TextSpan(text: _seasonRankNote(lines[i].label, lines, pitcherName)),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: Colors.black87, height: 1),
                ),
              ],
            ),
          ),
      ],
    );
  }

  double _seasonBlockH() {
    if (gameHasStarted(game)) return 0;
    final lines = math.max(_seasonParts(true).length, _seasonParts(false).length);
    if (lines == 0) return 0;
    return _seasonGap + lines * _seasonLineH;
  }

  int _int(String key) => int.tryParse('${game[key]}') ?? -1;

  bool _isPitcher(Map<String, dynamic> row) {
    final value = row['flg_pitcher'];
    if (value is bool) return value;
    final text = '$value'.trim().toLowerCase();
    return text == 'true' || text == 't' || text == '1';
  }

  String _defenseMark(String raw) {
    const positions = {'投', '捕', '一', '二', '三', '遊', '左', '中', '右', '指'};
    final text = raw.trim();
    if (positions.contains(text)) return text;
    return '';
  }

  String _batterMark(Map<String, dynamic> row) {
    final homers = int.tryParse('${row['int_homerun'] ?? ''}') ?? 0;
    if (homers > 0) return 'HR';
    final batting = '${row['txt_batting'] ?? ''}';
    if (RegExp(r'\d+HR').hasMatch(batting)) return 'HR';
    return '';
  }

  String _resultMark(dynamic code) {
    final text = '${code ?? ''}'.trim().toUpperCase();
    return switch (text) {
      'WIN' || '勝' => '勝',
      'LOSE' || '負' => '負',
      'SAVE' || 'S' => 'S',
      'HOLD' || 'H' => 'H',
      _ => '',
    };
  }

  /// 投手の役割マーク。先発=先、抑え(セーブ)=抑、それ以外の救援=中。
  String _pitcherRoleMark(String name, String starterName, dynamic codeResult) {
    if (name.trim().isEmpty) return '';
    if (name.trim() == starterName.trim() && starterName.trim().isNotEmpty) return '先';
    final result = _resultMark(codeResult);
    if (result == 'S') return '抑';
    return '中';
  }

  Color _pale(Color? color, {bool lighter = false}) {
    final base = color ?? const Color(0xFFE0E0E0);
    final mix = lighter ? 0.86 : 0.58;
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

  String _statOf(Map<String, dynamic> row, {required bool pitcher}) {
    if (!pitcher) return '';
    final raw = '${row['txt_pitching'] ?? ''}'.trim();
    if (raw.isEmpty || raw == 'null') return '';
    return raw;
  }

  String _playsOf(Map<String, dynamic> row) {
    final raw = '${row['txt_plays'] ?? ''}'.trim();
    if (raw.isEmpty || raw == 'null') return '';
    return raw;
  }

  bool _isPitchCount(String part) {
    final label = part.split('|').first.trim();
    return RegExp(r'^\d+球$').hasMatch(label);
  }

  List<String> _visibleAchievements(String raw) {
    final parts = raw.split(' ').where((part) => part.isNotEmpty).toList();
    final hasHqs = parts.any((part) => part == 'HQS' || part.startsWith('HQS|'));
    if (!hasHqs) return parts;
    return parts.where((part) => part != 'QS' && !part.startsWith('QS|')).toList();
  }

  bool _isPitcherFeat(String part) {
    final bar = part.lastIndexOf('|');
    final label = (bar < 0 ? part : part.substring(0, bar)).trim();
    final kind = bar < 0 ? '' : part.substring(bar + 1).trim();
    const labels = {'完全試合', 'ノーヒットノーラン', 'マダックス', '完封', '完投', 'HQS', 'QS'};
    const kinds = {'perfect', 'nohit', 'maddux', 'shutout', 'cg', 'hqs', 'qs'};
    return labels.contains(label) || kinds.contains(kind);
  }

  String _achieveOf(Map<String, dynamic> row, {bool pitcher = false}) {
    final raw = '${row['txt_achieve'] ?? ''}'.trim();
    if (raw.isEmpty || raw == 'null') return '';
    final finished = '${game['state'] ?? ''}'.contains('試合終了');
    final parts = raw.split(' ').where((part) => part.isNotEmpty).toList();
    final hasAllHit = parts.any((part) {
      final bits = part.split('|');
      final label = bits.first.trim();
      final kind = bits.length > 1 ? bits[1].trim() : '';
      return label == '全打席安打' || kind == 'allhit';
    });
    return parts.where((part) {
      final bits = part.split('|');
      final label = bits.first.trim();
      final kind = bits.length > 1 ? bits[1].trim() : '';
      // 試合中は全打席出塁を出さない（終了後のみ）。
      if (!finished && (label == '全打席出塁' || kind == 'allreach')) return false;
      // 全打席安打があるときは全打席出塁は出さない。
      if (hasAllHit && (label == '全打席出塁' || kind == 'allreach')) return false;
      if (pitcher) return label != '全打席安打' && label != '全打席出塁';
      return !_isPitcherFeat(part);
    }).join(' ');
  }

  String _enterRole(String name, int teamId) {
    final raw = game['lineup'];
    if (raw is! List) return '';
    for (final item in raw) {
      if (item is! Map) continue;
      final team = int.tryParse('${item['id_team']}') ?? -1;
      if (team != teamId) continue;
      final listed = item['players'];
      if (listed is! List) continue;
      for (final player in listed) {
        if (player is! Map) continue;
        if ('${player['name'] ?? ''}'.trim() != name) continue;
        final role = '${player['role'] ?? ''}'.trim();
        if (role.isNotEmpty && role != 'null') return role;
      }
    }
    return '';
  }

  String _shownName(_PlayerLine player) {
    final role = player.role.trim();
    // 投手の先/中/抑はバッジ表示。代打などの交代役割だけ名前に付ける。
    if (role.isEmpty || role == '先' || role == '中' || role == '抑') return player.name;
    return '$role: ${player.name}';
  }

  bool _flagTrue(dynamic value) {
    if (value == true) return true;
    if (value is num) return value != 0;
    final s = '$value'.trim().toLowerCase();
    return s == 'true' || s == 't' || s == '1';
  }

  /// ACE は試合開始前（state 空 or 試合前）だけ。
  bool _aceVisibleNow() {
    final state = '${game['state'] ?? ''}'.trim();
    return state.isEmpty || state == '試合前';
  }

  /// 中継ぎ・抑え、および今試合の投球回が少ない投手には出さない。
  bool _isAcePitcher(String name, {int? teamId, String role = '', String chips = '', String stat = ''}) {
    if (!_aceVisibleNow()) return false;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final roleMark = role.trim();
    if (roleMark == '中' || roleMark == '抑') return false;
    // 今試合の投球回が取れていて短い（概ね4回未満）なら中継ぎ扱い。
    final ip = _inningsPitched(chips.isNotEmpty ? chips : stat);
    if (ip != null && ip + 1e-9 < 4.0) return false;

    if (trimmed == _text('name_pitcher_home') && _flagTrue(game['flg_ace_pitcher_home'])) return true;
    if (trimmed == _text('name_pitcher_away') && _flagTrue(game['flg_ace_pitcher_away'])) return true;
    for (final row in rows) {
      if ('${row['name_full_summary'] ?? ''}'.trim() != trimmed) continue;
      if (teamId != null) {
        final summaryTeam = int.tryParse('${row['id_team_summary']}') ?? -1;
        if (summaryTeam != teamId) continue;
      }
      if (_flagTrue(row['flg_ace'])) return true;
    }
    return false;
  }

  /// `6.1回…` / チップ先頭の投球回からアウト換算のイニング数を返す。取れなければ null。
  double? _inningsPitched(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text == 'null') return null;
    final match = RegExp(r'([\d.]+)\s*回').firstMatch(text);
    if (match == null) return null;
    final v = double.tryParse(match.group(1) ?? '');
    if (v == null || v < 0) return null;
    final whole = v.truncateToDouble();
    final frac = ((v - whole) * 10).round();
    if (frac == 1) return whole + 1 / 3;
    if (frac == 2) return whole + 2 / 3;
    return whole;
  }

  String _toneOf(Map<String, dynamic> row) {
    final raw = '${row['txt_pitch_tone'] ?? ''}'.trim();
    if (raw.isEmpty || raw == 'null') return '';
    return raw;
  }

  String _chipsOf(Map<String, dynamic> row, {required bool starter}) {
    final raw = '${row['txt_pitch_chips'] ?? ''}'.trim();
    if (raw.isNotEmpty && raw != 'null') return raw;
    // 旧サーバで 0回のチップが空のとき、投球文字列から色付きチップを復元する。
    return _chipsFromPitchingText('${row['txt_pitching'] ?? ''}', starter: starter);
  }

  /// `0回1失点(被安打1無四球0奪三振)` / `6.1回8安打3失点(3四球3奪三振119球)` 形式から色付きチップを作る。
  String _chipsFromPitchingText(String raw, {required bool starter}) {
    final text = raw.trim();
    if (text.isEmpty || text == 'null') return '';
    final match = RegExp(r'^([\d.]+)回(?:(無|\d+)安打)?(無|\d+)失点(?:\((.+)\))?$').firstMatch(text);
    if (match == null) return '';
    final innings = double.tryParse(match.group(1)!) ?? 0;
    final runsRaw = match.group(3)!;
    final runs = runsRaw == '無' ? 0 : (int.tryParse(runsRaw) ?? 0);
    final body = match.group(4) ?? '';
    final hitsPrefix = match.group(2);
    final hits = hitsPrefix != null
        ? (hitsPrefix == '無' ? 0 : (int.tryParse(hitsPrefix) ?? 0))
        : body.contains('無安打')
            ? 0
            : (int.tryParse(RegExp(r'被安打(\d+)').firstMatch(body)?.group(1) ?? '') ?? 0);
    final walkMatch = RegExp(r'(無|\d+)四球').firstMatch(body);
    final walks = walkMatch == null || walkMatch.group(1) == '無' ? 0 : (int.tryParse(walkMatch.group(1)!) ?? 0);
    final hbp = int.tryParse(RegExp(r'(\d+)死球').firstMatch(body)?.group(1) ?? '') ?? 0;
    final strikeouts = int.tryParse(RegExp(r'(\d+)奪三振').firstMatch(body)?.group(1) ?? '') ?? 0;
    final pitches = int.tryParse(RegExp(r'(\d+)球').firstMatch(body)?.group(1) ?? '') ?? 0;
    return _buildPitcherChips(
      innings: innings,
      runs: runs,
      hits: hits,
      walks: walks,
      hbp: hbp,
      strikeouts: strikeouts,
      pitches: pitches,
      starter: starter,
    );
  }

  String _buildPitcherChips({
    required double innings,
    required int runs,
    required int hits,
    required int walks,
    required int hbp,
    required int strikeouts,
    required int pitches,
    required bool starter,
  }) {
    final whole = innings.truncate();
    var thirds = ((innings - whole) * 10).round();
    if (thirds < 0) thirds = 0;
    if (thirds > 2) thirds = 2;
    final outs = whole * 3 + thirds;
    final freePasses = walks + hbp;
    final hasWork = outs > 0 || pitches > 0 || hits > 0 || freePasses > 0 || strikeouts > 0 || runs > 0;
    if (!hasWork) return '';
    final ip = outs > 0 ? outs / 3.0 : 1 / 3.0;
    String lower(double rate, List<double> bounds) {
      const tones = ['crimson', 'rorange', 'yorange', 'yellow', 'green', 'blue'];
      for (var i = 0; i < bounds.length; i++) {
        if (rate <= bounds[i] + 1e-9) return tones[i];
      }
      return 'gray';
    }

    String higher(double rate, List<double> bounds) {
      const tones = ['crimson', 'rorange', 'yorange', 'yellow', 'green', 'blue'];
      for (var i = 0; i < bounds.length; i++) {
        if (rate + 1e-9 >= bounds[i]) return tones[i];
      }
      return 'gray';
    }

    String reliefK(double rate) {
      if (rate + 1e-9 >= 3) return 'crimson';
      if (rate + 1e-9 >= 2) return 'rorange';
      if (rate + 1e-9 >= 1) return 'yellow';
      return 'green';
    }

    final inningsLabel = thirds <= 0 ? '$whole回' : '$whole.$thirds回';
    final runsTone = lower(runs / ip, const [0, 0.15, 0.30, 0.45, 0.6, 0.75]);
    final parts = <String>[
      '$inningsLabel${runs == 0 ? '無失点' : '$runs失点'}|${runsTone == 'gray' ? 'dgray' : runsTone}',
      '被安打$hits|${lower(hits / ip, const [0, 0.3, 0.6, 0.9, 1.2, 1.5])}',
      '四死球$freePasses|${lower(freePasses / ip, const [0, 0.15, 0.30, 0.45, 0.6, 0.75])}',
      '$strikeouts奪三振|${starter ? higher(strikeouts / ip, const [1, 0.85, 0.7, 0.55, 0.4, 0.25]) : reliefK(strikeouts / ip)}',
    ];
    if (pitches > 0) parts.add('$pitches球|');
    return parts.join(' ');
  }

  String _predictLabel(dynamic raw) {
    final seen = <String>{};
    final marks = <String>[];
    for (final part in '$raw'.split(',')) {
      final text = part.trim();
      if (text.isEmpty || text == 'null') continue;
      final bar = text.indexOf('|');
      final label = (bar < 0 ? text : text.substring(0, bar)).trim();
      final color = bar < 0 ? '' : text.substring(bar + 1).trim();
      if (label.isEmpty || !seen.add('$label|$color')) continue;
      marks.add(color.isEmpty ? label : '$label|$color');
    }
    return marks.join(',');
  }

  /// 活躍選手のみ: 先発と勝/負/H/S の投手だけ。
  bool _keepNotablePitcher(_PlayerLine player, String starterName) {
    if (starterName.isNotEmpty && player.name == starterName) return true;
    return switch (player.mark) {
      '勝' || '負' || 'H' || 'S' => true,
      _ => false,
    };
  }

  List<_PlayerLine> _players({
    required bool home,
    required bool pitcher,
  }) {
    final teamId = _int(home ? 'id_team_home' : 'id_team_away');
    final starterName = _text(home ? 'name_pitcher_home' : 'name_pitcher_away');
    final starterColors = _text(home ? 'colors_pitcher_home' : 'colors_pitcher_away');
    final result = <_PlayerLine>[];

    void add(String name, String playerColors, String mark, [String stat = '', String hrTotal = '', String predict = '', String plays = '', String achieve = '', String tone = '', String chips = '', int rbi = 0, String roleOverride = '']) {
      if (name.trim().isEmpty) return;
      final role = roleOverride.isNotEmpty
          ? roleOverride
          : pitcher
              ? _pitcherRoleMark(name, starterName, '')
              : _enterRole(name, teamId);
      final index = result.indexWhere((player) => player.name == name);
      final labels = _predictLabel(predict);
      if (index < 0) {
        result.add((name: name, role: role, colors: playerColors, mark: mark, stat: stat, hrTotal: hrTotal, predict: labels, plays: plays, achieve: achieve, tone: tone, chips: chips, rbi: rbi));
        return;
      }
      final current = result[index];
      result[index] = (
        name: current.name,
        role: current.role.isNotEmpty ? current.role : role,
        colors: current.colors.isNotEmpty ? current.colors : playerColors,
        mark: current.mark.isNotEmpty ? current.mark : mark,
        stat: current.stat.isNotEmpty ? current.stat : stat,
        hrTotal: current.hrTotal.isNotEmpty ? current.hrTotal : hrTotal,
        predict: _predictLabel('${current.predict},$labels'),
        plays: current.plays.isNotEmpty ? current.plays : plays,
        achieve: current.achieve.isNotEmpty ? current.achieve : achieve,
        tone: current.tone.isNotEmpty ? current.tone : tone,
        chips: current.chips.isNotEmpty ? current.chips : chips,
        rbi: current.rbi > 0 ? current.rbi : rbi,
      );
    }

    for (final row in rows) {
      final name = '${row['name_full_summary'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final summaryTeam = int.tryParse('${row['id_team_summary']}') ?? -1;
      if (summaryTeam != teamId) continue;
      if (_isPitcher(row) != pitcher) continue;
      final colors = '${row['colors_summary'] ?? ''}'.trim();
      final mark = pitcher ? _resultMark(row['code_result_pitcher']) : _batterMark(row);
      final chips = pitcher ? _chipsOf(row, starter: name == starterName) : '';
      final role = pitcher ? _pitcherRoleMark(name, starterName, row['code_result_pitcher']) : '';
      add(
        name,
        colors.isNotEmpty ? colors : (name == starterName ? starterColors : ''),
        mark,
        chips.isNotEmpty ? '' : _statOf(row, pitcher: pitcher),
        '',
        '${row['titles_predict'] ?? ''}',
        pitcher ? '' : _playsOf(row),
        _achieveOf(row, pitcher: pitcher),
        pitcher && chips.isEmpty ? _toneOf(row) : '',
        chips,
        0,
        role,
      );
    }

    final starterTitles = pitcher ? _text(home ? 'titles_pitcher_home' : 'titles_pitcher_away') : '';
    if (pitcher && starterTitles.isNotEmpty && result.any((player) => player.name == starterName)) {
      add(starterName, starterColors, '', '', '', starterTitles, '', '', '', '', 0, '先');
    }

    if (result.isEmpty && pitcher) {
      add(starterName, starterColors, '', _seasonLine(home), '', starterTitles, '', '', '', '', 0, '先');
      if (_int('id_team_pitcher_win') == teamId) {
        final winName = _text('name_pitcher_win');
        add(winName, '', '勝', '', '', '', '', '', '', '', 0, _pitcherRoleMark(winName, starterName, 'WIN'));
      }
      if (_int('id_team_pitcher_lose') == teamId) {
        final loseName = _text('name_pitcher_lose');
        add(loseName, '', '負', '', '', '', '', '', '', '', 0, _pitcherRoleMark(loseName, starterName, 'LOSE'));
      }
      if (_int('id_team_pitcher_save') == teamId) {
        final saveName = _text('name_pitcher_save');
        add(saveName, '', 'S', '', '', '', '', '', '', '', 0, _pitcherRoleMark(saveName, starterName, 'SAVE'));
      }
    } else if (result.isEmpty && !pitcher) {
      add(_text(home ? 'name_homerun_home' : 'name_homerun_away'), '', 'HR');
    }

    // 活躍選手のみ: 投手は先発と勝敗HSのみ（出場選手全表示では登板者をそのまま出す）。
    if (pitcher && !allBatters) {
      return result.where((player) => _keepNotablePitcher(player, starterName)).toList();
    }
    return result;
  }

  List<_LineupSlot> _lineupSlots({required bool home}) {
    final teamId = _int(home ? 'id_team_home' : 'id_team_away');
    final byOrder = <int, List<_PlayerLine>>{};
    final raw = game['lineup'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final team = int.tryParse('${item['id_team']}') ?? -1;
        if (team != teamId) continue;
        final order = int.tryParse('${item['order']}') ?? 0;
        if (order < 1 || order > 9) continue;
        final players = <_PlayerLine>[];
        final listed = item['players'];
        if (listed is List) {
          for (final player in listed) {
            if (player is! Map) continue;
            final name = '${player['name'] ?? ''}'.trim();
            if (name.isEmpty) continue;
            final role = '${player['role'] ?? ''}'.trim();
            players.add(_lineupPlayer(name, '${player['plays'] ?? ''}', teamId, role == 'null' ? '' : role, '${player['pos'] ?? ''}', player.containsKey('rbi') ? int.tryParse('${player['rbi']}') ?? 0 : null));
          }
        }
        byOrder[order] = players;
      }
    }
    return [for (var order = 1; order <= 9; order++) (order: order, players: byOrder[order] ?? const <_PlayerLine>[])];
  }

  int _rbiFromBatting(String raw) {
    return int.tryParse(RegExp(r'(\d+)打点').firstMatch(raw)?.group(1) ?? '') ?? 0;
  }

  _PlayerLine _lineupPlayer(String name, String plays, int teamId, String role, String position, int? listedRbi) {
    Map<String, dynamic>? summary;
    for (final row in rows) {
      if ('${row['name_full_summary'] ?? ''}'.trim() != name) continue;
      final summaryTeam = int.tryParse('${row['id_team_summary']}') ?? -1;
      if (summaryTeam != teamId || _isPitcher(row)) continue;
      summary = row;
      break;
    }
    final rawPlays = plays.trim() == 'null' ? '' : plays.trim();
    final shownRole = role.isNotEmpty ? role : _enterRole(name, teamId);
    final pos = _defenseMark(position);
    final rbi = listedRbi ?? _rbiFromBatting('${summary?['txt_batting'] ?? ''}');
    if (summary == null) {
      return (name: name, role: shownRole, colors: '', mark: pos, stat: '', hrTotal: '', predict: '', plays: rawPlays, achieve: '', tone: '', chips: '', rbi: rbi);
    }
    final colors = '${summary['colors_summary'] ?? ''}'.trim();
    final summaryPlays = _playsOf(summary);
    return (
      name: name,
      role: shownRole,
      colors: colors == 'null' ? '' : colors,
      mark: pos,
      stat: '',
      hrTotal: '',
      predict: _predictLabel('${summary['titles_predict'] ?? ''}'),
      plays: summaryPlays.isNotEmpty ? summaryPlays : rawPlays,
      achieve: _achieveOf(summary),
      tone: '',
      chips: '',
      rbi: rbi,
    );
  }

  Widget _batterHeader(double labelSize, {bool bottom = false, bool right = true}) {
    return _textCell(
      '打者',
      size: labelSize,
      minSize: 9,
      color: _labelColor,
      textColor: Colors.white,
      weight: FontWeight.bold,
      right: right,
      bottom: bottom,
    );
  }

  Widget _batterStatLine(_PlayerLine player, double statSize, {bool includeOuts = false}) {
    final achievements = _visibleAchievements(player.achieve);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final part in _orderedPlays(player.plays, includeOuts: includeOuts)) _playChip(part, statSize, compact: includeOuts),
        if (includeOuts && player.rbi > 0)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Text(
              '${player.rbi}打点',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(fontSize: statSize, fontWeight: FontWeight.bold, color: Colors.black87, height: 1),
            ),
          ),
        for (final part in achievements) _playChip(part, statSize, blink: true),
        if (player.predict.isNotEmpty) ...[
          if (player.plays.isNotEmpty || player.achieve.isNotEmpty) const SizedBox(width: 2),
          for (final part in player.predict.split(','))
            if (part.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: _predictBadge(part, statSize),
              ),
        ],
      ],
    );
  }

  Widget _lineupCell(
    List<_LineupSlot> slots, {
    required Color color,
    required double size,
    required bool right,
    bool bottom = false,
  }) {
    final nameSize = size < _minPlayerNameSize ? _minPlayerNameSize : size;
    final statSize = (nameSize * 0.92).clamp(_minPlayerStatSize, 12.0);
    final badgeWidth = (nameSize + 2).clamp(9.0, 16.0);
    const orderW = 14.0;
    return _cell(
      color: color,
      right: right,
      bottom: bottom,
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: LayoutBuilder(builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final count = math.max(1, slots.length);
        final fitRowH = maxH.isFinite ? math.min(_playerRowH, maxH / count) : _playerRowH;
        final cellW = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        if (cellW < 1) return const SizedBox.expand();
        final scaler = MediaQuery.textScalerOf(context);
        var nameW = 0.0;
        for (final slot in slots) {
          if (slot.players.isEmpty) continue;
          final shown = _shownName(slot.players.first);
          final w = _textWidth(shown, nameSize, weight: FontWeight.bold, textScaler: scaler) + 8;
          if (w > nameW) nameW = w;
        }
        nameW = nameW.ceilToDouble();
        final leadingW = orderW + badgeWidth;
        final maxNameBox = math.max(0.0, cellW - leadingW);
        if (nameW > maxNameBox) nameW = maxNameBox;
        const gapW = 2.0;
        final statsViewportW = math.max(0.0, cellW - leadingW - nameW - gapW);

        Widget nameRow(_LineupSlot slot) {
          final player = slot.players.isEmpty ? null : slot.players.first;
          return SizedBox(
            height: fitRowH,
            child: Row(
              children: [
                SizedBox(
                  width: orderW,
                  child: Text(
                    '${slot.order}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: math.min(9, fitRowH * 0.7), fontWeight: FontWeight.bold, color: Colors.black87, height: 1),
                  ),
                ),
                SizedBox(
                  width: badgeWidth,
                  child: player == null || player.mark.isEmpty ? const SizedBox() : _lineupMark(player.mark, nameSize),
                ),
                SizedBox(
                  width: nameW,
                  child: player == null
                      ? const SizedBox()
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _pitcherNameBox(
                            name: _shownName(player),
                            colorsRaw: player.colors,
                            baseSize: nameSize,
                            minSize: _minPlayerNameSize,
                            alignLeft: true,
                          ),
                        ),
                ),
              ],
            ),
          );
        }

        Widget statRow(_LineupSlot slot) {
          return SizedBox(
            height: fitRowH,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (slot.players.isNotEmpty) _batterStatLine(slot.players.first, statSize, includeOuts: true),
                  for (final player in slot.players.skip(1)) ...[
                    const SizedBox(width: 6),
                    _pitcherNameBox(
                      name: _shownName(player),
                      colorsRaw: player.colors,
                      baseSize: nameSize,
                      minSize: _minPlayerNameSize,
                      alignLeft: true,
                    ),
                    const SizedBox(width: 2),
                    _batterStatLine(player, statSize, includeOuts: true),
                  ],
                ],
              ),
            ),
          );
        }

        return SizedBox(
          width: cellW,
          height: maxH.isFinite ? maxH : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: leadingW + nameW,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final slot in slots) nameRow(slot)],
                ),
              ),
              if (statsViewportW > 0) ...[
                const SizedBox(width: gapW),
                SizedBox(
                  width: statsViewportW,
                  height: maxH.isFinite ? maxH : fitRowH * count,
                  child: ClipRect(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [for (final slot in slots) statRow(slot)],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }

  int _batterCount(bool home) {
    if (!allBatters) return _players(home: home, pitcher: false).length;
    return 9;
  }

  double _pitcherBlockH(int count) => math.max(1, count) * _playerRowH + _seasonBlockH();

  double intrinsicHeight({bool stackedTeams = false}) {
    final homePitchers = _players(home: true, pitcher: true);
    final awayPitchers = _players(home: false, pitcher: true);
    final batterHome = _batterCount(true);
    final batterAway = _batterCount(false);
    const sectionPad = 2.0;
    const chrome = 8.0;
    final inProgress = '${game['state'] ?? ''}'.contains('回');
    final head = _minHeaderH + _minTeamRowH + (_showLineScore ? _lineScoreH : 0) + chrome + (inProgress ? 6.0 : 0.0);
    final batterHomeH = _showBatterStats ? math.max(1, batterHome) * _playerRowH : 0.0;
    final batterAwayH = _showBatterStats ? math.max(1, batterAway) * _playerRowH : 0.0;
    if (stackedTeams) {
      return head + _pitcherBlockH(homePitchers.length) + batterHomeH + _pitcherBlockH(awayPitchers.length) + batterAwayH + sectionPad * (_showBatterStats ? 4 : 2);
    }
    final pitcherN = math.max(1, math.max(homePitchers.length, awayPitchers.length));
    final batterH = _showBatterStats ? math.max(1, math.max(batterHome, batterAway)) * _playerRowH : 0.0;
    return head + pitcherN * _playerRowH + _seasonBlockH() + batterH + sectionPad * 2;
  }

  bool get _showLineScore {
    final state = _text('state');
    if (state.isEmpty || state == '試合前') return false;
    return _int('score_home') >= 0 && _int('score_away') >= 0;
  }

  bool get _showBatterStats => gameHasStarted(game) && _text('state') != '試合前';

  List<String> _inningScores(String key) {
    return _text(key).split(',').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  }

  String _countText(String key) {
    final raw = game[key];
    if (raw == null || '$raw'.trim().isEmpty) return '0';
    final n = int.tryParse('$raw');
    return n == null ? '0' : '$n';
  }

  Widget _lineScoreTable({
    required Color? homeBg,
    required Color? awayBg,
    required Color homeFg,
    required Color awayFg,
  }) {
    final homeInnings = _inningScores('txt_scores_home');
    final awayInnings = _inningScores('txt_scores_away');
    final n = math.max(9, math.max(homeInnings.length, awayInnings.length));
    String at(List<String> values, int index) => index < values.length ? values[index] : '0';

    Widget row({
      required bool header,
      required String name,
      required List<String> innings,
      required String runs,
      required String hits,
      required String errors,
      Color? teamBg,
      Color teamFg = Colors.black87,
    }) {
      final numbers = <String>[
        for (var i = 0; i < n; i++) header ? '${i + 1}' : at(innings, i),
        header ? '計' : runs,
        header ? '安' : hits,
        header ? '失' : errors,
      ];
      return SizedBox(
        height: _lineScoreH / 3,
        child: LayoutBuilder(builder: (context, constraints) {
          // 回・計・安・失は同じ固定幅。余った幅はチーム名だけが受け取る。
          const preferredNumberW = 18.0;
          const minNameW = 32.0;
          final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : preferredNumberW * numbers.length + minNameW;
          var numberW = preferredNumberW;
          var nameW = maxW - numberW * numbers.length;
          if (nameW < minNameW) {
            nameW = math.min(minNameW, maxW * 0.34);
            numberW = numbers.isEmpty ? 0.0 : math.max(0.0, (maxW - nameW) / numbers.length);
          }

          Widget numberCell(int index) {
            final label = numbers[index];
            final total = index >= numbers.length - 3;
            return SizedBox(
              width: numberW,
              child: _cell(
                color: header ? const Color(0xFF555555) : Colors.white,
                right: index != numbers.length - 1,
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1,
                      fontWeight: header || total ? FontWeight.bold : FontWeight.w600,
                      color: header ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            );
          }

          return Row(
            children: [
              SizedBox(
                width: nameW,
                child: _cell(
                  color: header ? const Color(0xFF555555) : (teamBg ?? Colors.white),
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      name,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1,
                        fontWeight: FontWeight.bold,
                        color: header ? Colors.white : teamFg,
                      ),
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < numbers.length; i++) numberCell(i),
            ],
          );
        }),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _lineColor)),
      ),
      child: Column(
        children: [
          row(header: true, name: '', innings: const [], runs: '', hits: '', errors: ''),
          row(
            header: false,
            name: _text('name_team_away'),
            innings: awayInnings,
            runs: _countText('int_runs_away'),
            hits: _countText('int_hit_away'),
            errors: _countText('int_error_away'),
            teamBg: awayBg,
            teamFg: awayFg,
          ),
          row(
            header: false,
            name: _text('name_team_home'),
            innings: homeInnings,
            runs: _countText('int_runs_home'),
            hits: _countText('int_hit_home'),
            errors: _countText('int_error_home'),
            teamBg: homeBg,
            teamFg: homeFg,
          ),
        ],
      ),
    );
  }

  Widget _logoMark({
    String? asset,
    String? networkUrl,
    Color? bg,
    Color? fg,
    required double side,
  }) {
    Widget? image;
    if (asset != null) {
      image = Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    } else if ((networkUrl ?? '').trim().isNotEmpty) {
      image = Image.network(
        networkUrl!.trim(),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    if (image == null) return const SizedBox(width: 2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: SizedBox(width: side, height: side, child: image),
    );
  }

  Widget _matchScoreCell({
    required String state,
    required String score,
    required double stateSize,
    required double scoreSize,
    required String homeName,
    required String awayName,
    String? homeAbbrev,
    String? awayAbbrev,
    Color? homeBg,
    Color? awayBg,
    Color? homeFg,
    Color? awayFg,
  }) {
    return _cell(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: LayoutBuilder(builder: (context, constraints) {
        const gap = 6.0;
        const scoreMin = 28.0;
        const logoPad = 2.0;
        final preferred = _minTeamRowH * 0.9;
        final innerW = constraints.maxWidth.isFinite ? constraints.maxWidth : preferred * 2 + gap * 2 + scoreMin;
        final fitted = math.max(0.0, (innerW - gap * 2 - scoreMin - logoPad * 2) / 2);
        final logoSide = math.min(preferred, fitted);
        final homeLogo = teamLogoVisual(homeName, abbrev: homeAbbrev);
        final awayLogo = teamLogoVisual(awayName, abbrev: awayAbbrev);
        final scoreColumn = Column(
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
            if (state.isNotEmpty) const SizedBox(height: 2),
            Text(
              score,
              style: TextStyle(
                fontSize: scoreSize,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ],
        );
        return Row(
          children: [
            _logoMark(
              asset: homeLogo.asset,
              networkUrl: homeLogo.networkUrl,
              bg: homeBg,
              fg: homeFg,
              side: logoSide,
            ),
            const SizedBox(width: gap),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: scoreColumn,
              ),
            ),
            const SizedBox(width: gap),
            _logoMark(
              asset: awayLogo.asset,
              networkUrl: awayLogo.networkUrl,
              bg: awayBg,
              fg: awayFg,
              side: logoSide,
            ),
          ],
        );
      }),
    );
  }

  Widget _cell({
    required Widget child,
    Color? color,
    bool right = true,
    bool bottom = true,
    AlignmentGeometry alignment = Alignment.center,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
  }) {
    return Container(
      clipBehavior: Clip.hardEdge,
      alignment: alignment,
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
    double minSize = 9,
  }) {
    return _cell(
      color: color,
      right: right,
      bottom: bottom,
      child: OneLineShrinkText(
        text,
        baseSize: size,
        minSize: minSize,
        color: textColor ?? Colors.black87,
        weight: weight,
        align: align,
      ),
    );
  }

  double _textWidth(
    String text,
    double fontSize, {
    FontWeight weight = FontWeight.normal,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text.isEmpty ? '—' : text,
        style: TextStyle(fontSize: fontSize, fontWeight: weight, height: 1.1),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final measured = painter.width;
    if (text.isEmpty) return measured;
    var cjk = 0;
    final glyphs = text.runes.length;
    for (final rune in text.runes) {
      if (rune > 0xFF) cjk++;
    }
    // フォント未読込の初回は全角が極端に狭く測れる。1文字ぶんは確保する。
    final floorWidth = fontSize * (cjk + (glyphs - cjk) * 0.55);
    return measured < floorWidth ? floorWidth : measured;
  }

  double _nameColumnWidth(
    Iterable<_PlayerLine> players,
    double fontSize,
    BuildContext context,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    var width = 0.0;
    for (final player in players) {
      // _pitcherNameBox の左右 padding 2+2 に、末尾が切れない余裕を足す。
      final w = _textWidth(player.name, fontSize, weight: FontWeight.bold, textScaler: scaler) + 8;
      if (w > width) width = w;
    }
    return width.ceilToDouble();
  }

  Widget _pitcherCell(
    List<_PlayerLine> pitchers, {
    required Color color,
    required double size,
    required bool right,
    bool bottom = true,
    double nameColW = 0,
    bool centerNames = false,
  }) {
    final nameSize = size < _minPlayerNameSize ? _minPlayerNameSize : size;
    final statSize = (nameSize * 0.92).clamp(_minPlayerStatSize, 12.0);
    final rowH = _playerRowH;
    final badgeWidth = (nameSize + 2).clamp(9.0, 16.0);
    const roleMarks = {'先', '中', '抑'};

    // 投手(先/中/抑+勝負)と打者で名前の開始位置を揃えるため、先頭は常に2枠分。
    final leadingBadgesW = badgeWidth * 2 + 0.5;

    Widget pitcherBadges(_PlayerLine pitcher) {
      final role = pitcher.role.trim();
      final hasRole = roleMarks.contains(role);
      final hasResult = pitcher.mark.isNotEmpty;
      // 左=勝負HS、右=先/中/抑
      return SizedBox(
        width: leadingBadgesW - 0.5,
        child: Row(
          children: [
            SizedBox(
              width: badgeWidth,
              child: hasResult ? _resultBadge(pitcher.mark, nameSize) : const SizedBox(),
            ),
            SizedBox(
              width: badgeWidth,
              child: hasRole ? _lineupMark(role, nameSize, pitcherRole: true) : const SizedBox(),
            ),
          ],
        ),
      );
    }

    return _cell(
      color: color,
      right: right,
      bottom: bottom,
      alignment: centerNames ? Alignment.center : Alignment.topLeft,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: pitchers.isEmpty
          ? const SizedBox.expand()
          : LayoutBuilder(builder: (context, constraints) {
              final maxH = constraints.maxHeight;
              final fitRowH = maxH.isFinite && pitchers.isNotEmpty ? math.min(rowH, maxH / pitchers.length) : rowH;
              final cellW = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
              final scaler = MediaQuery.textScalerOf(context);
              final nameStatGap = 2.0 + _textWidth(' ', nameSize, textScaler: scaler);

              if (!constraints.maxWidth.isFinite || constraints.maxWidth < 1) {
                return const SizedBox.expand();
              }

              if (centerNames) {
                Widget centerBadges(_PlayerLine pitcher) {
                  final role = pitcher.role.trim();
                  final hasRole = roleMarks.contains(role);
                  final hasResult = pitcher.mark.isNotEmpty;
                  if (!hasRole && !hasResult) return const SizedBox.shrink();
                  // 左=勝負HS、右=先/中/抑
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasResult) SizedBox(width: badgeWidth, child: _resultBadge(pitcher.mark, nameSize)),
                      if (hasRole && hasResult) const SizedBox(width: 0.5),
                      if (hasRole) SizedBox(width: badgeWidth, child: _lineupMark(role, nameSize, pitcherRole: true)),
                      const SizedBox(width: 0.5),
                    ],
                  );
                }

                return SizedBox(
                  width: cellW,
                  height: maxH.isFinite ? maxH : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final pitcher in pitchers)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  centerBadges(pitcher),
                                  _pitcherNameBox(
                                    name: _shownName(pitcher),
                                    colorsRaw: pitcher.colors,
                                    baseSize: nameSize,
                                    minSize: _minPlayerNameSize,
                                    alignLeft: false,
                                    showAce: _isAcePitcher(
                                      pitcher.name,
                                      role: pitcher.role,
                                      chips: pitcher.chips,
                                      stat: pitcher.stat,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (pitcher.stat.isNotEmpty || pitcher.predict.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: _seasonGap),
                                child: _seasonStatTable(pitcher.stat, pitcher.predict, statSize, pitcherName: pitcher.name),
                              ),
                          ],
                        ),
                    ],
                  ),
                );
              }

              final reservedNameW = nameColW > 0 ? nameColW : _nameColumnWidth(pitchers, nameSize, context);
              final leadingW = leadingBadgesW;
              // 名前幅は成績のために削らない。セル自体が名前より狭いときだけクリップする。
              final maxNameBox = math.max(0.0, cellW - leadingW);
              final hasAnyStats = pitchers.any((p) => p.stat.isNotEmpty || p.chips.isNotEmpty || p.predict.isNotEmpty || p.achieve.isNotEmpty || _orderedPlays(p.plays).isNotEmpty);
              // _nameColumnWidth の +8 のうち、字形と左右 padding を超える余裕。
              final glyphBoxW = math.max(0.0, reservedNameW - 4);
              var nameBoxW = math.min(reservedNameW, maxNameBox);
              if (hasAnyStats && maxNameBox - nameBoxW <= 0 && glyphBoxW < maxNameBox) {
                nameBoxW = glyphBoxW;
              }
              final restW = math.max(0.0, cellW - leadingW - nameBoxW);
              final gapW = hasAnyStats && restW > nameStatGap ? nameStatGap : 0.0;
              final statsViewportW = hasAnyStats ? math.max(0.0, restW - gapW) : 0.0;

              Widget statLine(_PlayerLine pitcher) {
                final achievements = _visibleAchievements(pitcher.achieve);
                final chipParts = pitcher.chips.split(' ').where((part) => part.isNotEmpty);
                final metrics = chipParts.where((part) => !_isPitchCount(part));
                final pitchCounts = chipParts.where(_isPitchCount);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final part in metrics)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: _metricChip(part, statSize),
                      ),
                    for (final part in _orderedPlays(pitcher.plays)) _playChip(part, statSize),
                    if (pitcher.stat.isNotEmpty) ...[
                      if (pitcher.plays.isNotEmpty || pitcher.chips.isNotEmpty) const SizedBox(width: 4),
                      _pitchStat(pitcher.stat, statSize, pitcher.tone),
                    ],
                    for (final part in pitchCounts)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: _metricChip(part, statSize),
                      ),
                    for (final part in achievements) _playChip(part, statSize, blink: true),
                    if (pitcher.predict.isNotEmpty) ...[
                      if (pitcher.stat.isNotEmpty || pitcher.chips.isNotEmpty || pitcher.plays.isNotEmpty || pitcher.achieve.isNotEmpty) const SizedBox(width: 2),
                      for (final part in pitcher.predict.split(','))
                        if (part.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: _predictBadge(part, statSize),
                          ),
                        ],
                    ],
                  ],
                );
              }

              return SizedBox(
                width: cellW,
                height: maxH.isFinite ? maxH : null,
                child: ClipRect(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: leadingW + nameBoxW,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final pitcher in pitchers)
                              SizedBox(
                                height: fitRowH,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: leadingW - 0.5,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: pitcherBadges(pitcher),
                                      ),
                                    ),
                                    const SizedBox(width: 0.5),
                                    SizedBox(
                                      width: nameBoxW,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: _pitcherNameBox(
                                          name: _shownName(pitcher),
                                          colorsRaw: pitcher.colors,
                                          baseSize: nameSize,
                                          minSize: _minPlayerNameSize,
                                          alignLeft: true,
                                          showAce: _isAcePitcher(
                                            pitcher.name,
                                            role: pitcher.role,
                                            chips: pitcher.chips,
                                            stat: pitcher.stat,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (statsViewportW > 0) ...[
                        if (gapW > 0) SizedBox(width: gapW),
                        SizedBox(
                          width: statsViewportW,
                          height: maxH.isFinite ? maxH : fitRowH * pitchers.length,
                          child: ClipRect(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              primary: false,
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final pitcher in pitchers)
                                    SizedBox(
                                      height: fitRowH,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: statLine(pitcher),
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
            }),
    );
  }

  String _homerNumberFirst(String label) {
    final head = RegExp(r'^(\d+回[表裏])').firstMatch(label);
    final prefix = head?.group(0) ?? '';
    final body = label.substring(prefix.length);
    final existing = RegExp(r'(\d+)号').firstMatch(body);
    if (existing == null || existing.start == 0) return label;
    final token = existing.group(0)!;
    return '$prefix$token${body.substring(0, existing.start)}${body.substring(existing.end)}';
  }

  Color _playColor(String kind, String label) {
    if (label.contains('併殺')) return Colors.black;
    if (label.contains('三振') || label.contains('振逃')) return const Color(0xFF616161);
    if (label.contains('邪') || label.contains('ポップ')) return const Color(0xFF1E88E5);
    if (label.contains('ゴロ') || label.contains('フライ') || label.contains('ライナー')) return const Color(0xFF1E88E5);
    return switch (kind) {
      'hr' || 'cycle' || 'cyclemis' || 'multihit' || 'allhit' || 'allreach' || 'perfect' || 'nohit' || 'maddux' || 'shutout' || 'cg' => const Color(0xFFDC143C),
      'timely' || 'hqs' => const Color(0xFFFF5722),
      'triple' || 'double' || 'extra' || 'qs' => const Color(0xFFFFB300),
      'single' => const Color(0xFFFFEB3B),
      'walk' => const Color(0xFF43A047),
      'dead' || 'error' => const Color(0xFF78909C),
      'sac' || 'sacfly' || 'squeeze' || 'sacbunt' => const Color(0xFF8E24AA),
      'k10' => const Color(0xFFDC143C),
      'steal' => const Color(0xFFC6FF00),
      'stealout' => const Color(0xFF757575),
      _ => const Color(0xFFEEEEEE),
    };
  }

  String _playKind(String encoded) {
    final bar = encoded.lastIndexOf('|');
    return bar < 0 ? '' : encoded.substring(bar + 1).trim();
  }

  int _playRank(String encoded) {
    final kind = _playKind(encoded);
    final label = encoded.lastIndexOf('|') < 0 ? encoded : encoded.substring(0, encoded.lastIndexOf('|'));
    return switch (kind) {
      'hr' => 0,
      'timely' => 1,
      'triple' => 2,
      'double' || 'extra' => 3,
      'single' => 4,
      'steal' || 'stealout' => 5,
      'sacfly' => 6,
      'squeeze' => 7,
      'walk' => 8,
      'dead' => 9,
      'error' => 10,
      'sacbunt' => 11,
      'sac' => label.contains('犠打') ? 11 : (label.contains('スクイズ') ? 7 : 6),
      'out' => 12,
      _ => 50,
    };
  }

  List<String> _orderedPlays(String raw, {bool includeOuts = false}) {
    return raw.split(' ').where((part) {
      if (part.isEmpty) return false;
      if (_playKind(part) == 'out') return includeOuts;
      return _playRank(part) >= 0;
    }).toList();
  }

  String _playLabel(String label, String kind) {
    if (kind == 'hr' || kind == 'timely') return label;
    return label.replaceFirst('代打', '');
  }

  Color _pitchToneColor(String tone) {
    // 黄・緑・青系はグレー表示（赤橙系の良い指標だけ色を残す）。
    return switch (tone) {
      'crimson' => const Color(0xFFDC143C),
      'rorange' => const Color(0xFFFF5722),
      'yorange' || 'yellow' || 'green' || 'blue' || 'gray' || 'dgray' => const Color(0xFF78909C),
      _ => const Color(0xFFEEEEEE),
    };
  }

  Widget _metricChip(String encoded, double fontSize) {
    final bar = encoded.lastIndexOf('|');
    final label = (bar < 0 ? encoded : encoded.substring(0, bar)).trim();
    final tone = bar < 0 ? '' : encoded.substring(bar + 1).trim();
    if (label.isEmpty) return const SizedBox.shrink();
    return _pitchStat(label, fontSize, tone);
  }

  Widget _pitchStat(String text, double fontSize, String tone) {
    final style = TextStyle(
      fontSize: fontSize,
      color: tone.isEmpty ? Colors.black87 : (_pitchToneColor(tone).computeLuminance() > 0.55 ? Colors.black87 : Colors.white),
      fontWeight: tone.isEmpty ? FontWeight.normal : FontWeight.w600,
      height: 1.0,
    );
    final label = Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.left,
      style: style,
    );
    if (tone.isEmpty) return label;
    return Container(
      height: 14,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _pitchToneColor(tone),
        borderRadius: BorderRadius.circular(2),
      ),
      child: label,
    );
  }

  ({String body, String direction}) _playBody(String label) {
    final marked = RegExp(r'\^([左中右遊一二三投捕])$').firstMatch(label);
    if (marked == null) return (body: label, direction: '');
    return (body: label.substring(0, marked.start), direction: marked.group(1)!);
  }

  String _compactPlay(String label, String kind, String direction) {
    if (kind == 'hr') return direction.isEmpty ? '本' : '$direction本';
    if (kind == 'timely') {
      final hit = label.contains('スリーベース')
          ? '3'
          : label.contains('ツーベース')
              ? '2'
              : '安';
      return '$direction$hit';
    }
    return label.replaceAll('邪飛', '邪').replaceAll('ポップ', '邪').replaceAll('ゴロ', 'ゴ').replaceAll('フライ', '飛').replaceAll('ライナー', '直').replaceAll('併殺', '併');
  }

  // 中継ぎ/ホールド=黄っぽいオレンジ、抑え/セーブ=赤っぽいオレンジ、外野=黄緑。
  static const _markYellowOrange = Color(0xFFFFB300);
  static const _markRedOrange = Color(0xFFFF5722);
  static const _markOutfield = Color(0xFFC6FF00);

  Color _positionColor(String mark, {bool pitcherRole = false}) {
    if (pitcherRole) {
      return switch (mark) {
        '先' => const Color(0xFFFF4B7D),
        '中' => _markYellowOrange,
        '抑' => _markRedOrange,
        _ => const Color(0xFFEEEEEE),
      };
    }
    return switch (mark) {
      '投' => const Color(0xFFFF4B7D),
      '捕' => const Color(0xFF1E88E5),
      '一' || '二' || '三' || '遊' => const Color(0xFFFFEB3B),
      '左' || '中' || '右' => _markOutfield,
      '指' => const Color(0xFF8E24AA),
      _ => const Color(0xFFEEEEEE),
    };
  }

  Widget _lineupMark(String mark, double fontSize, {bool pitcherRole = false}) {
    const positions = {'投', '捕', '一', '二', '三', '遊', '左', '中', '右', '指', '先', '抑'};
    if (!positions.contains(mark)) return _resultBadge(mark, fontSize);
    final bg = _positionColor(mark, pitcherRole: pitcherRole);
    final ink = bg.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    final side = (fontSize + 1).clamp(10.0, 14.0);
    return Center(
      child: Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          mark,
          style: TextStyle(fontSize: math.min(10, fontSize), fontWeight: FontWeight.bold, color: ink, height: 1),
        ),
      ),
    );
  }

  Widget _playChip(String encoded, double fontSize, {bool blink = false, bool compact = false}) {
    final bar = encoded.lastIndexOf('|');
    final label = (bar < 0 ? encoded : encoded.substring(0, bar)).trim();
    final kind = bar < 0 ? '' : encoded.substring(bar + 1).trim();
    if (label.isEmpty) return const SizedBox.shrink();
    final rawLabel = _playLabel(label, kind);
    final parsed = _playBody(kind == 'hr' ? _homerNumberFirst(rawLabel) : rawLabel);
    final shown = compact ? _compactPlay(parsed.body, kind, parsed.direction) : parsed.body.replaceAll('ポップ', '邪飛');
    final bg = _playColor(kind, parsed.body);
    final ink = parsed.body.contains('併殺') ? const Color(0xFFE53935) : (bg.computeLuminance() > 0.55 ? Colors.black87 : Colors.white);
    final chipSize = (fontSize - 1).clamp(8.0, 11.0);
    final text = Text(
      shown,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: ink,
        fontSize: chipSize,
        fontWeight: FontWeight.w600,
        height: 1.0,
      ),
    );
    if (!blink) {
      return Container(
        height: 14,
        margin: const EdgeInsets.only(right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(2),
        ),
        child: text,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: BlinkBg(
        base: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(2),
        ),
        color: const Color(0xFFFFF176),
        radius: 2,
        duration: const Duration(milliseconds: 700),
        child: Container(
          height: 14,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          child: text,
        ),
      ),
    );
  }

  Widget _predictBadge(String encoded, double fontSize) {
    final bar = encoded.indexOf('|');
    final label = (bar < 0 ? encoded : encoded.substring(0, bar)).trim();
    final colorName = bar < 0 ? '' : encoded.substring(bar + 1).trim();
    final height = (fontSize + 3).clamp(11.0, 15.0);
    final bg = parseColorName(colorName, const Color(0xFF37474F));
    final ink = bg.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    return Container(
      height: height,
      constraints: BoxConstraints(minWidth: height),
      padding: EdgeInsets.symmetric(horizontal: label.length > 1 ? 3 : 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: ink,
          fontSize: (fontSize * 0.78).clamp(7.0, 10.0),
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
    );
  }

  Widget _resultBadge(String mark, double fontSize) {
    final isHr = mark == 'HR';
    final color = switch (mark) {
      '勝' => Colors.red,
      '負' => Colors.blue,
      'H' => _markYellowOrange,
      'S' => _markRedOrange,
      'HR' => const Color(0xFFDC143C),
      _ => _markRedOrange,
    };
    final diameter = (fontSize + 2).clamp(9.0, 16.0);
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(isHr ? diameter * 0.18 : diameter * 0.08),
        child: FittedBox(
          fit: BoxFit.contain,
          child: Text(
            mark,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final stackedTeams = MediaQuery.sizeOf(context).width < stackedTeamsMaxWidth;
      final height = constraints.maxHeight.isFinite ? constraints.maxHeight : intrinsicHeight(stackedTeams: stackedTeams);
      final headerSize = (height * 0.10).clamp(10.0, 14.0);
      final teamSize = (height * 0.11).clamp(11.0, 16.0);
      final stateSize = (height * 0.09).clamp(9.0, 12.0);
      final scoreSize = (height * 0.13).clamp(12.0, 18.0);
      final detailSize = (height * 0.07).clamp(_minPlayerNameSize, 10.0);
      final labelSize = (height * 0.10).clamp(10.0, 14.0);

      final homeBg = parseColorNameOrNull(_text('color_back_home'));
      final awayBg = parseColorNameOrNull(_text('color_back_away'));
      final homeFg = parseColorNameOrNull(_text('color_font_home')) ?? Colors.black87;
      final awayFg = parseColorNameOrNull(_text('color_font_away')) ?? Colors.black87;
      final homePale = _pale(homeBg, lighter: _text('name_team_home').contains('ロッテ'));
      final awayPale = _pale(awayBg, lighter: _text('name_team_away').contains('ロッテ'));

      final scoreHome = _int('score_home');
      final scoreAway = _int('score_away');
      final score = scoreHome >= 0 && scoreAway >= 0 ? '$scoreHome - $scoreAway' : 'vs';
      final state = _text('state');
      final header = [
        if (_text('time_game').isNotEmpty) _text('time_game'),
        if (_text('name_stadium').isNotEmpty) _text('name_stadium'),
      ].join(' ');
      final homePitchers = _players(home: true, pitcher: true);
      final awayPitchers = _players(home: false, pitcher: true);
      final homeBatters = allBatters ? const <_PlayerLine>[] : _players(home: true, pitcher: false);
      final awayBatters = allBatters ? const <_PlayerLine>[] : _players(home: false, pitcher: false);
      final homeLineup = allBatters ? _lineupSlots(home: true) : const <_LineupSlot>[];
      final awayLineup = allBatters ? _lineupSlots(home: false) : const <_LineupSlot>[];
      final homeNameColW = _nameColumnWidth([...homePitchers, ...homeBatters], detailSize, context);
      final awayNameColW = _nameColumnWidth([...awayPitchers, ...awayBatters], detailSize, context);
      final pitcherN = math.max(1, math.max(homePitchers.length, awayPitchers.length));
      final batterN = allBatters ? 9 : math.max(1, math.max(homeBatters.length, awayBatters.length));
      final started = gameHasStarted(game) && state != '試合前';
      final midFlex = started ? 1 : 3;
      final pitcherFlex = math.max(1, (pitcherN * _playerRowH + _seasonBlockH()).round());
      final batterFlex = math.max(1, (batterN * _playerRowH).round());
      final homePitcherFlex = math.max(1, _pitcherBlockH(homePitchers.length).round());
      final awayPitcherFlex = math.max(1, _pitcherBlockH(awayPitchers.length).round());
      final homeBatterFlex = math.max(1, ((allBatters ? 9 : math.max(1, homeBatters.length)) * _playerRowH).round());
      final awayBatterFlex = math.max(1, ((allBatters ? 9 : math.max(1, awayBatters.length)) * _playerRowH).round());
      // 縦並び時の「投手」「打者」見出しは、文字左右に軽い余白が付く幅だけで足りる。
      final stackLabelW = (labelSize * 2 + 8).clamp(28.0, 36.0);
      const stackTeamHeaderW = 22.0;

      Widget verticalTeamHeader(String name, Color? bg, Color fg) {
        final chars = name.replaceAll(RegExp(r'\s+'), '').characters.toList();
        return ColoredBox(
          color: bg ?? _labelColor,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final ch in chars)
                    Text(
                      // 縦書きでは長音「ー」を縦棒向きにする
                      (ch == 'ー' || ch == '―' || ch == 'ｰ' || ch == '−') ? '｜' : ch,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        height: 1.05,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }

      Widget teamStats({
        required List<_PlayerLine> pitchers,
        required List<_PlayerLine> batters,
        required List<_LineupSlot> lineup,
        required Color pale,
        required double nameColW,
        required int pitcherFlex,
        required int batterFlex,
        required bool bottom,
        required String teamName,
        required Color? teamBg,
        required Color teamFg,
      }) {
        final showBatters = started;
        return Expanded(
          flex: pitcherFlex + (showBatters ? batterFlex : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: stackTeamHeaderW,
                child: verticalTeamHeader(teamName, teamBg, teamFg),
              ),
              SizedBox(
                width: stackLabelW,
                child: Column(
                  children: [
                    Expanded(
                      flex: pitcherFlex,
                      child: _textCell(
                        '投手',
                        size: labelSize,
                        minSize: 9,
                        color: _labelColor,
                        textColor: Colors.white,
                        weight: FontWeight.bold,
                      ),
                    ),
                    if (showBatters)
                      Expanded(
                        flex: batterFlex,
                        child: _batterHeader(labelSize, bottom: bottom),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: pitcherFlex,
                      child: _pitcherCell(
                        pitchers,
                        color: pale,
                        size: detailSize,
                        right: false,
                        bottom: showBatters || bottom,
                        nameColW: nameColW,
                        centerNames: !started,
                      ),
                    ),
                    if (showBatters)
                      Expanded(
                        flex: batterFlex,
                        child: allBatters
                            ? _lineupCell(lineup, color: pale, size: detailSize, right: false, bottom: bottom)
                            : _pitcherCell(
                                batters,
                                color: pale,
                                size: detailSize,
                                right: false,
                                bottom: bottom,
                                nameColW: nameColW,
                                centerNames: !started,
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

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
            SizedBox(
              height: _minHeaderH,
              child: _textCell(
                header.isEmpty ? '　' : header,
                size: headerSize,
                minSize: 9,
                color: homeBg ?? const Color(0xFFF4D03F),
                textColor: homeFg,
                weight: FontWeight.bold,
                right: false,
                align: TextAlign.left,
              ),
            ),
            SizedBox(
              height: _minTeamRowH,
              child: LayoutBuilder(builder: (context, teamConstraints) {
                final rowW = teamConstraints.maxWidth.isFinite ? teamConstraints.maxWidth : 0.0;
                // アイコンと得点の左右に少しだけ余白が残る幅。
                final scoreW = math.min(148.0, math.max(0.0, rowW - 96));
                final sideW = math.max(0.0, (rowW - scoreW) / 2);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: sideW,
                      child: _textCell(
                        _text('name_team_home'),
                        size: teamSize,
                        minSize: 9,
                        color: homeBg,
                        textColor: homeFg,
                        weight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(
                      width: scoreW,
                      child: _matchScoreCell(
                        state: state,
                        score: score,
                        stateSize: stateSize,
                        scoreSize: scoreSize,
                        homeName: _text('name_team_home'),
                        awayName: _text('name_team_away'),
                        homeAbbrev: _text('name_shortest_home'),
                        awayAbbrev: _text('name_shortest_away'),
                        homeBg: homeBg,
                        awayBg: awayBg,
                        homeFg: homeFg,
                        awayFg: awayFg,
                      ),
                    ),
                    Expanded(
                      child: _textCell(
                        _text('name_team_away'),
                        size: teamSize,
                        minSize: 9,
                        color: awayBg,
                        textColor: awayFg,
                        weight: FontWeight.bold,
                        right: false,
                      ),
                    ),
                  ],
                );
              }),
            ),
            if (stackedTeams) ...[
              teamStats(
                pitchers: homePitchers,
                batters: homeBatters,
                lineup: homeLineup,
                pale: homePale,
                nameColW: homeNameColW,
                pitcherFlex: homePitcherFlex,
                batterFlex: homeBatterFlex,
                bottom: true,
                teamName: _text('name_team_home'),
                teamBg: homeBg,
                teamFg: homeFg,
              ),
              teamStats(
                pitchers: awayPitchers,
                batters: awayBatters,
                lineup: awayLineup,
                pale: awayPale,
                nameColW: awayNameColW,
                pitcherFlex: awayPitcherFlex,
                batterFlex: awayBatterFlex,
                bottom: false,
                teamName: _text('name_team_away'),
                teamBg: awayBg,
                teamFg: awayFg,
              ),
            ] else ...[
              Expanded(
                flex: pitcherFlex,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _pitcherCell(
                        homePitchers,
                        color: homePale,
                        size: detailSize,
                        right: true,
                        nameColW: homeNameColW,
                        centerNames: !started,
                      ),
                    ),
                    Expanded(
                      flex: midFlex,
                      child: _textCell(
                        '投手',
                        size: labelSize,
                        minSize: 9,
                        color: _labelColor,
                        textColor: Colors.white,
                        weight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: _pitcherCell(
                        awayPitchers,
                        color: awayPale,
                        size: detailSize,
                        right: false,
                        nameColW: awayNameColW,
                        centerNames: !started,
                      ),
                    ),
                  ],
                ),
              ),
              if (started)
                Expanded(
                  flex: batterFlex,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: allBatters
                            ? _lineupCell(homeLineup, color: homePale, size: detailSize, right: true)
                            : _pitcherCell(
                                homeBatters,
                                color: homePale,
                                size: detailSize,
                                right: true,
                                bottom: false,
                                nameColW: homeNameColW,
                                centerNames: !started,
                              ),
                      ),
                      Expanded(
                        flex: midFlex,
                        child: _batterHeader(labelSize),
                      ),
                      Expanded(
                        flex: 5,
                        child: allBatters
                            ? _lineupCell(awayLineup, color: awayPale, size: detailSize, right: false)
                            : _pitcherCell(
                                awayBatters,
                                color: awayPale,
                                size: detailSize,
                                right: false,
                                bottom: false,
                                nameColW: awayNameColW,
                                centerNames: !started,
                              ),
                      ),
                    ],
                  ),
                ),
            ],
            if (_showLineScore)
              _lineScoreTable(
                homeBg: homeBg,
                awayBg: awayBg,
                homeFg: homeFg,
                awayFg: awayFg,
              ),
          ],
        ),
      );

      final sized = SizedBox(
        height: height,
        width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
        child: content,
      );

      if (state.contains('回')) {
        return BlinkBorder(
          color: Colors.amber,
          radius: 4,
          width: 3,
          duration: const Duration(milliseconds: 900),
          baseBgColor: Colors.transparent,
          fillUseColor: false,
          child: sized,
        );
      }
      return sized;
    });
  }
}

/// クリムゾンの菱形に白文字「ACE」
Widget _aceDiamond(double baseSize) {
  final side = (baseSize * 1.55).clamp(12.0, 18.0);
  final fontSize = (baseSize * 0.55).clamp(5.5, 8.0);
  return SizedBox(
    width: side,
    height: side,
    child: Transform.rotate(
      angle: math.pi / 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFDC143C),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Transform.rotate(
          angle: -math.pi / 4,
          child: Center(
            child: Text(
              'ACE',
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// 先発投手名の背景色を colors_user 形式で適用（/red/blue/ → グラデ）
Widget _pitcherNameBox({
  required String name,
  required String colorsRaw,
  required double baseSize,
  required bool alignLeft,
  double minSize = 9,
  Color? overrideTextColor,
  FontWeight? overrideWeight,
  bool showAce = false,
}) {
  final box = _PitcherNameBox(
    name: name,
    colorsRaw: colorsRaw,
    baseSize: baseSize,
    minSize: minSize,
    alignLeft: alignLeft,
    overrideTextColor: overrideTextColor,
    overrideWeight: overrideWeight,
  );
  if (!showAce) return box;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      box,
      const SizedBox(width: 3),
      _aceDiamond(baseSize),
    ],
  );
}

class _PitcherNameBox extends StatefulWidget {
  final String name;
  final String colorsRaw;
  final double baseSize;
  final double minSize;
  final bool alignLeft;
  final Color? overrideTextColor;
  final FontWeight? overrideWeight;

  const _PitcherNameBox({
    required this.name,
    required this.colorsRaw,
    required this.baseSize,
    required this.minSize,
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
    final weight = widget.overrideWeight ?? FontWeight.bold;

    final alignment = widget.alignLeft ? Alignment.centerLeft : Alignment.center;
    return Align(
      alignment: alignment,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: deco,
        child: Stack(
          alignment: alignment,
          clipBehavior: Clip.hardEdge,
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
            Text(
              widget.name.isNotEmpty ? widget.name : '—',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                fontSize: widget.baseSize < widget.minSize ? widget.minSize : widget.baseSize,
                fontWeight: weight,
                color: textColor,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
