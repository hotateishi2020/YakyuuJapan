import 'player_detail_dialog.dart';
import 'package:http/http.dart' as http;
import '../tools/Env.dart';
import 'compact_layout.dart';
import 'GamesBoard.dart' show teamLogoAsset;
import '../logic/draft_competition.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/baseball_loading.dart';

class DraftHistoryBoard extends StatefulWidget {
  const DraftHistoryBoard(
      {super.key, required this.year, this.activeDraft = false});
  final int year;
  final bool activeDraft;
  @override
  State<DraftHistoryBoard> createState() => _DraftHistoryBoardState();
}

class _DraftHistoryBoardState extends State<DraftHistoryBoard> {
  Map<String, dynamic>? _years;
  String? _team;
  int _mode = 0;
  int? _selectedYear;
  String? _error;
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = jsonDecode(await rootBundle.loadString(widget.activeDraft
          ? 'backend/assets/data/active_draft_history.json'
          : 'backend/assets/data/draft_history.json')) as Map<String, dynamic>;
      final years = Map<String, dynamic>.from(data['years'] as Map);
      if (!mounted) return;
      setState(() {
        _years = years;
        _error = null;
      });
      // Bundled history remains available if the research service is disabled.
      try {
        final response = await http
            .get(Env.api(
                '/draft-research?year=${widget.year}&active=${widget.activeDraft}'))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final updates = jsonDecode(utf8.decode(response.bodyBytes))['years'];
          if (updates is Map) {
            for (final entry in updates.entries) {
              final group = Map<String, dynamic>.from(entry.value as Map);
              final original =
                  Map<String, dynamic>.from(years[entry.key] as Map? ?? {});
              final picks = <Map<String, dynamic>>[
                for (final pick in original['picks'] as List? ?? [])
                  Map<String, dynamic>.from(pick as Map),
              ];
              for (final pick in group['picks'] as List? ?? []) {
                final item = Map<String, dynamic>.from(pick as Map);
                final index = picks.indexWhere((p) =>
                    p['team'] == item['team'] &&
                    p['name'] == item['name'] &&
                    p['type'] == item['type']);
                if (index < 0) {
                  picks.add(item);
                } else {
                  picks[index] = {...picks[index], ...item};
                }
              }
              years['${entry.key}'] = {...original, ...group, 'picks': picks};
            }
          }
        }
      } catch (_) {/* Keep the bundled historical results. */}

      if (!mounted) return;
      setState(() {
        _years = years;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'ドラフト記録を取得できませんでした');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        TextButton(onPressed: _load, child: const Text('再読み込み'))
      ]));
    }
    if (_years == null) return const BaseballLoading();
    final years = _years!.keys
        .map(int.parse)
        .where((y) => y <= widget.year)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (years.isEmpty) return const Center(child: Text('この年度までのドラフト記録はありません'));
    final selectedYear =
        years.contains(_selectedYear) ? _selectedYear! : years.first;
    final rows = <List<List<Map>>>[];
    var columns = 12;
    for (final year in years) {
      final picks = draftPicksWithCompetition(
          ((_years!['$year'] as Map)['picks'] as List).cast<Map>());
      if (_team == null) {
        rows.add([
          for (var i = 0; i < 12; i++)
            picks
                .where((p) =>
                    _matches(
                        i == 11 && year < 2005
                            ? '近鉄'
                            : _clubs.keys.elementAt(i),
                        '${p['team']}') &&
                    (widget.activeDraft ||
                        p['rank'] == '1' && p['type'] != '育成'))
                .toList(),
        ]);
      } else {
        final selected =
            picks.where((p) => _matches(_team!, '${p['team']}')).toList();
        selected.sort((a, b) {
          final category =
              (a['type'] == '育成' ? 1 : 0).compareTo(b['type'] == '育成' ? 1 : 0);
          if (category != 0) return category;
          final rank = (int.tryParse('${a['rank']}') ?? 0)
              .compareTo(int.tryParse('${b['rank']}') ?? 0);
          return rank != 0 ? rank : '${a['type']}'.compareTo('${b['type']}');
        });
        rows.add([
          for (final pick in selected) [pick]
        ]);
      }
    }
    if (_team != null) {
      columns =
          rows.fold<int>(1, (max, row) => row.length > max ? row.length : max);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.activeDraft)
        Row(children: [
          for (final entry in ['12球団1位指名', 'チーム別全年度', '年度ごと'].indexed)
            Flexible(
                flex: entry.$1 == 2 ? 2 : 3,
                child: Padding(
                  padding: EdgeInsets.only(right: entry.$1 == 2 ? 0 : 4),
                  child: ChoiceChip(
                    key: ValueKey('draft-mode-${entry.$1}'),
                    label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(entry.$2, maxLines: 1, softWrap: false)),
                    showCheckmark: false,
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    selected: _mode == entry.$1,
                    onSelected: (_) => setState(() {
                      _mode = entry.$1;
                      _team = _mode == 1 ? (_team ?? '巨人') : null;
                    }),
                  ),
                )),
        ]),
      if (!widget.activeDraft && _mode == 2)
        DropdownButton<int>(
          key: const ValueKey('draft-year-picker'),
          value: selectedYear,
          items: [
            for (final year in years)
              DropdownMenuItem(value: year, child: Text('$year年'))
          ],
          onChanged: (year) => setState(() => _selectedYear = year),
        ),
      if (!widget.activeDraft && _mode == 1)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            for (final team in _clubs.keys)
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Builder(builder: (context) {
                        final color = _colors[team]!;
                        final selected = _team == team;
                        return ChoiceChip(
                          key: ValueKey('draft-team-segment-$team'),
                          label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                  compactBaseballLayout(context)
                                      ? (_shortest[team] ?? team)
                                      : team,
                                  maxLines: 1,
                                  softWrap: false)),
                          padding: EdgeInsets.zero,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 2),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          tooltip: '$teamの全指名',
                          selected: selected,
                          showCheckmark: false,
                          backgroundColor: Color.lerp(color, Colors.white, .86),
                          selectedColor: color,
                          labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: selected && color.computeLuminance() < .45
                                  ? Colors.white
                                  : Colors.black87),
                          side: BorderSide(
                              color: selected
                                  ? color
                                  : Color.lerp(color, Colors.white, .65)!),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _team = team),
                        );
                      }))),
          ]),
        ),
      Expanded(
          child: _mode == 2
              ? _annualGrid(selectedYear)
              : LayoutBuilder(builder: (context, constraints) {
                  const yearWidth = 72.0;
                  final cellWidth = _team == null
                      ? ((constraints.maxWidth - yearWidth) / 12)
                          .clamp(88.0, 210.0)
                          .toDouble()
                      : 210.0;
                  final fontSize = cellWidth < 120
                      ? 10.0
                      : cellWidth < 160
                          ? 11.0
                          : 13.0;
                  Widget yearCell(Widget child) => _cell(child,
                      width: yearWidth,
                      background: Colors.black,
                      foreground: Colors.white);
                  Widget pinnedRow(List<Widget> cells, Widget year) =>
                      AnimatedBuilder(
                        animation: _horizontal,
                        builder: (context, _) => Stack(children: [
                          IntrinsicHeight(
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                const SizedBox(width: yearWidth),
                                ...cells,
                              ])),
                          Positioned(
                              left: _horizontal.hasClients
                                  ? _horizontal.offset
                                  : 0,
                              top: 0,
                              bottom: 0,
                              child: year),
                        ]),
                      );
                  return SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                        width: yearWidth + columns * cellWidth,
                        child: Column(children: [
                          pinnedRow(
                              [
                                for (var i = 0; i < columns; i++)
                                  _cell(
                                      SizedBox(
                                          height: 34,
                                          child: Center(
                                              child: Text(
                                            _team == null
                                                ? (i == 11
                                                    ? '楽天／近鉄'
                                                    : _clubs.keys.elementAt(i))
                                                : '指名順 ${i + 1}',
                                            key: ValueKey('draft-header-$i'),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontSize: fontSize,
                                                fontWeight: FontWeight.bold),
                                          ))),
                                      width: cellWidth,
                                      background: _colors[
                                          _team ?? _clubs.keys.elementAt(i)],
                                      foreground:
                                          (_team ?? _clubs.keys.elementAt(i)) ==
                                                  'ソフトバンク'
                                              ? Colors.black
                                              : Colors.white),
                              ],
                              yearCell(const Center(
                                  child: Text('年度',
                                      key: ValueKey('draft-year-header'),
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold))))),
                          Expanded(
                              child: ListView.builder(
                            key: ValueKey('draft-grid-${_team ?? "all"}'),
                            itemCount: years.length,
                            itemBuilder: (context, index) => pinnedRow(
                                [
                                  for (var i = 0; i < columns; i++)
                                    _cell(
                                        i >= rows[index].length ||
                                                rows[index][i].isEmpty
                                            ? const SizedBox(
                                                height: 72, child: Text('—'))
                                            : Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                    for (final entry
                                                        in rows[index][i]
                                                            .indexed)
                                                      if (entry.$1 ==
                                                          rows[index][i]
                                                                  .length -
                                                              1)
                                                        Expanded(
                                                            child: _pick(
                                                                entry.$2,
                                                                year: years[
                                                                    index],
                                                                fontSize:
                                                                    fontSize))
                                                      else
                                                        _pick(entry.$2,
                                                            year: years[index],
                                                            fontSize: fontSize),
                                                  ]),
                                        width: cellWidth),
                                ],
                                yearCell(Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('${years[index]}年',
                                              style: TextStyle(
                                                  fontSize: fontSize,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      TextButton(
                                          style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              minimumSize: Size.zero,
                                              padding: const EdgeInsets.all(4)),
                                          onPressed: () => launchUrl(
                                              Uri.parse(
                                                  (_years!['${years[index]}']
                                                          as Map)['source']
                                                      as String),
                                              mode: LaunchMode
                                                  .externalApplication),
                                          child: const Text('出典',
                                              style: TextStyle(fontSize: 10))),
                                      if (years[index] == 1978 &&
                                          (_team == null || _team == '巨人'))
                                        const Text('巨人不参加',
                                            style: TextStyle(fontSize: 9)),
                                    ]))),
                          )),
                        ])),
                  );
                })),
      if (!widget.activeDraft)
        const Text('オレンジ：競合抽選で交渉権獲得　青：再指名（抽選落選あり）',
            style: TextStyle(fontSize: 11)),
      if (!widget.activeDraft)
        const Text('当時の球団名・制度を併記。楽天／近鉄列は2004年以前が近鉄（別球団）。',
            style: TextStyle(fontSize: 11, color: Colors.black54)),
    ]);
  }

  Widget _annualGrid(int year) {
    final picks = draftPicksWithCompetition(
        ((_years!['$year'] as Map)['picks'] as List).cast<Map>());
    String slot(Map pick) => '${pick['type']}|${pick['rank']}';
    final slots = {for (final pick in picks) slot(pick)}.toList()
      ..sort((a, b) {
        final aa = a.split('|'), bb = b.split('|');
        final category =
            (aa[0] == '育成' ? 1 : 0).compareTo(bb[0] == '育成' ? 1 : 0);
        if (category != 0) return category;
        final type = aa[0].compareTo(bb[0]);
        return type != 0
            ? type
            : (int.tryParse(aa[1]) ?? 0).compareTo(int.tryParse(bb[1]) ?? 0);
      });
    return LayoutBuilder(builder: (context, constraints) {
      const side = 80.0;
      final width = ((constraints.maxWidth - side) / 12).clamp(100.0, 210.0);
      final clubs = _clubs.keys.take(12).toList();
      final widths = <int, TableColumnWidth>{
        0: const FixedColumnWidth(side),
        for (var i = 1; i <= 12; i++) i: FixedColumnWidth(width)
      };
      return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: side + 12 * width,
            child: Column(children: [
              Table(columnWidths: widths, children: [
                TableRow(children: [
                  _cell(
                      const SizedBox(
                          height: 36, child: Center(child: Text('指名順位'))),
                      width: side,
                      background: Colors.black,
                      foreground: Colors.white),
                  for (final club in clubs)
                    _cell(
                        SizedBox(
                            height: 36,
                            child: Center(
                                child: Text(club == '楽天' && year < 2005
                                    ? '近鉄'
                                    : club))),
                        width: width,
                        background: _colors[club],
                        foreground:
                            club == 'ソフトバンク' ? Colors.black : Colors.white),
                ])
              ]),
              Expanded(
                  child: SingleChildScrollView(
                      key: const ValueKey('draft-annual-grid'),
                      child: Table(
                        columnWidths: widths,
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.intrinsicHeight,
                        children: [
                          for (final key in slots)
                            TableRow(children: [
                              _cell(
                                  Center(
                                      child: Text(
                                          '${key.split('|')[0] == '-' ? '' : key.split('|')[0]} ${key.split('|')[1]}位')),
                                  width: side,
                                  background: Colors.black,
                                  foreground: Colors.white),
                              for (final club in clubs)
                                _cell(
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (final pick in picks.where((p) =>
                                              slot(p) == key &&
                                              _matches(
                                                  club == '楽天' && year < 2005
                                                      ? '近鉄'
                                                      : club,
                                                  '${p['team']}')))
                                            _pick(pick,
                                                year: year,
                                                fontSize:
                                                    width < 120 ? 10 : 12),
                                        ]),
                                    width: width),
                            ])
                        ],
                      ))),
            ]),
          ));
    });
  }

  static const _shortest = {
    '巨人': '巨',
    '阪神': '神',
    'DeNA': 'デ',
    '広島': '広',
    'ヤクルト': 'ヤ',
    '中日': '中',
    'ソフトバンク': 'ソ',
    '日本ハム': '日',
    'ロッテ': 'ロ',
    'オリックス': 'オ',
    '西武': '西',
    '楽天': '楽',
    '近鉄': '近'
  };
  static const _clubs = <String, List<String>>{
    '巨人': ['巨人'],
    '阪神': ['阪神'],
    'DeNA': ['DeNA', '横浜', '大洋'],
    '広島': ['広島'],
    'ヤクルト': ['ヤクルト', 'アトムズ', 'サンケイ'],
    '中日': ['中日'],
    'ソフトバンク': ['ソフトバンク', 'ダイエー', '南海'],
    '日本ハム': ['日本ハム', '日拓', '東映'],
    'ロッテ': ['ロッテ', '東京'],
    'オリックス': ['オリックス', '阪急'],
    '西武': ['西武', 'クラウン', '太平洋', '西鉄'],
    '楽天': ['楽天'],
    '近鉄': ['近鉄'],
  };
  bool _matches(String club, String name) => _clubs[club]!.contains(name);

  static const _colors = <String, Color>{
    '巨人': Color(0xFFF08300),
    '阪神': Color(0xFF222222),
    'DeNA': Color(0xFF0052A4),
    '広島': Color(0xFFCE0000),
    'ヤクルト': Color(0xFF006633),
    '中日': Color(0xFF003E8F),
    'ソフトバンク': Color(0xFFF5C700),
    '日本ハム': Color(0xFF0067A5),
    'ロッテ': Color(0xFF222222),
    'オリックス': Color(0xFF000033),
    '西武': Color(0xFF003147),
    '楽天': Color(0xFF870011),
    '近鉄': Color(0xFF003399),
  };

  Widget _cell(Widget child,
          {double width = 210, Color? background, Color? foreground}) =>
      Container(
        width: width,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: background ?? Colors.white,
            border: Border.all(color: Colors.grey.shade300)),
        child: DefaultTextStyle.merge(
            style: TextStyle(color: foreground), child: child),
      );

  Widget _competitionLogo(String team, int year) {
    final historical = switch (team) {
      '南海' => 'nankai_hawks.png',
      'ダイエー' => 'daiei.jpg',
      '阪急' => 'hankyu.jpg',
      '近鉄' => 'kintetsu.jpg',
      '西鉄' => 'nishitetsu.jpg',
      '太平洋' => 'taiheiyo_club.jpg',
      'クラウン' => 'crown_lighter.jpg',
      '東映' => 'toei.jpg',
      '日拓' => 'nittaku.png',
      '東京' => 'tokyo_orions.jpg',
      '大洋' => year < 1978 ? 'taiyo.jpg' : 'yokohama_whales.jpg',
      'サンケイ' when year >= 1966 => 'sankei_atoms.png',
      'アトムズ' => 'yakult_atoms.png',
      'ヤクルト' when year <= 1973 => 'yakult_atoms.png',
      'オリックス' when year <= 1990 => 'orix_braves.webp',
      'オリックス' when year <= 2004 => 'bluewave.jpg',
      'ロッテ' when year <= 1991 => 'lotte_orions.jpg',
      '日本ハム' when year <= 2003 => 'nipponham.jpg',
      '西武' when year <= 2007 => 'seibu.jpg',
      '横浜' => 'yokohama.jpg',
      _ => null,
    };
    final asset = historical != null
        ? 'backend/assets/images/thumb_history_$historical'
        : teamLogoAsset(team);
    Widget fallback() =>
        FittedBox(child: Text(team, style: const TextStyle(fontSize: 10)));
    return Tooltip(
        message: '$team（$year年・競合）',
        child: Semantics(
          label: '競合球団 $team',
          image: asset != null,
          child: SizedBox(
              width: 24,
              height: 24,
              child: asset == null
                  ? fallback()
                  : Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      cacheWidth: 72,
                      errorBuilder: (_, __, ___) => fallback(),
                    )),
        ));
  }

  Widget _pick(Map p, {required int year, double fontSize = 13}) {
    final count = p['competition'] as int?;
    final teams =
        (p['competition_teams'] as List?)?.cast<String>() ?? <String>[];
    final note = '${p['note'] ?? ''}';
    final type = '${p['type'] ?? ''}';
    final category = type == '-' || type.isEmpty
        ? ''
        : (type == '1' || type == '2' ? '第$type回 ' : '$type ');
    final rank = '${p['rank']}';
    return Container(
      padding: const EdgeInsets.all(3),
      color: count != null
          ? Colors.orange.shade50
          : note.contains('×')
              ? Colors.blue.shade50
              : null,
      child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: fontSize),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!widget.activeDraft)
              Text(
                  '${p['team']}　$category${int.tryParse(rank) != null ? '$rank位' : rank}',
                  style: TextStyle(fontSize: fontSize)),
            PlayerNameLink(
                player: Map<String, dynamic>.from(p),
                child: Text('${p['name']}${count == null ? '' : '　$count球団競合'}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: count != null
                            ? Colors.deepOrange.shade800
                            : null))),
            if (count != null) ...[
              if (teams.isEmpty)
                Text('競合球団：未確認', style: TextStyle(fontSize: fontSize))
              else
                Wrap(spacing: 3, runSpacing: 3, children: [
                  for (final team in teams) _competitionLogo(team, year),
                ]),
              if (teams.isNotEmpty && teams.length < count)
                Text('一部未確認', style: TextStyle(fontSize: fontSize)),
            ],
            if (widget.activeDraft) ...[
              Text('${p['position']}'),
              Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('前所属：'),
                    Container(
                      key: ValueKey('active-draft-former-$year-${p['name']}'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                          color: _colors['${p['from']}'] ?? Colors.blueGrey,
                          borderRadius: BorderRadius.circular(3)),
                      child: Text('${p['from']}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: p['from'] == 'ソフトバンク'
                                  ? Colors.black
                                  : Colors.white)),
                    ),
                  ]),
            ] else
              Text('${p['position']}・${p['from']}'),
            if ('${p['status'] ?? ''}'.isNotEmpty)
              Text('${p['status']}', style: TextStyle(fontSize: fontSize)),
            if (note.isNotEmpty)
              Text('抽選・備考：$note', style: TextStyle(fontSize: fontSize)),
          ])),
    );
  }
}
