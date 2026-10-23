import '../widgets/special_media.dart';
import 'player_detail_dialog.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../logic/record_awards.dart';
import '../tools/color_parse.dart';
import '../tools/open_youtube.dart';
import 'GamesBoard.dart' show teamLogoVisual, mlbTeamAbbrev;

/// Spreadsheet-style NPB awards board. Unknown winners remain explicitly empty.
class SeasonTitlesTable extends StatelessWidget {
  const SeasonTitlesTable({super.key, required this.groups, required this.year});
  final Map<String, List<Map<String, dynamic>>> groups;
  final int year;
  static const ink = Color(0xff25324b);
  static const muted = Color(0xff718096);
  static const border = Color(0xffe4e9f0);
  static const central = Color(0xffc6e5d1);
  static const pacific = Color(0xffc5e3f5);
  static const red = Color(0xff8e2f49);
  static const orange = Color(0xfff8d4a6);
  static const gold = Color(0xffefdf9c);
  static const blue = Color(0xffc6d8f5);
  static const pink = Color(0xfff2c9d3);
  static const green = Color(0xffc5e2cf);
  static const purple = Color(0xffd3c8ee);

  Widget surface(Widget child) {
    if (child is SizedBox && child.child == null) return child;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: const [BoxShadow(color: Color(0x080f172a), blurRadius: 12, offset: Offset(0, 3))],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(11), child: child),
    );
  }

  String detail(Map<String, dynamic> row) => '${row['detail'] ?? ''}';
  String league(Map<String, dynamic> row) {
    final text = '${row['league'] ?? ''} ${detail(row)}';
    if (RegExp('セ・|セントラル').hasMatch(text)) return 'セ';
    if (RegExp('パ・|パシフィック').hasMatch(text)) return 'パ';
    final team = '${row['team'] ?? ''}';
    if (RegExp('巨人|読売|阪神|横浜|DeNA|広島|中日|ヤクルト').hasMatch(team)) return 'セ';
    if (RegExp('ソフトバンク|日本ハム|西武|楽天|ロッテ|オリックス').hasMatch(team)) return 'パ';
    return '';
  }

  List<Map<String, dynamic>> rows(String key, {String? side, bool Function(Map<String, dynamic>)? where}) => (groups[key] ?? []).where((r) => (side == null || league(r) == side) && (where == null || where(r))).toList();

  Widget cell(Widget child, {Color color = Colors.white}) => Container(alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9), decoration: BoxDecoration(color: color, border: Border.all(color: border, width: .5)), child: child);
  Widget label(String text, Color color, {double height = 42}) => SizedBox(
      height: height,
      child: cell(
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color == red
                      ? Colors.white
                      : color == central
                          ? const Color(0xff246447)
                          : color == pacific
                              ? const Color(0xff25618b)
                              : ink)),
          color: color));

  String teamLabel(Map<String, dynamic> row, {required bool mlb}) {
    if (mlb) {
      // Cached records can contain Japanese names (or LA) in name_shortest.
      // Resolve the actual team before trusting those display labels.
      for (final field in ['team', 'name_shortest', 'team_shortest']) {
        final value = '${row[field] ?? ''}'.trim();
        final abbreviation = mlbTeamAbbrev(value);
        if (abbreviation != null) return abbreviation;
      }
      return recordShortestTeam(row);
    }
    return recordShortestTeam(row, preferCanonical: true);
  }

  Widget winners(List<Map<String, dynamic>> values, {bool mlb = false, String empty = '未定', bool showLogo = false, bool showStatus = true, bool showVideo = false, String? side, Color? background}) {
    return cell(values.isEmpty
        ? Text(empty, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: muted))
        : Column(mainAxisSize: MainAxisSize.min, children: [
            for (final row in values)
              Tooltip(
                  triggerMode: TooltipTriggerMode.tap,
                  message: '${detail(row)}\n${row['team'] ?? ''}\n${row['source'] ?? ''}'.trim(),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (showLogo) ...[
                          (() {
                            final visual = teamLogoVisual('${row['name'] ?? row['team'] ?? ''}');
                            return SizedBox(
                                height: 36,
                                child: visual.asset != null
                                    ? SpecialMedia(child: Image.asset(visual.asset!, fit: BoxFit.contain))
                                    : visual.networkUrl != null
                                        ? SpecialMedia(child: Image.network(visual.networkUrl!, fit: BoxFit.contain))
                                        : const SizedBox.shrink());
                          })(),
                          const SizedBox(height: 4),
                        ],
                        Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                          if (!showLogo && '${row['team'] ?? ''}'.isNotEmpty && row['team'] != row['name'])
                            Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(color: parseColorName(row['color_back']?.toString(), const Color(0xffedf1f6)), borderRadius: BorderRadius.circular(4)),
                                  child: Text(teamLabel(row, mlb: mlb), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: parseColorName(row['color_font']?.toString(), parseColorName(row['color_back']?.toString(), const Color(0xffedf1f6)).computeLuminance() > .179 ? Colors.black : Colors.white))),
                                )),
                          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: PlayerNameLink(player: row, enabled: !showLogo && !['fresh_champion', 'allstar_champion', 'series_champion', 'interleague_champion', 'league_champion', 'cs_champion', 'series_entrants'].any((key) => (groups[key] ?? []).contains(row)), child: Text('${row['name'] ?? '—'}', maxLines: 1, softWrap: false, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink))))),
                          if (showVideo) const SizedBox(width: 8),
                          if (showVideo)
                            Builder(builder: (context) {
                              final id = '${row['highlight_video_id'] ?? ''}';
                              final available = RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);
                              return IconButton(
                                key: ValueKey('sayonara-video-${row['name']}-${detail(row)}'),
                                tooltip: available ? 'サヨナラシーンをYouTubeで見る' : '該当シーンの動画は確認中です',
                                icon: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: available ? const Color(0xffd71920) : Colors.grey,
                                  ),
                                  child: const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                onPressed: available
                                    ? () async {
                                        if (!await openYoutube(id) && context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('動画を開けませんでした。')));
                                        }
                                      }
                                    : null,
                              );
                            }),
                        ]),
                        if (showStatus && row['confirmed'] != true) Text(row['statistical'] == true ? '指標首位（表彰対象外を含む）' : '現在首位（暫定）', style: const TextStyle(fontSize: 10, color: Color(0xffa64b00))),
                      ]))),
          ]), color: background ?? (side == 'セ'
              ? Color.lerp(central, Colors.white, 0.55)!
              : side == 'パ'
                  ? Color.lerp(pacific, Colors.white, 0.55)!
                  : Colors.white));
  }

  Widget line(List<Widget> cells, {List<int>? weights}) => IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < cells.length; i++) Expanded(flex: weights?[i] ?? 1, child: cells[i])]));
  static const double leagueColumnWidth = 112;

  Widget leagueLine(List<Widget> cells, {List<int>? weights}) => IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: leagueColumnWidth, child: cells.first),
        for (var i = 1; i < cells.length; i++)
          Expanded(flex: weights?[i] ?? 1, child: cells[i]),
      ]));

  Widget pair(List<Map<String, dynamic>> values) => Column(children: [
        Expanded(
            child: line([
          winners(values.where((r) => league(r) == 'セ').toList()),
          winners(values.where((r) => league(r) == 'パ').toList()),
        ])),
        if (values.any((r) => league(r).isEmpty)) winners(values.where((r) => league(r).isEmpty).toList()),
      ]);
  Widget award(String title, String key, Color color, {bool split = false, bool Function(Map<String, dynamic>)? where, double headerHeight = 48}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (split)
          SizedBox(
            key: ValueKey('titles-split-header-$key'),
            height: headerHeight,
            child: Column(children: [
              label(title, color, height: headerHeight / 2),
              line([
                label('セ', central, height: headerHeight / 2),
                label('パ', pacific, height: headerHeight / 2),
              ]),
            ]),
          )
        else
          label(title, color, height: headerHeight),
        Expanded(
            child: key == 'hikeshi' && rows(key).isNotEmpty
                ? line([
                    for (final row in rows(key)) winners([row])
                  ])
                : split
                    ? pair(rows(key, where: where))
                    : winners(rows(key, where: where), showLogo: key == 'interleague_champion' || key == 'series_champion', empty: key == 'nagashima' && year < 2026 ? '創設前（2026年から）' : '未定')),
      ]);

  Widget verticalLabel(String text, Color color) => cell(Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color == red ? Colors.white : ink)), color: color);

  Widget verticalRow(String title, List<Widget> values, Color color) => line([verticalLabel(title, color), ...values], weights: [3, for (final _ in values) 4]);

  Widget verticalLeagueHeader(String title, {List<String> sides = const ['セ', 'パ']}) => verticalRow(title, [for (final side in sides) verticalLabel(side, side == 'セ' ? central : pacific)], purple);

  Widget verticalAwards(String key, List<(String, String)> awards, Color color, {Set<String> split = const {}}) => SizedBox(
      key: ValueKey('titles-grid-$key'),
      width: double.infinity,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (title, awardKey) in awards)
          verticalRow(
              title,
              [
                if (split.contains(awardKey))
                  Column(children: [
                    line([label('セ', central), label('パ', pacific)]),
                    line([winners(rows(awardKey, side: 'セ')), winners(rows(awardKey, side: 'パ'))]),
                    if (rows(awardKey).any((r) => league(r).isEmpty)) winners(rows(awardKey).where((r) => league(r).isEmpty).toList()),
                  ])
                else if (awardKey == 'hikeshi' && rows(awardKey).isNotEmpty)
                  line([
                    for (final row in rows(awardKey)) winners([row])
                  ])
                else
                  winners(rows(awardKey), showLogo: ['series_champion', 'interleague_champion'].contains(awardKey), empty: awardKey == 'nagashima' && year < 2026 ? '創設前（2026年から）' : '未定'),
              ],
              color),
      ]));

  List<Map<String, dynamic>> monthlyWinners(String month, String side, String role) => rows('monthly', side: side, where: (r) {
        final text = detail(r).replaceAllMapped(RegExp('[０-９]'), (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xfee0));
        final numbers = RegExp(r'\d+').allMatches(text).map((m) => int.parse(m[0]!));
        final matchesMonth = month == '3・4'
            ? numbers.any((m) => m == 3 || m == 4)
            : month == '9・10'
                ? numbers.any((m) => m == 9 || m == 10)
                : numbers.contains(int.parse(month));
        return matchesMonth && (role == '投手' ? text.contains('投手') : RegExp('打者|野手').hasMatch(text));
      });

  List<Map<String, dynamic>> sayonaraWinners(String month, String side) => rows('sayonara', side: side, where: (r) {
        final match = RegExp(r'([0-9０-９]+)(?:[、・,]([0-9０-９]+))?月').firstMatch(detail(r));
        if (match == null) return false;
        final value = int.tryParse(String.fromCharCodes(match[1]!.runes.map((c) => c >= 0xff10 && c <= 0xff19 ? c - 0xfee0 : c)));
        return (value == 3 || value == 4
                ? '3・4'
                : value == 9 || value == 10
                    ? '9・10'
                    : '$value') ==
            month;
      });

  Widget positions(String key, String title, Color color, {bool dh = false, double availableWidth = 0, bool portrait = false}) {
    const positions = ['投手', '捕手', '一塁', '二塁', '三塁', '遊撃', '左翼', '中堅', '右翼'];
    final headers = ['', ...positions, if (dh) 'DH'];
    if (portrait) {
      return SizedBox(
          key: ValueKey('titles-grid-$key'),
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label(title, color),
            verticalLeagueHeader('守備位置'),
            for (final p in [...positions.take(6), '外野手', if (dh) 'DH'])
              verticalRow(
                  p,
                  [
                    for (final side in ['セ', 'パ'])
                      winners(rows(key,
                          side: side,
                          where: (r) => p == '外野手'
                              ? RegExp('外野|左翼|中堅|右翼').hasMatch(detail(r))
                              : p == 'DH'
                                  ? RegExp('DH|指名打者').hasMatch(detail(r))
                                  : detail(r).contains(p)), side: side)
                  ],
                  color),
          ]));
    }
    return SizedBox(
        key: ValueKey('titles-grid-$key'),
        width: gridWidth(dh ? 1540.0 : 1400.0, availableWidth),
        child: Column(children: [
          label(title, color),
          leagueLine([for (final p in headers) label(p, color)]),
          for (final side in ['セ', 'パ'])
            IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: leagueColumnWidth, child: label(side, side == 'セ' ? central : pacific, height: 48)),
              for (final p in positions.take(6)) Expanded(child: winners(rows(key, side: side, where: (r) => detail(r).contains(p)), side: side)),
              // Official awards often name three outfielders without left/center/right assignments.
              Expanded(flex: 3, child: winners(rows(key, side: side, where: (r) => RegExp('外野|左翼|中堅|右翼').hasMatch(detail(r))), side: side)),
              if (dh) Expanded(child: winners(rows(key, side: side, where: (r) => RegExp('DH|指名打者').hasMatch(detail(r))), side: side)),
            ])),
        ]));
  }

  double leagueAwardsWidth(BuildContext context) {
    var unit = 70.0;
    for (final key in ['league_champion', 'league_mvp', 'series_entrants', 'cs_mvp']) {
      final weight = ['league_champion', 'series_entrants'].contains(key) ? 3 : 2;
      for (final row in rows(key)) {
        final painter = TextPainter(text: TextSpan(text: "${row['name'] ?? '—'}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
        unit = math.max(unit, (painter.width + 24) / weight);
        painter.dispose();
      }
    }
    return unit * 11;
  }

  double gridWidth(double minimum, double available) => available >= 1066 ? available : math.max(minimum, available);

  Widget leagueAwards(double width, {bool portrait = false}) {
    const awards = [
      ('リーグ優勝', 'league_champion'),
      ('リーグMVP', 'league_mvp'),
      ('CS優勝', 'series_entrants'),
      ('CSMVP', 'cs_mvp'),
    ];
    List<Map<String, dynamic>> selected(String key, String side) => rows(key).where((r) => league((key == 'league_champion' || key == 'series_entrants') ? {...r, 'team': r['name']} : r) == side).toList();
    final unknown = [
      for (final (_, key) in awards) ...rows(key).where((r) => league((key == 'league_champion' || key == 'series_entrants') ? {...r, 'team': r['name']} : r).isEmpty)
    ];
    if (portrait) {
      return SizedBox(
          key: const ValueKey('titles-grid-league'),
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            verticalLeagueHeader('リーグ表彰'),
            for (final (title, key) in awards)
              verticalRow(
                  title,
                  [
                    for (final side in ['セ', 'パ']) winners(selected(key, side), showLogo: key == 'league_champion' || key == 'series_entrants', side: side)
                  ],
                  red),
            if (unknown.isNotEmpty) winners(unknown),
          ]));
    }
    return SizedBox(
        key: const ValueKey('titles-grid-league'),
        width: width,
        child: Column(children: [
          leagueLine([label('', orange), for (final (title, _) in awards) label(title, red)], weights: const [1, 3, 2, 3, 2]),
          for (final side in ['セ', 'パ']) leagueLine([label(side, side == 'セ' ? central : pacific), for (final (_, key) in awards) winners(selected(key, side), showLogo: key == 'league_champion' || key == 'series_entrants', side: side)], weights: const [1, 3, 2, 3, 2]),
          if (unknown.isNotEmpty) winners(unknown),
        ]));
  }

  Widget statistical({double availableWidth = 0, bool farm = false, bool portrait = false}) {
    const titles = [
      ('最多勝', '最多勝利'),
      ('最優秀防御率', '最優秀防御率'),
      ('奪三振王', '最多奪三振'),
      ('最高勝率', '最高勝率'),
      ('最優秀中継ぎ', '最優秀中継ぎ'),
      ('セーブ王', '最多セーブ'),
      ('首位打者', '首位打者'),
      ('本塁打王', '本塁打王'),
      ('打点王', '打点王'),
      ('盗塁王', '盗塁王'),
      ('最多安打', '最多安打'),
      ('最高出塁率', '最高出塁率'),
    ];
    final sides = farm ? (year >= 2026 ? ['東地区', '中地区', '西地区'] : ['イースタン', 'ウエスタン']) : ['セ', 'パ'];
    Widget result(String side, String normalized) => winners(
        rows(farm ? 'farm_major' : 'major', side: farm ? null : side, where: (r) {
          if (farm && r['farm_league'] != side) return false;
          final name = farm ? '${r['award_label'] ?? ''}' : detail(r).replaceFirst(RegExp(r'^.*?リーグ\s*'), '');
          return recordAwardLabel(name.replaceFirst(RegExp(r'賞$'), '')) == normalized;
        }),
        empty: farm && normalized == '最優秀中継ぎ' ? 'ー' : '未定',
        showStatus: !farm, side: side);
    if (portrait) {
      return SizedBox(
          key: ValueKey(farm ? 'titles-grid-farm' : 'titles-grid-statistical'),
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label(farm ? '2軍 個人タイトル' : '個人タイトル', gold),
            verticalLeagueHeader('タイトル', sides: sides),
            for (var i = 0; i < titles.length; i++) verticalRow(titles[i].$1, [for (final side in sides) result(side, titles[i].$2)], i < 6 ? blue : pink),
          ]));
    }
    return SizedBox(
        key: ValueKey(farm ? 'titles-grid-farm' : 'titles-grid-statistical'),
        width: gridWidth(1820.0, availableWidth),
        child: Column(children: [
          leagueLine([label(farm ? '2軍 個人タイトル' : '個人タイトル', const Color(0xfff2e2ac)), for (var i = 0; i < titles.length; i++) label(titles[i].$1, i < 6 ? blue : pink)]),
          for (final side in (farm ? (year >= 2026 ? ['東地区', '中地区', '西地区'] : ['イースタン', 'ウエスタン']) : ['セ', 'パ']))
            leagueLine([
              label(side, side == 'セ' ? central : pacific),
              for (final (_, normalized) in titles)
                winners(
                    rows(farm ? 'farm_major' : 'major', side: farm ? null : side, where: (r) {
                      if (farm && r['farm_league'] != side) return false;
                      final name = farm ? '${r['award_label'] ?? ''}' : detail(r).replaceFirst(RegExp(r'^.*?リーグ\s*'), '');
                      return recordAwardLabel(name.replaceFirst(RegExp(r'賞$'), '')) == normalized;
                    }),
                    empty: farm && normalized == '最優秀中継ぎ' ? 'ー' : '未定',
                    showStatus: !farm, side: side),
            ]),
        ]));
  }

  Widget sayonara({double availableWidth = 0, bool portrait = false}) {
    const months = ['3・4', '5', '6', '7', '8', '9・10'];
    if (portrait) {
      return SizedBox(
          key: const ValueKey('titles-grid-sayonara'),
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label('スカパー！サヨナラ賞', purple),
            verticalLeagueHeader('月'),
            for (final month in months)
              verticalRow(
                  '$month月',
                  [
                    for (final side in ['セ', 'パ']) winners(sayonaraWinners(month, side), showVideo: true, side: side)
                  ],
                  purple),
          ]));
    }
    return SizedBox(
      key: const ValueKey('titles-grid-sayonara'),
      width: gridWidth(1820, availableWidth),
      child: Column(children: [
        label('スカパー！サヨナラ賞', purple),
        leagueLine([label('', purple), for (final month in months) label('$month月', purple)]),
        for (final side in ['セ', 'パ'])
          leagueLine([
            label(side, side == 'セ' ? central : pacific),
            for (final month in months) winners(sayonaraWinners(month, side), showVideo: true, side: side),
          ]),
      ]),
    );
  }

  Widget monthly({double availableWidth = 0, bool portrait = false}) {
    const months = ['3・4', '5', '6', '7', '8', '9・10'];
    if (portrait) {
      return SizedBox(
          key: const ValueKey('titles-grid-monthly'),
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label('月間MVP', purple),
            verticalLeagueHeader('月／区分'),
            for (final month in months) ...[
              label('$month月', purple),
              for (final role in ['投手', '野手'])
                verticalRow(
                    role,
                    [
                      for (final side in ['セ', 'パ']) winners(monthlyWinners(month, side, role), side: side)
                    ],
                    purple),
            ],
          ]));
    }
    return SizedBox(
        key: const ValueKey('titles-grid-monthly'),
        width: gridWidth(1820.0, availableWidth),
        child: Column(children: [
          leagueLine([label('月間MVP', purple), for (final month in months) label('$month月月間MVP', purple)], weights: const [13, 20, 20, 20, 20, 20, 20]),
          for (final side in ['セ', 'パ'])
            leagueLine([
              label(side, side == 'セ' ? central : pacific),
              for (final month in months)
                for (final role in ['投手', '野手']) winners(monthlyWinners(month, side, role), empty: '$role：未定', side: side),
            ], weights: const [
              13,
              10,
              10,
              10,
              10,
              10,
              10,
              10,
              10,
              10,
              10,
              10,
              10
            ]),
        ]));
  }

  Widget weekly({double availableWidth = 0, bool portrait = false}) {
    const months = ['3・4', '5', '6', '7', '8', '9・10'];
    const tint = Color(0xffc8bcdf);
    DateTime? published(Map<String, dynamic> row) {
      final match = RegExp(r'(\d{4})/(\d{1,2})/(\d{1,2})発表').firstMatch(detail(row));
      if (match == null) return null;
      final date = DateTime(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
      return date.year == year && date.month == int.parse(match[2]!) && date.day == int.parse(match[3]!) ? date : null;
    }

    String bucket(DateTime date) => date.month == 3 || date.month == 4
        ? '3・4'
        : date.month == 9 || date.month == 10
            ? '9・10'
            : '${date.month}';
    bool classified(Map<String, dynamic> row) {
      final date = published(row);
      return date != null && months.contains(bucket(date)) && ['セ', 'パ'].contains(league(row)) && RegExp('投手|野手|打者').hasMatch(detail(row));
    }

    final values = rows('weekly');
    final dates = {for (final month in months) month: values.where(classified).map((r) => published(r)!).where((date) => bucket(date) == month).toSet().toList()..sort()};
    final count = dates.values.fold<int>(4, (n, list) => list.length > n ? list.length : n);
    final unclassified = values.where((r) => !classified(r)).toList();
    List<Map<String, dynamic>> selected(int week, String month, String side, String role) => values.where((r) => classified(r) && league(r) == side && dates[month]!.length > week && published(r) == dates[month]![week] && (role == '投手' ? detail(r).contains('投手') : RegExp('野手|打者').hasMatch(detail(r)))).toList();
    if (portrait) {
      return SizedBox(
          key: const ValueKey('titles-grid-weekly'),
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label('週間MVP', tint),
            for (final month in months) ...[
              verticalLeagueHeader('$month月'),
              for (var week = 0; week < count; week++)
                for (final role in ['投手', '野手'])
                  verticalRow(
                      '${week + 1}週目\n$role',
                      [
                        for (final side in ['セ', 'パ']) winners(selected(week, month, side, role), empty: 'ー', side: side)
                      ],
                      tint),
            ],
            const Padding(padding: EdgeInsets.all(8), child: Text('週間MVPは各月区分の発表日順です（対象試合の週番号ではありません）。選手名に発表日・出典を表示します。', style: TextStyle(fontSize: 12))),
            if (unclassified.isNotEmpty) ...[
              verticalLabel('週間MVP（月・リーグ・部門の区分未確認）', tint),
              winners(unclassified),
            ],
          ]));
    }
    Widget leagueRow(int week, String side) => line([
          label(side, side == 'セ' ? central : pacific),
          for (final month in months)
            for (final role in ['投手', '野手']) winners(selected(week, month, side, role), empty: 'ー', side: side),
        ], weights: const [
          3,
          10,
          10,
          10,
          10,
          10,
          10,
          10,
          10,
          10,
          10,
          10,
          10
        ]);
    return SizedBox(
        key: const ValueKey('titles-grid-weekly'),
        width: gridWidth(1820.0, availableWidth),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          line([label('', tint), label('', tint), for (final month in months) label('週間MVP（$month月）', tint)], weights: const [10, 3, 20, 20, 20, 20, 20, 20]),
          for (var week = 0; week < count; week++)
            IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 10, child: cell(Text('${week + 1}週目', style: const TextStyle(color: ink, fontWeight: FontWeight.w600)), color: tint)),
              Expanded(
                  flex: 123,
                  child: Column(children: [
                    leagueRow(week, 'セ'),
                    leagueRow(week, 'パ'),
                  ])),
            ])),
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('週間MVPは各月区分の発表日順です（対象試合の週番号ではありません）。選手名に発表日・出典を表示します。', style: TextStyle(fontSize: 12))),
          if (unclassified.isNotEmpty) ...[
            label('週間MVP（月・リーグ・部門の区分未確認）', tint),
            winners(unclassified),
          ],
        ]));
  }

  Widget portraitBoard() => Column(
        key: const ValueKey('titles-portrait-board'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          verticalAwards(
              'series',
              const [
                ('日本一', 'series_champion'),
                ('日本シリーズMVP', 'series_mvp'),
                ('日本シリーズ敢闘選手賞', 'series_fighting'),
                ('日本シリーズ優秀選手賞', 'series_outstanding'),
              ],
              red),
          leagueAwards(0, portrait: true),
          verticalAwards(
              'special-awards',
              const [
                ('最優秀監督賞', 'manager'),
                ('沢村栄治賞', 'sawamura'),
                ('長嶋茂雄賞', 'nagashima'),
                ('正力松太郎賞', 'shoriki'),
                ('正力松太郎賞 特別賞', 'shoriki_special'),
                ('連盟特別表彰（功労賞）', 'league_merit'),
                ('連盟特別表彰（特別賞）', 'league_special'),
                ('コミッショナー特別表彰', 'commissioner_special'),
                ('スピードアップ賞', 'speedup'),
                ('HIKESHI賞', 'hikeshi'),
              ],
              red),
          positions('best9', 'ベストナイン', orange, dh: true, portrait: true),
          positions('glove', 'ゴールデングラブ賞', gold, portrait: true),
          statistical(portrait: true),
          verticalAwards(
              'events',
              const [
                ('交流戦優勝', 'interleague_champion'),
                ('交流戦MVP', 'interleague_mvp'),
                ('交流戦優秀選手', 'interleague_outstanding'),
                ('フレッシュオールスター優勝', 'fresh_champion'),
                ('フレッシュオールスターMVP', 'fresh_mvp'),
                ('オールスター優勝', 'allstar_champion'),
                ('オールスターMVP', 'allstar_mvp'),
                ('ホームランダービー優勝', 'derby'),
                ('新人王', 'rookie'),
              ],
              green,
              split: const {'interleague_outstanding', 'rookie'}),
          monthly(portrait: true),
          sayonara(portrait: true),
          weekly(portrait: true),
          statistical(farm: true, portrait: true),
          if (rows('records').isNotEmpty)
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              label('シーズン記録更新', blue),
              winners(rows('records')),
            ]),
        ].map((child) => Padding(padding: const EdgeInsets.only(bottom: 20), child: surface(child))).toList(),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final portrait = MediaQuery.orientationOf(context) == Orientation.portrait && constraints.maxWidth < 1066;
        final viewportWidth = math.max(0.0, constraints.maxWidth - 32);
        final availableWidth = math.max(0.0, viewportWidth - 2);
        final leagueWidth = math.max(availableWidth, math.max(840.0, leagueAwardsWidth(context)));
        return ColoredBox(
            color: const Color(0xfff6f8fb),
            child: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: purple, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.emoji_events_outlined, color: Color(0xff65519c), size: 24)),
                        const SizedBox(width: 12),
                        Flexible(child: Text('$year年 タイトル', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ink))),
                      ]),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('「現在首位」は受賞確定ではありません。未定の項目は受賞者を表示していません。\n${portrait ? '' : '表は左右にスクロールできます。'}外野手は発表区分に合わせてまとめて表示します。', style: const TextStyle(fontSize: 12, color: muted, height: 1.6))),
                      if (portrait)
                        portraitBoard()
                      else
                        SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                                width: math.max(leagueWidth + 2, gridWidth(1820, availableWidth) + 2),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                          key: const ValueKey('titles-grid-series'),
                                          width: leagueWidth,
                                          child: line([
                                            award('日本一', 'series_champion', red, headerHeight: 42),
                                            award('日本シリーズMVP', 'series_mvp', red, headerHeight: 42),
                                            award('日本シリーズ敢闘選手賞', 'series_fighting', red, headerHeight: 42),
                                            award('日本シリーズ優秀選手賞', 'series_outstanding', red, headerHeight: 42),
                                          ])),
                                      const SizedBox(height: 28),
                                      leagueAwards(leagueWidth),
                                      const SizedBox(height: 28),
                                      SizedBox(
                                          key: const ValueKey('titles-grid-special-awards'),
                                          width: gridWidth(1050, availableWidth),
                                          child: Column(children: [
                                            for (final awards in const [
                                              [
                                                ('最優秀監督賞', 'manager'),
                                                ('沢村栄治賞', 'sawamura'),
                                                ('長嶋茂雄賞', 'nagashima'),
                                                ('正力松太郎賞', 'shoriki'),
                                                ('正力松太郎賞 特別賞', 'shoriki_special'),
                                              ],
                                              [
                                                ('連盟特別表彰（功労賞）', 'league_merit'),
                                                ('連盟特別表彰（特別賞）', 'league_special'),
                                                ('コミッショナー特別表彰', 'commissioner_special'),
                                                ('スピードアップ賞', 'speedup'),
                                                ('HIKESHI賞', 'hikeshi'),
                                              ],
                                            ])
                                              line([
                                                for (final (title, key) in awards) award(title, key, red, headerHeight: 52),
                                              ]),
                                          ])),
                                      const SizedBox(height: 28),
                                      positions('best9', 'ベストナイン', orange, availableWidth: availableWidth, dh: true),
                                      const SizedBox(height: 28),
                                      positions('glove', 'ゴールデングラブ賞', gold, availableWidth: availableWidth),
                                      const SizedBox(height: 28),
                                      statistical(availableWidth: availableWidth),
                                      const SizedBox(height: 28),
                                      SizedBox(
                                          key: const ValueKey('titles-grid-events'),
                                          width: gridWidth(1540.0, availableWidth),
                                          child: line([
                                            award('交流戦\n優勝', 'interleague_champion', green, headerHeight: 84),
                                            award('交流戦\nMVP', 'interleague_mvp', green, headerHeight: 84),
                                            award('交流戦優秀選手', 'interleague_outstanding', green, split: true, headerHeight: 84),
                                            award('フレッシュ\nオールスター\n優勝', 'fresh_champion', green, headerHeight: 84),
                                            award('フレッシュ\nオールスター\nMVP', 'fresh_mvp', green, headerHeight: 84),
                                            award('オールスター\n優勝', 'allstar_champion', green, headerHeight: 84),
                                            award('オールスター\nMVP', 'allstar_mvp', green, headerHeight: 84),
                                            award('ホームラン\nダービー\n優勝', 'derby', green, headerHeight: 84),
                                            award('新人王', 'rookie', green, split: true, headerHeight: 84),
                                          ], weights: const [
                                            1,
                                            1,
                                            2,
                                            1,
                                            1,
                                            1,
                                            1,
                                            1,
                                            2
                                          ])),
                                      const SizedBox(height: 28),
                                      monthly(availableWidth: availableWidth),
                                      const SizedBox(height: 28),
                                      sayonara(availableWidth: availableWidth),
                                      const SizedBox(height: 28),
                                      weekly(availableWidth: availableWidth),
                                      const SizedBox(height: 28),
                                      statistical(availableWidth: availableWidth, farm: true),
                                      const SizedBox(height: 28),
                                      for (final entry in const {
                                        'records': 'シーズン記録更新',
                                      }.entries)
                                        if (rows(entry.key).isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 20), child: SizedBox(width: gridWidth(1440, availableWidth), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [label(entry.value, blue), winners(rows(entry.key))]))),
                                    ].map(surface).toList()))),
                    ]))));
      });
}
