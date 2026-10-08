import 'package:flutter/material.dart';

import '../logic/mlb_postseason_bracket.dart';
import '../logic/postseason_bracket.dart';
import '../tools/color_parse.dart';
import 'GamesBoard.dart';

const _eliminatedBg = Color(0xFFBDBDBD);

/// OrgConfig と同じ: ア・リーグ＝赤、ナ・リーグ＝紺。
const _alColor = Color(0xFFC8102E);
const _nlColor = Color(0xFF002D72);
const _winLine = Color(0xFFFFD600);

/// NPB 同様、下のチームカードから上へ勝ち上がる配置。
///
/// 現行 MLB 組み合わせ（再シードなし）:
/// - WC: 4vs5 → 勝者は1と DS / 3vs6 → 勝者は2と DS
/// - シード1とシード2を対極に置く（外側＝1、内側＝2）
/// - 左 AL 表示順: 1, 4, 5, 3, 6, 2
/// - 右 NL 表示順（鏡映）: 2, 6, 3, 5, 4, 1
class MlbBracketGeom {
  static const boardW = 980.0;
  static const w = boardW;
  static const h = 540.0;
  static const cardW = 72.0;
  static const cardH = 120.0;
  static const cardTop = 390.0;
  static const wcY = 290.0;
  static const dsY = 210.0;
  static const csY = 130.0;
  static const wsY = 48.0;

  /// AL 表示スロット（左→右）= シード 1,4,5,3,6,2
  static const alXs = <double>[55, 130, 205, 280, 355, 430];

  /// NL 表示スロット（左→右）= シード 2,6,3,5,4,1
  static const nlXs = <double>[550, 625, 700, 775, 850, 925];

  // AL seed → x
  static double get al1 => alXs[0];
  static double get al4 => alXs[1];
  static double get al5 => alXs[2];
  static double get al3 => alXs[3];
  static double get al6 => alXs[4];
  static double get al2 => alXs[5];

  // NL seed → x
  static double get nl2 => nlXs[0];
  static double get nl6 => nlXs[1];
  static double get nl3 => nlXs[2];
  static double get nl5 => nlXs[3];
  static double get nl4 => nlXs[4];
  static double get nl1 => nlXs[5];

  static double get alWc45Mid => (al4 + al5) / 2;
  static double get alWc36Mid => (al3 + al6) / 2;
  static double get alDs1X => (al1 + alWc45Mid) / 2;
  static double get alDs2X => (alWc36Mid + al2) / 2;
  static double get alCsX => (alDs1X + alDs2X) / 2;

  static double get nlWc36Mid => (nl6 + nl3) / 2;
  static double get nlWc45Mid => (nl5 + nl4) / 2;
  static double get nlDs2X => (nl2 + nlWc36Mid) / 2;
  static double get nlDs1X => (nlWc45Mid + nl1) / 2;
  static double get nlCsX => (nlDs2X + nlDs1X) / 2;

  /// 枠をチーム列より狭くし、縦線が枠の「少し横」を通ってから左右辺へ直角に入るようにする。
  static final ws = Rect.fromCenter(center: const Offset(boardW / 2, wsY), width: 200, height: 44);
  static Rect get alCs => Rect.fromCenter(center: Offset(alCsX, csY), width: 120, height: 34);
  static Rect get nlCs => Rect.fromCenter(center: Offset(nlCsX, csY), width: 120, height: 34);
  static Rect get alDs1 => Rect.fromCenter(center: Offset(alDs1X, dsY), width: 88, height: 30);
  static Rect get alDs2 => Rect.fromCenter(center: Offset(alDs2X, dsY), width: 88, height: 30);
  static Rect get nlDs1 => Rect.fromCenter(center: Offset(nlDs1X, dsY), width: 88, height: 30);
  static Rect get nlDs2 => Rect.fromCenter(center: Offset(nlDs2X, dsY), width: 88, height: 30);

  static Rect get alWc45Box => Rect.fromCenter(center: Offset(alWc45Mid, wcY), width: 54, height: 26);
  static Rect get alWc36Box => Rect.fromCenter(center: Offset(alWc36Mid, wcY), width: 54, height: 26);
  static Rect get nlWc45Box => Rect.fromCenter(center: Offset(nlWc45Mid, wcY), width: 54, height: 26);
  static Rect get nlWc36Box => Rect.fromCenter(center: Offset(nlWc36Mid, wcY), width: 54, height: 26);
}

class MlbPostseasonBracket extends StatelessWidget {
  final List<Map<String, dynamic>> standings;
  final List<Map<String, dynamic>> games;

  /// 順位未取得中は「未確定」ではなくグルグルを出す
  final bool loadingTeams;

  const MlbPostseasonBracket({
    super.key,
    required this.standings,
    required this.games,
    this.loadingTeams = false,
  });

  @override
  Widget build(BuildContext context) {
    final board = buildMlbPostseasonBoard(standings: standings, games: games);
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: MlbBracketGeom.w,
        height: MlbBracketGeom.h,
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFFE91E63),
                      Color(0xFFD81B60),
                      Color(0xFFAD1457),
                      Color(0xFF5C6BC0),
                      Color(0xFF283593),
                      Color(0xFF0D1B4A),
                    ],
                    stops: [0.0, 0.18, 0.38, 0.62, 0.82, 1.0],
                  ),
                ),
              ),
            ),
            CustomPaint(
              size: const Size(MlbBracketGeom.boardW, MlbBracketGeom.h),
              painter: _MlbBracketLinePainter(board),
            ),
            _cornerLeagueLogo(
              left: 10,
              asset: 'backend/assets/images/logo_al.png',
            ),
            _cornerLeagueLogo(
              left: MlbBracketGeom.boardW - 10 - 88,
              asset: 'backend/assets/images/logo_nl.png',
            ),
            _stageBox(MlbBracketGeom.ws, 'WORLD SERIES', fontSize: 14, background: const Color(0xFF111111)),
            _stageBox(MlbBracketGeom.alCs, 'ALCS', background: _alColor),
            _stageBox(MlbBracketGeom.nlCs, 'NLCS', background: _nlColor),
            _stageBox(MlbBracketGeom.alDs1, 'ALDS', fontSize: 10, background: _alColor),
            _stageBox(MlbBracketGeom.alDs2, 'ALDS', fontSize: 10, background: _alColor),
            _stageBox(MlbBracketGeom.nlDs1, 'NLDS', fontSize: 10, background: _nlColor),
            _stageBox(MlbBracketGeom.nlDs2, 'NLDS', fontSize: 10, background: _nlColor),
            _stageBox(MlbBracketGeom.alWc45Box, 'ALWC', fontSize: 10, background: _alColor),
            _stageBox(MlbBracketGeom.alWc36Box, 'ALWC', fontSize: 10, background: _alColor),
            _stageBox(MlbBracketGeom.nlWc45Box, 'NLWC', fontSize: 10, background: _nlColor),
            _stageBox(MlbBracketGeom.nlWc36Box, 'NLWC', fontSize: 10, background: _nlColor),
            ..._stars(board),
            // AL: 1,4,5,3,6,2（外側=シード1、内側=シード2）
            _team(MlbBracketGeom.al1, board, board.american[0], mlbBracketLabel('AL', board.american[0]), _alColor),
            _team(MlbBracketGeom.al4, board, board.american[3], mlbBracketLabel('AL', board.american[3]), _alColor),
            _team(MlbBracketGeom.al5, board, board.american[4], mlbBracketLabel('AL', board.american[4]), _alColor),
            _team(MlbBracketGeom.al3, board, board.american[2], mlbBracketLabel('AL', board.american[2]), _alColor),
            _team(MlbBracketGeom.al6, board, board.american[5], mlbBracketLabel('AL', board.american[5]), _alColor),
            _team(MlbBracketGeom.al2, board, board.american[1], mlbBracketLabel('AL', board.american[1]), _alColor),
            // NL: 2,6,3,5,4,1（AL の鏡映。内側=シード2、外側=シード1）
            _team(MlbBracketGeom.nl2, board, board.national[1], mlbBracketLabel('NL', board.national[1]), _nlColor),
            _team(MlbBracketGeom.nl6, board, board.national[5], mlbBracketLabel('NL', board.national[5]), _nlColor),
            _team(MlbBracketGeom.nl3, board, board.national[2], mlbBracketLabel('NL', board.national[2]), _nlColor),
            _team(MlbBracketGeom.nl5, board, board.national[4], mlbBracketLabel('NL', board.national[4]), _nlColor),
            _team(MlbBracketGeom.nl4, board, board.national[3], mlbBracketLabel('NL', board.national[3]), _nlColor),
            _team(MlbBracketGeom.nl1, board, board.national[0], mlbBracketLabel('NL', board.national[0]), _nlColor),
          ],
        ),
      ),
    );
  }

  List<Widget> _stars(MlbPostseasonBoard board) {
    const cardTop = MlbBracketGeom.cardTop;
    final alWc45 = MlbBracketGeom.alWc45Box;
    final alWc36 = MlbBracketGeom.alWc36Box;
    final nlWc45 = MlbBracketGeom.nlWc45Box;
    final nlWc36 = MlbBracketGeom.nlWc36Box;
    final alDs1 = MlbBracketGeom.alDs1;
    final alDs2 = MlbBracketGeom.alDs2;
    final nlDs1 = MlbBracketGeom.nlDs1;
    final nlDs2 = MlbBracketGeom.nlDs2;
    final alCs = MlbBracketGeom.alCs;
    final nlCs = MlbBracketGeom.nlCs;
    final ws = MlbBracketGeom.ws;
    return [
      // AL WC 4-5
      _starsOnLine(MlbBracketGeom.al4, alWc45.center.dy, cardTop, toLeft: true, wins: board.alWc45.winsHigh, slots: 2),
      _starsOnLine(MlbBracketGeom.al5, alWc45.center.dy, cardTop, toLeft: false, wins: board.alWc45.winsLow, slots: 2),
      // AL WC 3-6
      _starsOnLine(MlbBracketGeom.al3, alWc36.center.dy, cardTop, toLeft: true, wins: board.alWc36.winsHigh, slots: 2),
      _starsOnLine(MlbBracketGeom.al6, alWc36.center.dy, cardTop, toLeft: false, wins: board.alWc36.winsLow, slots: 2),
      // AL DS: 外側シード1 / 内側シード2
      _starsOnLine(MlbBracketGeom.al1, alDs1.center.dy, cardTop, toLeft: true, wins: board.alDs1.winsHigh, slots: 3),
      _starsOnLine(MlbBracketGeom.alWc45Mid, alDs1.center.dy, alWc45.top, toLeft: false, wins: board.alDs1.winsLow, slots: 3),
      _starsOnLine(MlbBracketGeom.alWc36Mid, alDs2.center.dy, alWc36.top, toLeft: true, wins: board.alDs2.winsLow, slots: 3),
      _starsOnLine(MlbBracketGeom.al2, alDs2.center.dy, cardTop, toLeft: false, wins: board.alDs2.winsHigh, slots: 3),
      // AL LCS / WS
      _starsOnLine(MlbBracketGeom.alDs1X, alCs.center.dy, alDs1.top, toLeft: true, wins: board.alCs.winsHigh, slots: 4),
      _starsOnLine(MlbBracketGeom.alDs2X, alCs.center.dy, alDs2.top, toLeft: false, wins: board.alCs.winsLow, slots: 4),
      _starsOnLine(MlbBracketGeom.alCsX, ws.center.dy, alCs.top, toLeft: true, wins: board.worldSeries.winsHigh, slots: 4),
      // NL WC
      _starsOnLine(MlbBracketGeom.nl6, nlWc36.center.dy, cardTop, toLeft: true, wins: board.nlWc36.winsLow, slots: 2),
      _starsOnLine(MlbBracketGeom.nl3, nlWc36.center.dy, cardTop, toLeft: false, wins: board.nlWc36.winsHigh, slots: 2),
      _starsOnLine(MlbBracketGeom.nl5, nlWc45.center.dy, cardTop, toLeft: true, wins: board.nlWc45.winsLow, slots: 2),
      _starsOnLine(MlbBracketGeom.nl4, nlWc45.center.dy, cardTop, toLeft: false, wins: board.nlWc45.winsHigh, slots: 2),
      // NL DS: 内側シード2 / 外側シード1
      _starsOnLine(MlbBracketGeom.nl2, nlDs2.center.dy, cardTop, toLeft: true, wins: board.nlDs2.winsHigh, slots: 3),
      _starsOnLine(MlbBracketGeom.nlWc36Mid, nlDs2.center.dy, nlWc36.top, toLeft: false, wins: board.nlDs2.winsLow, slots: 3),
      _starsOnLine(MlbBracketGeom.nlWc45Mid, nlDs1.center.dy, nlWc45.top, toLeft: true, wins: board.nlDs1.winsLow, slots: 3),
      _starsOnLine(MlbBracketGeom.nl1, nlDs1.center.dy, cardTop, toLeft: false, wins: board.nlDs1.winsHigh, slots: 3),
      // NL LCS / WS
      _starsOnLine(MlbBracketGeom.nlDs2X, nlCs.center.dy, nlDs2.top, toLeft: true, wins: board.nlCs.winsLow, slots: 4),
      _starsOnLine(MlbBracketGeom.nlDs1X, nlCs.center.dy, nlDs1.top, toLeft: false, wins: board.nlCs.winsHigh, slots: 4),
      _starsOnLine(MlbBracketGeom.nlCsX, ws.center.dy, nlCs.top, toLeft: false, wins: board.worldSeries.winsLow, slots: 4),
    ];
  }

  /// 左上＝ア・リーグ、右上＝ナ・リーグ。背景透過 PNG。
  Widget _cornerLeagueLogo({required double left, required String asset}) {
    const size = 88.0;
    return Positioned(
      left: left,
      top: 6,
      width: size,
      height: size,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _starsOnLine(double lineX, double y1, double y2, {required bool toLeft, required int wins, required int slots}) {
    final top = y1 < y2 ? y1 : y2;
    final left = toLeft ? lineX - 16 : lineX + 4;
    return Positioned(
      left: left,
      top: top + 4,
      child: Column(
        children: [
          for (var i = 0; i < slots; i++)
            Text(
              i < wins ? '★' : '☆',
              style: TextStyle(
                fontSize: 12,
                height: 1.05,
                color: i < wins ? _winLine : Colors.black87,
              ),
            ),
        ],
      ),
    );
  }

  Widget _stageBox(Rect rect, String label, {double fontSize = 11, Color? background}) {
    if (rect.width <= 0 || rect.height <= 0) return const SizedBox.shrink();
    final colored = background != null;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background ?? Colors.white,
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: colored ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _team(double cx, MlbPostseasonBoard board, BracketTeam team, String rankLabel, Color leagueColor) {
    final unknown = team.name.isEmpty;
    final pending = unknown && loadingTeams;
    final out = !unknown && board.eliminated(team.id);
    final nameBg = out ? _eliminatedBg : (unknown ? Colors.white : (parseColorNameOrNull(team.colorBack) ?? Colors.white));
    final nameFg = out || unknown ? Colors.black87 : (parseColorNameOrNull(team.colorFont) ?? Colors.black87);
    final logoVisual = unknown ? null : teamLogoVisual(team.name, abbrev: team.nameShortest);
    final logoAsset = logoVisual?.asset;
    final logoUrl = logoVisual?.networkUrl;

    Widget logo;
    if (pending) {
      logo = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (unknown) {
      logo = const Text('未確定', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold));
    } else {
      logo = teamLogoImage(asset: logoAsset, networkUrl: logoUrl);
    }
    if (out) {
      logo = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: logo,
      );
    }

    return Positioned(
      left: cx - MlbBracketGeom.cardW / 2,
      top: MlbBracketGeom.cardTop,
      width: MlbBracketGeom.cardW,
      height: MlbBracketGeom.cardH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            children: [
              ColoredBox(
                color: out ? _eliminatedBg : leagueColor,
                child: SizedBox(
                  height: 18,
                  width: double.infinity,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          rankLabel,
                          maxLines: 1,
                          style: TextStyle(
                            color: out ? Colors.black87 : Colors.white,
                            fontSize: rankLabel.length >= 10 ? 7 : (rankLabel.length >= 5 ? 8 : 10),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(padding: const EdgeInsets.all(2), child: logo),
                    if (out) const ColoredBox(color: Color(0x66000000)),
                  ],
                ),
              ),
              ColoredBox(
                color: nameBg,
                child: SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: Center(
                    child: pending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : unknown
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        team.name,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        softWrap: false,
                                        style: TextStyle(
                                          color: nameFg,
                                          fontWeight: FontWeight.bold,
                                          fontSize: team.name.length >= 7 ? 8 : 9,
                                          height: 1.1,
                                        ),
                                      ),
                                      if (team.hasJapanPlayer) const Text(' 🇯🇵', style: TextStyle(fontSize: 10, height: 1)),
                                    ],
                                  ),
                                ),
                              ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MlbBracketLinePainter extends CustomPainter {
  final MlbPostseasonBoard board;

  _MlbBracketLinePainter(this.board);

  @override
  void paint(Canvas canvas, Size size) {
    void stroke(Path path, {required bool win}) {
      canvas.drawPath(
        path,
        Paint()
          ..color = win ? _winLine : Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = win ? 5.0 : 1.6
          ..strokeCap = StrokeCap.square,
      );
    }

    Path v(double x, double y1, double y2) => Path()
      ..moveTo(x, y1)
      ..lineTo(x, y2);
    Path h(double x1, double x2, double y) => Path()
      ..moveTo(x1, y)
      ..lineTo(x2, y);

    /// 枠の少し横まで縦に上げ、直角に曲げて左右辺の中心点へ繋ぐ。
    void toSide(double fromX, double fromY, Rect box, {required bool toLeft, required bool win}) {
      const gap = 10.0;
      final sideX = toLeft ? box.left : box.right;
      final midY = box.center.dy;
      // 縦レールは必ず枠の外側（辺から gap 離す）。チーム x が外側ならそれを優先。
      final railX = toLeft ? (fromX <= sideX - gap ? fromX : sideX - gap) : (fromX >= sideX + gap ? fromX : sideX + gap);
      stroke(v(railX, fromY, midY), win: win);
      stroke(h(railX, sideX, midY), win: win);
    }

    /// 下段枠の上辺付近から上段枠の左右中点へ（同じく枠の横→直角）。
    void upToSide(double fromX, double fromTop, Rect box, {required bool toLeft, required bool win}) {
      const gap = 10.0;
      final sideX = toLeft ? box.left : box.right;
      final midY = box.center.dy;
      final railX = toLeft ? (fromX <= sideX - gap ? fromX : sideX - gap) : (fromX >= sideX + gap ? fromX : sideX + gap);
      stroke(v(railX, fromTop, midY), win: win);
      stroke(h(railX, sideX, midY), win: win);
    }

    const cardTop = MlbBracketGeom.cardTop;
    final al = board.american;
    final nl = board.national;

    final alWc45 = MlbBracketGeom.alWc45Box;
    final alWc36 = MlbBracketGeom.alWc36Box;
    final alDs1 = MlbBracketGeom.alDs1;
    final alDs2 = MlbBracketGeom.alDs2;
    final alCs = MlbBracketGeom.alCs;
    final nlWc45 = MlbBracketGeom.nlWc45Box;
    final nlWc36 = MlbBracketGeom.nlWc36Box;
    final nlDs1 = MlbBracketGeom.nlDs1;
    final nlDs2 = MlbBracketGeom.nlDs2;
    final nlCs = MlbBracketGeom.nlCs;
    final ws = MlbBracketGeom.ws;

    final al4Won = board.alWc45.decided && board.alWc45.winnerId == al[3].id;
    final al5Won = board.alWc45.decided && board.alWc45.winnerId == al[4].id;
    final al3Won = board.alWc36.decided && board.alWc36.winnerId == al[2].id;
    final al6Won = board.alWc36.decided && board.alWc36.winnerId == al[5].id;

    // AL WC 4-5 → 黄線は WC 枠まで
    toSide(MlbBracketGeom.al4, cardTop, alWc45, toLeft: true, win: al4Won);
    toSide(MlbBracketGeom.al5, cardTop, alWc45, toLeft: false, win: al5Won);
    // AL1 bye / WC勝者 → ALDS（WC 決着だけでは黄線にしない）
    toSide(MlbBracketGeom.al1, cardTop, alDs1, toLeft: true, win: board.alDs1.decided && board.alDs1.winnerId == al[0].id);
    upToSide(MlbBracketGeom.alWc45Mid, alWc45.top, alDs1, toLeft: false, win: board.alDs1.decided && board.alDs1.winnerId != al[0].id);
    // ALDS → ALCS
    upToSide(MlbBracketGeom.alDs1X, alDs1.top, alCs, toLeft: true, win: board.alDs1.decided);

    // AL WC 3-6（内側シード2 側）
    toSide(MlbBracketGeom.al3, cardTop, alWc36, toLeft: true, win: al3Won);
    toSide(MlbBracketGeom.al6, cardTop, alWc36, toLeft: false, win: al6Won);
    upToSide(MlbBracketGeom.alWc36Mid, alWc36.top, alDs2, toLeft: true, win: board.alDs2.decided && board.alDs2.winnerId != al[1].id);
    toSide(MlbBracketGeom.al2, cardTop, alDs2, toLeft: false, win: board.alDs2.decided && board.alDs2.winnerId == al[1].id);
    upToSide(MlbBracketGeom.alDs2X, alDs2.top, alCs, toLeft: false, win: board.alDs2.decided);

    // ALCS → WS
    upToSide(MlbBracketGeom.alCsX, alCs.top, ws, toLeft: true, win: board.alCs.decided);

    final nl4Won = board.nlWc45.decided && board.nlWc45.winnerId == nl[3].id;
    final nl5Won = board.nlWc45.decided && board.nlWc45.winnerId == nl[4].id;
    final nl3Won = board.nlWc36.decided && board.nlWc36.winnerId == nl[2].id;
    final nl6Won = board.nlWc36.decided && board.nlWc36.winnerId == nl[5].id;

    // NL WC 3-6 → DS vs 2（黄線は WC 枠まで）
    toSide(MlbBracketGeom.nl6, cardTop, nlWc36, toLeft: true, win: nl6Won);
    toSide(MlbBracketGeom.nl3, cardTop, nlWc36, toLeft: false, win: nl3Won);
    toSide(MlbBracketGeom.nl2, cardTop, nlDs2, toLeft: true, win: board.nlDs2.decided && board.nlDs2.winnerId == nl[1].id);
    upToSide(MlbBracketGeom.nlWc36Mid, nlWc36.top, nlDs2, toLeft: false, win: board.nlDs2.decided && board.nlDs2.winnerId != nl[1].id);
    upToSide(MlbBracketGeom.nlDs2X, nlDs2.top, nlCs, toLeft: true, win: board.nlDs2.decided);

    // NL WC 4-5 → DS vs 1
    toSide(MlbBracketGeom.nl5, cardTop, nlWc45, toLeft: true, win: nl5Won);
    toSide(MlbBracketGeom.nl4, cardTop, nlWc45, toLeft: false, win: nl4Won);
    toSide(MlbBracketGeom.nl1, cardTop, nlDs1, toLeft: false, win: board.nlDs1.decided && board.nlDs1.winnerId == nl[0].id);
    upToSide(MlbBracketGeom.nlWc45Mid, nlWc45.top, nlDs1, toLeft: true, win: board.nlDs1.decided && board.nlDs1.winnerId != nl[0].id);
    upToSide(MlbBracketGeom.nlDs1X, nlDs1.top, nlCs, toLeft: false, win: board.nlDs1.decided);

    // NLCS → WS
    upToSide(MlbBracketGeom.nlCsX, nlCs.top, ws, toLeft: false, win: board.nlCs.decided);
  }

  @override
  bool shouldRepaint(covariant _MlbBracketLinePainter oldDelegate) => oldDelegate.board != board;
}
