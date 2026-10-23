import '../logic/auth_session.dart';
import '../logic/home_run_video.dart';
import '../tools/open_home_run_link.dart';
import 'package:Yakyuu_Japan/widgets/baseball_loading.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../tools/Env.dart';
import '../tools/json_utils.dart';
import '../logic/player_honors.dart';
import 'GamesBoard.dart' show GamePlayerAppearance;
import 'strength_contracts.dart' show contractSalaryLabel;

class PlayerDetailScope extends InheritedWidget {
  const PlayerDetailScope({super.key, required this.org, required this.year, required super.child});
  final String org;
  final int year;
  static PlayerDetailScope? of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<PlayerDetailScope>();
  @override
  bool updateShouldNotify(PlayerDetailScope old) => org != old.org || year != old.year;
}

Future<void> showPlayerDetail(BuildContext context, Map<String, dynamic> player) async {
  final scope = PlayerDetailScope.of(context);
  await showDialog<void>(context: context, builder: (_) => PlayerDetailDialog(player: playerDetailIdentity(player), org: scope?.org ?? player['org']?.toString() ?? ((int.tryParse('${player['id_league']}') ?? 0) >= 3 ? 'mlb' : 'npb'), year: scope?.year ?? int.tryParse('${player['int_year']}') ?? DateTime.now().year));
}

/// Preserve stable IDs; never interpret generic record IDs as player IDs.
Map<String, dynamic> playerDetailIdentity(Map<String, dynamic> player) {
  String first(List<String> fields) => fields.map((key) => '${player[key] ?? ''}'.trim()).firstWhere((v) => v.isNotEmpty, orElse: () => '');
  final name = first(['name_full', 'name_player', 'player_name', 'name']);
  final source = first(['source_player_id', 'official_source_player_id']);
  final url = first(['player_url', 'url']);
  final official = RegExp(r'/players/(\d+)\.html').firstMatch(url)?[1] ?? RegExp(r'^(?:npb|mlb):(\d+)$').firstMatch(first(['player_key']))?[1];
  return {...player, 'name': name, if (source.isNotEmpty || official != null) 'source_player_id': source.isNotEmpty ? source : official};
}

bool hasPlayerIdentity(Map<String, dynamic> player) {
  final p = playerDetailIdentity(player);
  return p['id_player'] != null || p['source_player_id'] != null || !{'', '—', 'ー', '-', '未定', '未取得'}.contains(p['name']);
}

class PlayerNameLink extends StatelessWidget {
  const PlayerNameLink({super.key, required this.player, required this.child, this.enabled = true});
  final Map<String, dynamic> player;
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) => !enabled || !hasPlayerIdentity(player) ? child : MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => showPlayerDetail(context, player), child: child));
}

class PlayerDetailDialog extends StatefulWidget {
  const PlayerDetailDialog({super.key, required this.player, required this.org, required this.year});
  final Map<String, dynamic> player;
  final String org;
  final int year;
  @override
  State<PlayerDetailDialog> createState() => _PlayerDetailDialogState();
}

class _PlayerDetailDialogState extends State<PlayerDetailDialog> {
  Map<String, dynamic> data = {};
  bool loading = true;
  String? error;
  final Map<String, Uri> _homeRunLinks = {};
  final Set<String> _homeRunChecked = {};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final p = widget.player;
      final q = <String, String>{'org': widget.org, 'year': '${widget.year}', 'name': '${p['name'] ?? p['name_full'] ?? p['name_player'] ?? p['player_name'] ?? ''}'.replaceAll(RegExp(r'\(.*\)$'), ''), if (p['id_player'] != null) 'id_player': '${p['id_player']}', if (p['source_player_id'] != null) 'source_player_id': '${p['source_player_id']}', if (p['id_team'] != null) 'id_team': '${p['id_team']}'};
      final r = await http.get(Env.api('/player-detail').replace(queryParameters: q)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (mounted) {
        setState(() => data = Map<String, dynamic>.from(d));
        prepareHomeRunVideos();
      }
    } catch (_) {
      if (mounted) setState(() => error = '選手情報を取得できませんでした。');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic> map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : {};
  Widget heading(String s) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 8), child: Text(s, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)));
  String hand(dynamic v) => switch ('$v') { '0' => '右', '1' => '左', '2' => '両', _ => '未確認' };

  double factsHeaderWidth(Iterable<String> labels) {
    final style = DefaultTextStyle.of(context).style.copyWith(fontWeight: FontWeight.bold, fontSize: 14);
    var headerWidth = 110.0;
    for (final label in labels) {
      final painter = TextPainter(text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout();
      if (painter.width + 20 > headerWidth) headerWidth = painter.width + 20;
      painter.dispose();
    }
    return headerWidth;
  }

  Widget facts(Map<String, dynamic> values, {Key? key, bool stretch = false, double? labelWidth}) {
    final headerWidth = labelWidth ?? factsHeaderWidth(values.keys);
    if (stretch) {
      return Column(key: key ?? const ValueKey('player-profile-grid'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final e in values.entries) Expanded(child: Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black12, width: .5)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: headerWidth, alignment: Alignment.centerLeft,
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0xffeceff1),
                border: Border(right: BorderSide(color: Colors.black12))),
              child: Text(e.key, softWrap: false, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            Expanded(child: Padding(padding: const EdgeInsets.all(8), child: Align(
              alignment: Alignment.centerLeft,
              child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 14), child: e.value is Widget ? e.value as Widget : Text(e.value == null || '${e.value}'.isEmpty ? '未確認' : '${e.value}'))))),
          ]),
        ))]);
    }
    return Table(
      key: key ?? const ValueKey('player-profile-grid'),
      columnWidths: {0: FixedColumnWidth(headerWidth)},
      border: TableBorder.all(color: Colors.black12),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final e in values.entries) TableRow(children: [TableCell(verticalAlignment: TableCellVerticalAlignment.fill, child: Container(color: const Color(0xffeceff1), padding: const EdgeInsets.all(8), alignment: Alignment.centerLeft, child: Text(e.key, softWrap: false, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)))), Padding(padding: const EdgeInsets.all(8), child: e.value is Widget ? e.value as Widget : Text(e.value == null || '${e.value}'.isEmpty ? '未確認' : '${e.value}'))])
      ]);
  }

  Widget profileOverview(String name, Map<String, dynamic> values, {bool pitching = false}) {
    final stats = <String, dynamic>{};
    for (final row in listMapFromJson(data['season_stats'])) {
      final title = '${row['title'] ?? ''}'.trim();
      if (pitching && {'代打起用数', '代打打率'}.contains(title)) continue;
      if (title.isEmpty || stats.containsKey(title)) continue;
      final value = '${row['stats'] ?? '—'}';
      final rank = int.tryParse('${row['int_rank']}');
      final ranked = rank != null && rank > 0 && rank < 1000 && value != '—';
      if (ranked && rank <= 3) {
        final colors = rank == 2
            ? const [Color(0xff929da7), Color(0xfff4f6f8), Color(0xffa6afb7)]
            : const [Color(0xffa26840), Color(0xffffd1a3), Color(0xffb4784b)];
        stats[title] = Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(value),
          Container(
            key: ValueKey('player-stat-medal-$title'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: rank == 1 ? const Color(0xffffd700) : null,
              image: rank == 1 ? const DecorationImage(
                image: AssetImage('backend/assets/images/analysis_grade_gold.jpg'), fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Color(0x66FFF2B0), BlendMode.screen)) : null,
              gradient: rank == 1 ? null : LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
              border: Border.all(color: rank == 1 ? const Color(0xffd6aa38) : colors.first),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('リーグ$rank位', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ]);
      } else {
        stats[title] = '$value（${ranked ? 'リーグ$rank位' : '順位なし'}）';
      }
    }
    final season = <String, dynamic>{
      ...stats,
    };
    if (season.isEmpty) return profileWithImage(name, values);
    if (MediaQuery.orientationOf(context) == Orientation.portrait) {
      return profileWithImage(name, {...values, ...season});
    }
    return LayoutBuilder(builder: (context, bounds) {
      final minimum = 1000 * MediaQuery.textScalerOf(context).scale(1);
      final width = bounds.maxWidth < minimum ? minimum : bounds.maxWidth;
      final entries = values.entries.toList();
      final split = entries.indexWhere((e) => e.key == 'Wikipedia');
      final upper = Map<String, dynamic>.fromEntries(split < 0 ? entries : entries.take(split));
      final lower = Map<String, dynamic>.fromEntries(split < 0 ? [] : entries.skip(split));
      final url = AuthSession.instance.showSpecialMedia ? map(data['character_image'])['url'] : null;
      final sharedHeaderWidth = factsHeaderWidth([...values.keys, ...season.keys]);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: width, child: Column(children: [
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (url is String) Container(
              key: const ValueKey('player-character-frame'), width: width * .336,
              decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
              child: Stack(children: [Positioned.fill(child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.network(Env.api(url).toString(), fit: BoxFit.contain,
                  cacheWidth: 640, cacheHeight: 960, semanticLabel: '$nameのキャラクターイラスト',
                  errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.person_outline, color: Colors.grey))),
              ))]),
            ),
            Expanded(child: facts(upper, stretch: true, labelWidth: sharedHeaderWidth)),
            Expanded(child: facts(season, stretch: true, labelWidth: sharedHeaderWidth,
              key: const ValueKey('player-season-stats-grid'))),
          ])),
          if (lower.isNotEmpty) facts(lower, labelWidth: sharedHeaderWidth, key: const ValueKey('player-profile-links-honors')),
        ])),
      );
    });
  }

  Widget profileWithImage(String name, Map<String, dynamic> values) {
    final url = AuthSession.instance.showSpecialMedia ? map(data['character_image'])['url'] : null;
    if (url is! String) return facts(values);
    final entries = values.entries.toList();
    final wikipediaIndex = entries.indexWhere((e) => e.key == 'Wikipedia');
    final split = wikipediaIndex < 0 ? entries.length : wikipediaIndex;
    final upper = Map<String, dynamic>.fromEntries(entries.take(split));
    final lower = Map<String, dynamic>.fromEntries(entries.skip(split));
    Widget image() => Image.network(Env.api(url).toString(), fit: BoxFit.contain,
      cacheWidth: 640, cacheHeight: 960,
      semanticLabel: '$nameのキャラクターイラスト',
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.person_outline, color: Colors.grey)));
    return LayoutBuilder(builder: (context, bounds) {
      if (MediaQuery.orientationOf(context) == Orientation.portrait) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            key: const ValueKey('player-character-frame'),
            height: (bounds.maxWidth * 1.5).clamp(200.0, 420.0),
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(border: Border(
              top: BorderSide(color: Colors.black12),
              left: BorderSide(color: Colors.black12),
              right: BorderSide(color: Colors.black12))),
            child: image(),
          ),
          facts(values),
        ]);
      }
      final width = bounds.maxWidth;
      return SizedBox(width: width, child: Column(children: [
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              key: const ValueKey('player-character-frame'),
              width: width * .48,
              decoration: const BoxDecoration(border: Border(
                top: BorderSide(color: Colors.black12),
                left: BorderSide(color: Colors.black12),
                bottom: BorderSide(color: Colors.black12))),
              child: Stack(children: [Positioned.fill(child: Padding(
                padding: const EdgeInsets.all(4),
                child: image(),
              ))]),
            ),
            Expanded(child: facts(upper, labelWidth: factsHeaderWidth(values.keys))),
          ])),
          if (lower.isNotEmpty) facts(lower, labelWidth: factsHeaderWidth(values.keys), key: const ValueKey('player-profile-links-honors')),
        ]));
    });
  }

  Widget usageBands({required bool batting, required bool pitching}) {
    int count(dynamic value) => (num.tryParse('$value')?.toInt() ?? 0).clamp(0, 100000);
    final usage = map(data['usage']);
    final roles = <String, int>{};
    if (pitching) {
      for (final row in listMapFromJson(usage['pitching_workload'])) {
        final appearances = count(row['appearances']);
        final starts = count(row['starts']).clamp(0, appearances);
        roles['先発'] = (roles['先発'] ?? 0) + starts;
        roles['救援'] = (roles['救援'] ?? 0) + appearances - starts;
      }
    }
    final positions = <String, int>{};
    if (batting) {
      for (final row in listMapFromJson(usage['positions'])) {
        final slot = '${row['slot'] ?? ''}';
        if (slot.isEmpty || slot.contains('投手')) continue;
        positions[slot] = (positions[slot] ?? 0) + count(row['count']);
      }
    }
    Widget band(Map<String, int> values, String label) {
      final entries = values.entries.where((e) => e.value > 0).toList();
      final total = entries.fold<int>(0, (sum, e) => sum + e.value);
      const colors = [Color(0xff527ca6), Color(0xff61a394), Color(0xffb38b55),
        Color(0xff8b78ae), Color(0xffc57b84), Color(0xff6e9fb6), Color(0xff929c55)];
      String text(int i) => '${entries[i].key} ${entries[i].value}回（${(entries[i].value * 100 / total).toStringAsFixed(1)}%）';
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(
          height: 30, child: Row(children: [
            for (var i = 0; i < entries.length; i++) Expanded(flex: entries[i].value,
              child: Tooltip(message: text(i), child: Semantics(label: text(i),
                child: Container(key: ValueKey('player-usage-${entries[i].key}'),
                  color: colors[i % colors.length], alignment: Alignment.center,
                  child: LayoutBuilder(builder: (context, bounds) => bounds.maxWidth < 60 * MediaQuery.textScalerOf(context).scale(1)
                    ? const SizedBox.shrink() : Text('${(entries[i].value * 100 / total).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                ))),
            ),
          ]))),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (var i = 0; i < entries.length; i++) Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 5), Text(text(i), style: const TextStyle(fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 8),
      ]);
    }
    final hasRoles = roles.values.any((n) => n > 0);
    final hasPositions = positions.values.any((n) => n > 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hasRoles) band(roles, '登板の内訳'),
      if (hasPositions) band(positions, '取得済みの守備位置別起用回数の内訳'),
      if (!hasRoles && !hasPositions) const Text('起用情報は未取得です。'),
    ]);
  }

  String careerSummary(Map<String, dynamic> roster, Map<String, dynamic> profile) {
    final names = <String>[];
    String? lastTeamId;
    void append(dynamic value, [dynamic teamId]) {
      final name = '${value ?? ''}'.trim();
      if (name.isEmpty) return;
      final id = teamId?.toString();
      if (names.isNotEmpty && (names.last == name || (id != null && id == lastTeamId))) {
        return;
      }
      names.add(name);
      lastTeamId = id;
    }

    for (final entry in listMapFromJson(roster['career_history'])) {
      append(entry['team']);
    }
    final seasons = listMapFromJson(data['careers']).toList()
      ..sort((a, b) {
        int number(dynamic value) => int.tryParse('$value') ?? 0;
        final year = number(a['int_year']).compareTo(number(b['int_year']));
        return year != 0 ? year : number(a['id']).compareTo(number(b['id']));
      });
    for (final season in seasons) {
      append(season['name_team'], season['id_team']);
    }
    append(profile['name_team'], profile['id_team']);
    return names.isEmpty ? '—' : names.join('→');
  }

  String careerValue(Map<String, dynamic> row, String key) {
    if (key == 'ops') {
      final obp = num.tryParse('${row['double_average_onbase']}');
      final slg = num.tryParse('${row['double_average_slugging']}');
      return obp == null || slg == null ? '—' : (obp + slg).toStringAsFixed(3);
    }
    final value = row[key];
    if (value == null) return '—';
    final number = num.tryParse('$value');
    if (number != null && key.startsWith('double_average')) {
      return number.toStringAsFixed(key == 'double_average_earned_runs' ? 2 : 3);
    }
    return '$value';
  }

  Widget history({required bool batting, required bool pitching}) {
    final columns = <String, String>{
      'int_year': '年',
      'name_team': '所属',
      'int_games': '試合',
      if (batting) ...{'int_appearance': '打席', 'int_batting': '打数', 'double_average_batting': '打率', 'int_hit1': '安打', 'int_homerun': '本塁打', 'int_rbi': '打点', 'int_steal_base': '盗塁', 'double_average_onbase': '出塁率', 'double_average_slugging': '長打率', 'ops': 'OPS', 'int_hit2': '二塁打', 'int_hit3': '三塁打', 'int_four_batting': '四球', 'int_strike_out_batting': '三振'},
      if (pitching) ...{'int_pitching': '登板', 'double_inning': '投球回', 'double_average_earned_runs': '防御率', 'int_win': '勝利', 'int_lose': '敗戦', 'double_average_win': '勝率', 'int_save': 'セーブ', 'int_hold': 'ホールド', 'int_hold_point': 'HP', 'int_strike_out_pitcher': '奪三振', 'int_four_pitcher': '与四球', 'int_hit_pitcher': '被安打', 'int_homerun_pitcher': '被本塁打', 'int_complete_game': '完投', 'int_shutout': '完封'}
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      heading('過去シーズン'),
      if (listMapFromJson(data['careers']).isEmpty)
        const Text('過去シーズンの成績は未取得です。')
      else
        LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: DataTable(
              border: TableBorder.all(color: const Color(0xffe0e5ec), width: .5),
              headingRowColor: const WidgetStatePropertyAll(Color(0xffe8edf3)),
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xff334155)),
              headingRowHeight: 40, dataRowMinHeight: 38, dataRowMaxHeight: 44,
              horizontalMargin: 14, columnSpacing: 20, columns: [
              for (final label in columns.values) DataColumn(label: Text(label))
            ], rows: [
              for (final entry in listMapFromJson(data['careers']).indexed) DataRow(
                color: WidgetStatePropertyAll(entry.$1.isEven ? Colors.white : const Color(0xfff5f7fa)),
                cells: [for (final k in columns.keys) DataCell(Text(careerValue(entry.$2, k)))])
            ])))))
    ]);
  }

  String recentOpponent(Map<String, dynamic> game) {
    String short(String name) {
      const aliases = {'西武': ['西武', 'ライオンズ'], 'ロッテ': ['ロッテ', 'マリーンズ'],
        'ソフトバンク': ['ソフトバンク', 'ホークス'], '日本ハム': ['日本ハム', 'ファイターズ'],
        '楽天': ['楽天', 'イーグルス'], 'オリックス': ['オリックス', 'バファローズ'],
        '阪神': ['阪神', 'タイガース'], '巨人': ['巨人', '読売', 'ジャイアンツ'],
        'DeNA': ['DeNA', 'ベイスターズ'], '広島': ['広島', 'カープ'],
        'ヤクルト': ['ヤクルト', 'スワローズ'], '中日': ['中日', 'ドラゴンズ']};
      if (widget.org == 'npb') {
        for (final entry in aliases.entries) {
          if (entry.value.any(name.contains)) return entry.key;
        }
      }
      return name;
    }
    if (game['opponent'] != null) return 'vs${short('${game['opponent']}')}';
    final team = short('${map(data['profile'])['name_team'] ?? widget.player['name_team'] ?? ''}');
    final home = short('${game['home'] ?? ''}'), away = short('${game['away'] ?? ''}');
    final opponent = team.isNotEmpty && team == home ? away : team.isNotEmpty && team == away ? home : '';
    return opponent.isEmpty ? '対戦相手未確認' : 'vs$opponent';
  }

  Widget recentTable(List<Map<String, dynamic>> games) {
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final rowHeight = 48.0 * scale;
    const widths = {0: FixedColumnWidth(92), 1: FixedColumnWidth(100)};
    const border = TableBorder(
      horizontalInside: BorderSide(color: Color(0xffdfe5ec), width: .5),
      verticalInside: BorderSide(color: Color(0xffdfe5ec), width: .5),
    );
    Widget bodyCell(Widget child) => SizedBox(height: rowHeight,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(alignment: Alignment.centerLeft, child: child)));
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Table(columnWidths: widths, border: border, children: [
          TableRow(decoration: const BoxDecoration(color: Color(0xffe8edf3)), children: [
            for (final title in ['日付', '対戦相手', '出場成績']) SizedBox(height: 40 * scale,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(alignment: Alignment.centerLeft, child: Text(title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))))),
          ]),
        ]),
        SizedBox(
          key: const ValueKey('recent-appearances-viewport'),
          height: rowHeight * games.length,
          child: Table(
              key: const ValueKey('recent-appearances-rows'),
              columnWidths: widths,
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: border,
              children: [for (final entry in games.indexed) TableRow(
                decoration: BoxDecoration(color: entry.$1.isEven ? Colors.white : const Color(0xfff5f7fa)),
                children: [
                  bodyCell(Text('${entry.$2['datetime_start']}'.split(RegExp('[ T]')).first, style: const TextStyle(fontSize: 12))),
                  bodyCell(Text(recentOpponent(entry.$2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  bodyCell(appearanceWithVideo(entry.$2)),
                ],
              )],
            ),
        ),
      ],
    ));
  }

  Future<void> prepareHomeRunVideos() async {
    final games = listMapFromJson(data['recent_games']).where(hasHomeRun).toList();
    if (games.isEmpty) return;
    List<dynamic> channels = [];
    try {
      final response = await http.get(Env.api('/videos').replace(queryParameters: {'org': widget.org}))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final feed = map(jsonDecode(utf8.decode(response.bodyBytes)));
        channels = feed['channels'] is List ? feed['channels'] as List : [];
      }
    } catch (_) {}
    // Resolve ahead of the click so browser user activation is preserved.
    for (final game in games) {
      if (!mounted) return;
      final uri = await resolveHomeRunVideo(game, channels);
      if (mounted) {
        setState(() {
          final key = '${game['datetime_start']}';
          _homeRunChecked.add(key);
          if (uri != null) _homeRunLinks[key] = uri;
        });
      }
    }
  }

  Future<Uri?> resolveHomeRunVideo(Map<String, dynamic> game, List<dynamic> channels) async {
    final profile = map(data['profile']);
    final name = '${profile['name_full'] ?? widget.player['name'] ?? ''}';
    final date =
        DateTime.tryParse('${game['datetime_start']}'.split(' ').first);
    if (name.isEmpty || date == null) return null;
    final pacific =
        '${profile['id_league'] ?? widget.player['id_league']}' == '2';
    final cachedId = matchingHomeRunVideo(channels, name, date, pacific: pacific);
    if (cachedId != null) return Uri.https('www.youtube.com', '/watch', {'v': cachedId});
    try {
      final response = await http
          .get(Env.api('/home-run-video').replace(queryParameters: {
            'name': name,
            'date': date.toIso8601String().split('T').first,
            'opponent': recentOpponent(game),
            'pacific': pacific ? '1' : '0',
          }))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final result = map(jsonDecode(utf8.decode(response.bodyBytes)));
        final id = matchingHomeRunVideo(
            result['channels'] is List ? result['channels'] as List : [],
            name,
            date,
            pacific: pacific);
        if (id != null) return Uri.https('www.youtube.com', '/watch', {'v': id});
      }
    } catch (_) {
      // No verified direct video: leave playback unavailable.
    }
    return null;
  }

  Widget appearanceWithVideo(Map<String, dynamic> game) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
            child: GamePlayerAppearance(
                org: widget.org,
                lines: listMapFromJson(game['lines']),
                plays: listMapFromJson(game['plays']))),
        if (hasHomeRun(game))
          Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                  message: _homeRunLinks['${game['datetime_start']}'] != null
                      ? 'この試合のホームラン動画を開く'
                      : _homeRunChecked.contains('${game['datetime_start']}') ? 'このホームランの動画を特定できませんでした' : 'ホームラン動画を確認中…',
                  child: Material(
                      color: _homeRunChecked.contains('${game['datetime_start']}') && !_homeRunLinks.containsKey('${game['datetime_start']}') ? Colors.grey : const Color(0xffff0000),
                      borderRadius: BorderRadius.circular(5),
                      child: InkWell(
                        key: ValueKey(
                            'home-run-video-${game['datetime_start']}'),
                        borderRadius: BorderRadius.circular(5),
                        onTap: _homeRunLinks['${game['datetime_start']}'] == null ? null : () async {
                          final opened = await openHomeRunLink(_homeRunLinks['${game['datetime_start']}']!);
                          if (!opened && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('動画を開けませんでした。')));
                        },
                        child: SizedBox(
                            width: 36, height: 24,
                            child: !_homeRunChecked.contains('${game['datetime_start']}')
                                ? const Center(child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                                : Icon(_homeRunLinks.containsKey('${game['datetime_start']}') ? Icons.play_arrow : Icons.videocam_off_outlined, size: 20, color: Colors.white)),
                      )))),
      ]);

  Future<void> showRecentBatting(String name, List<Map<String, dynamic>> games) => showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
            child: SizedBox(
                width: 1100,
                height: size.height * .8,
                child: Column(children: [
                  Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: Text('$name：直近25試合の出場成績', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), IconButton(tooltip: '閉じる', onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close))])),
                  Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (games.isEmpty) const Text('取得済みの出場成績がありません。') else recentTable(games), const SizedBox(height: 8), Text('${data['recent_note'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.blueGrey))])))
                ])));
      });

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: AuthSession.instance, builder: (_, __) => _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final profile = map(data['profile']), roster = map(data['roster']), verified = map(data['verified']);
    final position = '${profile['txt_position'] ?? widget.player['txt_position'] ?? roster['position'] ?? ''}';
    final twoWay = position.contains('二刀流') || RegExp(r'TWP|two.way', caseSensitive: false).hasMatch(position);
    final pitching = twoWay || position.contains('投手') || RegExp(r'^(P|SP|RP)$').hasMatch(position);
    final batting = twoWay || !pitching || RegExp('捕手|内野手|外野手|指名打者|DH').hasMatch(position);
    final honors = playerHonors(roster);
    final salaries = listMapFromJson(map(roster['contract_data'])['salary_history']).where((s) => int.tryParse('${s['year']}') == widget.year).toList();
    final games = listMapFromJson(data['recent_games']);
    final name = '${profile['name_full'] ?? widget.player['name'] ?? widget.player['name_player'] ?? widget.player['player_name'] ?? '選手詳細'}';
    return Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: size.width < 600 ? 8 : 40, vertical: 16),
        child: SizedBox(
            width: 1100,
            height: size.height - 32,
            child: Column(children: [
              Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))), IconButton(tooltip: '閉じる', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))])),
              Expanded(
                  child: loading
                      ? const Center(child: BaseballLoading())
                      : error != null
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(error!), TextButton(onPressed: load, child: const Text('再読み込み'))]))
                          : data['found'] == false
                              ? Center(child: Text('${data['message']}'))
                              : ListView(padding: const EdgeInsets.all(16), children: [
                                  profileOverview(name, {
                                    '所属': profile['name_team'],
                                    '生年月日': profile['date_birth'] == null ? null : '${profile['date_birth']}'.split(RegExp(r'[T\s]')).first,
                                    'ポジション': profile['txt_position'],
                                    '投打': '${hand(profile['pitching'])}投げ／${hand(profile['batting'])}打ち',
                                    '身長・体重': '${profile['height'] ?? '—'}cm / ${profile['weight'] ?? '—'}kg',
                                    '出身国': profile['birth_country'],
                                    '出身地': profile['birth_place'],
                                    '経歴': careerSummary(roster, profile),
                                    '${widget.year}年 年俸': salaries.isEmpty ? '今季の年俸情報は未収録です。' : salaries.map(contractSalaryLabel).join('\n'),
                                    for (final key in [
                                      '選手の特徴',
                                      '特技・趣味',
                                      if (batting) ...['打球速度', if (position.contains('捕手')) '二塁送球タイム', '一塁到達タイム', '遠投'],
                                      if (pitching) ...['投球速度', '変化球の球種']
                                    ])
                                      key: map(verified[key])['value'],
                                    'Wikipedia': Builder(builder: (context) {
                                    final stored = Uri.tryParse('${data['wikipedia_url'] ?? profile['wikipedia_url'] ?? ''}');
                                    final verified = stored != null && stored.scheme == 'https' && (stored.host == 'wikipedia.org' || stored.host.endsWith('.wikipedia.org'));
                                    final uri = verified ? stored : Uri.https('ja.wikipedia.org', '/w/index.php', {'search': '${name.replaceAll(RegExp(r'[\s　]'), '')} 野球'});
                                    return InkWell(
                                        key: const ValueKey('player-wikipedia-link'),
                                        onTap: () async {
                                          if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wikipediaを開けませんでした。')));
                                          }
                                        },
                                        child: Text(uri.toString(), style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                                      );
                                  }),
                                    '功績': ConstrainedBox(
                                      constraints: const BoxConstraints(minHeight: 100),
                                      child: Align(alignment: Alignment.centerLeft,
                                        child: honors.isEmpty
                                          ? const Text('確認済みの功績データは未収録です。')
                                          : Wrap(spacing: 8, runSpacing: 6, children: [
                                              for (final h in honors) Chip(label: Text('${h['year'] ?? ''} ${h['label']}')),
                                            ]),
                                      ),
                                    ),
                                  }, pitching: pitching),
                                  heading('今シーズンの起用'),
                                  usageBands(batting: batting, pitching: pitching),
                                  Row(children: [Expanded(child: heading('直近の試合の出場成績')),
                                    IconButton(tooltip: '直近25試合を表示', onPressed: () => showRecentBatting(name, games.take(25).toList()), icon: const Icon(Icons.more_horiz))]),
                                  if (games.isEmpty) const Text('取得済みの出場成績がありません。')
                                  else recentTable(games.take(10).toList()),
                                  history(batting: batting, pitching: pitching),
                                  const SizedBox(height: 20),

                                ]))
            ])));
  }
}
