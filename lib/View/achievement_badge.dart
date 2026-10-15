import 'package:flutter/material.dart';
import '../logic/achievement_priority.dart';

/// Stable designs by achievement: neither the player nor the year changes them.
({Color color, IconData symbol, bool trophy}) achievementBadgeStyle(
    Map<String, dynamic> achievement) {
  final label = '${achievement['label'] ?? ''}'.toLowerCase();
  final kind = achievement['kind'];
  bool has(String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(label);
  if (has('正力松太郎'))
    return (color: Colors.brown.shade800, symbol: Icons.diamond, trophy: true);
  if (has('沢村'))
    return (
      color: Colors.indigo.shade800,
      symbol: Icons.sports_baseball,
      trophy: true
    );
  if (has('cy young|サイ.?ヤング'))
    return (color: Colors.blue.shade800, symbol: Icons.bolt, trophy: true);
  if (has('五輪|金メダル'))
    return (color: Colors.amber.shade700, symbol: Icons.stars, trophy: false);
  if (kind == 'national_team')
    return (color: Colors.red.shade800, symbol: Icons.flag, trophy: false);
  if (kind == 'callup')
    return (
      color: Colors.red.shade400,
      symbol: Icons.person_add,
      trophy: false
    );
  if (kind == 'draft')
    return (
      color: Colors.deepOrange.shade600,
      symbol: Icons.looks_one,
      trophy: false
    );
  if (has('完全試合|ノーヒットノーラン'))
    return (
      color: Colors.blueGrey.shade800,
      symbol: Icons.verified,
      trophy: true
    );
  if (has('三冠|triple crown'))
    return (color: Colors.amber.shade800, symbol: Icons.diamond, trophy: true);
  if (has('50-50|40-40|トリプルスリー'))
    return (color: Colors.deepPurple, symbol: Icons.bolt, trophy: true);
  if (kind == 'record' || has('史上|新記録|最多.*更新'))
    return (
      color: Colors.blueGrey.shade600,
      symbol: Icons.auto_awesome,
      trophy: true
    );
  if (has('wbc|world baseball classic'))
    return (
      color: Colors.red.shade800,
      symbol: Icons.public,
      trophy: kind != 'championship'
    );
  if (has('日本一|日本シリーズ|world series'))
    return (
      color: Colors.amber.shade800,
      symbol: Icons.stars,
      trophy: kind != 'championship'
    );
  if (has('リーグ優勝|champion'))
    return (color: Colors.orange.shade800, symbol: Icons.flag, trophy: false);
  if (has('cs mvp|クライマックス|championship series'))
    return (color: Colors.deepOrange, symbol: Icons.star, trophy: true);
  if (has('月間|of the month'))
    return (
      color: Colors.purple.shade400,
      symbol: Icons.calendar_month,
      trophy: true
    );
  if (has('mvp|最優秀選手|most valuable'))
    return (color: Colors.purple.shade800, symbol: Icons.star, trophy: true);
  if (has('新人|rookie'))
    return (color: Colors.lightGreen.shade700, symbol: Icons.eco, trophy: true);
  if (has('規定打席'))
    return (
      color: Colors.green.shade700,
      symbol: Icons.sports_baseball,
      trophy: false
    );
  if (has('規定投球'))
    return (
      color: Colors.teal.shade700,
      symbol: Icons.sports_baseball,
      trophy: false
    );
  if (has('本塁打|home run|hank aaron|slugger'))
    return (
      color: Colors.red.shade700,
      symbol: Icons.local_fire_department,
      trophy: kind != 'milestone'
    );
  if (has('打点|rbi'))
    return (
      color: Colors.orange.shade800,
      symbol: Icons.adjust,
      trophy: kind != 'milestone'
    );
  if (has('打率|首位打者|安打|hit|batting'))
    return (
      color: Colors.green.shade700,
      symbol: Icons.sports_baseball,
      trophy: kind != 'milestone'
    );
  if (has('盗塁|stolen'))
    return (
      color: Colors.cyan.shade800,
      symbol: Icons.directions_run,
      trophy: kind != 'milestone'
    );
  if (has('防御率|cy young|沢村|earned run'))
    return (color: Colors.indigo, symbol: Icons.shield, trophy: true);
  if (has('奪三振|strikeout|strike out'))
    return (
      color: Colors.blue.shade800,
      symbol: Icons.bolt,
      trophy: kind != 'milestone'
    );
  if (has('セーブ|ホールド|中継|save|relie'))
    return (
      color: Colors.teal.shade700,
      symbol: Icons.lock,
      trophy: kind != 'milestone'
    );
  if (has('勝|wins'))
    return (
      color: Colors.blue.shade700,
      symbol: Icons.flag,
      trophy: kind != 'milestone'
    );
  if (has('glove|守備|ゴールデン.?グラブ'))
    return (color: Colors.amber.shade800, symbol: Icons.shield, trophy: true);
  // Give other named awards a stable accent rather than one identical generic medal.
  var hash = 0;
  for (final code in label.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  const colors = [
    Colors.indigo,
    Colors.brown,
    Colors.teal,
    Colors.deepOrange,
    Colors.purple
  ];
  const symbols = [
    Icons.star,
    Icons.auto_awesome,
    Icons.flag,
    Icons.sports_baseball,
    Icons.diamond
  ];
  return (
    color: colors[hash % colors.length],
    symbol: symbols[(hash ~/ colors.length) % symbols.length],
    trophy: kind == 'title'
  );
}

class AchievementBadge extends StatelessWidget {
  const AchievementBadge({super.key, required this.achievement});
  final Map<String, dynamic> achievement;
  @override
  Widget build(BuildContext context) {
    final style = achievementBadgeStyle(achievement);
    final size = achievementBadgeSize(achievement);
    if (isLeagueMvp(achievement)) {
      return ExcludeSemantics(
          child: SizedBox(
              width: size,
              height: size,
              child: FittedBox(
                  child: Container(
                key: const ValueKey('league-mvp-frame'),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 16 / 152),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(style.color, Colors.white, .92)!,
                      Color.lerp(style.color, Colors.white, .65)!
                    ],
                  ),
                  border: Border.all(color: style.color.withValues(alpha: .45)),
                ),
                child: CustomPaint(
                    painter: const LeagueMvpTrophyPainter(),
                    child: Stack(children: [
                      if (achievement['year'] != null)
                        Positioned(
                          right: size * .04,
                          top: size * .04,
                          child: Text('${achievement['year']}',
                              style: TextStyle(
                                  fontSize: size * .1,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black)),
                        ),
                      if (leagueMvpCaption(achievement) != 'MVP')
                        Positioned(
                          left: size * 8 / 152,
                          top: size * 4 / 152,
                          child: Container(
                            key: const ValueKey('league-mvp-league-circle'),
                            width: size * 30 / 152,
                            height: size * 30 / 152,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                  color: style.color, width: size / 152),
                            ),
                            child: Text(
                              leagueMvpCaption(achievement)
                                  .replaceFirst('MVP', ''),
                              style: TextStyle(
                                color: Colors.black,
                                height: 1,
                                fontSize: size * 22 / 152,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: size * .25,
                        right: size * .25,
                        top: size * .28,
                        height: size * .2,
                        child: Center(
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('MVP',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: size * .125,
                                        fontWeight: FontWeight.w900)))),
                      ),
                    ])),
              ))));
    }
    return ExcludeSemantics(
        child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                    width: size - 2,
                    height: size - 2,
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(size / (style.trophy ? 4 : 2)),
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(style.color, Colors.white, .92)!,
                            Color.lerp(style.color, Colors.white, .65)!
                          ]),
                      border:
                          Border.all(color: style.color.withValues(alpha: .45)),
                    )),
                Icon(
                    style.trophy ? Icons.emoji_events : Icons.workspace_premium,
                    color: style.color,
                    size: size * 27 / 34),
                Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(1),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: Icon(style.symbol,
                          size: size * 13 / 34, color: style.color),
                    )),
                if (achievement['year'] != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: size * .3,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('${achievement['year']}',
                            style: TextStyle(
                                fontSize: size * .27,
                                height: 1,
                                color: Colors.black,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ],
            )));
  }
}

/// A wide black cup keeps the white league caption entirely inside its bowl.
class LeagueMvpTrophyPainter extends CustomPainter {
  const LeagueMvpTrophyPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    final fill = Paint()..color = Colors.black;
    final handles = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = .065;
    canvas.drawPath(
        Path()
          ..moveTo(.26, .2)
          ..lineTo(.1, .2)
          ..lineTo(.1, .31)
          ..quadraticBezierTo(.1, .48, .32, .49),
        handles);
    canvas.drawPath(
        Path()
          ..moveTo(.74, .2)
          ..lineTo(.9, .2)
          ..lineTo(.9, .31)
          ..quadraticBezierTo(.9, .48, .68, .49),
        handles);
    canvas.drawPath(
        Path()
          ..moveTo(.23, .12)
          ..lineTo(.77, .12)
          ..lineTo(.74, .43)
          ..quadraticBezierTo(.72, .64, .5, .65)
          ..quadraticBezierTo(.28, .64, .26, .43)
          ..close(),
        fill);
    canvas.drawRect(const Rect.fromLTWH(.455, .62, .09, .19), fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(.35, .79, .3, .06),
            const Radius.circular(.015)),
        fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(.26, .85, .48, .08),
            const Radius.circular(.025)),
        fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LeagueMvpTrophyPainter oldDelegate) => false;
}
