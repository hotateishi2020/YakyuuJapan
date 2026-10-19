import 'compact_layout.dart';
import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';
import 'personal_stats_style.dart';
export 'personal_stats_style.dart' show personalStatPositionColor;
import 'player_detail_dialog.dart';
import 'player_stats_grid.dart';
import '../logic/season_schedule.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../config/app_design.dart';
import '../config/org_config.dart';
import '../logic/auth_session.dart';
import '../logic/display_settings.dart';
import '../logic/show_user_predictions.dart';
import '../tools/browser_cookie.dart';
import '../tools/color_parse.dart';
import '../tools/date_format.dart';
import 'Text.dart';
import 'GamesBoard.dart';

enum SeasonPane { combined, games, standings }

enum PersonalStatsLayout { segment, scroll, grid }

const personalStatsLayoutCookie = 'koko_personal_stats_layout';

/// 個人成績の選手名は姓名の間の空白を入れない。
String compactPersonalStatName(String name) {
  return name.replaceAll(RegExp(r'[\s\u3000]+'), '');
}

PersonalStatsLayout readPersonalStatsLayout() {
  final raw = readBrowserCookie(personalStatsLayoutCookie);
  if (raw == 'grid') return PersonalStatsLayout.grid;
  if (raw == 'scroll') return PersonalStatsLayout.scroll;
  return PersonalStatsLayout.segment;
}

void writePersonalStatsLayout(PersonalStatsLayout layout) {
  writeBrowserCookie(personalStatsLayoutCookie, layout.name);
}

/// 勝差の数値。首位・「-」・優勝・0 は間隔なし。値はすぐ上のチームとの差。
({String name, String abbrev, String label, double gb}) gamesBehindEntry(String name, String raw, {String abbrev = ''}) {
  final text = raw.trim();
  if (text.isEmpty || text == 'null' || text == '-' || text == '—' || text == '－' || text == '優勝' || text.toUpperCase() == 'W') {
    final label = (text == '優勝' || text.toUpperCase() == 'W') ? text : '-';
    return (name: name.trim(), abbrev: abbrev.trim(), label: label, gb: 0);
  }
  final parsed = double.tryParse(text);
  if (parsed != null) {
    return (name: name.trim(), abbrev: abbrev.trim(), label: text, gb: parsed < 0 ? 0 : parsed);
  }
  final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(text);
  if (match != null) {
    return (name: name.trim(), abbrev: abbrev.trim(), label: text, gb: double.parse(match.group(1)!));
  }
  return (name: name.trim(), abbrev: abbrev.trim(), label: text, gb: 0);
}

const double gbChartLogoSize = 56;
const double gbChartPxPerGame = 18;
const double gbChartLabelH = 16;

/// 上へ迂回したゲーム差の数字の上に空ける余白。
const double gbChartDetourHeadroom = 14;

/// 最下位（左）から首位（右）へ上げる傾き。1 だと横幅と同じだけ上がる。
const double gbChartSlope = 0.5;

double gbChartLabelWidth(String label) => label.length * 14.0 + 8;

String formatGamesBehindGap(double diff) {
  final rounded = (math.max(0, diff) * 10).round() / 10;
  if ((rounded - rounded.roundToDouble()).abs() < 0.001) {
    return '${rounded.round()}';
  }
  return rounded.toStringAsFixed(1);
}

class GamesBehindLogo {
  final String name;
  final String abbrev;
  final double left;
  final double top;

  const GamesBehindLogo({required this.name, required this.abbrev, required this.left, required this.top});
}

class GamesBehindLink {
  final String upper;
  final String lower;
  final String label;
  final bool side;
  final bool sideBelow;
  final double labelLeft;
  final double labelTop;

  const GamesBehindLink({
    required this.upper,
    required this.lower,
    required this.label,
    required this.side,
    required this.sideBelow,
    required this.labelLeft,
    required this.labelTop,
  });
}

class GamesBehindLayout {
  final List<GamesBehindLogo> logos;
  final List<GamesBehindLink> links;
  final double logoSize;
  final double height;
  final double width;

  const GamesBehindLayout({
    required this.logos,
    required this.links,
    required this.logoSize,
    required this.height,
    required this.width,
  });
}

/// 最下位を左下、首位を右上の一直線上に置く。差 0 は横に並べ、数字は点線から外す。
GamesBehindLayout layoutGamesBehindChart(
  List<({String name, String abbrev, String label, double gb})> entries, {
  double? targetWidth,
}) {
  if (entries.isEmpty) {
    return const GamesBehindLayout(logos: [], links: [], logoSize: gbChartLogoSize, height: 0, width: 0);
  }
  const tieGap = 4.0;
  const labelPad = 8.0;
  final groups = <List<int>>[];
  var current = <int>[0];
  for (var i = 1; i < entries.length; i++) {
    if (entries[i].gb <= 0) {
      current.add(i);
    } else {
      groups.add(current);
      current = <int>[i];
    }
  }
  groups.add(current);
  final groupGap = <double>[
    for (var i = 0; i < groups.length; i++) i == 0 ? 0.0 : entries[groups[i].first].gb,
  ];

  double textWidth(String label) => gbChartLabelWidth(label);
  double halfW(int group, double logo) {
    final n = groups[group].length;
    return (n * logo + (n - 1) * tieGap) / 2;
  }

  String gapLabel(int group) => formatGamesBehindGap(groupGap[group]);

  double measureWidth(double logo, double px) {
    var anchor = 0.0;
    var prevHalf = halfW(0, logo);
    var minLeft = -prevHalf;
    var maxRight = prevHalf;
    for (var i = 1; i < groups.length; i++) {
      final half = halfW(i, logo);
      final dx = math.max(groupGap[i] * px, prevHalf + half + labelPad);
      anchor += dx;
      minLeft = math.min(minLeft, anchor - half);
      maxRight = math.max(maxRight, anchor + half);
      prevHalf = half;
    }
    return maxRight - minLeft;
  }

  var logo = gbChartLogoSize;
  var px = gbChartPxPerGame;
  if (targetWidth != null && targetWidth > 0 && groups.length > 1) {
    logo = (targetWidth * 0.45 / entries.length).clamp(18.0, gbChartLogoSize);
    if (measureWidth(logo, 0) > targetWidth) {
      var lo = 12.0;
      var hi = logo;
      for (var k = 0; k < 18; k++) {
        final mid = (lo + hi) / 2;
        if (measureWidth(mid, 0) > targetWidth) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      logo = lo;
      px = 0;
    } else {
      var lo = 0.0;
      var hi = gbChartPxPerGame;
      while (measureWidth(logo, hi) < targetWidth && hi < 800) {
        hi *= 2;
      }
      for (var k = 0; k < 22; k++) {
        final mid = (lo + hi) / 2;
        if (measureWidth(logo, mid) > targetWidth) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      px = lo;
    }
  }

  final anchors = <Offset>[Offset.zero];
  var prevHalf = halfW(0, logo);
  for (var i = 1; i < groups.length; i++) {
    final half = halfW(i, logo);
    final dx = math.max(groupGap[i] * px, prevHalf + half + labelPad);
    final prev = anchors.last;
    anchors.add(Offset(prev.dx + dx, prev.dy + dx * gbChartSlope));
    prevHalf = half;
  }

  final pre = <({String name, String abbrev, double x, double y})>[];
  for (var gi = 0; gi < groups.length; gi++) {
    final members = groups[gi];
    final span = members.length * logo + (members.length - 1) * tieGap;
    var left = anchors[gi].dx - span / 2;
    final top = anchors[gi].dy - logo / 2;
    for (final index in members) {
      pre.add((name: entries[index].name, abbrev: entries[index].abbrev, x: left, y: top));
      left += logo + tieGap;
    }
  }

  var minLeft = double.infinity;
  var maxRight = double.negativeInfinity;
  for (final mark in pre) {
    minLeft = math.min(minLeft, mark.x);
    maxRight = math.max(maxRight, mark.x + logo);
  }
  final mirror = minLeft + maxRight;

  final mirroredLogos = <({String name, String abbrev, double x, double y})>[];
  for (final mark in pre) {
    mirroredLogos.add((
      name: mark.name,
      abbrev: mark.abbrev,
      x: mirror - (mark.x + logo),
      y: mark.y,
    ));
  }
  final mirroredAnchors = <Offset>[
    for (final anchor in anchors) Offset(mirror - anchor.dx, anchor.dy),
  ];

  double yOnLine(double x) {
    final a = mirroredAnchors.first;
    final b = mirroredAnchors.last;
    if ((b.dx - a.dx).abs() < 0.001) return a.dy;
    final t = (x - a.dx) / (b.dx - a.dx);
    return a.dy + t * (b.dy - a.dy);
  }

  final mirroredLinks = <({String upper, String lower, String label, double x, double y, double textW})>[];
  final placedLabels = <Rect>[];
  bool hits(Rect rect) {
    for (final mark in mirroredLogos) {
      final logoRect = Rect.fromLTWH(mark.x, mark.y, logo, logo).inflate(2);
      if (rect.overlaps(logoRect)) return true;
    }
    for (final taken in placedLabels) {
      if (rect.overlaps(taken)) return true;
    }
    return false;
  }

  for (var gi = 1; gi < groups.length; gi++) {
    final label = gapLabel(gi);
    final textW = textWidth(label);
    final midX = (mirroredAnchors[gi - 1].dx + mirroredAnchors[gi].dx) / 2;
    final left = midX - textW / 2;
    final lineTop = math.min(yOnLine(left), yOnLine(left + textW));
    var top = lineTop - 4 - gbChartLabelH;
    var rect = Rect.fromLTWH(left, top, textW, gbChartLabelH);
    var guard = 0;
    while (hits(rect) && guard < 40) {
      top -= 4;
      rect = Rect.fromLTWH(left, top, textW, gbChartLabelH);
      guard++;
    }
    placedLabels.add(rect);
    mirroredLinks.add((
      upper: entries[groups[gi - 1].last].name,
      lower: entries[groups[gi].first].name,
      label: label,
      x: left,
      y: top,
      textW: textW,
    ));
  }

  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  void include(double left, double top, double right, double bottom) {
    minX = math.min(minX, left);
    maxX = math.max(maxX, right);
    minY = math.min(minY, top);
    maxY = math.max(maxY, bottom);
  }

  for (final mark in mirroredLogos) {
    include(mark.x, mark.y, mark.x + logo, mark.y + logo);
  }
  for (final link in mirroredLinks) {
    include(link.x, link.y - gbChartDetourHeadroom, link.x + link.textW, link.y + gbChartLabelH);
  }
  if (mirroredLogos.isNotEmpty) {
    var logoTop = double.infinity;
    var logoBottom = double.negativeInfinity;
    for (final mark in mirroredLogos) {
      logoTop = math.min(logoTop, mark.y);
      logoBottom = math.max(logoBottom, mark.y + logo);
    }
    final mid = (logoTop + logoBottom) / 2;
    final above = mid - minY;
    final below = maxY - mid;
    if (below > above) {
      minY -= below - above;
    } else if (above > below) {
      maxY += above - below;
    }
  }
  final shiftX = -minX;
  final shiftY = -minY;
  return GamesBehindLayout(
    logos: [
      for (final mark in mirroredLogos) GamesBehindLogo(name: mark.name, abbrev: mark.abbrev, left: mark.x + shiftX, top: mark.y + shiftY),
    ],
    links: [
      for (final link in mirroredLinks)
        GamesBehindLink(
          upper: link.upper,
          lower: link.lower,
          label: link.label,
          side: false,
          sideBelow: false,
          labelLeft: link.x + shiftX,
          labelTop: link.y + shiftY,
        ),
    ],
    logoSize: logo,
    height: math.max(0, maxY - minY),
    width: math.max(0, maxX - minX),
  );
}

class GamesBehindChart extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  /// 指定すると順位表と同じ高さに収めて描く。
  final double? fitHeight;

  const GamesBehindChart({super.key, required this.rows, this.fitHeight});

  @override
  Widget build(BuildContext context) {
    final ordered = [...rows];
    final hasRank = ordered.any((row) => int.tryParse('${row['int_rank']}') != null);
    if (hasRank) {
      ordered.sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 999).compareTo(int.tryParse('${b['int_rank']}') ?? 999));
    }
    final knownBehind = ordered.any((row) {
      final text = '${row['game_behind'] ?? ''}'.trim();
      return text.isNotEmpty && text != 'null' && text != '-' && text != '—' && text != '－';
    });
    if (!knownBehind) return const SizedBox.shrink();
    final entries = [
      for (final row in ordered)
        gamesBehindEntry(
          '${row['name_team'] ?? ''}',
          '${row['game_behind'] ?? ''}',
          abbrev: '${row['name_shortest'] ?? ''}',
        ),
    ].where((entry) => entry.name.isNotEmpty).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : null;
      final layout = layoutGamesBehindChart(entries, targetWidth: maxW);
      final origin = fitHeight == null ? math.max(0.0, ((maxW ?? layout.width) - layout.width) / 2) : 0.0;
      final paint = SizedBox(
        width: fitHeight == null ? null : layout.width,
        height: layout.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: _GbDashPainter(layout, origin))),
            for (final logo in layout.logos)
              Positioned(
                left: origin + logo.left,
                top: logo.top,
                child: _GbLogo(name: logo.name, abbrev: logo.abbrev, size: layout.logoSize),
              ),
            for (final link in layout.links)
              Positioned(
                left: origin + link.labelLeft,
                top: link.labelTop,
                child: Text(
                  link.label,
                  key: ValueKey('gb-gap-${link.upper}-${link.lower}'),
                  style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold, height: 1),
                ),
              ),
          ],
        ),
      );
      final height = fitHeight;
      if (height == null || height <= 0) return paint;
      return SizedBox(
        height: height,
        width: maxW,
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: paint,
          ),
        ),
      );
    });
  }
}

class _GbDashPainter extends CustomPainter {
  final GamesBehindLayout layout;
  final double origin;

  _GbDashPainter(this.layout, this.origin);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF212121)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final logo = layout.logoSize;
    final rows = <List<GamesBehindLogo>>[];
    final sorted = [...layout.logos]..sort((a, b) => a.top.compareTo(b.top));
    for (final mark in sorted) {
      if (rows.isEmpty || (mark.top - rows.last.first.top).abs() > 0.5) {
        rows.add(<GamesBehindLogo>[mark]);
      } else {
        rows.last.add(mark);
      }
    }
    if (rows.length < 2) return;
    Rect boundsOf(List<GamesBehindLogo> row) {
      var rect = Rect.fromLTWH(origin + row.first.left, row.first.top, logo, logo);
      for (final mark in row.skip(1)) {
        rect = rect.expandToInclude(Rect.fromLTWH(origin + mark.left, mark.top, logo, logo));
      }
      return rect;
    }

    final centers = [for (final row in rows) boundsOf(row).center];
    for (var i = 0; i < rows.length - 1; i++) {
      final from = centers[i];
      final to = centers[i + 1];
      final delta = to - from;
      if (delta.distance <= 0) continue;
      final leave = _leaveRect(boundsOf(rows[i]), from, to);
      final enter = 1 - _leaveRect(boundsOf(rows[i + 1]), to, from);
      if (enter <= leave) continue;
      _dash(canvas, from + delta * leave, from + delta * enter, paint);
    }
  }

  /// 中心から [to] へ向かう直線が矩形の外へ出る割合。
  double _leaveRect(Rect rect, Offset from, Offset to) {
    final delta = to - from;
    var t = 1.0;
    if (delta.dx.abs() > 0.001) {
      t = math.min(t, (rect.width / 2) / delta.dx.abs());
    }
    if (delta.dy.abs() > 0.001) {
      t = math.min(t, (rect.height / 2) / delta.dy.abs());
    }
    return t;
  }

  void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const hole = 3.0;
    final delta = b - a;
    final length = delta.distance;
    if (length <= 0) return;
    final step = delta / length;
    var drawn = 0.0;
    while (drawn < length) {
      final end = math.min(drawn + dash, length);
      canvas.drawLine(a + step * drawn, a + step * end, paint);
      drawn = end + hole;
    }
  }

  @override
  bool shouldRepaint(covariant _GbDashPainter oldDelegate) => oldDelegate.layout != layout || oldDelegate.origin != origin;
}

class _GbLogo extends StatelessWidget {
  final String name;
  final String abbrev;
  final double size;

  const _GbLogo({required this.name, required this.abbrev, required this.size});

  @override
  Widget build(BuildContext context) {
    final visual = teamLogoVisual(name, abbrev: abbrev);
    final image = teamLogoImage(asset: visual.asset, networkUrl: visual.networkUrl);
    return SizedBox(
      key: ValueKey('gb-mark-$name'),
      width: size,
      height: size,
      child: visual.asset != null || visual.networkUrl != null
          ? image
          : Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF37474F),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                abbrev.isNotEmpty ? abbrev : name.characters.take(2).toString(),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
    );
  }
}

/// MLB ワイルドカード表は 9/1〜翌開幕までに出す。過去年は常に出す。
bool showMlbWildcardStandings({int? seasonYear, DateTime? now}) {
  final today = now ?? DateTime.now();
  final year = seasonYear ?? today.year;
  if (year != today.year) return true;
  if (today.month >= 9) return true;
  if (today.month <= 3) return true;
  return false;
}

class SeasonTableBlock extends StatelessWidget {
  final List<Map<String, dynamic>> standings;
  final List<Map<String, dynamic>> stats;
  final List<Map<String, dynamic>> games;
  final List<Map<String, dynamic>> seriesGames;
  final List<Map<String, dynamic>> scheduleGames;
  final bool showScheduleColumns;
  final bool showPredictionColumns;
  final bool showNpbLeagueColumn;
  final int? onlyLeagueId; // 団体内リーグ ID。null: 両方
  final String? gamesDateFilter; // "YYYY-MM-DD"（nullなら今日）
  final bool portraitLayout;
  final SeasonPane pane;
  final OrgConfig org;
  final PersonalStatsLayout personalStatsLayout;
  final ValueChanged<PersonalStatsLayout>? onPersonalStatsLayoutChanged;
  final bool loadingStandings;
  final bool loadingStats;
  final bool loadingGames;
  final int seasonYear;
  final Future<void> Function(DateTime date)? onNeedGameDate;
  final bool Function(DateTime date)? shouldLoadGameDate;
  final String? loadingGameDate;
  final int gameDateOffset;
  final ValueChanged<int>? onGameDateOffsetChanged;

  const SeasonTableBlock({
    super.key,
    required this.standings,
    required this.stats,
    this.games = const [],
    this.seriesGames = const [],
    this.scheduleGames = const [],
    this.showScheduleColumns = false,
    this.showPredictionColumns = true,
    this.showNpbLeagueColumn = false,
    this.onlyLeagueId,
    this.gamesDateFilter,
    this.portraitLayout = false,
    this.pane = SeasonPane.combined,
    this.org = OrgConfig.npb,
    this.personalStatsLayout = PersonalStatsLayout.segment,
    this.onPersonalStatsLayoutChanged,
    this.loadingStandings = false,
    this.loadingStats = false,
    this.loadingGames = false,
    this.seasonYear = 0,
    this.onNeedGameDate,
    this.shouldLoadGameDate,
    this.loadingGameDate,
    this.gameDateOffset = 0,
    this.onGameDateOffsetChanged,
  });

  Widget _sectionLoading({double height = 120}) {
    return SizedBox(
      height: height,
      child: const Center(child: BaseballLoading()),
    );
  }

  Color? _parseColorName(String? name) => parseColorNameOrNull(name);

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

  int get _seasonYear => seasonYear > 0 ? seasonYear : DateTime.now().year;

  bool get _showMlbWildcard => showMlbWildcardStandings(seasonYear: _seasonYear);

  // 文字→数値(表示用)
  String _num(dynamic v) => (v == null || '$v'.isEmpty) ? '—' : '$v';

  // リーグ別フィルタ
  List<Map<String, dynamic>> _standingsOf(int leagueId) => standings.where((e) => int.tryParse('${e['id_league']}') == leagueId).toList()..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0).compareTo(int.tryParse('${b['int_rank']}') ?? 0));

  /// MLB は東・中・西地区に分割。NPB はリーグ全体を1ブロック。
  List<({String label, List<Map<String, dynamic>> rows})> _standingSections(int leagueId) {
    final all = _standingsOf(leagueId);
    if (org.kind != OrgKind.mlb) {
      return [(label: '', rows: all)];
    }
    const areas = [
      ('EAST', '東地区'),
      ('CENTER', '中地区'),
      ('WEST', '西地区'),
    ];
    final sections = <({String label, List<Map<String, dynamic>> rows})>[];
    for (final area in areas) {
      final rows = all.where((e) => '${e['code_area'] ?? ''}'.trim().toUpperCase() == area.$1).toList()..sort((a, b) => (int.tryParse('${a['int_rank']}') ?? 0).compareTo(int.tryParse('${b['int_rank']}') ?? 0));
      if (rows.isNotEmpty) sections.add((label: area.$2, rows: rows));
    }
    if (sections.isNotEmpty) {
      double pct(Map<String, dynamic> row) {
        final wins = int.tryParse('${row['int_win']}') ?? 0;
        final losses = int.tryParse('${row['int_lose']}') ?? 0;
        return wins + losses == 0 ? 0 : wins / (wins + losses);
      }

      final divisionWinners = {
        for (final section in sections)
          if (section.rows.isNotEmpty) int.tryParse('${section.rows.first['id_team']}') ?? 0,
      };
      final wild = [
        for (final row in all)
          if (!divisionWinners.contains(int.tryParse('${row['id_team']}') ?? 0)) Map<String, dynamic>.from(row),
      ]..sort((a, b) {
          final byPct = pct(b).compareTo(pct(a));
          if (byPct != 0) return byPct;
          return (int.tryParse('${b['int_win']}') ?? 0).compareTo(int.tryParse('${a['int_win']}') ?? 0);
        });
      if (wild.isNotEmpty) {
        final leaderWins = int.tryParse('${wild.first['int_win']}') ?? 0;
        final leaderLosses = int.tryParse('${wild.first['int_lose']}') ?? 0;
        for (var i = 0; i < wild.length; i++) {
          final wins = int.tryParse('${wild[i]['int_win']}') ?? 0;
          final losses = int.tryParse('${wild[i]['int_lose']}') ?? 0;
          final behind = ((leaderWins - wins) + (losses - leaderLosses)) / 2;
          wild[i]['int_rank'] = i + 1;
          wild[i]['game_behind'] = i == 0 ? '-' : (behind == behind.roundToDouble() ? '${behind.round()}' : behind.toStringAsFixed(1));
        }
        if (_showMlbWildcard) {
          sections.add((label: 'ワイルドカード順位', rows: wild));
        }
      }
    }
    if (sections.isEmpty && all.isNotEmpty) {
      return [(label: '', rows: all)];
    }
    return sections;
  }

  Widget _sectionHeader(String label, Color color, {String? logoAsset, List<Color>? gradient, Color foreground = Colors.white}) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        gradient: gradient == null ? null : LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: gradient),
        color: gradient == null ? color : null,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (logoAsset != null) ...[
            Image.asset(logoAsset, height: 22, fit: BoxFit.contain),
            const SizedBox(width: 8),
          ],
          Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // 順位テーブル（上:順位行、下:スタッツ要約）
  Widget _leagueTable(int leagueId) {
    final Color leagueColor = org.leagueColor(leagueId);
    final leagueForeground = leagueColor.computeLuminance() > .65 ? Colors.black : Colors.white;
    // リーグ見出しは非表示

    // 打撃/投手タイトル（画像に近い簡易版）: stats_player の形に合わせて抽出
    const battingTitles = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
    const pitchingTitles = ['防御率', '最多勝', '奪三振', 'HP', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'K/BB', 'QS率'];
    final leagueStats = pane == SeasonPane.standings ? const <Map<String, dynamic>>[] : stats.where((e) => int.tryParse('${e['id_league']}') == leagueId).toList();
    final bat = leagueStats.where((e) => battingTitles.contains(((e['title'] ?? '').toString()))).toList();
    final pit = leagueStats.where((e) => pitchingTitles.contains(((e['title'] ?? '').toString()))).toList();

    // 文字幅の目安（12pxフォントで約14px/字）
    // 文字幅の目安（12pxフォントで約14px/字）
    const double kChar = 14.0;
    const double wChar2 = kChar * 2; // 2文字ぶん
    const double wChar1 = kChar * 1.5; // 1文字ぶん
    const double wChar3 = kChar * 3; // 3文字ぶん（順位表で使用中）

    bool isTrue(dynamic value) {
      if (value == true) return true;
      if (value is num) return value != 0;
      final s = '$value'.trim().toLowerCase();
      return s == 'true' || s == 't' || s == '1';
    }

    Widget gridCell(String text, {double h = 15, Color? bg, Color? fg, FontWeight? weight, TextAlign align = TextAlign.center, Color borderColor = Colors.black26}) {
      return Container(
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: borderColor, width: 1),
        ),
        child: OneLineShrinkText(text, baseSize: 12, minSize: 6, weight: weight, color: fg, align: align),
      );
    }

    Widget teamNameCell(String text, {required double h, Color? bg, Color? fg, bool showJapan = false}) {
      return Container(
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: Colors.black26, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: OneLineShrinkText(text, baseSize: 12, minSize: 6, weight: FontWeight.bold, color: fg, align: TextAlign.center),
              ),
              if (showJapan)
                const Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Text('🇯🇵', style: TextStyle(fontSize: 11, height: 1)),
                ),
            ],
          ),
        ),
      );
    }

    Widget personalStatsSheet(List<Map<String, dynamic>> bat, List<Map<String, dynamic>> pit) {
      // 画素の多い横長画面は、打者上段・投手下段の全スタッツグリッド（元仕様）。
      if (!portraitLayout) {
        return DualBandLeaguePersonalStats(
          org: org,
          batting: bat,
          pitching: pit,
          showJapanFlag: org.kind == OrgKind.mlb,
          columnWidthFactor: org.kind == OrgKind.mlb ? 0.5 : 0.8,
        );
      }
      return LeaguePersonalStatsHost(
        batting: bat,
        pitching: pit,
        org: org,
        showJapanFlag: org.kind == OrgKind.mlb,
        layout: personalStatsLayout,
        onLayoutChanged: onPersonalStatsLayoutChanged,
      );
    }

    // 左: チーム順位 / 右: 個人成績（打撃・投手）
    return LayoutBuilder(builder: (context, c) {
      Widget standingsTable() {
        return LayoutBuilder(builder: (context, lb) {
          final sections = _standingSections(leagueId);
          // セ・パは同じ順位表幅になるよう、両リーグのチーム名と予想列で幅を決める。
          final widthRows = org.kind == OrgKind.npb
              ? [
                  for (final row in standings)
                    if ((int.tryParse('${row['id_league']}') ?? 0) <= 2) row,
                ]
              : [for (final section in sections) ...section.rows];
          bool predictFilled(Map<String, dynamic> row) {
            final tateishi = '${row['team_name_tateishi'] ?? ''}'.trim();
            final ejima = '${row['team_name_ejima'] ?? ''}'.trim();
            return (tateishi.isNotEmpty && tateishi != '—') || (ejima.isNotEmpty && ejima != '—');
          }

          final bool showPredictCols = showPredictionColumns && ShowUserPredictions.of(context) && widthRows.any(predictFilled);
          // スクロール側（試合〜防御率）の基準幅。余りはチーム名ではなくこちらに足す。
          final opponents = showScheduleColumns ? {for (final r in standings) '${r['id_team']}': r}.values.toList() : <Map<String, dynamic>>[];
          final dates = showScheduleColumns ? scheduleWindow(DateTime.now()) : <DateTime>[];
          const opponentColumnWidth = 48.0;
          final extraWidth = opponents.length * opponentColumnWidth + dates.length * 44.0;
          final double scrollColsW = extraWidth +
              wChar2 + // 試合
              wChar1 * 3 + // 勝・負・分
              wChar2 + // 勝差
              wChar3 + // 勝率
              wChar2 + // 打率
              wChar3 + // 本塁打
              wChar2 + // 打点
              wChar2 + // 盗塁
              wChar3 + // 失策率
              wChar2 * 3 + wChar3; // 防御率3列＋先発負担率
          final double pinnedBaseW = (showPredictCols ? wChar2 * 3 : wChar2) + (showNpbLeagueColumn ? wChar2 : 0); // 順位(+立・江)
          final double wName = _standingsTeamNameWidth([(label: '', rows: [for (final row in widthRows) {...row, if (compactBaseballLayout(context)) 'name_team': row['name_shortest'] ?? row['name_team']}])], showJapan: org.kind == OrgKind.mlb);
          final double pinnedW = pinnedBaseW + wName;
          final double naturalTable = pinnedW + scrollColsW;
          final double parentW = lb.maxWidth.isFinite ? lb.maxWidth : naturalTable;
          final double gridBodyH = showScheduleColumns ? 38.0 : 20.0;

          ({double game, double result, double behind, double pct, double avg, double hr, double rbi, double sb, double field, double era, bool scrollStats, bool scrollAll}) statCols(double areaW) {
            pack(double scale, {required bool scrollStats, required bool scrollAll}) => (
                  game: wChar2 * scale,
                  result: wChar1 * scale,
                  behind: wChar2 * scale,
                  pct: wChar3 * scale,
                  avg: wChar2 * scale,
                  hr: wChar3 * scale,
                  rbi: wChar2 * scale,
                  sb: wChar2 * scale,
                  field: wChar3 * scale,
                  era: wChar2 * scale,
                  scrollStats: scrollStats,
                  scrollAll: scrollAll,
                );
            if (pinnedW > areaW + 0.5) {
              return pack(1, scrollStats: true, scrollAll: true);
            }
            final room = areaW - pinnedW;
            if (room + 0.5 < scrollColsW) {
              return pack(1, scrollStats: true, scrollAll: false);
            }
            return pack(room / scrollColsW, scrollStats: false, scrollAll: false);
          }

          Widget pinnedHeader() {
            return Row(children: [
              SizedBox(width: wChar2, child: gridCell('順位', h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground, weight: FontWeight.bold)),
              if (showPredictCols) ...[
                SizedBox(width: wChar2, child: gridCell('立', h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground, weight: FontWeight.bold)),
                SizedBox(width: wChar2, child: gridCell('江', h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground, weight: FontWeight.bold)),
              ],
              if (showNpbLeagueColumn) SizedBox(width: wChar2, child: gridCell('所属', h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground, weight: FontWeight.bold)),
              SizedBox(width: wName, child: gridCell('チーム', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
            ]);
          }

          Widget scrollHeader(({double game, double result, double behind, double pct, double avg, double hr, double rbi, double sb, double field, double era, bool scrollStats, bool scrollAll}) cols) {
            return Row(children: [
              SizedBox(width: cols.game, child: gridCell('試合', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(width: cols.result, child: gridCell('勝', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(width: cols.result, child: gridCell('負', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(width: cols.result, child: gridCell('分', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(width: cols.behind, child: gridCell('勝差', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(width: cols.pct, child: gridCell('勝率', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(width: cols.avg, child: gridCell('打率', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(width: cols.hr, child: gridCell('本塁打', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(width: cols.rbi, child: gridCell('打点', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(width: cols.sb, child: gridCell('盗塁', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(width: cols.field, child: gridCell('失策率', weight: FontWeight.bold, h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              SizedBox(
                width: cols.era * 3,
                child: Column(children: [
                  gridCell('防御率', weight: FontWeight.bold, h: ALL_HEADER_H / 2, bg: leagueColor, fg: leagueForeground),
                  Row(children: [
                    SizedBox(width: cols.era, child: gridCell('総合', weight: FontWeight.bold, h: ALL_HEADER_H / 2, bg: leagueColor, fg: leagueForeground, align: TextAlign.center)),
                    SizedBox(width: cols.era, child: gridCell('先発', weight: FontWeight.bold, h: ALL_HEADER_H / 2, bg: leagueColor, fg: leagueForeground, align: TextAlign.center)),
                    SizedBox(width: cols.era, child: gridCell('救援', weight: FontWeight.bold, h: ALL_HEADER_H / 2, bg: leagueColor, fg: leagueForeground, align: TextAlign.center)),
                  ]),
                ]),
              ),
              SizedBox(width: cols.pct, child: Tooltip(message: '先発投球回 ÷ チーム総投球回', child: Container(
                height: ALL_HEADER_H, alignment: Alignment.center,
                decoration: BoxDecoration(color: leagueColor, border: Border.all(color: Colors.black26)),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text('先発\n負担率', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: leagueForeground))),
              ))),
              for (final opponent in opponents) SizedBox(width: opponentColumnWidth * cols.game / wChar2, child: gridCell('${opponent['name_shortest'] ?? opponent['name_team']}\n勝–負–分', h: ALL_HEADER_H, bg: leagueColor, fg: leagueForeground)),
              for (final date in dates) Container(width: 44 * cols.game / wChar2, height: ALL_HEADER_H,
                alignment: Alignment.center, color: leagueColor,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  color: scheduleDate(date) == scheduleDate(DateTime.now()) ? Colors.yellow : Colors.transparent,
                  child: Text('${date.month}/${date.day}', style: TextStyle(fontSize: 10,
                    color: scheduleDate(date) == scheduleDate(DateTime.now()) ? Colors.black : leagueForeground)))),
            ]);
          }

          Widget pinnedBodyRow(Map<String, dynamic> row, int divisionRank) {
            final int rk = org.kind == OrgKind.mlb ? divisionRank : (int.tryParse('${row['int_rank']}') ?? divisionRank);
            final sourceLeague = int.tryParse('${row['source_league_id']}');
            final leagueLabel = switch (sourceLeague) { 1 => 'セ', 2 => 'パ', _ => '—' };
            final affiliationColor = sourceLeague == 1 || sourceLeague == 2 ? OrgConfig.npb.leagueColor(sourceLeague!) : Colors.grey;
            final Color? teamBg = _parseColorName(row['color_back']);
            final Color? teamFg = _parseColorName(row['color_font']);
            final Color? teamBgTateishi = _parseColorName(row['team_color_back_tateishi']);
            final Color? teamFgTateishi = _parseColorName(row['team_color_font_tateishi']);
            final Color? teamBgEjima = _parseColorName(row['team_color_back_ejima']);
            final Color? teamFgEjima = _parseColorName(row['team_color_font_ejima']);
            Widget predictCell(String text, {required bool hit, Color? bg, Color? fg}) {
              return gridCell(text, h: gridBodyH, bg: bg, fg: fg, weight: hit ? FontWeight.bold : null);
            }

            return Row(children: [
              SizedBox(width: wChar2, child: gridCell('$rk', h: gridBodyH, bg: leagueColor, fg: leagueForeground, weight: FontWeight.bold)),
              if (showPredictCols) ...[
                SizedBox(
                  width: wChar2,
                  child: predictCell(
                    _num(row['team_name_tateishi']),
                    hit: isTrue(row['flg_atari_tateishi']),
                    bg: teamBgTateishi,
                    fg: isTrue(row['flg_atari_tateishi']) ? Colors.blueAccent : teamFgTateishi,
                  ),
                ),
                SizedBox(
                  width: wChar2,
                  child: predictCell(
                    _num(row['team_name_ejima']),
                    hit: isTrue(row['flg_atari_ejima']),
                    bg: teamBgEjima,
                    fg: isTrue(row['flg_atari_ejima']) ? Colors.redAccent : teamFgEjima,
                  ),
                ),
              ],
              if (showNpbLeagueColumn) SizedBox(width: wChar2, child: gridCell(leagueLabel, h: gridBodyH, bg: affiliationColor, fg: Colors.white, weight: FontWeight.bold)),
              SizedBox(
                width: wName,
                child: teamNameCell(
                  _num(compactBaseballLayout(context) ? row['name_shortest'] ?? row['name_team'] : row['name_team']),
                  h: gridBodyH,
                  bg: teamBg,
                  fg: teamFg,
                  showJapan: org.kind == OrgKind.mlb && isTrue(row['flg_japan']),
                ),
              ),
            ]);
          }

          Widget scrollBodyRow(Map<String, dynamic> row, ({double game, double result, double behind, double pct, double avg, double hr, double rbi, double sb, double field, double era, bool scrollStats, bool scrollAll}) cols) {
            final Color? teamBg = _parseColorName(row['color_back']);
            final lotte = '${row['name_team'] ?? ''}'.contains('ロッテ');
            final Color paleBg = teamBg != null ? _paleOf(teamBg, lotte ? 0.9 : 0.72) : Colors.white;

            Color? topColor(bool cond) => cond ? const Color(0xFF32CD32) : null;
            Color? worstColor(bool cond) => cond ? Colors.red : null;

            final bool topBat = row['flg_top_num_avg_batting'] == true;
            final bool worstBat = row['flg_worst_num_avg_batting'] == true;
            final Color? fgBat = topColor(topBat) ?? worstColor(worstBat);
            final FontWeight? wtBat = (topBat || worstBat) ? FontWeight.bold : null;

            final bool topHr = row['flg_top_int_homerun'] == true;
            final bool worstHr = row['flg_worst_int_homerun'] == true;
            final Color? fgHr = topColor(topHr) ?? worstColor(worstHr);
            final FontWeight? wtHr = (topHr || worstHr) ? FontWeight.bold : null;

            final bool topRbi = row['flg_top_int_rbi'] == true;
            final bool worstRbi = row['flg_worst_int_rbi'] == true;
            final Color? fgRbi = topColor(topRbi) ?? worstColor(worstRbi);
            final FontWeight? wtRbi = (topRbi || worstRbi) ? FontWeight.bold : null;

            final bool topSb = row['flg_top_int_sh'] == true;
            final bool worstSb = row['flg_worst_int_sh'] == true;
            final Color? fgSb = topColor(topSb) ?? worstColor(worstSb);
            final FontWeight? wtSb = (topSb || worstSb) ? FontWeight.bold : null;

            final bool topFld = row['flg_top_num_avg_fielding'] == true;
            final bool worstFld = row['flg_worst_num_avg_fielding'] == true;
            final Color? fgFld = topColor(topFld) ?? worstColor(worstFld);
            final FontWeight? wtFld = (topFld || worstFld) ? FontWeight.bold : null;

            final bool topEraT = row['flg_top_num_era_total'] == true;
            final bool worstEraT = row['flg_worst_num_era_total'] == true;
            final Color? fgEraT = topColor(topEraT) ?? worstColor(worstEraT);
            final FontWeight? wtEraT = (topEraT || worstEraT) ? FontWeight.bold : null;

            final bool topEraS = row['flg_top_num_era_starter'] == true;
            final bool worstEraS = row['flg_worst_num_era_starter'] == true;
            final Color? fgEraS = topColor(topEraS) ?? worstColor(worstEraS);
            final FontWeight? wtEraS = (topEraS || worstEraS) ? FontWeight.bold : null;

            final bool topEraR = row['flg_top_num_era_relief'] == true;
            final bool worstEraR = row['flg_worst_num_era_relief'] == true;
            final Color? fgEraR = topColor(topEraR) ?? worstColor(worstEraR);
            final FontWeight? wtEraR = (topEraR || worstEraR) ? FontWeight.bold : null;

            final String gbText = '${row['game_behind']}'.trim();
            final double? gameBehindVal = double.tryParse(gbText);
            final bool closeBehind = gameBehindVal != null && gameBehindVal <= 2.0;
            final bool hasMagic = gbText.toUpperCase().contains('M');
            final bool isChampion = gbText == '優勝' || gbText.toUpperCase() == 'W';
            final Color? fgGb = isChampion ? Colors.yellow : (closeBehind ? const Color.fromARGB(255, 255, 68, 196) : null);
            final workloadExtreme = starterWorkloadExtreme(standings, row);
            final Color bgGb = isChampion ? Colors.red : paleBg;
            final FontWeight? wtGb = (closeBehind || hasMagic || isChampion) ? FontWeight.bold : null;
            final gbDisplay = isChampion && org.kind == OrgKind.mlb ? 'W' : _num(row['game_behind']);

            return Row(children: [
              SizedBox(width: cols.game, child: gridCell(_num(row['int_game']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: cols.result, child: gridCell(_num(row['int_win']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: cols.result, child: gridCell(_num(row['int_lose']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: cols.result, child: gridCell(_num(row['int_draw']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: cols.behind, child: gridCell(gbDisplay, h: gridBodyH, bg: bgGb, fg: fgGb, weight: wtGb)),
              SizedBox(width: cols.pct, child: gridCell(_num(row['pct_win']), h: gridBodyH, bg: paleBg)),
              SizedBox(width: cols.avg, child: gridCell(_num(row['num_avg_batting']), h: gridBodyH, bg: paleBg, fg: fgBat, weight: wtBat)),
              SizedBox(width: cols.hr, child: gridCell(_num(row['int_homerun']), h: gridBodyH, bg: paleBg, fg: fgHr, weight: wtHr)),
              SizedBox(width: cols.rbi, child: gridCell(_num(row['int_rbi']), h: gridBodyH, bg: paleBg, fg: fgRbi, weight: wtRbi)),
              SizedBox(width: cols.sb, child: gridCell(_num(row['int_sh']), h: gridBodyH, bg: paleBg, fg: fgSb, weight: wtSb)),
              SizedBox(width: cols.field, child: gridCell(_num(row['num_avg_fielding']), h: gridBodyH, bg: paleBg, fg: fgFld, weight: wtFld)),
              SizedBox(width: cols.era, child: gridCell(_num(row['num_era_total']), h: gridBodyH, bg: paleBg, fg: fgEraT, weight: wtEraT)),
              SizedBox(width: cols.era, child: gridCell(_num(row['num_era_starter']), h: gridBodyH, bg: paleBg, fg: fgEraS, weight: wtEraS)),
              SizedBox(width: cols.era, child: gridCell(_num(row['num_era_relief']), h: gridBodyH, bg: paleBg, fg: fgEraR, weight: wtEraR)),
              SizedBox(width: cols.pct, child: gridCell(starterWorkloadLabel(row['starter_workload_rate']), h: gridBodyH, bg: paleBg, fg: workloadExtreme == 1 ? Colors.green : workloadExtreme == -1 ? Colors.red : null, weight: workloadExtreme != 0 ? FontWeight.bold : null)),
              for (final opponent in opponents)
                SizedBox(
                    width: opponentColumnWidth * cols.game / wChar2,
                    child: Builder(builder: (context) {
                      final r = scheduleRecord(scheduleGames, row['id_team'], opponent: opponent['id_team']);
                      final extreme = scheduleOpponentExtreme(standings, scheduleGames, row, opponent['id_team']);
                      return gridCell('${row['id_team']}' == '${opponent['id_team']}' ? '—' : '${r.wins}–${r.losses}–${r.draws}', h: gridBodyH, bg: paleBg, fg: extreme == 1 ? Colors.green : extreme == -1 ? Colors.red : null, weight: extreme == 1 || extreme == -1 ? FontWeight.bold : FontWeight.normal);
                    })),
              for (final date in dates)
                SizedBox(
                    width: 44 * cols.game / wChar2,
                    child: Builder(builder: (context) {
                      final day = scheduleGames.where((g) => g['date'] == scheduleDate(date) && scheduleHasTeam(g, row['id_team'])).toList();
                      return Container(height: gridBodyH, alignment: Alignment.center,
                        decoration: BoxDecoration(color: paleBg, border: Border.all(color: Colors.white, width: .5)),
                        child: day.isEmpty ? const Text('—', style: TextStyle(fontSize: 10)) : Column(children: [
                          for (final g in day) Expanded(child: Builder(builder: (_) {
                            final home = '${g['id_team_home']}' == '${row['id_team']}';
                            final opponent = '${g[home ? 'name_away' : 'name_home'] ?? ''}';
                            final result = scheduleOutcome(g, row['id_team']);
                            final mark = result == '●' ? '×' : result;
                            final color = result == '○' ? Colors.red : result == '●' ? Colors.blue : Colors.amber;
                            return Column(children: [
                              Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (mark.isNotEmpty) Text(mark, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
                                Text(opponent, style: const TextStyle(fontSize: 10)),
                              ])))),
                              Container(height: 3, color: parseColorNameOrNull('${g['color_back_home'] ?? ''}') ?? Colors.grey),
                            ]);
                          })),
                        ]));
                    })),
            ]);
          }

          // MLB は地区ごとに「順位〜防御率」ヘッダーを繰り返す。NPB は先頭1回だけ。
          final bool headerPerSection = org.kind == OrgKind.mlb && sections.any((s) => s.label.isNotEmpty);

          Widget divisionBanner(String label) {
            return SizedBox(
              width: double.infinity,
              child: gridCell(label, h: gridBodyH, bg: const Color(0xFF37474F), fg: Colors.white, weight: FontWeight.bold, align: TextAlign.left),
            );
          }

          Widget sectionTable(
            ({String label, List<Map<String, dynamic>> rows}) section,
            ({double game, double result, double behind, double pct, double avg, double hr, double rbi, double sb, double field, double era, bool scrollStats, bool scrollAll}) cols,
          ) {
            final Widget pinned = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pinnedHeader(),
                for (var i = 0; i < section.rows.length; i++) pinnedBodyRow(section.rows[i], i + 1),
              ],
            );
            final Widget scroll = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                scrollHeader(cols),
                for (final row in section.rows) scrollBodyRow(row, cols),
              ],
            );
            if (cols.scrollAll) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [pinned, scroll],
                ),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: cols.scrollStats
                      ? BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 3,
                              offset: const Offset(2, 0),
                            ),
                          ],
                        )
                      : const BoxDecoration(),
                  child: pinned,
                ),
                Expanded(
                  child: cols.scrollStats
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: scroll,
                        )
                      : scroll,
                ),
              ],
            );
          }

          Widget sectionBlock(({String label, List<Map<String, dynamic>> rows}) section) {
            final showGamesBehind = section.label != 'ワイルドカード順位';
            final tableH = ALL_HEADER_H + section.rows.length * gridBodyH;
            const chartGap = 8.0;
            final roomForChart = parentW - naturalTable - chartGap;
            final beside = showGamesBehind && (roomForChart >= 200 || (MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height && parentW >= 600));
            final chartW = beside ? math.min(340.0, math.max(200.0, parentW * .23)) : 0.0;
            final areaW = beside ? parentW - chartW - chartGap : parentW;
            final cols = statCols(areaW);
            if (beside) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (headerPerSection && section.label.isNotEmpty) divisionBanner(section.label),
                  Row(
                    key: const Key('standings-gb-beside'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: sectionTable(section, cols)),
                      const SizedBox(width: chartGap),
                      SizedBox(
                        width: chartW,
                        height: tableH,
                        child: GamesBehindChart(rows: section.rows, fitHeight: tableH),
                      ),
                    ],
                  ),
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (headerPerSection && section.label.isNotEmpty) divisionBanner(section.label),
                sectionTable(section, cols),
                if (showGamesBehind) ...[
                  const SizedBox(height: 4),
                  GamesBehindChart(rows: section.rows),
                ],
              ],
            );
          }

          if (!headerPerSection) {
            return sections.isEmpty ? const SizedBox.shrink() : sectionBlock(sections.first);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) SizedBox(height: sections[i].label == 'ワイルドカード順位' ? 20 : 12),
                sectionBlock(sections[i]),
              ],
            ],
          );
        });
      }

      final Widget standingsBody = loadingStandings ? _sectionLoading(height: 140) : standingsTable();
      if (pane == SeasonPane.standings) {
        final leagueName = org.leagueName(leagueId);
        return Column(
          mainAxisSize: portraitLayout ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader(leagueName, leagueColor, foreground: leagueForeground),
            const SizedBox(height: 4),
            if (portraitLayout) standingsBody else Expanded(child: SingleChildScrollView(child: standingsBody)),
          ],
        );
      }

      final Widget gamesSwitcher = loadingGames
          ? _sectionLoading(height: portraitLayout ? 160 : 220)
          : GameDateSwitcher(
              key: ValueKey('gds-${org.kind.name}-$onlyLeagueId-$gamesDateFilter'),
              games: games,
              seriesGames: seriesGames,
              playerStats: stats,
              standings: standings,
              initialDate: gamesDateFilter,
              headerColor: leagueColor,
              leagueId: leagueId,
              leagueLabel: org.leagueName(leagueId),
              horizontal: true,
              onNeedGameDate: onNeedGameDate,
              shouldLoadGameDate: shouldLoadGameDate,
              loadingGameDate: loadingGameDate,
              dateOffset: gameDateOffset,
              onDateOffsetChanged: onGameDateOffsetChanged,
            );

      // 縦型は試合カードが選手人数で伸びる
      final Widget gamesBlock = portraitLayout ? gamesSwitcher : Expanded(child: gamesSwitcher);

      final Widget personalBody = loadingStats ? _sectionLoading(height: 180) : personalStatsSheet(bat, pit);

      final Widget teamPanel = Column(
        mainAxisSize: portraitLayout ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('チーム順位', leagueColor),
          const SizedBox(height: 6),
          if (portraitLayout) ...[
            standingsBody,
            const SizedBox(height: 12),
            gamesBlock,
          ] else
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: standingsBody),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverLayoutBuilder(
                    builder: (context, sliverConstraints) {
                      // スクロールで残り高さが縮むと、開いている守備図が下端から切れて閉じたように見える。
                      final gamesHeight = math.max(220.0, sliverConstraints.viewportMainAxisExtent);
                      return SliverToBoxAdapter(
                        child: SizedBox(height: gamesHeight, child: gamesSwitcher),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      );

      final Widget personalPanel = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('個人成績', leagueColor),
          const SizedBox(height: 6),
          Expanded(child: personalBody),
        ],
      );

      final leagueName = org.leagueName(leagueId);
      final selectedDay = DateTime.tryParse(gamesDateFilter ?? '') ?? DateTime.now();
      final day = DateFormatUtil.ymd(selectedDay.add(Duration(days: gameDateOffset)));
      final climax = npbClimaxHeader(
        leagueId: leagueId,
        fallbackLabel: leagueName,
        games: games.where((game) => gameDateOnly(game['date_game']) == day).toList(),
      );
      if (pane == SeasonPane.games) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader(climax.label, leagueColor, logoAsset: climax.logoAsset, gradient: climax.gradient),
            const SizedBox(height: 4),
            gamesBlock,
          ],
        );
      }
      if (portraitLayout) {
        // 縦スクロール時は、見出しと上位10名が見える高さに抑える。
        // Picker +（Segment二段 or 打者投手タブ）+ 上位10名。
        const double personalSectionHeight = 32.0 + 141.0 + _statRowH * 10;
        final Widget personalSection = personalStatsLayout == PersonalStatsLayout.scroll
            ? personalBody
            : SizedBox(
                height: personalSectionHeight,
                child: personalBody,
              );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            gamesBlock,
            const SizedBox(height: 16),
            _sectionHeader('チーム順位', leagueColor),
            const SizedBox(height: 6),
            standingsBody,
            const SizedBox(height: 16),
            _sectionHeader('個人成績', leagueColor),
            const SizedBox(height: 6),
            personalSection,
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: teamPanel),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: personalPanel),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      child: onlyLeagueId == null
          ? Column(
              children: [
                Expanded(child: _leagueTable(1)),
              ],
            )
          : _leagueTable(onlyLeagueId!),
    );
    // 縦型は内容高さ、横型は親に合わせて広げる
    if (portraitLayout) {
      return content;
    }
    return SizedBox.expand(child: content);
  }
}

/// 個人成績の「セ」「パ」「ア」「ナ」見出し。
const double _personalLeagueHeaderH = 33;

const double _statRowH = 20.8 * 1.5;

/// MLB 個人成績の短縮チーム名列（半角3文字 + 余白）
const double _mlbTeamAbbrevColW = 34.0;

/// チーム名が全文入る幅。余りは成績列へ回す。
double _standingsTeamNameWidth(List<({String label, List<Map<String, dynamic>> rows})> sections, {required bool showJapan}) {
  const style = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
  var widest = 0.0;
  void consider(String text, {double extra = 0}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width + 8 + extra);
  }

  consider('チーム');
  for (final section in sections) {
    for (final row in section.rows) {
      final name = '${row['name_team'] ?? ''}'.trim();
      if (name.isEmpty || name == 'null') continue;
      final flag = row['flg_japan'];
      final japan = showJapan && (flag == true || flag == 1 || '$flag'.trim().toLowerCase() == 'true' || '$flag'.trim() == '1');
      consider(name, extra: japan ? 16 : 0);
    }
  }
  return math.max(widest, 48);
}

/// パワプロのポジション色を薄くした個人成績の地色。

List<Color> personalStatPositionColors(Map<String, dynamic> row) {
  final colors = <Color>[];
  for (final role in ['${row['txt_position'] ?? ''}', ...?((row['season_position_groups'] is List) ? (row['season_position_groups'] as List).map((v) => '$v') : null)]) {
    final color = personalStatPositionColor(role);
    if (color != null && !colors.contains(color)) colors.add(color);
  }
  return colors;
}

// 個人成績の地色は主ポジションの単色に統一する。
LinearGradient? personalStatPositionGradient(Map<String, dynamic> row) => null;

class PlayerStatCell extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> allRows;
  final double? width;
  final bool showRank;
  final bool showJapanFlag;

  const PlayerStatCell({
    super.key,
    required this.row,
    this.allRows = const [],
    this.width,
    this.showRank = true,
    this.showJapanFlag = false,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Set<String>>(
        valueListenable: DisplaySettings.instance,
        builder: (context, _, child) => _buildCell(context),
      );

  Widget _buildCell(BuildContext context) {
    final rankRaw = row['int_rank'];
    final rankText = '${rankRaw ?? ''}';
    final int rankNum = rankRaw is int
        ? rankRaw
        : rankRaw is num
            ? rankRaw.round()
            : num.tryParse(rankText.trim())?.round() ?? -1;
    final team = '${row['name_team'] ?? ''}';
    final name = '${row['player_name'] ?? row['name_player'] ?? ''}';
    final stat = personalStatDisplay(row, allRows);
    final isNoRank = rankNum == 1000;
    const noRankBg = Color(0xFFC8C8C8);
    bool isTrue(dynamic value) {
      if (value == true) return true;
      if (value is num) return value != 0;
      final text = '$value'.trim().toLowerCase();
      return text == 'true' || text == 't' || text == '1';
    }

    final showUserPredictions = ShowUserPredictions.of(context);
    final isJapan = showJapanFlag && (DisplaySettings.instance.shows('flg_japan') && isTrue(row['flg_japan']));
    final countryEmoji = '${row['emoji_country'] ?? ''}'.trim();
    final marks = [
      if (isJapan) (countryEmoji.isNotEmpty ? countryEmoji : '🇯🇵'),
      if ((DisplaySettings.instance.shows('flg_saga') && isTrue(row['flg_saga']))) '佐',
      if ((DisplaySettings.instance.shows('flg_rookie') && isTrue(row['flg_rookie']))) '🔰',
      if ((DisplaySettings.instance.shows('flg_career_this_year') && isTrue(row['flg_career_this_year']))) '✨',
      if ((DisplaySettings.instance.shows('flg_under21') && isTrue(row['flg_under21']))) '🌱',
      if ((DisplaySettings.instance.shows('flg_age35') && isTrue(row['flg_age35']))) '🍁',
      if ((DisplaySettings.instance.shows('flg_retired') && isTrue(row['flg_retired']))) '💐',
      if ((DisplaySettings.instance.shows('flg_injury') && isTrue(row['flg_injury']))) '🤕',
    ];
    final positionBg = personalStatPositionColor('${row['txt_position'] ?? ''}');
    final compacted = compactPersonalStatName(name);
    final paren = compacted.indexOf('(');
    final label = paren >= 0 ? compacted.substring(0, paren) : compacted;
    final suffix = paren >= 0 ? compacted.substring(paren) : '';

    BoxDecoration? nameBg() {
      final raw = showUserPredictions ? '${row['colors_user'] ?? ''}' : '';
      final parts = raw.split('/').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
      final cols = [
        for (final part in parts)
          if (parseColorNameOrNull(part) != null) parseColorNameOrNull(part)!
      ];
      if (cols.isEmpty) return null;
      if (cols.length == 1) {
        return BoxDecoration(color: cols.first, borderRadius: BorderRadius.circular(4));
      }
      return BoxDecoration(
        gradient: LinearGradient(colors: cols, begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(4),
      );
    }

    Widget cellBg({required Widget child, Color? overlay}) {
      return ColoredBox(
        color: isNoRank && personalStatPositionGradient(row) == null ? (overlay ?? noRankBg) : (overlay ?? Colors.transparent),
        child: child,
      );
    }

    final decoration = nameBg();
    final hasBg = decoration != null;
    final hasPredictColor = showUserPredictions && '${row['colors_user'] ?? ''}'.split('/').any((s) => s.trim().isNotEmpty);
    final nameColor = hasPredictColor ? Colors.white : null;
    final nameWeight = hasBg ? FontWeight.bold : null;
    final nameLine = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: OneLineShrinkText(label.isEmpty ? '—' : label, baseSize: 10, minSize: 1, fast: true, color: nameColor, weight: nameWeight, align: TextAlign.center),
        ),
        for (final mark in marks)
          mark == '佐'
              ? Container(
                  margin: const EdgeInsets.only(left: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(color: const Color(0xFF0D47A1), borderRadius: BorderRadius.circular(2)),
                  child: const Text('佐', style: TextStyle(fontSize: 9, height: 1.0, color: Colors.white, fontWeight: FontWeight.bold)),
                )
              : Text(mark, style: TextStyle(fontSize: 10, height: 1.0, color: nameColor)),
        if (suffix.isNotEmpty)
          Flexible(
            fit: FlexFit.loose,
            child: OneLineShrinkText(suffix, baseSize: 10, minSize: 1, fast: true, color: nameColor, weight: nameWeight, align: TextAlign.center),
          ),
      ],
    );
    final Widget nameWidget;
    if (hasBg) {
      nameWidget = Container(decoration: decoration, alignment: Alignment.center, child: nameLine);
    } else {
      nameWidget = cellBg(child: Align(alignment: Alignment.center, child: nameLine));
    }

    Widget body = SizedBox(
      width: width,
      height: _statRowH,
      child: ColoredBox(
        key: const ValueKey('player-stat-bg'),
        color: isNoRank ? noRankBg : (positionBg ?? Colors.transparent),
        child: Container(
          decoration: BoxDecoration(gradient: personalStatPositionGradient(row), border: Border.all(color: Colors.black26, width: 1)),
          child: Row(children: [
            if (showRank)
              Expanded(
                flex: 2,
                child: ColoredBox(
                  color: const Color(0xFF424242),
                  child: Center(
                    child: rankNum == 1
                        ? const FittedBox(fit: BoxFit.contain, child: Text('👑', style: TextStyle(fontSize: 12, height: 1.0)))
                        : isNoRank
                            ? const FittedBox(
                                fit: BoxFit.contain,
                                child: Text('-', style: TextStyle(fontSize: 12, height: 1.0, color: Colors.white)),
                              )
                            : OneLineShrinkText(
                                rankText.isNotEmpty ? '$rankNum' : '—',
                                baseSize: 10,
                                minSize: 1,
                                fast: true,
                                color: Colors.white,
                              ),
                  ),
                ),
              ),
            // MLB略称（NYY 等）: 半角3文字 + 余白。NPB は従来どおり flex。
            if (showJapanFlag)
              SizedBox(
                width: _mlbTeamAbbrevColW,
                child: cellBg(
                  overlay: parseColorNameOrNull('${row['color_back'] ?? ''}') ?? (isNoRank ? noRankBg : Colors.transparent),
                  child: Align(
                    alignment: Alignment.center,
                    child: OneLineShrinkText(team, baseSize: 10, minSize: 1, fast: true, color: parseColorNameOrNull('${row['color_font'] ?? ''}')),
                  ),
                ),
              )
            else
              Expanded(
                flex: 2,
                child: cellBg(
                  overlay: parseColorNameOrNull('${row['color_back'] ?? ''}') ?? (isNoRank ? noRankBg : Colors.transparent),
                  child: Align(
                    alignment: Alignment.center,
                    child: OneLineShrinkText(team, baseSize: 10, minSize: 1, fast: true, color: parseColorNameOrNull('${row['color_font'] ?? ''}')),
                  ),
                ),
              ),
            Expanded(flex: 10, child: PlayerNameLink(player: row, child: nameWidget)),
            Expanded(
              flex: row['title'] == '盗塁' ? 8 : 4,
              child: cellBg(
                child: Align(
                  alignment: Alignment.center,
                  child: OneLineShrinkText(stat, baseSize: 10, minSize: 1, fast: true),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    return body;
  }
}

const _statsBattingFallback = Color(0xFFF12C51);
const _statsPitchingFallback = Color(0xFF1A1AFF);

/// 打撃：左の黄→橙→右の赤ピンク（横方向）
/// 打撃／投手グラデ背景（タブ・タイトルヘッダー・Segment 共通）。
Widget _statsGradBackground({required bool batting, double opacity = 1.0}) {
  final fill = DecoratedBox(
    decoration: batting ? statsBattingGradDecoration : statsPitchingGradDecoration,
  );
  return Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: batting ? _statsBattingFallback : _statsPitchingFallback),
      Opacity(opacity: opacity.clamp(0.0, 1.0), child: fill),
    ],
  );
}

Widget _statsGradHeader({
  required bool batting,
  required Widget child,
  double height = 20,
  BorderRadius? borderRadius,
}) {
  return SizedBox(
    height: height,
    child: ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _statsGradBackground(batting: batting),
          Center(child: child),
        ],
      ),
    ),
  );
}

String _normalizePersonalTitle(String t) => t == 'ホールド' ? 'HP' : t;

bool _personalRowIsPitcher(Map<String, dynamic> row) {
  const pitchingTitles = {'防御率', '最多勝', '奪三振', 'HP', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'K/BB', 'QS率', ...extraPitchingTitles};
  final value = row['flg_pitcher'];
  if (value is bool) return value;
  final text = '$value'.trim().toLowerCase();
  if (text == 'true' || text == 't' || text == '1') return true;
  if (text == 'false' || text == 'f' || text == '0') return false;
  return pitchingTitles.contains('${row['title'] ?? ''}'.trim());
}

List<String> _titlesInOrder(List<Map<String, dynamic>> rows, List<String> preferred) {
  final present = <String>{};
  for (final row in rows) {
    final title = _normalizePersonalTitle('${row['title'] ?? ''}'.trim());
    if (title.isEmpty || title == '盗塁成功率') continue;
    present.add(title);
  }
  final ordered = <String>[];
  for (final title in preferred) {
    final key = _normalizePersonalTitle(title);
    if (present.remove(key)) ordered.add(title);
  }
  ordered.addAll(present);
  return ordered;
}

bool _loggedInPredictedTitle(List<Map<String, dynamic>> rows, String title) {
  if (extraBattingTitles.contains(title) || extraPitchingTitles.contains(title)) return false;
  final id = AuthSession.instance.user?.id ?? 0;
  if (id <= 0) return false;
  final needle = '/$id/';
  for (final row in rows) {
    final t = '${row['title'] ?? ''}'.trim();
    if (t != title && _normalizePersonalTitle(t) != _normalizePersonalTitle(title)) {
      continue;
    }
    if ('${row['id_users'] ?? ''}'.contains(needle)) return true;
  }
  return false;
}

Widget _verticalStatLabel(String text, {required Color color, required FontWeight weight, double fontSize = 10, bool starred = false}) {
  final chars = text.characters.toList();
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final ch in chars)
        Text(
          (ch == 'ー' || ch == '―' || ch == 'ｰ' || ch == '−') ? '｜' : ch,
          style: TextStyle(
            color: color,
            fontWeight: weight,
            fontSize: fontSize,
            height: 1.05,
          ),
        ),
      if (starred) Text('⭐️', style: TextStyle(fontSize: fontSize, height: 1, color: color)),
    ],
  );
}

Widget _horizontalTitleLabel(String title, {required bool starred, required Widget child}) {
  if (!starred) return child;
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      child,
      const Text('⭐️', style: TextStyle(fontSize: 11, height: 1, color: Colors.white)),
    ],
  );
}

double _statsSegmentHeightFor(List<String> labels) {
  if (labels.isEmpty) return 0;
  final maxChars = labels.fold<int>(1, (m, label) => label.characters.length > m ? label.characters.length : m);
  return (maxChars * 11.0 + 10).clamp(36.0, 72.0);
}

/// 選択中はグラデーション、非選択は薄いグレー。
class StatsSegmentControl extends StatelessWidget {
  final List<String> labels;
  final Set<String> starredTitles;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  final String? backgroundAsset;
  final Decoration? backgroundDecoration;
  final Color fallbackColor;
  final Color foreground;
  final double? height;

  const StatsSegmentControl({
    super.key,
    required this.labels,
    this.starredTitles = const {},
    required this.selectedIndex,
    required this.onSelected,
    required this.fallbackColor,
    this.backgroundAsset,
    this.backgroundDecoration,
    this.foreground = Colors.white,
    this.height,
  });

  Widget _backgroundFill({required bool selected}) {
    final fill = backgroundDecoration != null
        ? DecoratedBox(decoration: backgroundDecoration!)
        : backgroundAsset != null
            ? Image.asset(
                backgroundAsset!,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            : const SizedBox.shrink();
    if (selected) return fill;
    return ColoredBox(color: Colors.grey.shade300);
  }

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    const extra = 12.0;
    final barH = (height ?? _statsSegmentHeightFor(labels)) + (height == null ? extra : 0);
    return SizedBox(
      height: barH,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) Container(width: 1, color: foreground.withValues(alpha: 0.85)),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelected(i),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: fallbackColor),
                        _backgroundFill(selected: selectedIndex == i),
                        if (selectedIndex == i)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        Center(
                          child: _verticalStatLabel(
                            labels[i],
                            color: selectedIndex == i ? foreground : Colors.black87,
                            weight: selectedIndex == i ? FontWeight.w900 : FontWeight.w600,
                            fontSize: labels.length > 9 ? 9 : 10,
                            starred: starredTitles.contains(labels[i]) || starredTitles.contains(_normalizePersonalTitle(labels[i])),
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
  }
}

/// 上段＝打者・下段＝投手の二段 Segment を持つ個人成績パネル。
class _DualStatsSegmentBars extends StatelessWidget {
  final List<String> battingTitles;
  final List<String> pitchingTitles;
  final Set<String> starredTitles;
  final bool battingSelected;
  final int titleIndex;
  final ValueChanged<({bool batting, int index})> onSelected;

  const _DualStatsSegmentBars({
    required this.battingTitles,
    required this.pitchingTitles,
    this.starredTitles = const {},
    required this.battingSelected,
    required this.titleIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // 打者・投手で文字数が違っても、二段の高さを揃える。
    final sharedH = [
          _statsSegmentHeightFor(battingTitles),
          _statsSegmentHeightFor(pitchingTitles),
        ].fold<double>(0, (a, b) => a > b ? a : b) +
        12;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (battingTitles.isNotEmpty)
          StatsSegmentControl(
            labels: battingTitles,
            starredTitles: starredTitles,
            selectedIndex: battingSelected ? titleIndex : null,
            backgroundDecoration: statsBattingGradDecoration,
            fallbackColor: _statsBattingFallback,
            height: sharedH,
            onSelected: (i) => onSelected((batting: true, index: i)),
          ),
        if (battingTitles.isNotEmpty && pitchingTitles.isNotEmpty) const SizedBox(height: 4),
        if (pitchingTitles.isNotEmpty)
          StatsSegmentControl(
            labels: pitchingTitles,
            starredTitles: starredTitles,
            selectedIndex: battingSelected ? null : titleIndex,
            backgroundDecoration: statsPitchingGradDecoration,
            fallbackColor: _statsPitchingFallback,
            height: sharedH,
            onSelected: (i) => onSelected((batting: false, index: i)),
          ),
      ],
    );
  }
}

/// 個人成績の「セグメント表示 / スクロール表示」Picker。
class PersonalStatsLayoutPicker extends StatelessWidget {
  final PersonalStatsLayout layout;
  final ValueChanged<PersonalStatsLayout> onChanged;

  const PersonalStatsLayoutPicker({
    super.key,
    required this.layout,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold);
    final label = switch (layout) { PersonalStatsLayout.segment => 'セグメント表示', PersonalStatsLayout.scroll => 'スクロール表示', PersonalStatsLayout.grid => 'グリッド表示' };
    return SizedBox(
      height: TAB_BAR_H,
      width: double.infinity,
      child: Material(
        color: Colors.black,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Colors.black),
          borderRadius: BorderRadius.circular(TAB_RADIUS),
        ),
        child: PopupMenuButton<PersonalStatsLayout>(
          padding: EdgeInsets.zero,
          tooltip: '',
          color: Colors.black,
          initialValue: layout,
          position: PopupMenuPosition.under,
          onSelected: onChanged,
          itemBuilder: (context) => const [
            PopupMenuItem(value: PersonalStatsLayout.grid, child: Center(child: Text('グリッド表示', style: style))),
            PopupMenuItem(
              value: PersonalStatsLayout.segment,
              child: Center(child: Text('セグメント表示', textAlign: TextAlign.center, style: style)),
            ),
            PopupMenuItem(
              value: PersonalStatsLayout.scroll,
              child: Center(child: Text('スクロール表示', textAlign: TextAlign.center, style: style)),
            ),
          ],
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, textAlign: TextAlign.center, style: style),
              const Positioned(
                right: 2,
                child: Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _batterPitcherTabBar({
  required int selectedIndex,
  required ValueChanged<int> onSelected,
}) {
  const tabs = [('打者', 0), ('投手', 1)];
  return SizedBox(
    height: TAB_BAR_H,
    child: Row(
      children: [
        for (var i = 0; i < tabs.length; i++) ...[
          if (i > 0) const SizedBox(width: ALL_SPACE_BLOCK),
          Expanded(
            child: GestureDetector(
              onTap: () => onSelected(tabs[i].$2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TAB_RADIUS),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 選択中はグラデをそのまま、非選択は薄いグレーのみ（選択エフェクトなし）
                    if (selectedIndex == tabs[i].$2) _statsGradBackground(batting: tabs[i].$2 == 0) else ColoredBox(color: Colors.grey.shade300),
                    Center(
                      child: Text(
                        tabs[i].$1,
                        style: TextStyle(
                          fontSize: TAB_BAR_H / 2,
                          fontWeight: selectedIndex == tabs[i].$2 ? FontWeight.bold : FontWeight.normal,
                          color: selectedIndex == tabs[i].$2 ? Colors.white : Colors.black87,
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
}

/// 1リーグ分。Picker でセグメント／スクロールを切り替える。
class LeaguePersonalStatsHost extends StatefulWidget {
  final List<Map<String, dynamic>> batting;
  final List<Map<String, dynamic>> pitching;
  final bool showJapanFlag;
  final OrgConfig org;
  final PersonalStatsLayout layout;
  final ValueChanged<PersonalStatsLayout>? onLayoutChanged;

  const LeaguePersonalStatsHost({
    super.key,
    required this.batting,
    required this.pitching,
    this.showJapanFlag = false,
    this.org = OrgConfig.npb,
    this.layout = PersonalStatsLayout.segment,
    this.onLayoutChanged,
  });

  @override
  State<LeaguePersonalStatsHost> createState() => _LeaguePersonalStatsHostState();
}

class _LeaguePersonalStatsHostState extends State<LeaguePersonalStatsHost> {
  int _batterPitcherTab = 0;
  List<Map<String, dynamic>> get batting => widget.batting.where((r) => widget.org.kind != OrgKind.npb || r['title'] != 'ボール球見極め率').toList();

  void _setLayout(PersonalStatsLayout value) {
    if (value == widget.layout) return;
    writePersonalStatsLayout(value);
    widget.onLayoutChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final battingSelected = _batterPitcherTab == 0;
    final picker = PersonalStatsLayoutPicker(
      layout: widget.layout,
      onChanged: _setLayout,
    );
    if (widget.layout == PersonalStatsLayout.grid) {
      return Column(children: [picker, const SizedBox(height: 4), _batterPitcherTabBar(selectedIndex: _batterPitcherTab, onSelected: (i) => setState(() => _batterPitcherTab = i)), Expanded(child: PlayerStatsGrid(rows: battingSelected ? batting : widget.pitching, batting: battingSelected, showBallSelection: widget.org.kind != OrgKind.npb))]);
    }
    if (widget.layout == PersonalStatsLayout.scroll) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          picker,
          const SizedBox(height: 4),
          _batterPitcherTabBar(
            selectedIndex: _batterPitcherTab,
            onSelected: (i) {
              if (i == _batterPitcherTab) return;
              setState(() => _batterPitcherTab = i);
            },
          ),
          const SizedBox(height: 4),
          ScrollLeaguePersonalStats(
            rows: battingSelected ? batting : widget.pitching,
            batting: battingSelected,
            showJapanFlag: widget.showJapanFlag,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        picker,
        const SizedBox(height: 4),
        Expanded(
          child: SegmentedLeaguePersonalStats(
            batting: batting,
            pitching: widget.pitching,
            showJapanFlag: widget.showJapanFlag,
          ),
        ),
      ],
    );
  }
}

/// スクロール表示（1リーグ）。各スタッツの全選手を親のスクロール領域に表示。
class ScrollLeaguePersonalStats extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final bool batting;
  final bool showJapanFlag;

  const ScrollLeaguePersonalStats({
    super.key,
    required this.rows,
    required this.batting,
    this.showJapanFlag = false,
  });

  static const _battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
  static const _pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'K/BB', 'QS率'];

  @override
  Widget build(BuildContext context) {
    final cols = batting ? _battingCols : _pitchingCols;
    final titles = _titlesInOrder(rows, cols);
    if (titles.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      const headerH = 28.0;
      if (titles.isEmpty) {
        return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final title in titles) ...[
            DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: Colors.black26, width: 1)),
              child: _statsGradHeader(
                batting: batting,
                height: headerH + 12,
                child: _horizontalTitleLabel(
                  title,
                  starred: _loggedInPredictedTitle(rows, title),
                  child: OneLineShrinkText(
                    title,
                    baseSize: 12,
                    minSize: 6,
                    weight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Builder(builder: (context) {
              final matched = rows.where((m) {
                final t = '${m['title'] ?? ''}'.trim();
                return t == title || _normalizePersonalTitle(t) == _normalizePersonalTitle(title);
              }).toList();
      sortPersonalStatRows(matched);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in matched)
                    PlayerStatCell(
                      row: row,
                      allRows: rows,
                      showJapanFlag: showJapanFlag,
                    ),
                ],
              );
            }),
            const SizedBox(height: 8),
          ],
        ],
      );
    });
  }
}

/// 横長画面用。上段＝全打撃スタッツ、下段＝全投手スタッツのグリッド（打者／投手切替なし）。
class DualBandLeaguePersonalStats extends StatefulWidget {
  final List<Map<String, dynamic>> batting;
  final List<Map<String, dynamic>> pitching;
  final bool showJapanFlag;
  final OrgConfig org;
  final double columnWidthFactor;

  const DualBandLeaguePersonalStats({
    super.key,
    required this.batting,
    required this.pitching,
    this.showJapanFlag = false,
    this.org = OrgConfig.npb,
    this.columnWidthFactor = 1,
  });

  @override
  State<DualBandLeaguePersonalStats> createState() => _DualBandLeaguePersonalStatsState();
}

class _DualBandLeaguePersonalStatsState extends State<DualBandLeaguePersonalStats> {
  bool grid = false;
  List<Map<String, dynamic>> get batting => widget.batting.where((r) => widget.org.kind != OrgKind.npb || r['title'] != 'ボール球見極め率').toList();
  List<Map<String, dynamic>> get pitching => widget.pitching;
  bool get showJapanFlag => widget.showJapanFlag;
  double get columnWidthFactor => widget.columnWidthFactor;
  @override
  Widget build(BuildContext context) {
    if (batting.isEmpty && pitching.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }
    return DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Expanded(child: TabBar(tabs: [Tab(text: '打者スタッツ'), Tab(text: '投手スタッツ')])),
              TextButton(onPressed: () => setState(() => grid = !grid), child: Text(grid ? '従来の表' : 'グリッド表'))
            ]),
            Expanded(
                child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
              grid ? PlayerStatsGrid(rows: batting, batting: true, showBallSelection: widget.org.kind != OrgKind.npb) : _FillScrollLeaguePersonalStats(rows: batting, batting: true, showJapanFlag: showJapanFlag, columnWidthFactor: columnWidthFactor),
              grid ? PlayerStatsGrid(rows: pitching, batting: false) : _FillScrollLeaguePersonalStats(rows: pitching, batting: false, showJapanFlag: showJapanFlag, columnWidthFactor: columnWidthFactor),
            ])),
          ],
        ));
  }
}

/// スタッツ列を並べ、表全体を縦横にスクロールする。
class _FillScrollLeaguePersonalStats extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final bool batting;
  final bool showJapanFlag;
  final double columnWidthFactor;

  const _FillScrollLeaguePersonalStats({
    required this.rows,
    required this.batting,
    this.showJapanFlag = false,
    this.columnWidthFactor = 1,
  });

  static const _battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
  static const _pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'K/BB', 'QS率'];

  @override
  Widget build(BuildContext context) {
    final cols = batting ? _battingCols : _pitchingCols;
    final titles = _titlesInOrder(rows, cols);
    if (titles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final parentW = constraints.maxWidth.isFinite && constraints.maxWidth > 0 ? constraints.maxWidth : 300.0;
      final colW = math.max(parentW / titles.length, parentW * (MediaQuery.sizeOf(context).width >= 1000 ? 0.3 : 0.2) * columnWidthFactor);
      final grouped = [for (final title in titles)
        rows.where((r) => _normalizePersonalTitle('${r['title'] ?? ''}') == _normalizePersonalTitle(title)).toList()];
      for (final group in grouped) { sortPersonalStatRows(group); }
      final rowCount = grouped.fold<int>(0, (count, group) => math.max(count, group.length));
      final height = math.max(constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0, 40 + rowCount * _statRowH);
      return SingleChildScrollView(
        child: SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: SizedBox(height: height, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < titles.length; i++)
              SizedBox(width: colW, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
                  child: _statsGradHeader(batting: batting, height: 40,
                    child: _horizontalTitleLabel(titles[i], starred: _loggedInPredictedTitle(rows, titles[i]),
                      child: OneLineShrinkText(titles[i], baseSize: 12, minSize: 6, weight: FontWeight.bold, color: Colors.white)))),
                for (final row in grouped[i]) PlayerStatCell(row: row, allRows: rows, width: colW, showJapanFlag: showJapanFlag),
                Expanded(child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.black26)))),
              ])),
          ]))),
      );
    });
  }
}

Widget _personalLeagueTabs(OrgConfig org) => Builder(builder: (context) {
      final controller = DefaultTabController.of(context);
      return AnimatedBuilder(
          animation: controller,
          builder: (context, _) => SizedBox(
                height: TAB_BAR_H,
                child: Row(children: [
                  for (var i = 0; i < org.leagues.length; i++) ...[
                    if (i > 0) const SizedBox(width: ALL_SPACE_BLOCK),
                    Expanded(
                        child: Material(
                      color: controller.index == i ? org.tabColor : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(TAB_RADIUS),
                      child: InkWell(
                        onTap: () => controller.animateTo(i),
                        borderRadius: BorderRadius.circular(TAB_RADIUS),
                        child: Center(child: Text(org.leagues[i].name, style: TextStyle(fontSize: 12, height: 1, fontWeight: controller.index == i ? FontWeight.bold : FontWeight.normal, color: controller.index == i ? Colors.white : Colors.black87))),
                      ),
                    )),
                  ],
                ]),
              ));
    });

/// 横長・項目ごと表示。NPB・MLBともリーグタブで切り替える。
class DualBandBothLeaguePersonalStats extends StatelessWidget {
  final List<Map<String, dynamic>> stats;
  final OrgConfig org;

  const DualBandBothLeaguePersonalStats({
    super.key,
    required this.stats,
    this.org = OrgConfig.npb,
  });

  @override
  Widget build(BuildContext context) {
    Widget side(int leagueId, Color color, String name) {
      final leagueRows = stats.where((row) => (int.tryParse('${row['id_league']}') ?? 0) == leagueId).toList();
      final bat = leagueRows.where((row) => !_personalRowIsPitcher(row)).toList();
      final pit = leagueRows.where(_personalRowIsPitcher).toList();
      return DualBandLeaguePersonalStats(
        batting: bat,
        pitching: pit,
        org: org,
        showJapanFlag: org.kind == OrgKind.mlb,
        columnWidthFactor: org.kind == OrgKind.mlb ? 0.5 : 0.4,
      );
    }

    return DefaultTabController(
      length: org.leagues.length,
      child: Column(children: [
        _personalLeagueTabs(org),
        Expanded(
            child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
          for (final league in org.leagues) side(league.id, league.color, league.name),
        ])),
      ]),
    );
  }
}

/// スクロール表示（両リーグ）。全スタッツを一つの表としてスクロール。
class ScrollBothLeaguePersonalStats extends StatelessWidget {
  final List<Map<String, dynamic>> stats;
  final bool pitcher;
  final OrgConfig org;

  const ScrollBothLeaguePersonalStats({
    super.key,
    required this.stats,
    required this.pitcher,
    this.org = OrgConfig.npb,
  });

  @override
  Widget build(BuildContext context) {
    final rows = stats.where((row) => _personalRowIsPitcher(row) == pitcher &&
      (org.kind != OrgKind.npb || row['title'] != 'ボール球見極め率')).toList();
    final preferred = pitcher ? const ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'K/BB', 'QS率'] : const ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
    final titles = _titlesInOrder(rows, preferred);
    if (titles.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }

    List<Map<String, dynamic>> side(int leagueId, String title) {
      final result = rows.where((row) {
        if ((int.tryParse('${row['id_league']}') ?? 0) != leagueId) {
          return false;
        }
        final t = '${row['title'] ?? ''}'.trim();
        return t == title || _normalizePersonalTitle(t) == _normalizePersonalTitle(title);
      }).toList();
      sortPersonalStatRows(result);
      return result;
    }

    return ListView(
      children: [
        for (final title in titles) ...[
          _statsGradHeader(
            batting: !pitcher,
            height: 38,
            child: _horizontalTitleLabel(
              title,
              starred: _loggedInPredictedTitle(rows, title),
              child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: _personalLeagueHeaderH,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    color: org.leagues[0].color,
                    child: Text(
                      org.leagues[0].name.replaceAll('・リーグ', ''),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    color: org.leagues[1].color,
                    child: Text(
                      org.leagues[1].name.replaceAll('・リーグ', ''),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Builder(builder: (context) {
            final left = side(org.leagues[0].id, title);
            final right = side(org.leagues[1].id, title);
            final rowCount = left.length > right.length ? left.length : right.length;
            return Column(
                  children: [
                    for (var i = 0; i < rowCount; i++)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: i < left.length
                                ? PlayerStatCell(
                                    row: left[i],
                                    allRows: rows,
                                    showRank: true,
                                    showJapanFlag: org.kind == OrgKind.mlb,
                                  )
                                : const SizedBox(height: _statRowH),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: i < right.length
                                ? PlayerStatCell(
                                    row: right[i],
                                    allRows: rows,
                                    showRank: true,
                                    showJapanFlag: org.kind == OrgKind.mlb,
                                  )
                                : const SizedBox(height: _statRowH),
                          ),
                        ],
                      ),
                  ],
            );
          }),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// 1リーグ分の個人成績。打者／投手タイトルを二段 Segment で切り替える。
class SegmentedLeaguePersonalStats extends StatefulWidget {
  final List<Map<String, dynamic>> batting;
  final List<Map<String, dynamic>> pitching;
  final bool showJapanFlag;

  const SegmentedLeaguePersonalStats({
    super.key,
    required this.batting,
    required this.pitching,
    this.showJapanFlag = false,
  });

  @override
  State<SegmentedLeaguePersonalStats> createState() => _SegmentedLeaguePersonalStatsState();
}

class _SegmentedLeaguePersonalStatsState extends State<SegmentedLeaguePersonalStats> {
  static const _battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
  static const _pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'K/BB', 'QS率'];

  bool _battingSelected = true;
  int _titleIndex = 0;

  @override
  void didUpdateWidget(covariant SegmentedLeaguePersonalStats oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.batting != widget.batting || oldWidget.pitching != widget.pitching) {
      _battingSelected = widget.batting.isNotEmpty;
      _titleIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final batTitles = _titlesInOrder(widget.batting, _battingCols);
    final pitTitles = _titlesInOrder(widget.pitching, _pitchingCols);
    final starred = {
      for (final title in [...batTitles, ...pitTitles])
        if (_loggedInPredictedTitle([...widget.batting, ...widget.pitching], title)) title,
    };
    if (batTitles.isEmpty && pitTitles.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }
    final battingSelected = batTitles.isEmpty ? false : (pitTitles.isEmpty ? true : _battingSelected);
    final titles = battingSelected ? batTitles : pitTitles;
    final index = titles.isEmpty ? 0 : _titleIndex.clamp(0, titles.length - 1);
    final title = titles.isEmpty ? '' : titles[index];
    final src = battingSelected ? widget.batting : widget.pitching;
    final rows = src.where((m) {
      final t = '${m['title'] ?? ''}';
      return t == title || _normalizePersonalTitle(t) == _normalizePersonalTitle(title);
    }).toList();
      sortPersonalStatRows(rows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DualStatsSegmentBars(
          battingTitles: batTitles,
          pitchingTitles: pitTitles,
          starredTitles: starred,
          battingSelected: battingSelected,
          titleIndex: index,
          onSelected: (sel) => setState(() {
            _battingSelected = sel.batting;
            _titleIndex = sel.index;
          }),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => PlayerStatCell(
              row: rows[i],
              allRows: src,
              showRank: true,
              showJapanFlag: widget.showJapanFlag,
            ),
          ),
        ),
      ],
    );
  }
}

/// 項目ごとの個人成績。Picker でセグメント／スクロールを切り替える。
class BothLeaguePersonalStats extends StatefulWidget {
  final List<Map<String, dynamic>> stats;
  final OrgConfig org;
  final PersonalStatsLayout layout;
  final ValueChanged<PersonalStatsLayout>? onLayoutChanged;

  const BothLeaguePersonalStats({
    super.key,
    required this.stats,
    this.org = OrgConfig.npb,
    this.layout = PersonalStatsLayout.segment,
    this.onLayoutChanged,
  });

  @override
  State<BothLeaguePersonalStats> createState() => _BothLeaguePersonalStatsState();
}

class _BothLeaguePersonalStatsState extends State<BothLeaguePersonalStats> {
  static const _battingCols = ['打率', '本塁打', '打点', '盗塁', '出塁率', '最多安打', '長打率', 'OPS'];
  static const _pitchingCols = ['防御率', '最多勝', '奪三振', 'ホールド', 'セーブ', 'WHIP', '被打率', '奪三振率', '与四球率', 'K/BB', 'QS率'];

  bool _battingSelected = true;
  int _titleIndex = 0;
  int _batterPitcherTab = 0;

  @override
  void didUpdateWidget(covariant BothLeaguePersonalStats oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats != widget.stats) {
      _titleIndex = 0;
    }
  }

  void _setLayout(PersonalStatsLayout value) {
    if (value == widget.layout) return;
    writePersonalStatsLayout(value);
    widget.onLayoutChanged?.call(value);
  }

  Widget _segmentBody() {
    final battingRows = widget.stats.where((row) => !_personalRowIsPitcher(row)).toList();
    final pitchingRows = widget.stats.where(_personalRowIsPitcher).toList();
    final batTitles = _titlesInOrder(battingRows, _battingCols);
    final pitTitles = _titlesInOrder(pitchingRows, _pitchingCols);
    final starred = {
      for (final title in [...batTitles, ...pitTitles])
        if (_loggedInPredictedTitle(widget.stats, title)) title,
    };
    if (batTitles.isEmpty && pitTitles.isEmpty) {
      return const Center(child: Text('成績はありません', style: TextStyle(fontSize: 12)));
    }

    final battingSelected = batTitles.isEmpty ? false : (pitTitles.isEmpty ? true : _battingSelected);
    final titles = battingSelected ? batTitles : pitTitles;
    final index = titles.isEmpty ? 0 : _titleIndex.clamp(0, titles.length - 1);
    final title = titles.isEmpty ? '' : titles[index];
    final rows = battingSelected ? battingRows : pitchingRows;
    final org = widget.org;

    List<Map<String, dynamic>> side(int leagueId) {
      final result = rows.where((row) {
        if ((int.tryParse('${row['id_league']}') ?? 0) != leagueId) {
          return false;
        }
        final t = '${row['title'] ?? ''}'.trim();
        return t == title || _normalizePersonalTitle(t) == _normalizePersonalTitle(title);
      }).toList();
      sortPersonalStatRows(result);
      return result;
    }

    final left = side(org.leagues[0].id);
    final right = side(org.leagues[1].id);
    final rowCount = left.length > right.length ? left.length : right.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DualStatsSegmentBars(
          battingTitles: batTitles,
          pitchingTitles: pitTitles,
          starredTitles: starred,
          battingSelected: battingSelected,
          titleIndex: index,
          onSelected: (sel) => setState(() {
            _battingSelected = sel.batting;
            _titleIndex = sel.index;
          }),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: _personalLeagueHeaderH,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  color: org.leagues[0].color,
                  child: Text(
                    org.leagues[0].name.replaceAll('・リーグ', ''),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  color: org.leagues[1].color,
                  child: Text(
                    org.leagues[1].name.replaceAll('・リーグ', ''),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: ListView.builder(
            itemCount: rowCount,
            itemBuilder: (context, i) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: i < left.length
                      ? PlayerStatCell(
                          row: left[i],
                          allRows: rows,
                          showRank: true,
                          showJapanFlag: org.kind == OrgKind.mlb,
                        )
                      : const SizedBox(height: _statRowH),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: i < right.length
                      ? PlayerStatCell(
                          row: right[i],
                          allRows: rows,
                          showRank: true,
                          showJapanFlag: org.kind == OrgKind.mlb,
                        )
                      : const SizedBox(height: _statRowH),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scrollBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _batterPitcherTabBar(
          selectedIndex: _batterPitcherTab,
          onSelected: (i) {
            if (i == _batterPitcherTab) return;
            setState(() => _batterPitcherTab = i);
          },
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ScrollBothLeaguePersonalStats(
            stats: widget.stats,
            pitcher: _batterPitcherTab == 1,
            org: widget.org,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.org.kind == OrgKind.npb) {
      return DefaultTabController(
          length: widget.org.leagues.length,
          child: Column(children: [
            _personalLeagueTabs(widget.org),
            PersonalStatsLayoutPicker(layout: widget.layout, onChanged: _setLayout),
            Expanded(
                child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
              for (final league in widget.org.leagues)
                Builder(builder: (context) {
                  final rows = widget.stats.where((r) => '${r['id_league']}' == '${league.id}' && r['title'] != 'ボール球見極め率').toList();
                  final batting = rows.where((r) => !_personalRowIsPitcher(r)).toList();
                  final pitching = rows.where(_personalRowIsPitcher).toList();
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (widget.layout == PersonalStatsLayout.grid) ...[
                      _batterPitcherTabBar(selectedIndex: _batterPitcherTab, onSelected: (i) => setState(() => _batterPitcherTab = i)),
                      Expanded(child: PlayerStatsGrid(rows: _batterPitcherTab == 0 ? batting : pitching, batting: _batterPitcherTab == 0, showBallSelection: false)),
                    ] else if (widget.layout == PersonalStatsLayout.segment)
                      Expanded(child: SegmentedLeaguePersonalStats(batting: batting, pitching: pitching))
                    else ...[
                      _batterPitcherTabBar(selectedIndex: _batterPitcherTab, onSelected: (i) => setState(() => _batterPitcherTab = i)),
                      Expanded(child: SingleChildScrollView(child: ScrollLeaguePersonalStats(rows: _batterPitcherTab == 0 ? batting : pitching, batting: _batterPitcherTab == 0))),
                    ],
                  ]);
                }),
            ])),
          ]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PersonalStatsLayoutPicker(
          layout: widget.layout,
          onChanged: _setLayout,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: widget.layout == PersonalStatsLayout.grid
            ? Column(children: [
                _batterPitcherTabBar(selectedIndex: _batterPitcherTab, onSelected: (i) => setState(() => _batterPitcherTab = i)),
                Expanded(child: PlayerStatsGrid(rows: widget.stats.where((r) => _personalRowIsPitcher(r) == (_batterPitcherTab == 1)).toList(), batting: _batterPitcherTab == 0)),
              ])
            : widget.layout == PersonalStatsLayout.segment ? _segmentBody() : _scrollBody(),
        ),
      ],
    );
  }
}
