import 'package:flutter/material.dart';
import '../logic/achievement_priority.dart';

/// Stable designs by achievement: neither the player nor the year changes them.
({Color color, IconData symbol, bool trophy}) achievementBadgeStyle(Map<String, dynamic> achievement) {
  final label = '${achievement['label'] ?? ''}'.toLowerCase();
  final kind = achievement['kind'];
  bool has(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(label);
  if (has('正力松太郎')) {
    return (color: Colors.brown.shade800, symbol: Icons.diamond, trophy: true);
  }
  if (has('沢村')) {
    return (color: Colors.indigo.shade800, symbol: Icons.sports_baseball, trophy: true);
  }
  if (has('cy young|サイ.?ヤング')) {
    return (color: Colors.blue.shade800, symbol: Icons.bolt, trophy: true);
  }
  if (has('五輪|金メダル')) {
    return (color: Colors.amber.shade700, symbol: Icons.stars, trophy: false);
  }
  if (kind == 'national_team') {
    return (color: Colors.red.shade800, symbol: Icons.flag, trophy: false);
  }
  if (kind == 'callup') {
    return (color: Colors.red.shade400, symbol: Icons.person_add, trophy: false);
  }
  if (kind == 'draft') {
    return (color: Colors.deepOrange.shade600, symbol: Icons.looks_one, trophy: false);
  }
  if (has('完全試合|ノーヒットノーラン')) {
    return (color: Colors.blueGrey.shade800, symbol: Icons.verified, trophy: true);
  }
  if (has('三冠|triple crown')) {
    return (color: Colors.amber.shade800, symbol: Icons.diamond, trophy: true);
  }
  if (has('50-50|40-40|トリプルスリー')) {
    return (color: Colors.deepPurple, symbol: Icons.bolt, trophy: true);
  }
  if (kind == 'record' || has('史上|新記録|最多.*更新')) {
    return (color: Colors.blueGrey.shade600, symbol: Icons.auto_awesome, trophy: true);
  }
  if (has('wbc|world baseball classic')) {
    return (color: Colors.red.shade800, symbol: Icons.public, trophy: kind != 'championship');
  }
  if (has('日本一|日本シリーズ|world series')) {
    return (color: Colors.amber.shade800, symbol: Icons.stars, trophy: kind != 'championship');
  }
  if (has('リーグ優勝|champion')) {
    return (color: Colors.orange.shade800, symbol: Icons.flag, trophy: false);
  }
  if (has('cs mvp|クライマックス|championship series')) {
    return (color: Colors.deepOrange, symbol: Icons.star, trophy: true);
  }
  if (has('月間|of the month')) {
    return (color: Colors.purple.shade400, symbol: Icons.calendar_month, trophy: true);
  }
  if (has('mvp|最優秀選手|most valuable')) {
    return (color: Colors.purple.shade800, symbol: Icons.star, trophy: true);
  }
  if (has('新人|rookie')) {
    return (color: Colors.lightGreen.shade700, symbol: Icons.eco, trophy: true);
  }
  if (has('規定打席')) {
    return (color: Colors.green.shade700, symbol: Icons.sports_baseball, trophy: false);
  }
  if (has('規定投球')) {
    return (color: Colors.teal.shade700, symbol: Icons.sports_baseball, trophy: false);
  }
  if (has('本塁打|home run|hank aaron|slugger')) {
    return (color: Colors.red.shade700, symbol: Icons.local_fire_department, trophy: kind != 'milestone');
  }
  if (has('打点|rbi')) {
    return (color: Colors.orange.shade800, symbol: Icons.adjust, trophy: kind != 'milestone');
  }
  if (has('打率|首位打者|安打|hit|batting')) {
    return (color: Colors.green.shade700, symbol: Icons.sports_baseball, trophy: kind != 'milestone');
  }
  if (has('盗塁|stolen')) {
    return (color: Colors.cyan.shade800, symbol: Icons.directions_run, trophy: kind != 'milestone');
  }
  if (has('防御率|cy young|沢村|earned run')) {
    return (color: Colors.indigo, symbol: Icons.shield, trophy: true);
  }
  if (has('奪三振|strikeout|strike out')) {
    return (color: Colors.blue.shade800, symbol: Icons.bolt, trophy: kind != 'milestone');
  }
  if (has('セーブ|ホールド|中継|save|relie')) {
    return (color: Colors.teal.shade700, symbol: Icons.lock, trophy: kind != 'milestone');
  }
  if (has('勝|wins')) {
    return (color: Colors.blue.shade700, symbol: Icons.flag, trophy: kind != 'milestone');
  }
  if (has('glove|守備|ゴールデン.?グラブ')) {
    return (color: Colors.amber.shade800, symbol: Icons.shield, trophy: true);
  }
  // Give other named awards a stable accent rather than one identical generic medal.
  var hash = 0;
  for (final code in label.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  const colors = [Colors.indigo, Colors.brown, Colors.teal, Colors.deepOrange, Colors.purple];
  const symbols = [Icons.star, Icons.auto_awesome, Icons.flag, Icons.sports_baseball, Icons.diamond];
  return (color: colors[hash % colors.length], symbol: symbols[(hash ~/ colors.length) % symbols.length], trophy: kind == 'title');
}

/// Keep the achievement distinguishable even without opening its tooltip.
String achievementBadgeCaption(Map<String, dynamic> achievement) {
  final label = '${achievement['label'] ?? '功績'}';
  const captions = {
    '最優秀選手賞': 'MVP', '最優秀選手': 'MVP', '優秀選手賞': 'MVP',
    '最多本塁打': '本塁打王', '最多打点': '打点王', '最多盗塁': '盗塁王',
    '最優秀防御率': '防御率', '最多奪三振': '奪三振王',
    '最多勝利': '最多勝', '最高勝率': '勝率王', '最高出塁率': '出塁率',
    '最多セーブ投手': 'セーブ王', '最多セーブ': 'セーブ王',
    '最優秀中継ぎ投手': '中継ぎ王', '最優秀中継ぎ': '中継ぎ王',
    '最多盗塁者': '盗塁王', '最多勝利投手': '最多勝',
    '最多安打者': '最多安打', '最多三振奪取投手': '奪三振王',
    '最高出塁率者': '出塁率', '最優秀防御率投手': '防御率',
    'ゴールデン・グラブ賞': 'GG賞', 'サイ・ヤング賞': 'サイ賞',
    '新人王': '新人王', '正力松太郎賞': '正力賞',
    'ゴールデングラブ賞': 'GG賞', 'ベストナイン': 'ベスト9',
    '最優秀新人': '新人王', '規定打席到達': '規定打席', '規定投球回到達': '規定投球回',
  };
  if (captions.containsKey(label)) return captions[label]!;
  for (final key in captions.keys.toList()..sort((a, b) => b.length.compareTo(a.length))) {
    if (label.contains(key)) return captions[key]!;
  }
  return label;
}

/// Keep numeric milestones (including grouped/decimal values) on one line.
String achievementBadgeEngraving(String caption) {
  final tokens = <String>[];
  final number = RegExp(r'[0-9０-９]+(?:[,，.．][0-9０-９]+)*');
  var offset = 0;
  for (final match in number.allMatches(caption)) {
    tokens.addAll(caption.substring(offset, match.start).characters);
    tokens.add(match.group(0)!);
    offset = match.end;
  }
  tokens.addAll(caption.substring(offset).characters);
  final lineCount = (caption.characters.length / 4).ceil().clamp(1, 3);
  final target = (caption.characters.length / lineCount).ceil();
  final lines = <String>[''];
  for (final token in tokens) {
    if (lines.last.isNotEmpty && lines.length < lineCount &&
        lines.last.characters.length + token.characters.length > target) {
      lines.add('');
    }
    lines[lines.length - 1] += token;
  }
  return lines.join('\n');
}

class AchievementBadge extends StatelessWidget {
  const AchievementBadge({super.key, required this.achievement});
  final Map<String, dynamic> achievement;
  @override
  Widget build(BuildContext context) {
    final style = achievementBadgeStyle(achievement);
    final size = achievementBadgeSize(achievement);
    final caption = achievementBadgeCaption(achievement);
    final engraving = achievementBadgeEngraving(caption);
    Widget yearLabel(double fontSize) => Container(
      key: const ValueKey('achievement-year-label'),
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: size * .025, vertical: size * .015),
      child: Text('${achievement['year']}',
        style: TextStyle(fontSize: fontSize, height: 1,
          fontWeight: FontWeight.bold, color: Colors.black)),
    );
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
                  borderRadius: BorderRadius.zero,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(style.color, Colors.white, .92)!, Color.lerp(style.color, Colors.white, .65)!],
                  ),
                  border: Border.all(color: style.color.withValues(alpha: .45)),
                ),
                child: CustomPaint(
                    painter: const LeagueMvpTrophyPainter(),
                    child: Stack(children: [
                      if (achievement['year'] != null)
                        Positioned(
                          right: size * .04,
                          bottom: size * .04,
                          child: yearLabel(size * .1),
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
                              border: Border.all(color: style.color, width: size / 152),
                            ),
                            child: Text(
                              leagueMvpCaption(achievement).replaceFirst('MVP', ''),
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
                        child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text('MVP', style: TextStyle(color: Colors.white, fontSize: size * .125, fontWeight: FontWeight.w900)))),
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
                    key: const ValueKey('achievement-frame'),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.zero,
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(style.color, Colors.white, .92)!, Color.lerp(style.color, Colors.white, .65)!]),
                      border: Border.all(color: style.color.withValues(alpha: .45)),
                    )),
                if (style.trophy)
                  SizedBox(width: size, height: size,
                    child: CustomPaint(painter: LeagueMvpTrophyPainter(color: style.color)))
                else ...[
                  // The medal glyph has a transparent center. Fill it so the
                  // engraving sits on a solid dark face, not the pale frame.
                  Positioned(
                    left: size * .265, top: size * .16,
                    width: size * .47, height: size * .47,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.lerp(style.color, Colors.black, .35)!,
                      ),
                    ),
                  ),
                  Icon(Icons.workspace_premium,
                    color: Color.lerp(style.color, Colors.black, .35)!,
                    size: size * 27 / 34),
                ],
                Positioned(
                  left: size * .27, right: size * .27,
                  top: size * .24, height: size * .32,
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown,
                      child: Text(engraving, textAlign: TextAlign.center, softWrap: false,
                        key: const ValueKey('achievement-engraving'),
                        style: TextStyle(fontSize: size * .14, height: 1.1,
                          color: const Color(0xFFFFF3CF), fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(color: Colors.black.withValues(alpha: .7), offset: Offset(0, -size * .008)),
                            Shadow(color: Colors.white.withValues(alpha: .3), offset: Offset(0, size * .008)),
                          ]))),
                  ),
                ),
                if (achievement['year'] != null)
                  Positioned(
                    right: size * .04,
                    bottom: size * .04,
                    child: yearLabel(size * .13),
                  ),
              ],
            )));
  }
}

/// A wide black cup keeps the white league caption entirely inside its bowl.
class LeagueMvpTrophyPainter extends CustomPainter {
  const LeagueMvpTrophyPainter({this.color = Colors.black});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    final fill = Paint()..color = color;
    final handles = Paint()
      ..color = color
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
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(.35, .79, .3, .06), const Radius.circular(.015)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(.26, .85, .48, .08), const Radius.circular(.025)), fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LeagueMvpTrophyPainter oldDelegate) => oldDelegate.color != color;
}
