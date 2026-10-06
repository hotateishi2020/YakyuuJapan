import 'package:flutter/material.dart';

import '../logic/postseason_bracket.dart';
import '../tools/color_parse.dart';
import 'GamesBoard.dart';

const _eliminatedBg = Color(0xFFBDBDBD);
const _centralLeague = Color(0xFF0E8E2D);
const _pacificLeague = Color(0xFF01B1EA);

class BracketGeom {
  static const boardW = 844.0;
  static const w = boardW;
  static const h = 500.0;
  static const xs = <double>[65, 199, 333, 503, 637, 771];
  static const cardW = 114.0;
  static const cardTop = 328.0;
  static const cardH = 156.0;

  static double get midC => (xs[1] + xs[2]) / 2;
  static double get midP => (xs[3] + xs[4]) / 2;

  static final cs1C = Rect.fromCenter(center: Offset(midC, 276), width: 112, height: 34);
  static final cs1P = Rect.fromCenter(center: Offset(midP, 276), width: 112, height: 34);
  static final finC = Rect.fromCenter(center: Offset((xs[0] + midC) / 2, 176), width: 156, height: 40);
  static final finP = Rect.fromCenter(center: Offset((xs[5] + midP) / 2, 176), width: 156, height: 40);
  static final js = Rect.fromLTRB(xs[0] - 8, 20, xs[5] + 8, 132);
}

class PostseasonBracket extends StatelessWidget {
  final List<Map<String, dynamic>> standings;
  final List<Map<String, dynamic>> games;
  /// 順位未取得中は「未確定」ではなくグルグルを出す
  final bool loadingTeams;

  const PostseasonBracket({
    super.key,
    required this.standings,
    required this.games,
    this.loadingTeams = false,
  });

  @override
  Widget build(BuildContext context) {
    final board = buildPostseasonBoard(standings: standings, games: games);
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: BracketGeom.w,
        height: BracketGeom.h,
        child: DecoratedBox(
          key: const Key('postseason-background'),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF8CFAF7),
                Color(0xFF2BCFAD),
                Color(0xFF14C4C0),
                Color(0xFF5AD8EA),
                Color(0xFF1E6FE0),
                Color(0xFF1F52EB),
              ],
              stops: [0.0, 0.22, 0.38, 0.52, 0.75, 1.0],
            ),
          ),
          child: _bracket(board),
        ),
      ),
    );
  }

  Widget _bracket(PostseasonBoard board) {
    return Stack(
      children: [
            CustomPaint(
              size: const Size(BracketGeom.boardW, BracketGeom.h),
              painter: _BracketLinePainter(board),
            ),
            _innerLogo(BracketGeom.xs[0] + 14, 'backend/assets/images/logo_cs_central.png'),
            _innerLogo(BracketGeom.xs[5] - 14 - 96, 'backend/assets/images/logo_cs_pacific.png'),
            _leagueLogo(central: true),
            _leagueLogo(central: false),
            _japanBox(BracketGeom.js),
            _stars(BracketGeom.js.left + 10, _starTop(BracketGeom.js, board.japan.slots, insetTop: 28), board.japan.winsHigh, board.japan.slots),
            _stars(BracketGeom.js.right - 26, _starTop(BracketGeom.js, board.japan.slots, insetTop: 28), board.japan.winsLow, board.japan.slots),
            _stageBox(BracketGeom.finC, 'CS FINAL STAGE', background: _centralLeague),
            _stageBox(BracketGeom.finP, 'CS FINAL STAGE', background: _pacificLeague),
            _starsOnLine(BracketGeom.xs[0], BracketGeom.finC.center.dy, BracketGeom.cardTop, toLeft: true, wins: board.finalCentral.winsHigh, slots: board.finalCentral.slots),
            _starsOnLine(BracketGeom.midC, BracketGeom.finC.center.dy, BracketGeom.cs1C.top, toLeft: false, wins: board.finalCentral.winsLow, slots: board.finalCentral.slots),
            _starsOnLine(BracketGeom.midP, BracketGeom.finP.center.dy, BracketGeom.cs1P.top, toLeft: true, wins: board.finalPacific.winsLow, slots: board.finalPacific.slots),
            _starsOnLine(BracketGeom.xs[5], BracketGeom.finP.center.dy, BracketGeom.cardTop, toLeft: false, wins: board.finalPacific.winsHigh, slots: board.finalPacific.slots),
            _stageBox(BracketGeom.cs1C, 'CS 1st STAGE', fontSize: 10, background: _centralLeague),
            _stageBox(BracketGeom.cs1P, 'CS 1st STAGE', fontSize: 10, background: _pacificLeague),
            _starsOnLine(BracketGeom.xs[1], BracketGeom.cs1C.center.dy, BracketGeom.cardTop, toLeft: true, wins: board.cs1Central.winsHigh, slots: board.cs1Central.slots),
            _starsOnLine(BracketGeom.xs[2], BracketGeom.cs1C.center.dy, BracketGeom.cardTop, toLeft: false, wins: board.cs1Central.winsLow, slots: board.cs1Central.slots),
            _starsOnLine(BracketGeom.xs[3], BracketGeom.cs1P.center.dy, BracketGeom.cardTop, toLeft: true, wins: board.cs1Pacific.winsLow, slots: board.cs1Pacific.slots),
            _starsOnLine(BracketGeom.xs[4], BracketGeom.cs1P.center.dy, BracketGeom.cardTop, toLeft: false, wins: board.cs1Pacific.winsHigh, slots: board.cs1Pacific.slots),
            _team(0, board, board.central1, 'セ1位'),
            _team(1, board, board.central2, 'セ2位'),
            _team(2, board, board.central3, 'セ3位'),
            _team(3, board, board.pacific3, 'パ3位'),
            _team(4, board, board.pacific2, 'パ2位'),
            _team(5, board, board.pacific1, 'パ1位'),
      ],
    );
  }

  /// セ・パそれぞれの、日本シリーズの下で両リーグのあいだに空いている内側。
  /// アセットは「マーク＋リーグ名」なので、下の文字は切り落としてマークのみ出す。
  Widget _leagueLogo({required bool central}) {
    const width = 110.0;
    const height = 78.0;
    const gap = 22.0;
    // webp 全体のうちマーク部分のおおよそ上側（文字は下部）
    const markFraction = 0.62;
    final center = BracketGeom.boardW / 2;
    final top = BracketGeom.js.bottom + 10;
    return Positioned(
      left: central ? center - gap - width : center + gap,
      top: top,
      width: width,
      height: height,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: markFraction,
          child: Image.asset(
            central ? 'backend/assets/images/k-central.webp' : 'backend/assets/images/k-pacific.webp',
            width: width,
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
          ),
        ),
      ),
    );
  }

  /// 1位の縦線とCS 1stのあいだ、ファイナルの下にある内側の空き。
  Widget _innerLogo(double left, String asset) {
    return Positioned(
      left: left,
      top: BracketGeom.finC.bottom + 8,
      width: 96,
      height: 84,
      child: Image(image: AssetImage(asset), fit: BoxFit.contain),
    );
  }

  Widget _japanBox(Rect rect) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: Column(
            children: [
              ColoredBox(
                color: Color(0xFF004832),
                child: SizedBox(
                  height: 22,
                  width: double.infinity,
                  child: Center(
                    child: Text('日本シリーズ', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, height: 1.05)),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(36, 2, 36, 2),
                  child: Image(image: AssetImage('backend/assets/images/logo_japan_series.png'), fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stageBox(Rect rect, String label, {double fontSize = 11, Color? background}) {
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
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: colored ? Colors.white : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  double _starTop(Rect rect, int slots, {double insetTop = 0}) {
    const pitch = 15.0;
    final used = (slots <= 0 ? 4 : slots) * pitch;
    final bodyTop = rect.top + insetTop;
    final bodyHeight = rect.height - insetTop;
    final top = bodyTop + (bodyHeight - used) / 2;
    return top < bodyTop + 4 ? bodyTop + 4 : top;
  }

  /// 星は勝ち上がり線の上端から、線の脇に詰めて置く。
  Widget _starsOnLine(double lineX, double y1, double y2, {required bool toLeft, required int wins, required int slots}) {
    final count = slots <= 0 ? 0 : slots;
    final top = y1 < y2 ? y1 : y2;
    final left = toLeft ? lineX - 18 : lineX + 4;
    return _stars(left, top, wins, count);
  }

  Widget _stars(double left, double top, int wins, int slots) {
    return Positioned(
      left: left,
      top: top,
      child: Column(
        children: [
          for (var i = 0; i < slots; i++)
            Text(
              i < wins ? '★' : '☆',
              style: TextStyle(
                fontSize: 13,
                height: 1,
                color: i < wins ? const Color(0xFFFFD600) : Colors.black87,
              ),
            ),
        ],
      ),
    );
  }

  Widget _team(int index, PostseasonBoard board, BracketTeam team, String rankLabel) {
    final unknown = team.name.isEmpty;
    final pending = unknown && loadingTeams;
    final out = !unknown && board.eliminated(team.id);
    final nameBg = out ? _eliminatedBg : (unknown ? Colors.white : (parseColorNameOrNull(team.colorBack) ?? Colors.white));
    final nameFg = out || unknown ? Colors.black87 : (parseColorNameOrNull(team.colorFont) ?? Colors.black87);
    final leagueColor = team.leagueId == 2 ? _pacificLeague : _centralLeague;
    final rankTitle = rankLabel.startsWith('パ')
        ? 'パ・リーグ${rankLabel.substring(1)}'
        : rankLabel.startsWith('セ')
            ? 'セ・リーグ${rankLabel.substring(1)}'
            : rankLabel;
    final logoVisual = unknown ? null : teamLogoVisual(team.name);
    final logoAsset = logoVisual?.asset;
    final logoUrl = logoVisual?.networkUrl;
    return Positioned(
      left: BracketGeom.xs[index] - BracketGeom.cardW / 2,
      top: BracketGeom.cardTop,
      width: BracketGeom.cardW,
      height: BracketGeom.cardH,
      child: DecoratedBox(
        key: Key('postseason-team-${team.id}-$rankLabel'),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: out ? _eliminatedBg : leagueColor),
                child: SizedBox(
                  height: 22,
                  width: double.infinity,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        rankTitle,
                        style: TextStyle(
                          color: out ? Colors.black87 : Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: pending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : unknown
                      ? const Text(
                          '未確定',
                          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13),
                        )
                      : logoAsset != null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Image.asset(logoAsset, fit: BoxFit.contain),
                        )
                      : logoUrl != null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Image.network(logoUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              ColoredBox(
                color: nameBg,
                child: SizedBox(
                  height: 40,
                  width: double.infinity,
                  child: Center(
                    child: pending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
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
                                      fontSize: team.name.length >= 7 ? 9 : 11,
                                      height: 1.15,
                                    ),
                                  ),
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

class _BracketLinePainter extends CustomPainter {
  final PostseasonBoard board;

  _BracketLinePainter(this.board);

  @override
  void paint(Canvas canvas, Size size) {
    void stroke(Path path, bool thick) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = thick ? 4.5 : 1.3
          ..strokeCap = StrokeCap.square,
      );
    }

    Path v(double x, double y1, double y2) => Path()..moveTo(x, y1)..lineTo(x, y2);
    Path h(double x1, double x2, double y) => Path()..moveTo(x1, y)..lineTo(x2, y);

    final cardY = BracketGeom.cardTop;

    final c2won = board.cs1Central.winnerId == board.central2.id && board.central2.id > 0;
    final c3won = board.cs1Central.winnerId == board.central3.id && board.central3.id > 0;
    final c1final = board.finalCentral.winnerId == board.central1.id && board.central1.id > 0;
    final cFinalFromCs = board.finalCentral.decided && board.finalCentral.winnerId != board.central1.id && (board.finalCentral.winnerId ?? 0) > 0;
    final p3won = board.cs1Pacific.winnerId == board.pacific3.id && board.pacific3.id > 0;
    final p2won = board.cs1Pacific.winnerId == board.pacific2.id && board.pacific2.id > 0;
    final p1final = board.finalPacific.winnerId == board.pacific1.id && board.pacific1.id > 0;
    final pFinalFromCs = board.finalPacific.decided && board.finalPacific.winnerId != board.pacific1.id && (board.finalPacific.winnerId ?? 0) > 0;

    final c2thick = c2won || cFinalFromCs && board.finalCentral.winnerId == board.central2.id;
    final c3thick = c3won || cFinalFromCs && board.finalCentral.winnerId == board.central3.id;
    stroke(v(BracketGeom.xs[1], cardY, BracketGeom.cs1C.center.dy), c2thick);
    stroke(h(BracketGeom.xs[1], BracketGeom.cs1C.left, BracketGeom.cs1C.center.dy), c2thick);
    stroke(v(BracketGeom.xs[2], cardY, BracketGeom.cs1C.center.dy), c3thick);
    stroke(h(BracketGeom.cs1C.right, BracketGeom.xs[2], BracketGeom.cs1C.center.dy), c3thick);
    stroke(v(BracketGeom.midC, BracketGeom.cs1C.top, BracketGeom.finC.center.dy), board.cs1Central.decided);
    stroke(h(BracketGeom.finC.right, BracketGeom.midC, BracketGeom.finC.center.dy), board.cs1Central.decided);

    stroke(v(BracketGeom.xs[0], cardY, BracketGeom.finC.center.dy), c1final);
    stroke(h(BracketGeom.xs[0], BracketGeom.finC.left, BracketGeom.finC.center.dy), c1final);
    stroke(v(BracketGeom.finC.center.dx, BracketGeom.js.bottom, BracketGeom.finC.top), board.finalCentral.decided);

    final p3thick = p3won || pFinalFromCs && board.finalPacific.winnerId == board.pacific3.id;
    final p2thick = p2won || pFinalFromCs && board.finalPacific.winnerId == board.pacific2.id;
    stroke(v(BracketGeom.xs[3], cardY, BracketGeom.cs1P.center.dy), p3thick);
    stroke(h(BracketGeom.xs[3], BracketGeom.cs1P.left, BracketGeom.cs1P.center.dy), p3thick);
    stroke(v(BracketGeom.xs[4], cardY, BracketGeom.cs1P.center.dy), p2thick);
    stroke(h(BracketGeom.cs1P.right, BracketGeom.xs[4], BracketGeom.cs1P.center.dy), p2thick);
    stroke(v(BracketGeom.midP, BracketGeom.cs1P.top, BracketGeom.finP.center.dy), board.cs1Pacific.decided);
    stroke(h(BracketGeom.midP, BracketGeom.finP.left, BracketGeom.finP.center.dy), board.cs1Pacific.decided);

    stroke(v(BracketGeom.xs[5], cardY, BracketGeom.finP.center.dy), p1final);
    stroke(h(BracketGeom.finP.right, BracketGeom.xs[5], BracketGeom.finP.center.dy), p1final);
    stroke(v(BracketGeom.finP.center.dx, BracketGeom.js.bottom, BracketGeom.finP.top), board.finalPacific.decided);
  }

  @override
  bool shouldRepaint(covariant _BracketLinePainter oldDelegate) => oldDelegate.board != board;
}
