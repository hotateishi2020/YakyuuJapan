import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../config/app_design.dart';
import '../logic/clinched_series.dart';
import '../logic/show_user_predictions.dart';
import '../logic/game_dedupe.dart';
import '../tools/color_parse.dart';
import '../tools/date_format.dart';
import 'Text.dart';
import 'Border.dart';
import 'BlinkBg.dart';

/// Phone portrait and other narrow windows stack in-progress team stats,
/// and always put match cards in a single column.
const stackedTeamsMaxWidth = 600.0;

/// 試合カード同士の間隔。
const gameBlockGap = 8.0;

String gameDateOnly(dynamic value) {
  final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch('${value ?? ''}');
  return match?.group(0) ?? '${value ?? ''}'.trim();
}

/// シリーズ全体で決着したあとの未実施を除いてから、その日の試合だけにする。
List<Map<String, dynamic>> gamesOnDate(
  List<Map<String, dynamic>> games,
  String date, {
  List<Map<String, dynamic>> standings = const [],
  List<Map<String, dynamic>> seriesGames = const [],
}) {
  final kept = dropUnplayedClinchedGames(games, standings: standings, seriesGames: seriesGames);
  return normalizeGames(kept.where((game) => gameDateOnly(game['date_game']) == date).toList());
}

const _csCentralGradient = [Color(0xFF8CFAF7), Color(0xFF2BCFAD), Color(0xFF14C4C0)];
const _csPacificGradient = [Color(0xFF5AD8EA), Color(0xFF1E6FE0), Color(0xFF1F52EB)];

/// クライマックスの試合日はリーグ名の代わりにステージ名とCSロゴを出す。
({String label, String? logoAsset, List<Color>? gradient}) npbClimaxHeader({
  required int leagueId,
  required String fallbackLabel,
  required List<Map<String, dynamic>> games,
}) {
  final codes = [
    for (final game in games) '${game['code_game'] ?? ''}'.trim().toUpperCase(),
  ];
  final hasCs1 = codes.contains('CS1');
  final hasFinal = codes.contains('CS2') || codes.contains('CS');
  final hasJs = codes.contains('JS');
  if (!hasCs1 && !hasFinal && !hasJs) {
    return (label: fallbackLabel, logoAsset: null, gradient: null);
  }
  final label = hasJs && !hasCs1 && !hasFinal
      ? 'JAPAN SERIES'
      : hasFinal && !hasCs1
          ? 'CS FINAL STAGE'
          : 'CS 1st STAGE';
  final central = leagueId == 1;
  return (
    label: label,
    logoAsset: central
        ? 'backend/assets/images/logo_cs_central.png'
        : leagueId == 2
            ? 'backend/assets/images/logo_cs_pacific.png'
            : null,
    gradient: central
        ? _csCentralGradient
        : leagueId == 2
            ? _csPacificGradient
            : null,
  );
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

/// トーナメントのチームロゴを試合カードより先に温める。
void precacheTeamLogos(BuildContext context, Iterable<Map<String, dynamic>> rows) {
  for (final row in rows) {
    final visual = teamLogoVisual(
      '${row['name_team'] ?? row['name_short'] ?? ''}',
      abbrev: '${row['name_shortest'] ?? ''}',
    );
    final asset = visual.asset;
    final url = visual.networkUrl;
    if (asset != null) {
      precacheImage(AssetImage(asset), context);
    } else if (url != null) {
      precacheImage(NetworkImage(url), context);
    }
  }
}

Widget teamLogoImage({String? asset, String? networkUrl, BoxFit fit = BoxFit.contain}) {
  if (asset != null) {
    return Image.asset(
      asset,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
  if (networkUrl != null) {
    return Image.network(
      networkUrl,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
  return const SizedBox.shrink();
}

String _compactPlayerName(String name) {
  final cut = name.split(RegExp(r'[（(]')).first;
  return cut.replaceAll(RegExp(r'[\s\u3000]+'), '');
}

String _playerNameKey(String name) {
  return _compactPlayerName(name).replaceAll(RegExp(r'[・･·]'), '').replaceFirst(RegExp(r'^[A-Za-zＡ-Ｚ]{1,3}[\.．]'), '');
}

String? _givenNamePart(String name) {
  final parts = name.split(RegExp(r'[・･·]')).where((part) => part.trim().isNotEmpty).toList();
  if (parts.length < 2) return null;
  return parts.first.replaceAll(RegExp(r'[\s\u3000]+'), '');
}

final _latinInitialRe = RegExp(r'^([A-Za-zＡ-Ｚ]{1,3})[\.．]');

String? _latinInitial(String name) {
  final match = _latinInitialRe.firstMatch(_compactPlayerName(name));
  if (match == null) return null;
  return _asciiUpper(match.group(1)!);
}

String _asciiUpper(String raw) {
  const wide = 'ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ';
  const ascii = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final out = StringBuffer();
  for (final char in raw.split('')) {
    final index = wide.indexOf(char);
    out.write(index >= 0 ? ascii[index] : char.toUpperCase());
  }
  return out.toString();
}

/// カタカナの名が、そのラテンイニシャルであり得るか。
/// ヘーゲンは H、ケードは C/K。C.スミスをヘーゲン・スミスとはみなさない。
bool _givenMatchesInitial(String given, String initial) {
  final letter = _asciiUpper(initial);
  if (letter.isEmpty) return false;
  final name = _asciiUpper(given);
  if (RegExp(r'^[A-Z]+$').hasMatch(name)) return name == letter;
  final possible = _kanaInitials(given);
  if (possible.isEmpty) return true;
  return possible.contains(letter[0]);
}

String _kanaInitials(String given) {
  const digraphs = {
    'ウィ': 'W',
    'ウェ': 'W',
    'ウォ': 'W',
    'ヴァ': 'V',
    'ヴィ': 'V',
    'ヴェ': 'V',
    'ヴォ': 'V',
    'チェ': 'C',
    'シェ': 'S',
    'ジェ': 'J',
    'ティ': 'T',
    'ディ': 'D',
    'ファ': 'F',
    'フィ': 'F',
    'フェ': 'F',
    'フォ': 'F',
  };
  const kana = {
    'ア': 'A',
    'イ': 'IY',
    'ウ': 'U',
    'エ': 'E',
    'オ': 'O',
    'カ': 'KC',
    'キ': 'KC',
    'ク': 'KCQ',
    'ケ': 'KC',
    'コ': 'KC',
    'サ': 'S',
    'シ': 'S',
    'ス': 'S',
    'セ': 'SC',
    'ソ': 'S',
    'タ': 'T',
    'チ': 'CT',
    'ツ': 'TS',
    'テ': 'T',
    'ト': 'T',
    'ナ': 'N',
    'ニ': 'N',
    'ヌ': 'N',
    'ネ': 'N',
    'ノ': 'N',
    'ハ': 'H',
    'ヒ': 'H',
    'フ': 'FH',
    'ヘ': 'H',
    'ホ': 'H',
    'マ': 'M',
    'ミ': 'M',
    'ム': 'M',
    'メ': 'M',
    'モ': 'M',
    'ヤ': 'Y',
    'ユ': 'YU',
    'ヨ': 'Y',
    'ラ': 'RL',
    'リ': 'RL',
    'ル': 'RL',
    'レ': 'RL',
    'ロ': 'RL',
    'ワ': 'W',
    'ヲ': 'O',
    'ン': 'N',
    'ガ': 'G',
    'ギ': 'G',
    'グ': 'G',
    'ゲ': 'G',
    'ゴ': 'G',
    'ザ': 'ZJ',
    'ジ': 'JG',
    'ズ': 'Z',
    'ゼ': 'ZJ',
    'ゾ': 'Z',
    'ダ': 'D',
    'デ': 'D',
    'ド': 'D',
    'バ': 'BV',
    'ビ': 'BV',
    'ブ': 'BV',
    'ベ': 'BV',
    'ボ': 'BV',
    'パ': 'P',
    'ピ': 'P',
    'プ': 'P',
    'ペ': 'P',
    'ポ': 'P',
  };
  if (given.length >= 2) {
    final two = digraphs[given.substring(0, 2)];
    if (two != null) return two;
  }
  if (given.isEmpty) return '';
  return kana[given.substring(0, 1)] ?? '';
}

bool samePlayerStatName(String left, String right) {
  final leftGiven = _givenNamePart(left);
  final rightGiven = _givenNamePart(right);
  if (leftGiven != null && rightGiven != null && leftGiven != rightGiven) return false;
  final leftInitial = _latinInitial(left);
  final rightInitial = _latinInitial(right);
  if (leftInitial != null && rightInitial != null && leftInitial != rightInitial) return false;
  if (leftGiven != null && rightInitial != null && !_givenMatchesInitial(leftGiven, rightInitial)) return false;
  if (rightGiven != null && leftInitial != null && !_givenMatchesInitial(rightGiven, leftInitial)) return false;
  final a = _playerNameKey(left);
  final b = _playerNameKey(right);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (a.length >= 2 && b.length >= 2 && (a.contains(b) || b.contains(a))) return true;
  return false;
}

const postseasonGameCodes = {
  'WC',
  'DS',
  'LCS',
  'WS',
  'ALWC',
  'NLWC',
  'ALWC36',
  'ALWC45',
  'NLWC36',
  'NLWC45',
  'ALDS',
  'NLDS',
  'ALDS1',
  'ALDS2',
  'NLDS1',
  'NLDS2',
  'ALCS',
  'NLCS',
  'CS1',
  'CS2',
  'CS',
  'JS',
};

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

/// 試合前（未開始）。MLB の「予想先発」や NPB の「試合前」「スタメン」を含む。
bool gameIsPregameState(String state) {
  final s = state.trim();
  return s.isEmpty || s == '試合前' || s == '予想先発' || s == 'スタメン';
}

/// スコアボード上の表記。未開始はすべて「試合前」。
String displayBoardState(String state) {
  if (gameIsPregameState(state)) return '試合前';
  return state.trim();
}

/// 6回を超えて2点差以内。8回と9回だけは1点差以内。
bool isHeatedGame(String state, int scoreHome, int scoreAway) {
  if (scoreHome < 0 || scoreAway < 0) return false;
  if (state.contains('試合終了') || state.contains('コールド') || state.contains('中止') || state.contains('延期')) return false;
  final live = liveAtBatHalf(state);
  if (live == null || live.inning <= 6) return false;
  final diff = (scoreHome - scoreAway).abs();
  if (live.inning == 8 || live.inning == 9) return diff <= 1;
  return diff <= 2;
}

/// 進行中の「5回裏」などから、攻撃中イニングと表裏を取る。
({int inning, bool bottom})? liveAtBatHalf(String state) {
  final match = RegExp(r'(\d+)\s*回\s*(表|裏)').firstMatch(state);
  if (match == null) return null;
  return (inning: int.parse(match.group(1)!), bottom: match.group(2) == '裏');
}

int? liveOuts(String state) {
  final match = RegExp(r'(\d+)\s*アウト').firstMatch(state);
  if (match != null) return int.parse(match.group(1)!);
  if (state.contains('三死') || state.contains('三アウト')) return 3;
  return null;
}

({int inning, bool bottom}) nextLiveHalf(({int inning, bool bottom}) half) {
  if (!half.bottom) return (inning: half.inning, bottom: true);
  return (inning: half.inning + 1, bottom: false);
}

/// 3アウトになった回の次の攻撃を点滅する。
({int inning, bool bottom})? liveBlinkHalf(String state, {int? outs}) {
  final live = liveAtBatHalf(state);
  if (live == null) return null;
  final n = liveOuts(state) ?? ((outs != null && outs > 0) ? outs : null);
  if (n != null && n >= 3) return nextLiveHalf(live);
  return live;
}

bool lineScoreInningStarted({
  required int inning,
  required bool homeRow,
  required ({int inning, bool bottom})? live,
  required bool finished,
  required int recordedLength,
}) {
  if (live != null) {
    if (inning < live.inning) return true;
    if (inning > live.inning) return false;
    return homeRow ? live.bottom : true;
  }
  if (finished) return inning <= recordedLength;
  return inning <= recordedLength;
}

bool gameHasStarted(Map<String, dynamic> game) {
  final state = '${game['state'] ?? ''}'.trim();
  if (gameIsPregameState(state)) return false;
  if (state.contains('中止') || state.contains('延期') || state.contains('サスペンデッド')) return false;
  if (state.contains('試合終了') || state.contains('コールド')) return true;
  if (state.contains('回')) return true;
  if (state.contains('終了')) return true;
  // 不明な非空 state は開始扱い（従来互換）。スコアだけある場合も開始。
  if (state.isNotEmpty) return true;
  final home = int.tryParse('${game['score_home']}') ?? -1;
  final away = int.tryParse('${game['score_away']}') ?? -1;
  return home >= 0 && away >= 0;
}

const resultBadgeWin = 'backend/assets/images/result_win.png';
const resultBadgeLose = 'backend/assets/images/result_lose.png';
const resultBadgeDraw = 'backend/assets/images/result_draw.png';

enum FinishedGameOutcome { homeWin, awayWin, draw }

/// 試合終了・コールドでスコアが揃っているときだけ勝敗を返す。
FinishedGameOutcome? finishedGameOutcome(String state, int scoreHome, int scoreAway) {
  if (!state.contains('試合終了') && !state.contains('コールド')) return null;
  if (scoreHome < 0 || scoreAway < 0) return null;
  if (scoreHome == scoreAway) return FinishedGameOutcome.draw;
  if (scoreHome > scoreAway) return FinishedGameOutcome.homeWin;
  return FinishedGameOutcome.awayWin;
}

String? teamResultBadge(FinishedGameOutcome? outcome, {required bool home}) {
  switch (outcome) {
    case FinishedGameOutcome.homeWin:
      return home ? resultBadgeWin : resultBadgeLose;
    case FinishedGameOutcome.awayWin:
      return home ? resultBadgeLose : resultBadgeWin;
    case FinishedGameOutcome.draw:
    case null:
      return null;
  }
}

bool gameIsInProgress(Map<String, dynamic> game) {
  final state = '${game['state'] ?? ''}'.trim();
  if (gameIsPregameState(state)) return false;
  if (state.contains('試合終了') || state.contains('コールド')) return false;
  if (state.contains('中止') || state.contains('延期') || state.contains('サスペンデッド')) return false;
  return gameHasStarted(game);
}

bool _gameHasLineup(Map<String, dynamic> game) {
  final raw = game['lineup'];
  if (raw is! List || raw.isEmpty) return false;
  for (final item in raw) {
    if (item is! Map) continue;
    final players = item['players'];
    if (players is List && players.isNotEmpty) return true;
  }
  return false;
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
  return dedupeSameDayMatchupRows([
    for (final rows in groupGamesByMatchup(games))
      {
        ...rows.first,
        'summaries': rows,
      },
  ]);
}

const _rosterModeStyle = TextStyle(fontSize: 11, height: 1.0, fontWeight: FontWeight.bold);

/// 選手成績を開いたバー。チェック時は全員、未チェックは活躍選手。
Widget rosterAllBattersCheckbox({
  required bool allBatters,
  required ValueChanged<bool> onChanged,
  required Color foreground,
  double height = TAB_BAR_H,
}) {
  final checkOn = foreground.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  const uncheckedFill = Color(0xFFD0D0D0);
  const uncheckedSide = Color(0xFF8A8A8A);
  return SizedBox(
    height: height,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!allBatters),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: allBatters,
                onChanged: (value) => onChanged(value ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: allBatters ? foreground : uncheckedSide, width: 1.5),
                fillColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return foreground;
                  return uncheckedFill;
                }),
                checkColor: checkOn,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '詳細表示',
              maxLines: 1,
              softWrap: false,
              style: _rosterModeStyle.copyWith(
                color: foreground,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class GameDateSwitcher extends StatefulWidget {
  final List<Map<String, dynamic>> games;
  final List<Map<String, dynamic>> seriesGames;
  final List<Map<String, dynamic>> playerStats;
  final List<Map<String, dynamic>> standings;
  final Color headerColor;
  final int leagueId;
  final String? leagueLabel;
  final String? initialDate;
  final bool horizontal;
  final Future<void> Function(DateTime date)? onNeedGameDate;
  final bool Function(DateTime date)? shouldLoadGameDate;
  final String? loadingGameDate;
  final int dateOffset;
  final ValueChanged<int>? onDateOffsetChanged;

  const GameDateSwitcher({
    super.key,
    required this.games,
    this.seriesGames = const [],
    this.playerStats = const [],
    this.standings = const [],
    required this.headerColor,
    this.leagueId = 0,
    this.leagueLabel,
    this.initialDate,
    this.horizontal = true,
    this.onNeedGameDate,
    this.shouldLoadGameDate,
    this.loadingGameDate,
    this.dateOffset = 0,
    this.onDateOffsetChanged,
  });

  @override
  State<GameDateSwitcher> createState() => _GameDateSwitcherState();
}

class _GameDateSwitcherState extends State<GameDateSwitcher> {
  late DateTime _baseDate;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _baseDate = DateTime.tryParse(widget.initialDate ?? '') ?? DateTime.now();
    _baseDate = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
    _offset = widget.dateOffset;
    // 初回フレームはウェブフォントの幅が足りず、選手名が切れることがある。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant GameDateSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDate != widget.initialDate) {
      _baseDate = DateTime.tryParse(widget.initialDate ?? '') ?? DateTime.now();
      _baseDate = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
      _offset = widget.dateOffset;
    } else if (oldWidget.dateOffset != widget.dateOffset) {
      _offset = widget.dateOffset;
    }
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
    final nextOffset = _offset + by;
    final next = _baseDate.add(Duration(days: nextOffset));
    final need = widget.shouldLoadGameDate?.call(next) ?? false;
    setState(() => _offset = nextOffset);
    widget.onDateOffsetChanged?.call(nextOffset);
    if (need) widget.onNeedGameDate?.call(next);
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
    final dayGames = gamesOnDate(widget.games, date, standings: widget.standings, seriesGames: widget.seriesGames);
    final climax = npbClimaxHeader(
      leagueId: widget.leagueId,
      fallbackLabel: widget.leagueLabel ?? '',
      games: dayGames,
    );
    final header = Container(
      height: 42,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: climax.gradient == null ? null : LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: climax.gradient!),
        color: climax.gradient == null ? widget.headerColor : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _dateButton('<< 前の日', -1),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() => _offset = 0);
                  widget.onDateOffsetChanged?.call(0);
                },
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (climax.logoAsset != null) ...[
                            Image.asset(climax.logoAsset!, height: 18, fit: BoxFit.contain),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            climax.logoAsset != null ? climax.label : _dayLabel(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                          ),
                        ],
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
    final loading = widget.loadingGameDate == date;
    final board = loading
        ? const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        : GamesBoardYahooStyle(
            key: ValueKey('games-$date-${dayGames.map(gameMatchupKey).join('|')}'),
            games: dayGames,
            playerStats: widget.playerStats,
            standings: widget.standings,
            dateFilter: date,
            horizontal: widget.horizontal,
          );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxHeight.isFinite) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
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
  final List<Map<String, dynamic>> seriesGames;
  final List<Map<String, dynamic>> playerStats;
  final List<Map<String, dynamic>> standings;
  final String? initialDate;
  final List<Widget> leading;
  final List<({int id, String name, Color color})> leagues;
  final Future<void> Function(DateTime date)? onNeedGameDate;
  final bool Function(DateTime date)? shouldLoadGameDate;
  final String? loadingGameDate;
  final bool loadingGames;
  final int dateOffset;
  final ValueChanged<int>? onDateOffsetChanged;

  const BothLeagueGameDay({
    super.key,
    required this.games,
    this.seriesGames = const [],
    this.playerStats = const [],
    this.standings = const [],
    this.initialDate,
    this.leading = const [],
    this.leagues = const [
      (id: 1, name: 'セ・リーグ', color: Color(0xFF0E8E2D)),
      (id: 2, name: 'パ・リーグ', color: Color(0xFF01B1EA)),
    ],
    this.onNeedGameDate,
    this.shouldLoadGameDate,
    this.loadingGameDate,
    this.loadingGames = false,
    this.dateOffset = 0,
    this.onDateOffsetChanged,
  });

  @override
  State<BothLeagueGameDay> createState() => _BothLeagueGameDayState();
}

class _BothLeagueGameDayState extends State<BothLeagueGameDay> {
  late DateTime _baseDate;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _baseDate = DateTime.tryParse(widget.initialDate ?? '') ?? DateTime.now();
    _baseDate = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
    _offset = widget.dateOffset;
  }

  @override
  void didUpdateWidget(covariant BothLeagueGameDay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDate != widget.initialDate) {
      _baseDate = DateTime.tryParse(widget.initialDate ?? '') ?? DateTime.now();
      _baseDate = DateTime(_baseDate.year, _baseDate.month, _baseDate.day);
      _offset = widget.dateOffset;
    } else if (oldWidget.dateOffset != widget.dateOffset) {
      _offset = widget.dateOffset;
    }
  }

  DateTime get _selectedDate => _baseDate.add(Duration(days: _offset));

  void _move(int by) {
    final nextOffset = _offset + by;
    final next = _baseDate.add(Duration(days: nextOffset));
    final need = widget.shouldLoadGameDate?.call(next) ?? false;
    setState(() => _offset = nextOffset);
    widget.onDateOffsetChanged?.call(nextOffset);
    if (need) widget.onNeedGameDate?.call(next);
  }

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
    final dayGames = gamesOnDate(widget.games, date, standings: widget.standings, seriesGames: widget.seriesGames);
    Widget dateButton(String label, int by) {
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
                onTap: () {
                  setState(() => _offset = 0);
                  widget.onDateOffsetChanged?.call(0);
                },
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

    Widget leagueBlock(String label, Color color, int leagueId, List<Map<String, dynamic>> leagueGames) {
      final climax = npbClimaxHeader(leagueId: leagueId, fallbackLabel: label, games: leagueGames);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: climax.gradient == null ? null : LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: climax.gradient!),
              color: climax.gradient == null ? color : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (climax.logoAsset != null) ...[
                  Image.asset(climax.logoAsset!, height: 22, fit: BoxFit.contain),
                  const SizedBox(width: 8),
                ],
                Text(climax.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          GamesBoardYahooStyle(
            key: ValueKey('both-$leagueId-$date-${leagueGames.map(gameMatchupKey).join('|')}'),
            games: leagueGames,
            playerStats: widget.playerStats,
            standings: widget.standings,
            dateFilter: date,
            horizontal: true,
          ),
        ],
      );
    }

    final leagueBlocks = <Widget>[];
    final shown = <Map<String, dynamic>>{};
    for (final league in widget.leagues) {
      final leagueGames = _leagueGames(dayGames, league.id);
      if (leagueGames.isEmpty) continue;
      shown.addAll(leagueGames);
      if (leagueBlocks.isNotEmpty) leagueBlocks.add(const SizedBox(height: 16));
      leagueBlocks.add(leagueBlock(league.name, league.color, league.id, leagueGames));
    }
    final leftover = [
      for (final game in dayGames)
        if (!shown.contains(game)) game
    ];
    if (leftover.isNotEmpty) {
      if (leagueBlocks.isNotEmpty) leagueBlocks.add(const SizedBox(height: 16));
      leagueBlocks.add(leagueBlock('交流戦', const Color(0xFF37474F), 0, leftover));
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
              if (widget.loadingGames || widget.loadingGameDate == date)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (leagueBlocks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('この日の試合はありません')),
                )
              else
                ...leagueBlocks,
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
  final List<Map<String, dynamic>> standings;
  final String? dateFilter; // "YYYY-MM-DD"
  /// true のとき試合カードを横並び表示（リーグ内の1日分向け）
  final bool horizontal;

  /// 選手成績を最初から開いておく。試合開始後の初期表示は畳む。試合前は開く。
  final bool initialStatsExpanded;

  const GamesBoardYahooStyle({
    super.key,
    required this.games,
    this.playerStats = const [],
    this.standings = const [],
    this.dateFilter,
    this.horizontal = false,
    this.initialStatsExpanded = false,
  });

  @override
  State<GamesBoardYahooStyle> createState() => _GamesBoardYahooStyleState();
}

class _AnimatedGameSlot extends StatefulWidget {
  final double target;
  final double collapsed;
  final Widget Function(double reveal, double layoutHeight) builder;

  const _AnimatedGameSlot({
    super.key,
    required this.target,
    required this.collapsed,
    required this.builder,
  });

  @override
  State<_AnimatedGameSlot> createState() => _AnimatedGameSlotState();
}

class _AnimatedGameSlotState extends State<_AnimatedGameSlot> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 200);

  late final AnimationController _ctrl;
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration, value: 1)..addStatusListener(_onStatus);
    _from = widget.target;
    _to = widget.target;
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _from = _to;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _AnimatedGameSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((_to - widget.target).abs() < 0.5) return;
    final current = _height;
    _from = current;
    _to = widget.target;
    if ((current - _to).abs() < 0.5) {
      _from = _to;
      _ctrl.value = 1;
      return;
    }
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  double get _height {
    final t = Curves.easeOutCubic.transform(_ctrl.value);
    return _from + (_to - _from) * t;
  }

  @override
  Widget build(BuildContext context) {
    final atRestCollapsed = (_to - widget.collapsed).abs() < 0.5 && (_from - _to).abs() < 0.5 && _ctrl.value == 1;
    final layoutH = atRestCollapsed ? widget.collapsed : math.max(_from, _to);
    final child = widget.builder(atRestCollapsed ? 0.0 : 1.0, layoutH);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return LayoutBuilder(builder: (context, constraints) {
          final raw = _height;
          final height = constraints.maxHeight.isFinite ? math.min(raw, constraints.maxHeight) : raw;
          final viewport = math.max(0.0, height);
          if (layoutH <= viewport + 0.5) {
            return SizedBox(height: viewport, child: child);
          }
          return SizedBox(
            height: viewport,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: layoutH,
                maxHeight: layoutH,
                child: child,
              ),
            ),
          );
        });
      },
      child: child,
    );
  }
}

class _GamesBoardYahooStyleState extends State<GamesBoardYahooStyle> {
  final Map<String, bool> _allBattersByGame = {};
  final Map<String, bool> _statsExpandedByGame = {};

  List<Map<String, dynamic>> get games => dropUnplayedClinchedGames(widget.games, standings: widget.standings);
  String? get dateFilter => widget.dateFilter;
  bool get horizontal => widget.horizontal;

  bool _statsOpen(Map<String, dynamic> game) {
    final stored = _statsExpandedByGame[gameMatchupKey(game)];
    if (stored != null) return stored;
    if (widget.initialStatsExpanded) return true;
    return gameIsPregameState('${game['state'] ?? ''}');
  }

  bool _allBattersOf(Map<String, dynamic> game) {
    final key = gameMatchupKey(game);
    return _allBattersByGame[key] ?? (gameIsInProgress(game) && _gameHasLineup(game));
  }

  _TableGameCard _viewCard(
    List<Map<String, dynamic>> rows, {
    required double reveal,
    required double layoutHeight,
  }) {
    final game = rows.first;
    final key = gameMatchupKey(game);
    final allBatters = _allBattersOf(game);
    final statsExpanded = _statsOpen(game);
    return _TableGameCard(
      rows,
      playerStats: widget.playerStats,
      allBatters: allBatters,
      onAllBattersChanged: (value) {
        if (value == allBatters) return;
        setState(() => _allBattersByGame[key] = value);
      },
      statsExpanded: statsExpanded,
      statsReveal: reveal,
      statsLayoutHeight: layoutHeight,
      onStatsExpandedChanged: (value) {
        if (value == statsExpanded) return;
        setState(() => _statsExpandedByGame[key] = value);
      },
    );
  }

  _TableGameCard _measureCard(List<Map<String, dynamic>> rows, {required bool expanded}) {
    return _TableGameCard(
      rows,
      playerStats: widget.playerStats,
      allBatters: _allBattersOf(rows.first),
      onAllBattersChanged: (_) {},
      statsExpanded: expanded,
      onStatsExpandedChanged: (_) {},
    );
  }

  bool _cardCanGrow(List<Map<String, dynamic>> rows) {
    return _measureCard(rows, expanded: true)._hasCollapsibleStats;
  }

  double _collapsedHeight(List<Map<String, dynamic>> rows, {required bool stacked}) {
    return _measureCard(rows, expanded: false).intrinsicHeight(stackedTeams: stacked);
  }

  double _expandedHeight(List<Map<String, dynamic>> rows, {required bool stacked}) {
    return _measureCard(rows, expanded: true).intrinsicHeight(stackedTeams: stacked);
  }

  Widget _sizedCard(
    List<Map<String, dynamic>> rows, {
    required double target,
    required double collapsed,
  }) {
    final key = gameMatchupKey(rows.first);
    return _AnimatedGameSlot(
      key: ValueKey('game-card-shell-$key'),
      target: target,
      collapsed: collapsed,
      builder: (reveal, layoutHeight) => _viewCard(rows, reveal: reveal, layoutHeight: layoutHeight),
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

  @override
  Widget build(BuildContext context) {
    final src = (dateFilter == null || dateFilter!.isEmpty) ? games : games.where((g) => gameDateOnly(g['date_game']) == dateFilter).toList();
    final grouped = _groupGames(normalizeGames(src));

    if (horizontal) {
      if (grouped.isEmpty) {
        return const SizedBox(
          height: 40,
          child: Center(child: Text('試合はありません', style: TextStyle(fontSize: 12))),
        );
      }
      return LayoutBuilder(builder: (context, constraints) {
        final started = grouped.any((rows) => gameHasStarted(rows.first));
        final narrow = MediaQuery.sizeOf(context).width < stackedTeamsMaxWidth;
        bool stackedOf(List<Map<String, dynamic>> rows) => narrow && gameHasStarted(rows.first);
        final collapsed = [for (final rows in grouped) _collapsedHeight(rows, stacked: stackedOf(rows))];
        final expanded = [for (final rows in grouped) _expandedHeight(rows, stacked: stackedOf(rows))];
        final open = [for (final rows in grouped) _statsOpen(rows.first) && _cardCanGrow(rows)];
        if (started || narrow) {
          final gaps = gameBlockGap * math.max(0, grouped.length - 1);
          var restSum = gaps;
          var openWeight = 0.0;
          for (var i = 0; i < grouped.length; i++) {
            restSum += open[i] ? expanded[i] : collapsed[i];
            if (open[i]) openWeight += expanded[i];
          }
          final canFit = constraints.maxHeight.isFinite && constraints.maxHeight + 0.5 >= restSum;
          final extra = canFit ? math.max(0.0, constraints.maxHeight - restSum) : 0.0;
          final targets = [
            for (var i = 0; i < grouped.length; i++)
              if (!open[i] || !canFit || openWeight <= 0) open[i] ? expanded[i] : collapsed[i] else expanded[i] + extra * expanded[i] / openWeight,
          ];
          final column = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < grouped.length; i++) ...[
                if (i > 0) const SizedBox(height: gameBlockGap),
                _sizedCard(grouped[i], target: targets[i], collapsed: collapsed[i]),
              ],
            ],
          );
          if (canFit || !constraints.maxHeight.isFinite) return column;
          return SingleChildScrollView(child: column);
        }

        final intrinsics = [for (var i = 0; i < grouped.length; i++) open[i] ? expanded[i] : collapsed[i]];
        final neededH = intrinsics.reduce(math.max);
        final bounded = constraints.maxHeight.isFinite;
        final rowFits = !bounded || constraints.maxHeight + 0.5 >= neededH;
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < grouped.length; i++) ...[
              if (i > 0) const SizedBox(width: gameBlockGap),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _sizedCard(
                    grouped[i],
                    target: rowFits && bounded && open[i] ? constraints.maxHeight : intrinsics[i],
                    collapsed: collapsed[i],
                  ),
                ),
              ),
            ],
          ],
        );
        if (!bounded || rowFits) return row;
        return SingleChildScrollView(child: row);
      });
    }

    final bySec = <String, List<List<Map<String, dynamic>>>>{};
    for (final rows in grouped) {
      final sec = _sectionOf(rows.first);
      bySec.putIfAbsent(sec, () => []).add(rows);
    }

    if (bySec.isEmpty) {
      return const Center(child: Text('試合はありません', style: TextStyle(fontSize: 12)));
    }

    return LayoutBuilder(builder: (context, c) {
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
            final stacked = MediaQuery.sizeOf(context).width < stackedTeamsMaxWidth && gameHasStarted(g.first);
            final collapsedH = _collapsedHeight(g, stacked: stacked);
            final expandedH = _expandedHeight(g, stacked: stacked);
            final open = _statsOpen(g.first);
            final target = !open ? collapsedH : (hAvail > 0 ? math.max(expandedH, hAvail) : expandedH);
            final card = Align(
              alignment: Alignment.topCenter,
              child: _sizedCard(g, target: target, collapsed: collapsedH),
            );
            if (hAvail <= 0 || hAvail >= minCardH) return card;
            return SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: SizedBox(height: math.max(minCardH, target), child: card),
            );
          });
        }

        // 元の3分割構成を維持。足りないときだけ各枠内をスクロール
        return Column(
          children: [
            Expanded(child: slot(g0)),
            const SizedBox(height: gameBlockGap),
            Expanded(child: slot(g1)),
            const SizedBox(height: gameBlockGap),
            Expanded(child: slot(g2)),
          ],
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

typedef _PlayerLine = ({String name, String role, String colors, String mark, String pos, String stat, String hrTotal, String predict, String plays, String achieve, String tone, String chips, int rbi, String pinchNames});

typedef _LineupSlot = ({int order, List<_PlayerLine> players});

class _TableGameCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> playerStats;
  final bool allBatters;
  final ValueChanged<bool> onAllBattersChanged;
  final bool statsExpanded;

  /// 0 で畳み、1 で選手成績を全部見せる。開閉中はその間。
  final double statsReveal;
  final double statsLayoutHeight;
  final ValueChanged<bool> onStatsExpandedChanged;

  const _TableGameCard(
    this.rows, {
    this.playerStats = const [],
    this.allBatters = false,
    required this.onAllBattersChanged,
    this.statsExpanded = false,
    this.statsReveal = 0,
    this.statsLayoutHeight = 0,
    required this.onStatsExpandedChanged,
  });

  Map<String, dynamic> get game => rows.first;

  static const _lineColor = Color(0xFF333333);
  static const _labelColor = Color(0xFF5A5A5A);
  static const _minPlayerNameSize = 8.0;
  static const _minPlayerStatSize = 8.0;
  static const _minHeaderH = 22.0;
  double get _gameHeaderH => (_showRosterPicker ? TAB_BAR_H : _minHeaderH) * 2;
  static const _defenseRowH = 160.0;
  static const _statsToggleH = 22.0;
  static const _minTeamRowH = 46.0;
  static const _playerRowH = 18.0;
  static const _lineScoreH = 84.0;
  static const _scoreOnBoardH = 44.0;
  static const _lineupOrderW = 14.0;
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
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

  double? _qualifyingPercent(List<({String label, String value, bool leader})> lines) {
    for (final line in lines) {
      if (line.label != '規定到達率') continue;
      return double.tryParse(line.value.replaceAll('%', '').trim());
    }
    return null;
  }

  int? _seasonRank(String label, List<({String label, String value, bool leader})> lines, String pitcherName) {
    if (label == '規定到達率' || label.isEmpty) return null;
    final titles = switch (label) {
      '勝敗' => const ['最多勝', '勝利'],
      '防御率' => const ['防御率'],
      '奪三振' => const ['奪三振'],
      _ => const <String>[],
    };
    if (titles.isEmpty) return null;
    if (label == '防御率') {
      final rate = _qualifyingPercent(lines);
      if (rate == null || rate < 100) return null;
    }
    final compact = _compactPlayerName(pitcherName);
    final home = _compactPlayerName(_text('name_pitcher_home'));
    final away = _compactPlayerName(_text('name_pitcher_away'));
    final leagueId = compact == home
        ? (int.tryParse('${game['id_league_home']}') ?? 0)
        : compact == away
            ? (int.tryParse('${game['id_league_away']}') ?? 0)
            : 0;
    return pitcherLeagueRank(stats: playerStats, name: pitcherName, leagueId: leagueId, titles: titles);
  }

  String _seasonRankNote(String label, List<({String label, String value, bool leader})> lines, String pitcherName) {
    final rank = _seasonRank(label, lines, pitcherName);
    if (rank == null || rank <= 1) return '';
    return '（リーグ$rank位）';
  }

  static const _goldLeader = Color(0xFFFFD700);

  String _seasonTitleKey(String label) {
    if (label == '勝敗') return '最多勝';
    if (label == 'ホールド') return 'HP';
    return label;
  }

  Map<String, String> _pitcherNumberOneStats(String pitcherName) {
    if (pitcherName.trim().isEmpty) return const {};
    final compact = _compactPlayerName(pitcherName);
    final home = _compactPlayerName(_text('name_pitcher_home'));
    final away = _compactPlayerName(_text('name_pitcher_away'));
    final leagueId = compact == home
        ? (int.tryParse('${game['id_league_home']}') ?? 0)
        : compact == away
            ? (int.tryParse('${game['id_league_away']}') ?? 0)
            : 0;
    const titles = {
      '防御率',
      '最多勝',
      '奪三振',
      'HP',
      'ホールド',
      'セーブ',
      'WHIP',
      '被打率',
      '奪三振率',
      '与四球率',
      'K/BB',
      'QS率',
    };
    final found = <String, String>{};
    for (final row in playerStats) {
      final rank = int.tryParse('${row['int_rank']}') ?? 0;
      if (rank != 1) continue;
      final title = '${row['title'] ?? ''}'.trim();
      if (!titles.contains(title)) continue;
      final rowLeague = int.tryParse('${row['id_league']}') ?? 0;
      if (leagueId > 0 && rowLeague > 0 && rowLeague != leagueId) continue;
      final name = '${row['name_player'] ?? row['player_name'] ?? ''}';
      if (!samePlayerStatName(pitcherName, name)) continue;
      final value = '${row['stats'] ?? ''}'.trim();
      if (value.isEmpty || value == 'null') continue;
      found[_seasonTitleKey(title)] = value;
    }
    return found;
  }

  List<({String label, String value, bool leader})> _seasonDisplayLines(String stat, String pitcherName) {
    final base = stat.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).map(_seasonStat).toList();
    final leaders = _pitcherNumberOneStats(pitcherName);
    final shown = {for (final line in base) _seasonTitleKey(line.label)};
    final out = [
      for (final line in base) (label: line.label, value: line.value, leader: leaders.containsKey(_seasonTitleKey(line.label))),
    ];
    for (final entry in leaders.entries) {
      if (shown.contains(entry.key)) continue;
      out.add((label: entry.key, value: entry.value, leader: true));
      shown.add(entry.key);
    }
    return out;
  }

  Widget _seasonStatTable(String stat, String predict, double fontSize, {required String pitcherName}) {
    final lines = _seasonDisplayLines(stat, pitcherName);
    if (lines.isEmpty) return const SizedBox.shrink();
    final colors = _seasonChipColors(predict, lines.length);
    var labelW = 0.0;
    for (final line in lines) {
      final w = _textWidth(line.label, fontSize, weight: FontWeight.bold) + 8;
      if (w > labelW) labelW = w;
    }
    Widget valueText(int i) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: lines[i].value),
            TextSpan(text: _seasonRankNote(lines[i].label, lines, pitcherName)),
          ],
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.start,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: Colors.black87, height: 1),
      );
    }

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
                _seasonNameChip(lines[i].label, fontSize, labelW, lines[i].leader ? const [_goldLeader] : colors[i]),
                const SizedBox(width: 3),
                valueText(i),
                if (lines[i].leader || _seasonRank(lines[i].label, lines, pitcherName) == 1) Text('👑', style: TextStyle(fontSize: fontSize, height: 1)),
              ],
            ),
          ),
      ],
    );
  }

  double _seasonBlockH() {
    if (gameHasStarted(game)) return 0;
    final lines = math.max(
      _seasonDisplayLines(_seasonLine(true), _text('name_pitcher_home')).length,
      _seasonDisplayLines(_seasonLine(false), _text('name_pitcher_away')).length,
    );
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
    return switch (text.toUpperCase()) {
      'P' || 'PITCHER' => '投',
      'C' || 'CATCHER' => '捕',
      'FIRST' || '1B' => '一',
      'SECOND' || '2B' => '二',
      'THIRD' || '3B' => '三',
      'SS' => '遊',
      'LEFT' || 'LF' => '左',
      'CENTER' || 'CF' => '中',
      'RIGHT' || 'RF' => '右',
      'DH' => '指',
      _ => '',
    };
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

  String _preferRicherPlays(String current, String incoming) {
    if (incoming.isEmpty) return current;
    if (current.isEmpty) return incoming;
    return _playsRichness(incoming) > _playsRichness(current) ? incoming : current;
  }

  int _playsRichness(String plays) {
    var score = 0;
    for (final part in plays.split(' ')) {
      if (part.isEmpty) continue;
      score += 4;
      final kind = _playKind(part);
      final label = _playText(part);
      final genericHit = kind == 'single' && (label == '安' || label == 'ヒット');
      if (genericHit) score -= 3;
      if (label.contains('^') || RegExp(r'[左中右遊一二三投捕]').hasMatch(label)) score += 2;
      if (kind != 'single' || label.length > 1) score += 1;
    }
    return score;
  }

  bool _isPitchCount(String part) {
    final label = part.split('|').first.trim();
    return RegExp(r'^\d+球$').hasMatch(label);
  }

  bool _isVeloChip(String part) {
    final label = part.split('|').first.trim();
    return RegExp(r'^\d+(?:km|mph)$').hasMatch(label);
  }

  String _insertChipAfterPitchCount(String raw, String velo) {
    final parts = raw.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.any(_isVeloChip)) return raw;
    final at = parts.lastIndexWhere(_isPitchCount);
    if (at < 0) return parts.isEmpty ? velo : '${parts.join(' ')} $velo';
    parts.insert(at + 1, velo);
    return parts.join(' ');
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
        if (!samePlayerStatName('${player['name'] ?? ''}', name)) continue;
        final role = '${player['role'] ?? ''}'.trim();
        if (role.isNotEmpty && role != 'null') return role;
      }
    }
    return '';
  }

  String _lineupDefense(String name, int teamId) {
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
        if (!samePlayerStatName('${player['name'] ?? ''}', name)) continue;
        final pos = _defenseMark('${player['pos'] ?? ''}');
        if (pos.isNotEmpty) return pos;
      }
    }
    return '';
  }

  bool get _isMlbGame {
    final home = _int('id_league_home');
    final away = _int('id_league_away');
    return home == 3 || home == 4 || away == 3 || away == 4;
  }

  bool get _isPostseasonGame {
    return postseasonGameCodes.contains(_text('code_game').trim().toUpperCase());
  }

  bool _showJapanFlag(String name) {
    if (!_isMlbGame || name.trim().isEmpty) return false;
    for (final row in rows) {
      if (!samePlayerStatName(name, '${row['name_full_summary'] ?? ''}')) continue;
      if (_flagTrue(row['flg_japan'])) return true;
    }
    for (final row in playerStats) {
      if (!samePlayerStatName(name, '${row['name_player'] ?? ''}') && !samePlayerStatName(name, '${row['name_last'] ?? ''}')) {
        continue;
      }
      if (_flagTrue(row['flg_japan'])) return true;
    }
    return false;
  }

  bool _isSeasonStatLeader(String name) {
    if (!_isPostseasonGame || name.trim().isEmpty) return false;
    for (final row in playerStats) {
      final rank = int.tryParse('${row['int_rank']}') ?? 0;
      if (rank != 1) continue;
      if (samePlayerStatName(name, '${row['name_player'] ?? ''}') || samePlayerStatName(name, '${row['name_last'] ?? ''}')) {
        return true;
      }
    }
    return false;
  }

  Widget _nameBox(
    _PlayerLine player, {
    required double baseSize,
    required bool alignLeft,
    bool showAce = false,
  }) {
    return _pitcherNameBox(
      name: player.name,
      colorsRaw: player.colors,
      baseSize: baseSize,
      minSize: _minPlayerNameSize,
      alignLeft: alignLeft,
      showAce: showAce,
      showCrown: _isSeasonStatLeader(player.name),
      showJapan: _showJapanFlag(player.name),
    );
  }

  Color _pinchMarkColor(int index) => _pinchMarkColors[index % _pinchMarkColors.length];

  int? _pinchFlagIndex(Set<String> flags, {bool pinchOverride = false}) {
    for (var i = 0; i < _pinchMarkColors.length; i++) {
      if (flags.contains('pinch$i')) return i;
    }
    if (pinchOverride || flags.contains('pinch')) return 0;
    return null;
  }

  String _encodePinchCaption(String role, String name) => '$role\t${_compactPlayerName(name)}';

  List<({String role, String name})> _pinchCaptionParts(String raw) {
    if (raw.trim().isEmpty) return const [];
    if (raw.contains('\t')) {
      return [
        for (final line in raw.split('\n'))
          if (line.contains('\t'))
            (
              role: line.split('\t').first,
              name: line.split('\t').sublist(1).join('\t'),
            ),
      ];
    }
    final parts = <({String role, String name})>[];
    for (final part in raw.split(RegExp(r'\s{2,}'))) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final match = RegExp(r'^(代打|代走|代守)\s*[:：]?\s*(.+)$').firstMatch(text);
      parts.add(match != null ? (role: match.group(1)!, name: match.group(2)!.trim()) : (role: '', name: text));
    }
    return parts;
  }

  Widget _pinchCaptionsRow(String pinchNames, double fontSize) {
    final captions = _pinchCaptionParts(pinchNames);
    if (captions.isEmpty) return const SizedBox.shrink();
    final multiple = captions.length > 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < captions.length; i++)
          _pinchCaptionChip(
            role: captions[i].role,
            name: captions[i].name,
            fontSize: fontSize,
            colorIndex: i,
            colon: !multiple,
          ),
      ],
    );
  }

  Widget _pinchCaptionChip({
    required String role,
    required String name,
    required double fontSize,
    required int colorIndex,
    required bool colon,
  }) {
    final compact = _compactPlayerName(name);
    final text = colon ? '$role：$compact' : '$role $compact';
    final bg = _pinchMarkColor(colorIndex);
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 2),
      child: Container(
        key: ValueKey('pinch-caption-$colorIndex'),
        height: 14,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(2)),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: _inkOn(bg),
            fontSize: (fontSize - 1).clamp(8.0, 11.0),
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  bool _isPinchRole(String role) {
    return role == '代打' || role == '代走' || role == '代守';
  }

  bool _flagTrue(dynamic value) {
    if (value == true) return true;
    if (value is num) return value != 0;
    final s = '$value'.trim().toLowerCase();
    return s == 'true' || s == 't' || s == '1';
  }

  /// ACE は試合開始前（空 / 試合前 / 予想先発 / スタメン）だけ。
  bool _aceVisibleNow() {
    return gameIsPregameState('${game['state'] ?? ''}');
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
    var raw = '${row['txt_pitch_chips'] ?? ''}'.trim();
    if (raw.isEmpty || raw == 'null') {
      raw = _chipsFromPitchingText('${row['txt_pitching'] ?? ''}', starter: starter);
    }
    raw = _alertHighWalkChips(raw);
    final velo = _veloChip(row);
    if (velo.isEmpty) return raw;
    return _insertChipAfterPitchCount(raw, velo);
  }

  /// 保存済みチップでも、1回あたり四死球1.5以上は黒アラートにする。
  String _alertHighWalkChips(String raw) {
    final parts = raw.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return raw;
    double? innings;
    var walkAt = -1;
    var walks = 0;
    for (var i = 0; i < parts.length; i++) {
      final label = parts[i].split('|').first;
      final ipMatch = RegExp(r'^(\d+(?:\.\d+)?)回(?:無|\d+)失点$').firstMatch(label);
      if (ipMatch != null) innings = _pitchInnings(ipMatch.group(1)!);
      final walkMatch = RegExp(r'^(?:四死球)?(\d+)(?:BB|四死)?$').firstMatch(label);
      if (walkMatch != null && (label.contains('BB') || label.contains('四死'))) {
        walkAt = i;
        walks = int.parse(walkMatch.group(1)!);
      }
    }
    if (innings == null || walkAt < 0 || walks / innings < 1.5 - 1e-9) return raw;
    final part = parts[walkAt];
    final bar = part.lastIndexOf('|');
    final label = bar < 0 ? part : part.substring(0, bar);
    final kept = bar < 0 ? const <String>[] : part.substring(bar + 1).split('/').where((flag) => flag.isNotEmpty && flag != 'alert' && !_isPitchTone(flag)).toList();
    parts[walkAt] = '$label|${['alert', ...kept].join('/')}';
    return parts.join(' ');
  }

  bool _isPitchTone(String flag) {
    return const {'crimson', 'rorange', 'yorange', 'yellow', 'green', 'blue', 'gray', 'dgray', 'alert'}.contains(flag);
  }

  double _pitchInnings(String raw) {
    final value = double.tryParse(raw) ?? 0;
    final whole = value.truncate();
    var thirds = ((value - whole) * 10).round();
    if (thirds < 0) thirds = 0;
    if (thirds > 2) thirds = 2;
    final outs = whole * 3 + thirds;
    return outs > 0 ? outs / 3.0 : 1 / 3.0;
  }

  String _veloChip(Map<String, dynamic> row) {
    final kmh = int.tryParse('${row['int_velo_max'] ?? ''}') ?? 0;
    if (kmh <= 0) return '';
    if (_isMlbGame) {
      final mph = (kmh / 1.60934).round();
      if (mph >= 100) return '${mph}mph|crimson/blink';
      if (mph >= 98) return '${mph}mph|rorange/blink';
      return '';
    }
    if (kmh >= 160) return '${kmh}km|crimson/blink';
    if (kmh >= 155) return '${kmh}km|rorange/blink';
    return '';
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

    String runsTone(double rate) {
      if (rate >= 2 - 1e-9) return 'alert';
      return lower(rate, const [0.0, 2 / 9, 3 / 9, 4.5 / 9, 6 / 9, 1.0]);
    }

    String walksTone(double rate) {
      if (rate >= 1.5 - 1e-9) return 'alert';
      return lower(rate, const [0, 0.15, 0.30, 0.45, 0.6, 0.75]);
    }

    final inningsLabel = thirds <= 0 ? '$whole回' : '$whole.$thirds回';
    final tone = runsTone(runs / ip);
    final parts = <String>[
      '$inningsLabel${runs == 0 ? '無失点' : '$runs失点'}|${tone == 'gray' ? 'dgray' : tone}',
      '被安打$hits|${lower(hits / ip, const [0, 0.3, 0.6, 0.9, 1.2, 1.5])}',
      '${freePasses}四死|${walksTone(freePasses / ip)}',
      '${strikeouts}K|${starter ? higher(strikeouts / ip, const [1, 0.85, 0.7, 0.55, 0.4, 0.25]) : reliefK(strikeouts / ip)}',
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
    bool showUserPredictions = true,
  }) {
    final teamId = _int(home ? 'id_team_home' : 'id_team_away');
    final starterName = _text(home ? 'name_pitcher_home' : 'name_pitcher_away');
    final starterColors = showUserPredictions ? _text(home ? 'colors_pitcher_home' : 'colors_pitcher_away') : '';
    final result = <_PlayerLine>[];

    void add(String name, String playerColors, String mark, [String stat = '', String hrTotal = '', String predict = '', String plays = '', String achieve = '', String tone = '', String chips = '', int rbi = 0, String roleOverride = '']) {
      if (name.trim().isEmpty) return;
      final role = roleOverride.isNotEmpty
          ? roleOverride
          : pitcher
              ? _pitcherRoleMark(name, starterName, '')
              : _enterRole(name, teamId);
      final index = result.indexWhere((player) => player.name == name);
      final labels = showUserPredictions ? _predictLabel(predict) : '';
      final colors = showUserPredictions ? playerColors : '';
      if (index < 0) {
        result.add((name: name, role: role, colors: colors, mark: mark, pos: pitcher ? '' : _lineupDefense(name, teamId), stat: stat, hrTotal: hrTotal, predict: labels, plays: plays, achieve: achieve, tone: tone, chips: chips, rbi: rbi, pinchNames: ''));
        return;
      }
      final current = result[index];
      result[index] = (
        name: current.name,
        role: current.role.isNotEmpty ? current.role : role,
        colors: current.colors.isNotEmpty ? current.colors : colors,
        mark: current.mark.isNotEmpty ? current.mark : mark,
        pos: current.pos.isNotEmpty ? current.pos : (pitcher ? '' : _lineupDefense(name, teamId)),
        stat: current.stat.isNotEmpty ? current.stat : stat,
        hrTotal: current.hrTotal.isNotEmpty ? current.hrTotal : hrTotal,
        predict: showUserPredictions ? _predictLabel('${current.predict},$labels') : '',
        plays: _preferRicherPlays(current.plays, plays),
        achieve: current.achieve.isNotEmpty ? current.achieve : achieve,
        tone: current.tone.isNotEmpty ? current.tone : tone,
        chips: current.chips.isNotEmpty ? current.chips : chips,
        rbi: current.rbi > 0 ? current.rbi : rbi,
        pinchNames: current.pinchNames,
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
      final batting = pitcher ? '' : '${row['txt_batting'] ?? ''}';
      final plays = pitcher
          ? ''
          : () {
              final raw = _playsOf(row);
              if (raw.isNotEmpty) return raw;
              return _battingFallbackPlays(batting, mark);
            }();
      add(
        name,
        colors.isNotEmpty ? colors : (name == starterName ? starterColors : ''),
        mark,
        chips.isNotEmpty ? '' : _statOf(row, pitcher: pitcher),
        '',
        '${row['titles_predict'] ?? ''}',
        plays,
        _achieveOf(row, pitcher: pitcher),
        pitcher && chips.isEmpty ? _toneOf(row) : '',
        chips,
        pitcher ? 0 : _rbiFromBatting(batting),
        role,
      );
    }

    final starterTitles = (pitcher && showUserPredictions) ? _text(home ? 'titles_pitcher_home' : 'titles_pitcher_away') : '';
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

    // スタメン発表後も試合前なら、先発行にシーズン成績を載せる。
    if (pitcher && !gameHasStarted(game) && starterName.isNotEmpty) {
      add(starterName, starterColors, '', _seasonLine(home), '', starterTitles, '', '', '', '', 0, '先');
    }

    // 活躍選手のみ: 投手は先発と勝敗HSのみ（出場選手全表示では登板者をそのまま出す）。
    if (pitcher && !allBatters) {
      return result.where((player) => _keepNotablePitcher(player, starterName)).toList();
    }
    return result;
  }

  List<_LineupSlot> _lineupSlots({required bool home, bool showUserPredictions = true}) {
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
            players.add(_lineupPlayer(
              name,
              '${player['plays'] ?? ''}',
              teamId,
              role == 'null' ? '' : role,
              '${player['pos'] ?? ''}',
              player.containsKey('rbi') ? int.tryParse('${player['rbi']}') ?? 0 : null,
              showUserPredictions: showUserPredictions,
            ));
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

  ({int inning, bool bottom})? _attackingHalf() {
    final state = _text('state');
    if (gameIsPregameState(state) || state.contains('試合終了') || state.contains('コールド')) return null;
    return liveBlinkHalf(state, outs: _int('int_outs'));
  }

  int _dueBatterOrder({required bool home, required String attached}) {
    final stated = _int('int_batter_order');
    if (stated >= 1 && stated <= 9) return stated;
    final exact = <int>[];
    final loose = <int>[];
    for (final slot in _lineupSlots(home: home, showUserPredictions: false)) {
      if (slot.players.isEmpty) continue;
      final name = slot.players.last.name;
      if (_playerNameKey(name) == _playerNameKey(attached)) {
        exact.add(slot.order);
      } else if (samePlayerStatName(attached, name)) {
        loose.add(slot.order);
      }
    }
    if (exact.length == 1) return exact.single;
    if (exact.isEmpty && loose.length == 1) return loose.single;
    return 0;
  }

  String _dueBatterName({required bool home}) {
    final half = _attackingHalf();
    if (half == null || home != half.bottom) return '';
    final want = _int(home ? 'id_team_home' : 'id_team_away');
    if (want <= 0 || _int('id_team_batter') != want) return '';
    final attached = _text('name_batter').trim();
    if (attached.isEmpty) return '';
    final order = _dueBatterOrder(home: home, attached: attached);
    if (order > 0) {
      for (final slot in _lineupSlots(home: home, showUserPredictions: false)) {
        if (slot.order != order || slot.players.isEmpty) continue;
        return slot.players.last.name;
      }
    }
    if (order == 0) return '';
    return attached;
  }

  bool _isLiveBatter(String name, {required bool home, int? order}) {
    final due = _dueBatterName(home: home);
    if (due.isEmpty) return false;
    final attached = _text('name_batter').trim();
    final dueOrder = attached.isEmpty ? 0 : _dueBatterOrder(home: home, attached: attached);
    if (order != null && dueOrder > 0 && order != dueOrder) return false;
    if (order != null && dueOrder <= 0) return false;
    return samePlayerStatName(due, name);
  }

  static const _playChipH = 14.0;
  static const _playChipPadH = 3.0;

  double _playChipSize(double fontSize) => (fontSize - 1).clamp(8.0, 11.0);

  double _playChipWidth(double fontSize) {
    return _textWidth('中安', _playChipSize(fontSize), weight: FontWeight.w600) + _playChipPadH * 2;
  }

  Widget _nowPlayChip(double fontSize) {
    final chipSize = _playChipSize(fontSize);
    final chip = SizedBox(
      key: const ValueKey('now-play-chip'),
      height: _playChipH,
      width: _playChipWidth(fontSize),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'Now',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFB71C1C),
            fontSize: chipSize,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: BlinkBg(
        key: const ValueKey('live-batter-stats'),
        base: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(2),
        ),
        color: const Color(0xFFFF6D00),
        radius: 2,
        duration: const Duration(milliseconds: 380),
        fillMin: 0.05,
        fillMax: 1,
        borderColor: const Color(0xFFBF360C),
        borderWidth: 1.5,
        child: chip,
      ),
    );
  }

  Widget _blinkLiveBatterStats(Widget child, {required bool live, required double statSize}) {
    if (!live) return child;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        _nowPlayChip(statSize),
      ],
    );
  }

  _PlayerLine _lineupPlayer(
    String name,
    String plays,
    int teamId,
    String role,
    String position,
    int? listedRbi, {
    bool showUserPredictions = true,
  }) {
    Map<String, dynamic>? summary;
    for (final row in rows) {
      if (!samePlayerStatName('${row['name_full_summary'] ?? ''}', name)) continue;
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
      return (name: name, role: shownRole, colors: '', mark: _hrMarkFrom(rawPlays, null), pos: pos, stat: '', hrTotal: '', predict: '', plays: rawPlays, achieve: '', tone: '', chips: '', rbi: rbi, pinchNames: '');
    }
    final colors = showUserPredictions ? '${summary['colors_summary'] ?? ''}'.trim() : '';
    final summaryPlays = _playsOf(summary);
    final shownPlays = rawPlays.isNotEmpty ? rawPlays : summaryPlays;
    return (
      name: name,
      role: shownRole,
      colors: colors == 'null' ? '' : colors,
      mark: _hrMarkFrom(shownPlays, summary),
      pos: pos,
      stat: '',
      hrTotal: '',
      predict: showUserPredictions ? _predictLabel('${summary['titles_predict'] ?? ''}') : '',
      plays: shownPlays,
      achieve: _achieveOf(summary),
      tone: '',
      chips: '',
      rbi: rbi,
      pinchNames: '',
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

  static const _defensePosOrder = ['投', '捕', '一', '二', '三', '遊', '左', '中', '右', '指'];

  /// 正方形の球場画像に対する位置（左上 0,0、右下 1,1）。
  /// 表示枠の縦横比が変わっても、BoxFit.cover と同じ切り抜きに載せる。
  static const _defensePosOnImage = <String, Offset>{
    '投': Offset(0.50, 0.57),
    '捕': Offset(0.50, 0.72),
    '一': Offset(0.63, 0.62),
    '二': Offset(0.56, 0.49),
    '三': Offset(0.37, 0.62),
    '遊': Offset(0.44, 0.49),
    '左': Offset(0.30, 0.38),
    '中': Offset(0.50, 0.30),
    '右': Offset(0.70, 0.38),
    '指': Offset(0.18, 0.80),
  };

  /// セル全体を覆う切り抜き。縦が足りるときは中堅から捕手が見える位置に寄せる。
  static ({BoxFit fit, Alignment alignment, Offset origin, double drawn}) defenseImageFrame(Size box) {
    const image = 1024.0;
    const bandTop = 0.22;
    const bandBottom = 0.88;
    if (box.width <= 0 || box.height <= 0) {
      return (fit: BoxFit.cover, alignment: Alignment.center, origin: Offset.zero, drawn: 0);
    }
    final coverScale = math.max(box.width / image, box.height / image);
    final coverDrawn = image * coverScale;
    final visibleH = box.height / coverDrawn;
    final imageTop = visibleH >= 1 ? 0.0 : ((bandTop + bandBottom) / 2 - visibleH / 2).clamp(0.0, math.max(0.0, 1 - visibleH));
    final dy = -imageTop * coverDrawn;
    final dx = (box.width - coverDrawn) / 2;
    final denom = box.height - coverDrawn;
    final ay = denom.abs() < 0.5 ? 0.0 : ((dy * 2 / denom) - 1).clamp(-1.0, 1.0);
    return (fit: BoxFit.cover, alignment: Alignment(0, ay), origin: Offset(dx, dy), drawn: coverDrawn);
  }

  /// 1024×1024 の球場画像を [box] に合わせたときの、画像上の点。
  static Offset defenseImagePoint(Offset fraction, Size box) {
    final frame = defenseImageFrame(box);
    return frame.origin + Offset(fraction.dx * frame.drawn, fraction.dy * frame.drawn);
  }

  /// 名札の中心を、枠の中で重ならない位置へずらす。
  static List<Offset> separateDefenseNameCenters(List<Offset> centers, List<Size> sizes, Size box) {
    if (centers.isEmpty) return const [];
    final placed = [...centers];
    const gap = 2.0;
    for (var iter = 0; iter < 16; iter++) {
      var moved = false;
      for (var i = 0; i < placed.length; i++) {
        for (var j = i + 1; j < placed.length; j++) {
          final overlapX = (sizes[i].width + sizes[j].width) / 2 + gap - (placed[j].dx - placed[i].dx).abs();
          final overlapY = (sizes[i].height + sizes[j].height) / 2 + gap - (placed[j].dy - placed[i].dy).abs();
          if (overlapX <= 0 || overlapY <= 0) continue;
          if (overlapX < overlapY) {
            final sign = placed[j].dx >= placed[i].dx ? 1.0 : -1.0;
            final push = overlapX / 2;
            placed[i] = Offset(placed[i].dx - sign * push, placed[i].dy);
            placed[j] = Offset(placed[j].dx + sign * push, placed[j].dy);
          } else {
            final sign = placed[j].dy >= placed[i].dy ? 1.0 : -1.0;
            final push = overlapY / 2;
            placed[i] = Offset(placed[i].dx, placed[i].dy - sign * push);
            placed[j] = Offset(placed[j].dx, placed[j].dy + sign * push);
          }
          moved = true;
        }
      }
      if (!moved) break;
    }
    double clampCenter(double value, double half, double extent) {
      if (half * 2 >= extent) return extent / 2;
      return value.clamp(half, extent - half);
    }

    for (var i = 0; i < placed.length; i++) {
      placed[i] = Offset(
        clampCenter(placed[i].dx, sizes[i].width / 2, box.width),
        clampCenter(placed[i].dy, sizes[i].height / 2, box.height),
      );
    }
    return placed;
  }

  Size _defenseSpotSize(
    ({String pos, String starter, List<String> pinches, String starterMarks, List<String> pinchMarks}) spot,
    TextScaler scaler,
  ) {
    Size labelSize(String name, String marks, {required bool pinch}) {
      final fontSize = pinch ? 8.0 : 9.0;
      final painter = TextPainter(
        text: TextSpan(
          text: pinch ? '(${_diagramName(name)})' : _diagramName(name),
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, height: 1.05),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final badges = marks.split(RegExp(r'\s+')).where((part) => part == 'E' || part == 'FP').length;
      return Size(painter.width + 6 + badges * 18, painter.height + 2);
    }

    final starter = labelSize(spot.starter, spot.starterMarks, pinch: false);
    var width = starter.width;
    var height = starter.height;
    for (var i = 0; i < spot.pinches.length; i++) {
      final pinch = labelSize(spot.pinches[i], i < spot.pinchMarks.length ? spot.pinchMarks[i] : '', pinch: true);
      width = math.max(width, pinch.width);
      height += pinch.height;
    }
    return Size(width, height);
  }

  String _currentPitcherName({required bool home}) {
    final teamId = _int(home ? 'id_team_home' : 'id_team_away');
    var last = '';
    final raw = game['lineup'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        if ((int.tryParse('${item['id_team']}') ?? -1) != teamId) continue;
        final listed = item['players'];
        if (listed is! List) continue;
        for (final player in listed) {
          if (player is! Map) continue;
          final name = '${player['name'] ?? ''}'.trim();
          final pos = _defenseMark('${player['pos'] ?? ''}');
          final role = '${player['role'] ?? ''}'.trim();
          if (name.isEmpty || pos != '投') continue;
          if (role == '代打' || role == '代走') continue;
          last = name;
        }
      }
    }
    if (last.isNotEmpty) return last;
    for (final row in rows) {
      if (!_isPitcher(row)) continue;
      if ((int.tryParse('${row['id_team_summary']}') ?? -1) != teamId) continue;
      final name = '${row['name_full_summary'] ?? ''}'.trim();
      if (name.isNotEmpty) last = name;
    }
    if (last.isNotEmpty) return last;
    return _text(home ? 'name_pitcher_home' : 'name_pitcher_away');
  }

  List<({String pos, String starter, List<String> pinches, String starterMarks, List<String> pinchMarks})> _defenseSpots({required bool home}) {
    final teamId = _int(home ? 'id_team_home' : 'id_team_away');
    final byPos = <String, List<({String name, String marks})>>{};
    final raw = game['lineup'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        if ((int.tryParse('${item['id_team']}') ?? -1) != teamId) continue;
        final listed = item['players'];
        if (listed is! List) continue;
        for (final player in listed) {
          if (player is! Map) continue;
          final name = '${player['name'] ?? ''}'.trim();
          final pos = _defenseMark('${player['pos'] ?? ''}');
          final role = '${player['role'] ?? ''}'.trim();
          if (name.isEmpty || pos.isEmpty) continue;
          if (role == '代打' || role == '代走') continue;
          byPos.putIfAbsent(pos, () => []).add((name: name, marks: '${player['field_marks'] ?? ''}'.trim()));
        }
      }
    }
    final pitchers = byPos['投'];
    if (pitchers != null && pitchers.isNotEmpty) {
      byPos['投'] = [pitchers.last];
    } else {
      final current = _currentPitcherName(home: home);
      if (current.isNotEmpty) {
        byPos['投'] = [(name: current, marks: '')];
      }
    }
    return [
      for (final pos in _defensePosOrder)
        if (byPos[pos] != null && byPos[pos]!.isNotEmpty)
          (
            pos: pos,
            starter: byPos[pos]!.first.name,
            pinches: [for (final player in byPos[pos]!.skip(1)) player.name],
            starterMarks: byPos[pos]!.first.marks,
            pinchMarks: [for (final player in byPos[pos]!.skip(1)) player.marks],
          ),
    ];
  }

  String _diagramName(String name) {
    final compact = _compactPlayerName(name);
    final parts = compact.split(RegExp(r'[・･·]')).where((part) => part.isNotEmpty).toList();
    final short = parts.length >= 2 ? parts.last : compact;
    if (short.length <= 6) return short;
    return short.substring(0, 6);
  }

  Widget _fieldMarkBadge(String mark) {
    final error = mark == 'E';
    return Container(
      key: ValueKey('field-mark-$mark'),
      margin: const EdgeInsets.only(left: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFC62828) : const Color(0xFFF9A825),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        mark,
        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800, height: 1.1),
      ),
    );
  }

  Widget _defenseNameColumn(String name, String marks, {required String pos, bool pinch = false}) {
    final bg = _positionColor(pos);
    final ink = _inkOn(bg);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: ValueKey(pinch ? 'defense-bg-pinch-$name' : 'defense-bg-$name'),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                pinch ? '(${_diagramName(name)})' : _diagramName(name),
                key: ValueKey(pinch ? 'defense-pinch-$name' : 'defense-name-$name'),
                style: TextStyle(
                  color: ink,
                  fontSize: pinch ? 8 : 9,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
            ),
            for (final mark in marks.split(RegExp(r'\s+')).where((part) => part == 'E' || part == 'FP')) _fieldMarkBadge(mark),
          ],
        ),
      ],
    );
  }

  Widget _defenseCell({required bool home, required Color pale, bool bottom = false, bool right = true}) {
    final inside = _text('path_image_inside');
    final spots = _defenseSpots(home: home);
    return _cell(
      color: pale,
      right: right,
      bottom: bottom,
      padding: const EdgeInsets.all(2),
      child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 120.0;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : _defenseRowH;
        final box = Size(w, h);
        final frame = defenseImageFrame(box);
        final scaler = MediaQuery.textScalerOf(context);
        final centers = separateDefenseNameCenters(
          [
            for (final spot in spots) defenseImagePoint(_defensePosOnImage[spot.pos] ?? const Offset(0.5, 0.5), box),
          ],
          [for (final spot in spots) _defenseSpotSize(spot, scaler)],
          box,
        );
        return SizedBox(
          width: w,
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (inside.isNotEmpty)
                  Image.asset(
                    inside,
                    fit: frame.fit,
                    alignment: frame.alignment,
                    errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1B5E20)),
                  )
                else
                  const ColoredBox(color: Color(0xFF1B5E20)),
                for (var i = 0; i < spots.length; i++)
                  () {
                    final spot = spots[i];
                    final at = centers[i];
                    return Positioned(
                      left: at.dx,
                      top: at.dy,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, -0.5),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _defenseNameColumn(spot.starter, spot.starterMarks, pos: spot.pos),
                            for (var i = 0; i < spot.pinches.length; i++)
                              _defenseNameColumn(
                                spot.pinches[i],
                                i < spot.pinchMarks.length ? spot.pinchMarks[i] : '',
                                pos: spot.pos,
                                pinch: true,
                              ),
                          ],
                        ),
                      ),
                    );
                  }(),
              ],
            ),
          ),
        );
      }),
    );
  }

  ({String plays, String pinchNames}) _slotPlayLine(
    List<_PlayerLine> players, {
    required String displayedName,
    Map<String, String> fallbackPlays = const {},
  }) {
    final captionPlayers = [
      for (final player in players)
        if (_isPinchRole(player.role) && (!samePlayerStatName(player.name, displayedName) || players.length == 1)) player,
    ];
    final multiple = captionPlayers.length > 1;
    final indexByKey = <String, int>{
      for (var i = 0; i < captionPlayers.length; i++) _playerNameKey(captionPlayers[i].name): i,
    };
    final parts = <String>[];
    for (final player in players) {
      final raw = player.plays.isNotEmpty
          ? player.plays
          : fallbackPlays.entries
              .firstWhere(
                (entry) => entry.key == _playerNameKey(player.name) || samePlayerStatName(entry.key, player.name),
                orElse: () => const MapEntry('', ''),
              )
              .value;
      final idx = indexByKey[_playerNameKey(player.name)];
      for (final part in raw.split(' ')) {
        if (part.isEmpty) continue;
        parts.add(idx == null ? part : _withPlayFlag(part, multiple ? 'pinch$idx' : 'pinch'));
      }
    }
    return (
      plays: parts.join(' '),
      pinchNames: [
        for (final player in captionPlayers) _encodePinchCaption(player.role, player.name),
      ].join('\n'),
    );
  }

  Widget _lineupSlotStatLine(_LineupSlot slot, double statSize) {
    final displayed = slot.players.isEmpty ? '' : slot.players.first.name;
    final packed = _slotPlayLine(slot.players, displayedName: displayed);
    final achievements = <String>[];
    final predicts = <String>[];
    var rbi = 0;
    for (final player in slot.players) {
      rbi += player.rbi;
      achievements.addAll(_visibleAchievements(player.achieve));
      if (player.predict.isNotEmpty) predicts.add(player.predict);
    }
    return _battingChipsRow(
      plays: packed.plays,
      rbi: rbi,
      achievements: achievements,
      pinchNames: packed.pinchNames,
      predict: predicts.join(','),
      statSize: statSize,
      includeOuts: true,
      showFiveTako: slot.players.any((player) => _isFivePlateOuts(player.plays)),
    );
  }

  Widget _battingChipsRow({
    required String plays,
    required int rbi,
    required List<String> achievements,
    required String pinchNames,
    required String predict,
    required double statSize,
    required bool includeOuts,
    bool showFiveTako = false,
  }) {
    final parts = _orderedPlays(plays, includeOuts: includeOuts, rbi: rbi);
    final extraAt = _extraRbiIndex(parts, rbi);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) _playChip(parts[i], statSize, compact: includeOuts, rbiOverride: extraAt == i ? rbi : -1),
        for (final part in achievements) _playChip(part, statSize, blink: true),
        if (pinchNames.isNotEmpty) _pinchCaptionsRow(pinchNames, statSize),
        if (predict.isNotEmpty) ...[
          if (plays.isNotEmpty || achievements.isNotEmpty) const SizedBox(width: 2),
          for (final part in predict.split(','))
            if (part.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: _predictBadge(part, statSize),
              ),
        ],
        if (showFiveTako) _fiveTakoChip(statSize),
      ],
    );
  }

  Widget _lineupCell(
    List<_LineupSlot> slots, {
    required Color color,
    required double size,
    required bool right,
    required bool home,
    bool bottom = false,
    double nameColW = 0,
  }) {
    final nameSize = size < _minPlayerNameSize ? _minPlayerNameSize : size;
    final statSize = (nameSize * 0.92).clamp(_minPlayerStatSize, 12.0);
    final badgeWidth = (nameSize + 2).clamp(9.0, 16.0);
    final leadingW = _statLeadWidth(badgeWidth);
    return _cell(
      color: color,
      right: right,
      bottom: bottom,
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: LayoutBuilder(builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final count = math.max(1, slots.length);
        final fitRowH = maxH.isFinite ? math.min(_playerRowH, maxH / count) : _playerRowH;
        final cellW = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        if (cellW < 1) return const SizedBox.expand();
        final scaler = MediaQuery.textScalerOf(context);
        var nameW = nameColW > 0 ? nameColW : 0.0;
        if (nameColW <= 0) {
          for (final slot in slots) {
            if (slot.players.isEmpty) continue;
            final player = slot.players.first;
            var w = _textWidth(_compactPlayerName(player.name), nameSize, weight: FontWeight.bold, textScaler: scaler) + 8;
            if (_isSeasonStatLeader(player.name)) w += nameSize;
            if (_showJapanFlag(player.name)) w += nameSize;
            if (w > nameW) nameW = w;
          }
          nameW = nameW.ceilToDouble();
        }
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
                  width: leadingW,
                  child: Row(
                    children: [
                      SizedBox(
                        width: _lineupOrderW,
                        child: Text(
                          '${slot.order}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: math.min(9, fitRowH * 0.7), fontWeight: FontWeight.bold, color: Colors.black87, height: 1),
                        ),
                      ),
                      SizedBox(
                        width: badgeWidth,
                        child: player == null || player.pos.isEmpty ? const SizedBox() : _lineupMark(player.pos, nameSize),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: nameW,
                  child: player == null
                      ? const SizedBox()
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _nameBox(
                            player,
                            baseSize: nameSize,
                            alignLeft: true,
                          ),
                        ),
                ),
              ],
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
                        children: [
                          for (final slot in slots)
                            SizedBox(
                              height: fitRowH,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _blinkLiveBatterStats(
                                  _lineupSlotStatLine(slot, statSize),
                                  live: slot.players.isNotEmpty && _isLiveBatter(slot.players.last.name, home: home, order: slot.order),
                                  statSize: statSize,
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
      }),
    );
  }

  List<_PlayerLine> _notableBatters({required bool home, bool showUserPredictions = true}) {
    final merged = _mergeLineupPlays(
      _players(home: home, pitcher: false, showUserPredictions: showUserPredictions),
      _lineupSlots(home: home, showUserPredictions: showUserPredictions),
    ).where(_keepNotableBatter).toList();
    merged.sort((a, b) {
      final byPoints = _batterPoints(b).compareTo(_batterPoints(a));
      if (byPoints != 0) return byPoints;
      return _playerNameKey(a.name).compareTo(_playerNameKey(b.name));
    });
    return merged;
  }

  String _battingFallbackPlays(String batting, String mark) {
    final text = batting.trim();
    if (text.isEmpty) return '';
    final rbi = _rbiFromBatting(text);
    if (mark == 'HR' || RegExp(r'\d+HR').hasMatch(text)) return '';
    if (text.contains('犠飛') && rbi > 0) return '犠飛|sacfly';
    if ((text.contains('犠打') || text.contains('犠')) && rbi > 0) return '犠打|sacbunt';
    if (rbi > 0 && RegExp(r'[1-9]\d*安打').hasMatch(text)) return 'タイムリー|timely';
    final hits = int.tryParse(RegExp(r'(\d+)安打').firstMatch(text)?.group(1) ?? '') ?? 0;
    if (hits >= 3) return '安|single 安|single 安|single';
    return '';
  }

  String _hrMarkFrom(String plays, Map<String, dynamic>? summary) {
    if (summary != null && _batterMark(summary) == 'HR') return 'HR';
    for (final part in plays.split(' ')) {
      if (part.isNotEmpty && _playKind(part) == 'hr') return 'HR';
    }
    return '';
  }

  /// 本塁打・タイムリー・打点付き犠打犠飛・猛打賞・日本人。
  bool _keepNotableBatter(_PlayerLine player) {
    if (player.mark == 'HR' || _showJapanFlag(player.name)) return true;
    if (player.rbi > 0) return true;
    if (_hasMultiHitAward(player)) return true;
    for (final part in player.plays.split(' ')) {
      if (part.isEmpty) continue;
      if (_isFeaturedBatterPlay(part, rbi: player.rbi)) return true;
    }
    return false;
  }

  bool _hasMultiHitAward(_PlayerLine player) {
    final achieve = player.achieve;
    if (achieve.contains('猛打賞') || achieve.contains('multihit') || achieve.contains('サイクル') || achieve.contains('cycle')) {
      return true;
    }
    var hits = 0;
    for (final part in player.plays.split(' ')) {
      if (part.isEmpty) continue;
      switch (_playKind(part)) {
        case 'hr' || 'timely' || 'single' || 'double' || 'triple' || 'extra':
          hits++;
      }
    }
    return hits >= 3;
  }

  bool _isFeaturedBatterPlay(String encoded, {int rbi = 0}) {
    if (_isErrorOrInterferencePlay(encoded)) return false;
    final kind = _playKind(encoded);
    if (kind == 'hr' || kind == 'timely') return true;
    if (kind == 'sacfly' || kind == 'squeeze') return true;
    if (kind == 'sac' || kind == 'sacbunt') {
      final label = _playText(encoded);
      return rbi > 0 || _rbiOfEncoded(encoded) > 0 || label.contains('スクイズ');
    }
    if (kind == 'out' || kind == 'walk' || kind == 'fc') {
      return _rbiOfEncoded(encoded) > 0;
    }
    return false;
  }

  bool _isNotableBatterStatPlay(String encoded, {int rbi = 0}) {
    if (_isErrorOrInterferencePlay(encoded)) return false;
    final kind = _playKind(encoded);
    if (kind == 'single' || kind == 'double' || kind == 'triple' || kind == 'extra') return true;
    return _isFeaturedBatterPlay(encoded, rbi: rbi);
  }

  double _batterPoints(_PlayerLine player) {
    var points = 0.0;
    for (final part in player.plays.split(' ')) {
      if (part.isEmpty) continue;
      final kind = _playKind(part);
      final rbi = _rbiOfEncoded(part);
      points += switch (kind) {
        'hr' => 1 + 5 + rbi * 2,
        'timely' || 'single' || 'double' || 'triple' || 'extra' => 1 + rbi * 2,
        'steal' => 1,
        'walk' => 0.8 + rbi * 2,
        'dead' => 0.2,
        'sacfly' || 'squeeze' || 'sac' || 'sacbunt' => 0.2 + rbi * 2,
        _ => rbi * 2,
      };
    }
    return points;
  }

  bool _hasHighlightBatterPlay(_PlayerLine player) {
    if (_keepNotableBatter(player)) return true;
    return false;
  }

  bool _isErrorOrInterferencePlay(String encoded) {
    final kind = _playKind(encoded);
    if (kind == 'error' || kind == 'fc') return true;
    final label = _playText(encoded);
    return label.contains('投失') || label.contains('失策') || label.contains('野選') || label.contains('遊選') || label.contains('打妨') || label.contains('打撃妨害') || label.contains('走塁妨害') || label.contains('守備妨害');
  }

  _PlayerLine? _playerByStatName(Map<String, _PlayerLine> byName, String name) {
    final direct = byName[_playerNameKey(name)];
    if (direct != null) return direct;
    for (final player in byName.values) {
      if (samePlayerStatName(player.name, name)) return player;
    }
    return null;
  }

  bool _statNameUsed(Set<String> used, String name) {
    if (used.contains(_playerNameKey(name))) return true;
    return used.any((key) => samePlayerStatName(key, name) || samePlayerStatName(key, _playerNameKey(name)));
  }

  /// 活躍選手は打席チップを先に並べ、代打・代走・代守の名前は右端に出す。
  List<_PlayerLine> _mergeLineupPlays(List<_PlayerLine> notables, List<_LineupSlot> slots) {
    if (slots.every((slot) => slot.players.isEmpty)) return notables;
    final byName = <String, _PlayerLine>{};
    for (final player in notables) {
      byName[_playerNameKey(player.name)] = player;
    }
    final used = <String>{};
    final merged = <_PlayerLine>[];
    for (final slot in slots) {
      if (slot.players.isEmpty) continue;
      final notableInSlot = slot.players.where((player) => _playerByStatName(byName, player.name) != null).toList();
      if (notableInSlot.isEmpty && !slot.players.any(_hasHighlightBatterPlay)) continue;
      final starter = slot.players.first;
      final head = _playerByStatName(byName, starter.name) ?? (notableInSlot.isEmpty ? starter : _playerByStatName(byName, notableInSlot.first.name) ?? starter);
      final packed = _slotPlayLine(
        slot.players,
        displayedName: head.name,
        fallbackPlays: {
          for (final entry in byName.entries) entry.key: entry.value.plays,
        },
      );
      for (final player in slot.players) {
        used.add(_playerNameKey(player.name));
        final matched = _playerByStatName(byName, player.name);
        if (matched != null) used.add(_playerNameKey(matched.name));
      }
      merged.add((
        name: head.name,
        role: starter.role,
        colors: head.colors,
        mark: _hrMarkFrom(packed.plays, null).isNotEmpty ? 'HR' : (head.mark == 'HR' ? 'HR' : ''),
        pos: starter.pos.isNotEmpty ? starter.pos : head.pos,
        stat: head.stat,
        hrTotal: head.hrTotal,
        predict: head.predict,
        plays: packed.plays,
        achieve: head.achieve,
        tone: head.tone,
        chips: head.chips,
        rbi: math.max(head.rbi, starter.rbi),
        pinchNames: packed.pinchNames,
      ));
    }
    for (final player in notables) {
      if (!_statNameUsed(used, player.name)) merged.add(player);
    }
    return merged.isEmpty ? notables : merged;
  }

  int _batterCount(bool home) {
    if (!allBatters) return _notableBatters(home: home).length;
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
    final headerH = _gameHeaderH;
    final head = headerH + _teamBlockH + chrome + (inProgress ? 6.0 : 0.0);
    final batterHomeH = _showBatterStats ? math.max(1, batterHome) * _playerRowH : 0.0;
    final batterAwayH = _showBatterStats ? math.max(1, batterAway) * _playerRowH : 0.0;
    final defenseH = _showDefense ? _defenseRowH : 0.0;
    final showPitchers = _showPitcherStats;
    final toggleH = _hasCollapsibleStats ? _statsToggleH : 0.0;
    final rosterBarH = statsExpanded && _showRosterPicker ? _statsToggleH : 0.0;
    // カード枠と、試合中の点滅枠の分だけ足す。余白は置かない。
    final frame = 2.0 + (inProgress ? 6.0 : 0.0);
    if (!statsExpanded) return headerH + _teamBlockH + toggleH + frame;
    if (stackedTeams) {
      final homePitchH = showPitchers ? _pitcherBlockH(homePitchers.length) : 0.0;
      final awayPitchH = showPitchers ? _pitcherBlockH(awayPitchers.length) : 0.0;
      return head + toggleH + rosterBarH + homePitchH + batterHomeH + defenseH + awayPitchH + batterAwayH + defenseH + sectionPad * (_showBatterStats ? 4 : 2);
    }
    final pitcherN = math.max(1, math.max(homePitchers.length, awayPitchers.length));
    final pitcherH = showPitchers ? pitcherN * _playerRowH + _seasonBlockH() : 0.0;
    final batterH = _showBatterStats ? math.max(1, math.max(batterHome, batterAway)) * _playerRowH : 0.0;
    return head + toggleH + rosterBarH + pitcherH + batterH + defenseH + sectionPad * 2;
  }

  double _statLeadWidth(double badgeWidth) {
    return math.max(badgeWidth * 2, _lineupOrderW + badgeWidth) + 0.5;
  }

  bool get _showLineScore {
    if (gameIsPregameState(_text('state'))) return false;
    return _int('score_home') >= 0 && _int('score_away') >= 0;
  }

  bool get _showBatterStats => gameHasStarted(game) && !gameIsPregameState(_text('state'));

  bool _hasPitcherName(String raw) {
    final name = raw.trim();
    return name.isNotEmpty && name != 'null';
  }

  bool get _hasAnnouncedStarters => _hasPitcherName(_text('name_pitcher_home')) || _hasPitcherName(_text('name_pitcher_away'));

  /// 試合前は予告先発がいるときだけ投手欄を出す。
  bool get _showPitcherStats => _showBatterStats || _hasAnnouncedStarters;

  bool get _showDefense => allBatters && _gameHasLineup(game);

  bool get _hasCollapsibleStats => _showPitcherStats || _showBatterStats;

  Widget _playerStatsToggle() {
    return SizedBox(
      height: _statsToggleH,
      child: Material(
        color: _labelColor,
        child: InkWell(
          onTap: () => onStatsExpandedChanged(!statsExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                const Text(
                  '選手成績',
                  maxLines: 1,
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, height: 1),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: statsExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: const Icon(Icons.expand_more, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _showRosterPicker => _showBatterStats;

  Widget _allBattersBar() {
    return SizedBox(
      height: _statsToggleH,
      child: ColoredBox(
        color: const Color(0xFFE8E8E8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: rosterAllBattersCheckbox(
              allBatters: allBatters,
              onChanged: onAllBattersChanged,
              foreground: const Color(0xFF222222),
              height: _statsToggleH - 2,
            ),
          ),
        ),
      ),
    );
  }

  double get _teamBlockH => _showLineScore ? _scoreOnBoardH + _lineScoreH : _minTeamRowH;

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
    bool embedded = false,
  }) {
    final homeInnings = _inningScores('txt_scores_home');
    final awayInnings = _inningScores('txt_scores_away');
    final state = _text('state');
    final live = liveBlinkHalf(state, outs: _int('int_outs'));
    final finished = state.contains('試合終了') || state.contains('コールド');
    final n = math.max(9, math.max(homeInnings.length, math.max(awayInnings.length, live?.inning ?? 0)));
    String at(List<String> values, int index, {required bool homeRow}) {
      if (!lineScoreInningStarted(
        inning: index + 1,
        homeRow: homeRow,
        live: live,
        finished: finished,
        recordedLength: values.length,
      )) {
        return '';
      }
      return index < values.length ? values[index] : '';
    }

    final homeLogo = teamLogoVisual(_text('name_team_home'), abbrev: _text('name_shortest_home'));
    final awayLogo = teamLogoVisual(_text('name_team_away'), abbrev: _text('name_shortest_away'));

    Widget row({
      required bool header,
      required List<String> innings,
      required String runs,
      required String hits,
      required String errors,
      Color? teamBg,
      ({String? asset, String? networkUrl})? logo,
      bool? homeRow,
    }) {
      final numbers = <String>[
        for (var i = 0; i < n; i++) header ? '${i + 1}' : at(innings, i, homeRow: homeRow ?? false),
        header ? 'R' : runs,
        header ? 'H' : hits,
        header ? 'E' : errors,
      ];
      return Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          const preferredNumberW = 20.0;
          const minLogoW = 28.0;
          const maxLogoW = 56.0;
          final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : preferredNumberW * numbers.length + minLogoW;
          var numberW = preferredNumberW;
          var logoW = maxW - numberW * numbers.length;
          if (logoW > maxLogoW) {
            logoW = maxLogoW;
            numberW = numbers.isEmpty ? 0.0 : math.max(0.0, (maxW - logoW) / numbers.length);
          } else if (logoW < minLogoW) {
            logoW = math.min(minLogoW, maxW * 0.18);
            numberW = numbers.isEmpty ? 0.0 : math.max(0.0, (maxW - logoW) / numbers.length);
          }

          Widget numberCell(int index) {
            final label = numbers[index];
            final total = index >= numbers.length - 3;
            final liveCell = !header && !total && live != null && homeRow != null && live.inning == index + 1 && live.bottom == homeRow;
            const inningGreen = Color(0xFF1B5E20);
            Widget number = Text(
              label,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1,
                fontWeight: header || total ? FontWeight.bold : FontWeight.w600,
                color: Colors.white,
              ),
            );
            if (liveCell) {
              number = BlinkBg(
                key: const ValueKey('live-inning-cell'),
                base: const BoxDecoration(),
                color: const Color(0xFFFFF176),
                radius: 2,
                duration: const Duration(milliseconds: 700),
                borderWidth: 0,
                child: number,
              );
            }
            return SizedBox(
              width: numberW,
              child: _cell(
                color: header ? const Color(0xFF555555) : inningGreen,
                right: index != numbers.length - 1,
                padding: EdgeInsets.zero,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: number,
                  ),
                ),
              ),
            );
          }

          return Row(
            children: [
              SizedBox(
                width: logoW,
                child: _cell(
                  color: header ? const Color(0xFF555555) : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: header ? const SizedBox.shrink() : _logoMark(asset: logo?.asset, networkUrl: logo?.networkUrl, bg: teamBg, fg: Colors.white, side: math.max(10, logoW - 2)),
                ),
              ),
              for (var i = 0; i < numbers.length; i++) numberCell(i),
            ],
          );
        }),
      );
    }

    final table = Column(
      children: [
        row(header: true, innings: const [], runs: '', hits: '', errors: ''),
        row(
          header: false,
          innings: awayInnings,
          runs: _countText('int_runs_away'),
          hits: _countText('int_hit_away'),
          errors: _countText('int_error_away'),
          teamBg: awayBg,
          logo: awayLogo,
          homeRow: false,
        ),
        row(
          header: false,
          innings: homeInnings,
          runs: _countText('int_runs_home'),
          hits: _countText('int_hit_home'),
          errors: _countText('int_error_home'),
          teamBg: homeBg,
          logo: homeLogo,
          homeRow: true,
        ),
      ],
    );
    if (embedded) return table;
    return SizedBox(height: _lineScoreH, child: table);
  }

  Widget _scoreBoardCenter({
    required String score,
    required String state,
    required bool heated,
    required double scoreSize,
    required double stateSize,
    required Color? homeBg,
    required Color? awayBg,
    required String homeName,
    required String awayName,
    String? homeAbbrev,
    String? awayAbbrev,
    bool draw = false,
  }) {
    final shownState = displayBoardState(state);
    return _cell(
      color: Colors.white,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SizedBox(
            height: _scoreOnBoardH,
            child: _scoreWithLogos(
              height: _scoreOnBoardH,
              state: shownState,
              score: score,
              heated: heated,
              stateSize: stateSize,
              scoreSize: scoreSize,
              homeName: homeName,
              awayName: awayName,
              homeAbbrev: homeAbbrev,
              awayAbbrev: awayAbbrev,
              draw: draw,
            ),
          ),
          Expanded(
            child: _lineScoreTable(
              homeBg: homeBg,
              awayBg: awayBg,
              embedded: true,
            ),
          ),
        ],
      ),
    );
  }

  /// ロゴはセル高さの約80%。試合前・イニング表記の左右に少し余白を空けて置く。
  Widget _scoreWithLogos({
    required double height,
    required String state,
    required String score,
    required bool heated,
    required double stateSize,
    required double scoreSize,
    required String homeName,
    required String awayName,
    String? homeAbbrev,
    String? awayAbbrev,
    bool draw = false,
  }) {
    final logoSide = height * 0.8;
    const sidePad = 4.0;
    final shownState = state.trim();
    final homeLogo = teamLogoVisual(homeName, abbrev: homeAbbrev);
    final awayLogo = teamLogoVisual(awayName, abbrev: awayAbbrev);
    final labels = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shownState.isNotEmpty)
          Text(
            shownState,
            maxLines: 1,
            style: TextStyle(
              fontSize: stateSize,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
        Text(
          score,
          maxLines: 1,
          style: TextStyle(
            fontSize: scoreSize,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        if (draw)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Image.asset(
              resultBadgeDraw,
              height: 14,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        if (heated)
          BlinkBg(
            key: const ValueKey('heated-game'),
            base: BoxDecoration(borderRadius: BorderRadius.circular(3), color: const Color(0xFFFFF3E0)),
            color: const Color(0xFFFF7043),
            radius: 3,
            duration: const Duration(milliseconds: 700),
            fillMin: 0.15,
            fillMax: 0.95,
            borderColor: const Color(0xFFD84315),
            borderWidth: 1,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: Text(
                '白熱試合',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFB71C1C),
                ),
              ),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _logoMark(
              asset: homeLogo.asset,
              networkUrl: homeLogo.networkUrl,
              bg: Colors.white,
              fg: Colors.black87,
              side: logoSide,
            ),
            const SizedBox(width: sidePad),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: math.max(8, height - 2)),
              child: FittedBox(fit: BoxFit.scaleDown, child: labels),
            ),
            const SizedBox(width: sidePad),
            _logoMark(
              asset: awayLogo.asset,
              networkUrl: awayLogo.networkUrl,
              bg: Colors.white,
              fg: Colors.black87,
              side: logoSide,
            ),
          ],
        ),
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
    required bool heated,
    required double stateSize,
    required double scoreSize,
    required String homeName,
    required String awayName,
    String? homeAbbrev,
    String? awayAbbrev,
    bool draw = false,
    Color? homeBg,
    Color? awayBg,
    Color? homeFg,
    Color? awayFg,
  }) {
    return _cell(
      color: Colors.white,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite && constraints.maxHeight > 0 ? constraints.maxHeight : _minTeamRowH;
        return _scoreWithLogos(
          height: maxH,
          state: displayBoardState(state),
          score: score,
          heated: heated,
          stateSize: stateSize,
          scoreSize: scoreSize,
          homeName: homeName,
          awayName: awayName,
          homeAbbrev: homeAbbrev,
          awayAbbrev: awayAbbrev,
          draw: draw,
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

  Widget _teamNameCell({
    required String name,
    required String milestone,
    required double size,
    required Color? color,
    required Color textColor,
    String? resultBadge,
    bool right = true,
  }) {
    return _cell(
      color: color,
      right: right,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (resultBadge != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: SizedBox(
                height: 22,
                child: Image.asset(
                  resultBadge,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          Flexible(
            child: OneLineShrinkText(
              name,
              baseSize: size,
              minSize: 9,
              color: textColor,
              weight: FontWeight.bold,
              align: TextAlign.center,
            ),
          ),
          if (milestone.isNotEmpty)
            Center(
              child: IntrinsicWidth(
                child: BlinkBg(
                  base: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(2)),
                  color: const Color(0xFFFFF176),
                  radius: 2,
                  duration: const Duration(milliseconds: 700),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    child: Text(
                      milestone,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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

  double _roleHeaderWidth(double labelSize, BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final textW = [
      _textWidth('投手', labelSize, weight: FontWeight.bold, textScaler: scaler),
      _textWidth('打者', labelSize, weight: FontWeight.bold, textScaler: scaler),
      _textWidth('守備', labelSize, weight: FontWeight.bold, textScaler: scaler),
    ].reduce(math.max);
    // _textCell の左右 padding 4px に、文字際の軽い余白を足す。
    return (textW + 10).clamp(26.0, 44.0);
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
      var w = _textWidth(_compactPlayerName(player.name), fontSize, weight: FontWeight.bold, textScaler: scaler) + 8;
      if (_isSeasonStatLeader(player.name)) w += fontSize;
      if (_showJapanFlag(player.name)) w += fontSize;
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
    bool notableBatting = false,
    bool home = false,
  }) {
    final nameSize = size < _minPlayerNameSize ? _minPlayerNameSize : size;
    final statSize = (nameSize * 0.92).clamp(_minPlayerStatSize, 12.0);
    final rowH = _playerRowH;
    final badgeWidth = (nameSize + 2).clamp(9.0, 16.0);
    const roleMarks = {'先', '中', '抑'};

    // 投手(先/中/抑+勝負)と打者で成績ブロックの左端を揃える。
    final leadingBadgesW = _statLeadWidth(badgeWidth);

    Widget pitcherBadges(_PlayerLine pitcher) {
      if (notableBatting) {
        final hasHr = pitcher.mark == 'HR';
        final pos = pitcher.pos.trim();
        return SizedBox(
          width: leadingBadgesW - 0.5,
          child: Row(
            children: [
              SizedBox(
                width: badgeWidth,
                child: hasHr ? _resultBadge('HR', nameSize) : const SizedBox(),
              ),
              SizedBox(
                width: badgeWidth,
                child: pos.isEmpty ? const SizedBox() : _lineupMark(pos, nameSize),
              ),
            ],
          ),
        );
      }
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
              const nameStatGap = 2.0;

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

                final body = Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final pitcher in pitchers)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              centerBadges(pitcher),
                              _nameBox(
                                pitcher,
                                baseSize: nameSize,
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
                          if (_seasonDisplayLines(pitcher.stat, pitcher.name).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: _seasonGap),
                              child: _seasonStatTable(pitcher.stat, pitcher.predict, statSize, pitcherName: pitcher.name),
                            ),
                        ],
                      ),
                  ],
                );

                return SizedBox(
                  width: cellW,
                  height: maxH.isFinite ? maxH : null,
                  child: ClipRect(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      physics: const ClampingScrollPhysics(),
                      child: IntrinsicWidth(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: cellW, minHeight: maxH.isFinite ? maxH : 0),
                          child: Align(alignment: Alignment.center, child: body),
                        ),
                      ),
                    ),
                  ),
                );
              }

              final reservedNameW = nameColW > 0 ? nameColW : _nameColumnWidth(pitchers, nameSize, context);
              final leadingW = leadingBadgesW;
              // 名前幅は成績のために削らない。セル自体が名前より狭いときだけクリップする。
              final maxNameBox = math.max(0.0, cellW - leadingW);
              final hasAnyStats = pitchers.any((p) => p.stat.isNotEmpty || p.chips.isNotEmpty || p.predict.isNotEmpty || p.achieve.isNotEmpty || _orderedPlays(p.plays, includeOuts: notableBatting, notableBatting: notableBatting, rbi: p.rbi).isNotEmpty);
              // _nameColumnWidth の +8 のうち、字形と左右 padding を超える余裕。
              final glyphBoxW = math.max(0.0, reservedNameW - 4);
              var nameBoxW = math.min(reservedNameW, maxNameBox);
              if (hasAnyStats && maxNameBox - nameBoxW <= 0 && glyphBoxW < maxNameBox) {
                nameBoxW = glyphBoxW;
              }
              final restW = math.max(0.0, cellW - leadingW - nameBoxW);
              final gapW = hasAnyStats && restW > nameStatGap ? nameStatGap : 0.0;
              var statsViewportW = hasAnyStats ? math.max(0.0, restW - gapW) : 0.0;
              if (hasAnyStats) {
                const minStatsW = 72.0;
                if (statsViewportW < minStatsW && cellW > leadingW + 48) {
                  nameBoxW = math.max(36.0, cellW - leadingW - nameStatGap - minStatsW);
                  statsViewportW = math.max(0.0, cellW - leadingW - nameBoxW - nameStatGap);
                }
              }
              final scrollWholeRow = hasAnyStats && statsViewportW < 16;

              Widget statLine(_PlayerLine pitcher) {
                final achievements = _visibleAchievements(pitcher.achieve);
                final chipParts = pitcher.chips.split(' ').where((part) => part.isNotEmpty);
                final metrics = chipParts.where((part) => !_isPitchCount(part) && !_isVeloChip(part));
                final pitchCounts = chipParts.where(_isPitchCount);
                final velos = chipParts.where(_isVeloChip);
                final playParts = _orderedPlays(pitcher.plays, includeOuts: notableBatting, notableBatting: notableBatting, rbi: pitcher.rbi);
                final extraAt = _extraRbiIndex(playParts, pitcher.rbi);
                final row = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final part in metrics)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: _metricChip(part, statSize, textScaler: scaler),
                      ),
                    for (var i = 0; i < playParts.length; i++)
                      _playChip(
                        playParts[i],
                        statSize,
                        notableBatting: notableBatting,
                        rbiOverride: extraAt == i ? pitcher.rbi : -1,
                        pinchOverride: notableBatting ? false : _isPinchRole(pitcher.role),
                      ),
                    if (notableBatting && pitcher.pinchNames.isNotEmpty) _pinchCaptionsRow(pitcher.pinchNames, statSize),
                    if (!notableBatting && _isPinchRole(pitcher.role)) _pinchCaption(pitcher, statSize),
                    if (pitcher.stat.isNotEmpty) ...[
                      if (pitcher.plays.isNotEmpty || pitcher.chips.isNotEmpty) const SizedBox(width: 4),
                      _pitchStat(pitcher.stat, statSize, pitcher.tone, textScaler: scaler),
                    ],
                    for (final part in pitchCounts)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: _metricChip(part, statSize, textScaler: scaler),
                      ),
                    for (final part in velos)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: _metricChip(part, statSize, textScaler: scaler),
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
                    if (notableBatting && _isFivePlateOuts(pitcher.plays)) _fiveTakoChip(statSize),
                  ],
                );
                return _blinkLiveBatterStats(
                  row,
                  live: notableBatting && _isLiveBatter(pitcher.name, home: home),
                  statSize: statSize,
                );
              }

              Widget nameCluster(_PlayerLine pitcher, {required double nameW, bool scaleName = true}) {
                final nameBox = _nameBox(
                  pitcher,
                  baseSize: nameSize,
                  alignLeft: true,
                  showAce: _isAcePitcher(
                    pitcher.name,
                    role: pitcher.role,
                    chips: pitcher.chips,
                    stat: pitcher.stat,
                  ),
                );
                return Row(
                  mainAxisSize: MainAxisSize.min,
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
                      width: nameW,
                      child: scaleName ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: nameBox) : Align(alignment: Alignment.centerLeft, child: nameBox),
                    ),
                  ],
                );
              }

              if (scrollWholeRow) {
                return SizedBox(
                  width: cellW,
                  height: maxH.isFinite ? maxH : null,
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  nameCluster(pitcher, nameW: reservedNameW, scaleName: false),
                                  if (hasAnyStats) SizedBox(width: nameStatGap),
                                  if (hasAnyStats) statLine(pitcher),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
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
                                child: nameCluster(pitcher, nameW: nameBoxW),
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

  String _stripInningPrefix(String label) {
    return label.replaceFirst(RegExp(r'^\d+回[表裏]'), '');
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
    if (kind == 'fc' || label.contains('野選')) return const Color(0xFF9E9E9E);
    if (label.contains('邪') || label.contains('ポップ')) return const Color(0xFF1E88E5);
    if (label.contains('ゴロ') || label.contains('フライ') || label.contains('ライナー')) return const Color(0xFF1E88E5);
    return switch (kind) {
      'hr' || 'cycle' || 'cyclemis' || 'multihit' || 'allhit' || 'allreach' || 'perfect' || 'nohit' || 'maddux' || 'shutout' || 'cg' => const Color(0xFFDC143C),
      'timely' || 'hqs' => const Color(0xFFFF5722),
      'triple' || 'double' || 'extra' || 'qs' => const Color(0xFFFFB300),
      'single' => const Color(0xFFFFEB3B),
      'walk' => const Color(0xFF43A047),
      'dead' => label.contains('死球') ? const Color(0xFFE53935) : const Color(0xFF78909C),
      'error' => const Color(0xFF78909C),
      'sac' || 'sacfly' || 'squeeze' || 'sacbunt' => const Color(0xFF8E24AA),
      'k10' => const Color(0xFFDC143C),
      'steal' => const Color(0xFFC6FF00),
      'stealout' => const Color(0xFF757575),
      _ => const Color(0xFFEEEEEE),
    };
  }

  String _playText(String encoded) {
    final bar = encoded.lastIndexOf('|');
    return (bar < 0 ? encoded : encoded.substring(0, bar)).trim();
  }

  String _playKindRaw(String encoded) {
    final bar = encoded.lastIndexOf('|');
    return bar < 0 ? '' : encoded.substring(bar + 1).trim();
  }

  String _playKind(String encoded) {
    return _playKindRaw(encoded).split('/').first;
  }

  Set<String> _playFlags(String encoded) {
    final raw = _playKindRaw(encoded);
    if (raw.isEmpty) return const {};
    return raw.split('/').skip(1).where((part) => part.isNotEmpty).toSet();
  }

  int _nonBattingRunsFromFlags(Set<String> flags) {
    if (flags.contains('run')) return 1;
    for (final flag in flags) {
      final match = RegExp(r'^run(\d+)$').firstMatch(flag);
      if (match != null) return int.parse(match.group(1)!);
    }
    return 0;
  }

  String _withPlayFlag(String encoded, String flag) {
    if (_playFlags(encoded).contains(flag)) return encoded;
    final bar = encoded.lastIndexOf('|');
    if (bar < 0) return '$encoded|$flag';
    return '$encoded/$flag';
  }

  /// 打席が5つで、すべて凡退（振逃を除くアウト）のとき true。
  bool _isFivePlateOuts(String plays) {
    final appearances = <String>[];
    for (final part in plays.split(' ')) {
      if (part.isEmpty) continue;
      final kind = _playKind(part);
      if (kind == 'steal' || kind == 'stealout') continue;
      appearances.add(part);
    }
    if (appearances.length != 5) return false;
    return appearances.every((part) {
      if (_playKind(part) != 'out') return false;
      return !_playText(part).contains('振逃');
    });
  }

  Widget _fiveTakoChip(double fontSize) {
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Container(
        key: const ValueKey('five-tako'),
        height: _playChipH,
        padding: const EdgeInsets.fromLTRB(3, 0, 3, 0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          '5タコ',
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFE53935),
            fontSize: _playChipSize(fontSize),
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ),
    );
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
      'fc' || 'out' => 12,
      _ => 50,
    };
  }

  List<String> _orderedPlays(String raw, {bool includeOuts = false, bool notableBatting = false, int rbi = 0}) {
    final parts = raw.split(' ').where((part) {
      if (part.isEmpty) return false;
      if (_playKind(part) == 'out') return includeOuts;
      return _playRank(part) >= 0;
    }).toList();
    final attached = _attachStealFlags(parts);
    if (!notableBatting) return attached;
    final notable = attached.where((part) => _isNotableBatterStatPlay(part, rbi: rbi)).toList();
    final extraAt = _extraRbiIndex(attached, rbi);
    if (extraAt >= 0) {
      final extra = attached[extraAt];
      if (!notable.contains(extra)) notable.add(extra);
    }
    return notable;
  }

  int _rbiOfEncoded(String encoded) {
    final kind = _playKind(encoded);
    if (kind == 'error') return 0;
    final flags = _playFlags(encoded);
    for (final flag in flags) {
      if (flag == 'rbi') return 1;
      final match = RegExp(r'^rbi(\d+)$').firstMatch(flag);
      if (match != null) return int.parse(match.group(1)!);
    }
    return _rbiOnPlay(_playBody(_playLabel(_playText(encoded), kind)).body, kind);
  }

  int _extraRbiIndex(List<String> parts, int rbi) {
    if (rbi <= 0) return -1;
    final sum = parts.fold<int>(0, (a, part) => a + _rbiOfEncoded(part));
    if (sum > 0) return -1;
    return parts.lastIndexWhere((part) {
      final kind = _playKind(part);
      return kind != 'steal' && kind != 'stealout' && kind != 'error' && kind != 'fc';
    });
  }

  List<String> _attachStealFlags(List<String> parts) {
    final out = <String>[];
    for (final part in parts) {
      final kind = _playKind(part);
      if ((kind == 'steal' || kind == 'stealout') && out.isNotEmpty) {
        out[out.length - 1] = _withPlayFlag(out.last, kind);
        continue;
      }
      out.add(part);
    }
    return out;
  }

  String _playLabel(String label, String kind) {
    if (kind == 'hr' || kind == 'timely') return label;
    return label.replaceFirst('代打', '');
  }

  Widget _pinchCaption(_PlayerLine player, double fontSize) {
    return _pinchCaptionChip(
      role: player.role,
      name: player.name,
      fontSize: fontSize,
      colorIndex: 0,
      colon: true,
    );
  }

  Color _pitchToneColor(String tone, {String label = ''}) {
    final runsChip = label.contains('回') && (label.contains('失点') || label.contains('無失点'));
    return switch (tone) {
      'alert' => Colors.black,
      'crimson' => const Color(0xFFDC143C),
      'rorange' => const Color(0xFFFF5722),
      'yorange' => runsChip ? _markYellowOrange : const Color(0xFF78909C),
      'yellow' || 'green' || 'blue' || 'gray' || 'dgray' => const Color(0xFF78909C),
      _ => const Color(0xFFEEEEEE),
    };
  }

  Widget _metricChip(String encoded, double fontSize, {TextScaler textScaler = TextScaler.noScaling}) {
    final bar = encoded.lastIndexOf('|');
    final label = _chipDisplayLabel((bar < 0 ? encoded : encoded.substring(0, bar)).trim());
    final toneRaw = bar < 0 ? '' : encoded.substring(bar + 1).trim();
    final flags = toneRaw.split('/').where((part) => part.isNotEmpty).toList();
    final tone = flags.firstWhere((flag) => flag != 'blink', orElse: () => '');
    final blink = flags.contains('blink') || _isVeloChip(encoded);
    if (label.isEmpty) return const SizedBox.shrink();
    final chip = _pitchStat(label, fontSize, tone, textScaler: textScaler, paintBackground: !blink);
    if (!blink) return chip;
    final bg = _pitchToneColor(tone, label: label);
    return BlinkBg(
      base: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(2)),
      color: const Color(0xFFFFF176),
      radius: 2,
      duration: const Duration(milliseconds: 700),
      child: chip,
    );
  }

  String _chipDisplayLabel(String label) {
    final walks = RegExp(r'^(?:四死球)?(\d+)(?:BB|四死)?$').firstMatch(label);
    if (walks != null && (label.contains('BB') || label.contains('四死'))) {
      return '${walks.group(1)}四死';
    }
    final strikeouts = RegExp(r'^(\d+)奪三振$').firstMatch(label);
    if (strikeouts != null) return '${strikeouts.group(1)}K';
    return label;
  }

  String? _pitchStatWidthTemplate(String label) {
    if (RegExp(r'^\d+(?:\.\d+)?回(?:無|\d+)失点$').hasMatch(label)) return '0.1回無失点';
    if (RegExp(r'^被安打\d+$').hasMatch(label)) return '被安打10';
    if (RegExp(r'^\d+(?:BB|四死)$').hasMatch(label)) return '12四死';
    if (RegExp(r'^\d+K$').hasMatch(label)) return '12K';
    if (RegExp(r'^\d+km$').hasMatch(label)) return '160km';
    if (RegExp(r'^\d+mph$').hasMatch(label)) return '100mph';
    return null;
  }

  Widget _pitchStat(String text, double fontSize, String tone, {TextScaler textScaler = TextScaler.noScaling, bool paintBackground = true}) {
    final bg = tone.isEmpty ? null : _pitchToneColor(tone, label: text);
    final ink = tone == 'alert' ? Colors.red : (tone.isEmpty || bg == null || bg.computeLuminance() > 0.55 ? Colors.black87 : Colors.white);
    final weight = tone.isEmpty ? FontWeight.normal : FontWeight.w600;
    final style = TextStyle(
      fontSize: fontSize,
      color: ink,
      fontWeight: weight,
      height: 1.0,
    );
    final template = _pitchStatWidthTemplate(text);
    final minTextW = template == null ? null : _textWidth(template, fontSize, weight: weight, textScaler: textScaler);
    final label = Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.center,
      style: style,
    );
    final child = minTextW == null
        ? label
        : SizedBox(
            width: minTextW,
            child: FittedBox(fit: BoxFit.scaleDown, child: label),
          );
    if (!paintBackground) {
      return Container(
        height: 14,
        width: minTextW == null ? null : minTextW + 6,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        child: child,
      );
    }
    if (tone.isEmpty || bg == null) return child;
    return Container(
      height: 14,
      width: minTextW == null ? null : minTextW + 6,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
      ),
      child: child,
    );
  }

  ({String body, String direction}) _playBody(String label) {
    final marked = RegExp(r'\^([左中右遊一二三投捕])$').firstMatch(label);
    if (marked == null) return (body: label, direction: '');
    return (body: label.substring(0, marked.start), direction: marked.group(1)!);
  }

  Color _inkOn(Color bg) => bg.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;

  String _fullwidthHitDigits(String label) {
    return label.replaceAllMapped(RegExp(r'([左中右遊一二三投捕])([23])(?![ラン点号回])'), (match) {
      return '${match.group(1)}${match.group(2) == '2' ? '２' : '３'}';
    });
  }

  String _insertDirection(String body, String direction, String kind) {
    if (direction.isEmpty || body.contains(direction)) return body;
    if (kind == 'hr') {
      final at = body.indexOf('ホームラン');
      if (at >= 0) return '${body.substring(0, at)}$direction${body.substring(at)}';
    }
    if (kind == 'timely') {
      final at = body.indexOf('タイムリー');
      if (at >= 0) return '${body.substring(0, at)}$direction${body.substring(at)}';
    }
    return '$direction$body';
  }

  String _omitDirection(String body, String kind) {
    if (kind == 'hr') {
      return body.replaceFirst(RegExp(r'[左中右遊一二三投捕](?=ホームラン)'), '');
    }
    if (kind == 'timely') {
      return body.replaceFirst(RegExp(r'[左中右遊一二三投捕](?=タイムリー)'), '');
    }
    return body;
  }

  int _rbiOnPlay(String label, String kind) {
    if (kind == 'hr') {
      if (label.contains('満塁')) return 4;
      if (label.contains('3ラン') || label.contains('３ラン')) return 3;
      if (label.contains('2ラン') || label.contains('２ラン')) return 2;
      return 1;
    }
    final points = RegExp(r'(\d+)点').firstMatch(label);
    if (points != null) return int.parse(points.group(1)!);
    final rbiWord = RegExp(r'(\d+)打点').firstMatch(label);
    if (rbiWord != null) return int.parse(rbiWord.group(1)!);
    if (kind == 'timely' || label.contains('タイムリー')) return 1;
    if (kind == 'sacfly' || label.contains('犠飛')) return 1;
    return 0;
  }

  Widget _cornerBadge(String text, {required Color bg, required Color fg, Key? key}) {
    return Container(
      key: key,
      constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(color: fg, fontSize: 7, fontWeight: FontWeight.bold, height: 1),
      ),
    );
  }

  String _compactPlay(String label, String kind, String direction) {
    var stripped = label.replaceAll(RegExp(r'先制|同点|逆転|勝ち越し|サヨナラ|決勝'), '');
    var dir = direction;
    if (dir.isEmpty) {
      final lead = RegExp(r'[左中右遊一二三投捕]').firstMatch(stripped);
      if (lead != null) dir = lead.group(0)!;
    }
    if (kind == 'hr') return dir.isEmpty ? '本' : '$dir本';
    if (kind == 'timely') {
      final hit = stripped.contains('スリーベース')
          ? '３'
          : stripped.contains('ツーベース')
              ? '２'
              : '安';
      return dir.isEmpty ? hit : '$dir$hit';
    }
    stripped = stripped.replaceAll('ヒット', '安').replaceAll('タイムリー', '安');
    var result = _fullwidthHitDigits(stripped.replaceAll('打撃妨害', '打妨').replaceAll('野選', '選').replaceAll('邪飛', '邪').replaceAll('ポップ', '邪').replaceAll('ゴロ', 'ゴ').replaceAll('フライ', '飛').replaceAll('ライナー', '直').replaceAll('併殺', '併'));
    if (dir.isNotEmpty && !result.contains(dir)) {
      result = '$dir$result';
    }
    return result;
  }

  // 中継ぎ/ホールド=黄っぽいオレンジ、抑え/セーブ=赤っぽいオレンジ、外野=黄緑。
  static const _markYellowOrange = Color(0xFFFFB300);
  static const _markRedOrange = Color(0xFFFF5722);
  static const _markOutfield = Color(0xFFC6FF00);
  static const _pinchMarkColors = [
    Color(0xFF5C6BC0),
    Color(0xFF3F51B5),
    Color(0xFF283593),
    Color(0xFF1A237E),
  ];

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
    final ink = _inkOn(bg);
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

  Widget _playChip(String encoded, double fontSize, {bool blink = false, bool compact = false, bool notableBatting = false, int rbiOverride = -1, bool pinchOverride = false}) {
    final bar = encoded.lastIndexOf('|');
    final label = (bar < 0 ? encoded : encoded.substring(0, bar)).trim();
    final kind = _playKind(encoded);
    final flags = _playFlags(encoded);
    if (label.isEmpty) return const SizedBox.shrink();
    if (kind == 'steal' || kind == 'stealout') {
      final safe = kind == 'steal';
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: SizedBox(
          height: 14,
          child: Align(
            alignment: Alignment.center,
            child: _cornerBadge(
              '盗',
              key: ValueKey(safe ? 'steal-badge' : 'stealout-badge'),
              bg: safe ? _markOutfield : const Color(0xFF757575),
              fg: safe ? Colors.black87 : Colors.white,
            ),
          ),
        ),
      );
    }
    final rawLabel = _stripInningPrefix(_playLabel(label, kind));
    final parsed = _playBody(kind == 'hr' ? _homerNumberFirst(rawLabel) : rawLabel);
    final strippedBody = parsed.body.replaceAll('ポップ', '邪飛');
    var shown = compact
        ? _compactPlay(parsed.body, kind, parsed.direction)
        : notableBatting
            ? (kind == 'hr' || kind == 'timely')
                ? _omitDirection(strippedBody, kind)
                : _compactPlay(parsed.body, kind, parsed.direction)
            : _insertDirection(strippedBody, parsed.direction, kind);
    shown = _fullwidthHitDigits(shown).replaceAll(RegExp(r'(?<!\d)1点'), '');
    final hbp = kind == 'dead' && parsed.body.contains('死球');
    final bg = _playColor(kind, parsed.body);
    final ink = hbp ? Colors.black : (parsed.body.contains('併殺') ? const Color(0xFFE53935) : _inkOn(bg));
    final chipSize = _playChipSize(fontSize);
    final rbi = kind == 'error' ? 0 : (rbiOverride >= 0 ? rbiOverride : _rbiOfEncoded(encoded));
    final steal = flags.contains('steal');
    final stealOut = flags.contains('stealout');
    final pinchIndex = _pinchFlagIndex(flags, pinchOverride: pinchOverride);
    final nonBattingRuns = _nonBattingRunsFromFlags(flags);
    final marks = <({String text, Color bg, Color fg, Key key})>[
      if (rbi > 0) (text: '$rbi', bg: const Color(0xFFE53935), fg: Colors.white, key: ValueKey('rbi-badge-$rbi')),
      if (steal || stealOut)
        (
          text: '盗',
          bg: steal ? _markOutfield : const Color(0xFF757575),
          fg: steal ? Colors.black87 : Colors.white,
          key: ValueKey(steal ? 'steal-badge' : 'stealout-badge'),
        ),
      if (pinchIndex != null)
        (
          text: '代',
          bg: _pinchMarkColor(pinchIndex),
          fg: Colors.white,
          key: ValueKey(pinchIndex == 0 ? 'pinch-badge' : 'pinch-badge-$pinchIndex'),
        ),
    ];
    final text = Text(
      shown,
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: ink,
        fontSize: chipSize,
        fontWeight: FontWeight.w600,
        height: 1.0,
      ),
    );
    Widget chip;
    if (!blink) {
      chip = Container(
        height: 14,
        padding: const EdgeInsets.fromLTRB(3, 0, 3, 0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(2),
        ),
        child: text,
      );
    } else {
      chip = BlinkBg(
        base: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(2),
        ),
        color: const Color(0xFFFFF176),
        radius: 2,
        duration: const Duration(milliseconds: 700),
        child: Container(
          height: 14,
          padding: const EdgeInsets.fromLTRB(3, 0, 3, 0),
          alignment: Alignment.center,
          child: text,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          chip,
          if (nonBattingRuns > 0)
            Positioned(
              top: -3,
              left: -3,
              child: _cornerBadge(
                '$nonBattingRuns',
                key: ValueKey('run-badge-$nonBattingRuns'),
                bg: const Color(0xFF1E88E5),
                fg: Colors.white,
              ),
            ),
          for (var i = 0; i < marks.length; i++)
            Positioned(
              top: -3,
              right: -3 + (marks.length - 1 - i) * 7,
              child: _cornerBadge(marks[i].text, key: marks[i].key, bg: marks[i].bg, fg: marks[i].fg),
            ),
        ],
      ),
    );
  }

  Widget _predictBadge(String encoded, double fontSize) {
    final bar = encoded.indexOf('|');
    final label = (bar < 0 ? encoded : encoded.substring(0, bar)).trim();
    final colorName = bar < 0 ? '' : encoded.substring(bar + 1).trim();
    final height = (fontSize + 3).clamp(11.0, 15.0);
    final bg = parseColorName(colorName, const Color(0xFF37474F));
    final ink = _inkOn(bg);
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
    final ink = _inkOn(color);
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
            style: TextStyle(
              color: ink,
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
      final state = _text('state');
      final started = gameHasStarted(game) && !gameIsPregameState(state);
      // 試合前は投手欄を横並びのままにする。狭い画面では試合カード自体を1列にする。
      final stackedTeams = MediaQuery.sizeOf(context).width < stackedTeamsMaxWidth && started;
      final natural = intrinsicHeight(stackedTeams: stackedTeams);
      final viewport = constraints.maxHeight.isFinite ? constraints.maxHeight : natural;
      final layoutH = statsLayoutHeight > 0 ? statsLayoutHeight : natural;
      final height = layoutH;
      final showStats = statsExpanded || statsReveal > 0.01;
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
      final heated = isHeatedGame(state, scoreHome, scoreAway);
      final outcome = finishedGameOutcome(state, scoreHome, scoreAway);
      final header = [
        if (_text('time_game').isNotEmpty) _text('time_game'),
        if (_text('name_stadium').isNotEmpty) _text('name_stadium'),
      ].join(' ');
      final showUserPredictions = ShowUserPredictions.of(context);
      final homePitchers = _players(home: true, pitcher: true, showUserPredictions: showUserPredictions);
      final awayPitchers = _players(home: false, pitcher: true, showUserPredictions: showUserPredictions);
      final homeBatters = allBatters ? const <_PlayerLine>[] : _notableBatters(home: true, showUserPredictions: showUserPredictions);
      final awayBatters = allBatters ? const <_PlayerLine>[] : _notableBatters(home: false, showUserPredictions: showUserPredictions);
      final homeLineup = allBatters ? _lineupSlots(home: true, showUserPredictions: showUserPredictions) : const <_LineupSlot>[];
      final awayLineup = allBatters ? _lineupSlots(home: false, showUserPredictions: showUserPredictions) : const <_LineupSlot>[];
      final homeNameColW = _nameColumnWidth([
        ...homePitchers,
        ...homeBatters,
        ...[
          for (final slot in homeLineup)
            if (slot.players.isNotEmpty) slot.players.first
        ]
      ], detailSize, context);
      final awayNameColW = _nameColumnWidth([
        ...awayPitchers,
        ...awayBatters,
        ...[
          for (final slot in awayLineup)
            if (slot.players.isNotEmpty) slot.players.first
        ]
      ], detailSize, context);
      final pitcherN = math.max(1, math.max(homePitchers.length, awayPitchers.length));
      final batterN = allBatters ? 9 : math.max(1, math.max(homeBatters.length, awayBatters.length));
      final pitcherFlex = math.max(1, (pitcherN * _playerRowH + _seasonBlockH()).round());
      final batterFlex = math.max(1, (batterN * _playerRowH).round());
      final homePitcherFlex = math.max(1, _pitcherBlockH(homePitchers.length).round());
      final awayPitcherFlex = math.max(1, _pitcherBlockH(awayPitchers.length).round());
      final homeBatterFlex = math.max(1, ((allBatters ? 9 : math.max(1, homeBatters.length)) * _playerRowH).round());
      final awayBatterFlex = math.max(1, ((allBatters ? 9 : math.max(1, awayBatters.length)) * _playerRowH).round());
      final defenseFlex = _showDefense ? _defenseRowH.round() : 0;
      final roleHeaderW = _roleHeaderWidth(labelSize, context);
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
        required int defenseFlex,
        required bool bottom,
        required bool home,
        required String teamName,
        required Color? teamBg,
        required Color teamFg,
      }) {
        final showBatters = started;
        final showDefense = _showDefense;
        final showPitchers = pitcherFlex > 0 && _showPitcherStats;
        return Expanded(
          flex: (showPitchers ? pitcherFlex : 0) + (showBatters ? batterFlex : 0) + (showDefense ? defenseFlex : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: stackTeamHeaderW,
                child: verticalTeamHeader(teamName, teamBg, teamFg),
              ),
              SizedBox(
                width: roleHeaderW,
                child: Column(
                  children: [
                    if (showPitchers)
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
                        child: _batterHeader(labelSize, bottom: showDefense ? false : bottom),
                      ),
                    if (showDefense)
                      Expanded(
                        flex: defenseFlex,
                        child: _textCell(
                          '守備',
                          size: labelSize,
                          minSize: 9,
                          color: _labelColor,
                          textColor: Colors.white,
                          weight: FontWeight.bold,
                          bottom: bottom,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    if (showPitchers)
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
                            ? _lineupCell(lineup, color: pale, size: detailSize, right: false, bottom: showDefense ? false : bottom, nameColW: nameColW, home: home)
                            : _pitcherCell(
                                batters,
                                color: pale,
                                size: detailSize,
                                right: false,
                                bottom: showDefense ? false : bottom,
                                nameColW: nameColW,
                                centerNames: !started,
                                notableBatting: true,
                                home: home,
                              ),
                      ),
                    if (showDefense)
                      Expanded(
                        flex: defenseFlex,
                        child: _defenseCell(home: home, pale: pale, bottom: bottom, right: false),
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
              height: _gameHeaderH,
              child: _cell(
                color: homeBg ?? const Color(0xFFF4D03F),
                right: false,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_text('time_game').isNotEmpty)
                          OneLineShrinkText(
                            _text('time_game'),
                            baseSize: headerSize,
                            minSize: 9,
                            color: homeFg,
                            weight: FontWeight.bold,
                            align: TextAlign.left,
                          ),
                        if (_text('path_image_outside').isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Image.asset(
                            _text('path_image_outside'),
                            height: _gameHeaderH - 6,
                            width: _gameHeaderH + 4,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ],
                        if (_text('name_stadium').isNotEmpty) ...[
                          const SizedBox(width: 3),
                          OneLineShrinkText(
                            _text('name_stadium'),
                            baseSize: headerSize,
                            minSize: 9,
                            color: homeFg,
                            weight: FontWeight.bold,
                            align: TextAlign.left,
                          ),
                        ],
                        if (header.isEmpty)
                          OneLineShrinkText(
                            '　',
                            baseSize: headerSize,
                            minSize: 9,
                            color: homeFg,
                            weight: FontWeight.bold,
                            align: TextAlign.left,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: _teamBlockH,
              child: LayoutBuilder(builder: (context, teamConstraints) {
                final rowW = teamConstraints.maxWidth.isFinite ? teamConstraints.maxWidth : 0.0;
                final boardW = _showLineScore ? (rowW * 0.62).clamp(176.0, math.max(176.0, rowW - 80)).toDouble() : math.min(148.0, math.max(0.0, rowW - 96));
                final sideW = math.max(0.0, (rowW - boardW) / 2);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: sideW,
                      child: _teamNameCell(
                        name: _text('name_team_home'),
                        milestone: _text('milestone_home'),
                        size: teamSize,
                        color: homeBg,
                        textColor: homeFg,
                        resultBadge: teamResultBadge(outcome, home: true),
                      ),
                    ),
                    SizedBox(
                      width: boardW,
                      child: _showLineScore
                          ? _scoreBoardCenter(
                              score: score,
                              state: state,
                              heated: heated,
                              scoreSize: scoreSize,
                              stateSize: stateSize,
                              homeBg: homeBg,
                              awayBg: awayBg,
                              homeName: _text('name_team_home'),
                              awayName: _text('name_team_away'),
                              homeAbbrev: _text('name_shortest_home'),
                              awayAbbrev: _text('name_shortest_away'),
                              draw: outcome == FinishedGameOutcome.draw,
                            )
                          : _matchScoreCell(
                              state: state,
                              score: score,
                              heated: heated,
                              stateSize: stateSize,
                              scoreSize: scoreSize,
                              homeName: _text('name_team_home'),
                              awayName: _text('name_team_away'),
                              homeAbbrev: _text('name_shortest_home'),
                              awayAbbrev: _text('name_shortest_away'),
                              draw: outcome == FinishedGameOutcome.draw,
                              homeBg: homeBg,
                              awayBg: awayBg,
                              homeFg: homeFg,
                              awayFg: awayFg,
                            ),
                    ),
                    Expanded(
                      child: _teamNameCell(
                        name: _text('name_team_away'),
                        milestone: _text('milestone_away'),
                        size: teamSize,
                        color: awayBg,
                        textColor: awayFg,
                        resultBadge: teamResultBadge(outcome, home: false),
                        right: false,
                      ),
                    ),
                  ],
                );
              }),
            ),
            if (_hasCollapsibleStats) _playerStatsToggle(),
            if (showStats && _showRosterPicker) _allBattersBar(),
            if (showStats && stackedTeams) ...[
              teamStats(
                pitchers: homePitchers,
                batters: homeBatters,
                lineup: homeLineup,
                pale: homePale,
                nameColW: homeNameColW,
                pitcherFlex: homePitcherFlex,
                batterFlex: homeBatterFlex,
                defenseFlex: defenseFlex,
                bottom: true,
                home: true,
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
                defenseFlex: defenseFlex,
                bottom: false,
                home: false,
                teamName: _text('name_team_away'),
                teamBg: awayBg,
                teamFg: awayFg,
              ),
            ] else if (showStats) ...[
              if (_showPitcherStats)
                Expanded(
                  flex: pitcherFlex,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _pitcherCell(
                          homePitchers,
                          color: homePale,
                          size: detailSize,
                          right: true,
                          nameColW: homeNameColW,
                          centerNames: !started,
                        ),
                      ),
                      SizedBox(
                        width: roleHeaderW,
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
                        child: allBatters
                            ? _lineupCell(homeLineup, color: homePale, size: detailSize, right: true, nameColW: homeNameColW, home: true, bottom: !_showDefense)
                            : _pitcherCell(
                                homeBatters,
                                color: homePale,
                                size: detailSize,
                                right: true,
                                bottom: !_showDefense,
                                nameColW: homeNameColW,
                                centerNames: !started,
                                notableBatting: true,
                                home: true,
                              ),
                      ),
                      SizedBox(
                        width: roleHeaderW,
                        child: _batterHeader(labelSize, bottom: !_showDefense),
                      ),
                      Expanded(
                        child: allBatters
                            ? _lineupCell(awayLineup, color: awayPale, size: detailSize, right: false, nameColW: awayNameColW, home: false, bottom: !_showDefense)
                            : _pitcherCell(
                                awayBatters,
                                color: awayPale,
                                size: detailSize,
                                right: false,
                                bottom: !_showDefense,
                                nameColW: awayNameColW,
                                centerNames: !started,
                                notableBatting: true,
                                home: false,
                              ),
                      ),
                    ],
                  ),
                ),
              if (_showDefense)
                Expanded(
                  flex: defenseFlex,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _defenseCell(home: true, pale: homePale, bottom: false, right: true)),
                      SizedBox(
                        width: roleHeaderW,
                        child: _textCell(
                          '守備',
                          size: labelSize,
                          minSize: 9,
                          color: _labelColor,
                          textColor: Colors.white,
                          weight: FontWeight.bold,
                        ),
                      ),
                      Expanded(child: _defenseCell(home: false, pale: awayPale, bottom: false, right: false)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      );

      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : null;
      final inner = SizedBox(height: layoutH, width: width, child: content);
      final clip = viewport + 0.5 < layoutH;
      Widget card = clip
          ? SizedBox(
              height: viewport,
              width: width,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: layoutH,
                  maxHeight: layoutH,
                  child: inner,
                ),
              ),
            )
          : inner;
      if (state.contains('回')) {
        card = BlinkBorder(
          color: Colors.amber,
          radius: 4,
          width: 3,
          duration: const Duration(milliseconds: 900),
          baseBgColor: Colors.transparent,
          fillUseColor: false,
          child: card,
        );
      }
      final extraBelow = !clip && constraints.maxHeight.isFinite && constraints.maxHeight > layoutH + 0.5;
      if (extraBelow) {
        return Align(alignment: Alignment.topCenter, child: card);
      }
      return card;
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
  bool showCrown = false,
  bool showJapan = false,
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
  if (!showAce && !showCrown && !showJapan) return box;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      box,
      if (showAce) ...[
        const SizedBox(width: 3),
        _aceDiamond(baseSize),
      ],
      if (showJapan) Text('🇯🇵', style: TextStyle(fontSize: baseSize, height: 1)),
      if (showCrown) Text('👑', style: TextStyle(fontSize: baseSize, height: 1)),
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
    final textColor = widget.overrideTextColor ?? (hasColor ? Colors.white : Colors.black87);
    final weight = widget.overrideWeight ?? FontWeight.bold;

    final alignment = widget.alignLeft ? Alignment.centerLeft : Alignment.center;
    final shownName = _compactPlayerName(widget.name);
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
              shownName.isNotEmpty ? shownName : '—',
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
