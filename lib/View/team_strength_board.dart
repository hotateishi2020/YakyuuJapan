import 'strength_research.dart';
import 'strength_careers.dart';
import '../tools/network_error.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_design.dart';
import '../config/org_config.dart';
import '../tools/Env.dart';
import '../tools/color_parse.dart';
import '../tools/json_utils.dart';
import 'strength_vertical_label.dart';
import 'strength_grids.dart';
import '../logic/strength_usage.dart';
import '../logic/strength_analytics.dart';
import 'strength_contracts.dart';

/// 戦力タブを開いたときだけ、登録済みの球団別データを取得する。
class TeamStrengthBoard extends StatefulWidget {
  const TeamStrengthBoard({super.key, required this.org, required this.year});

  final OrgConfig org;
  final int year;

  @override
  State<TeamStrengthBoard> createState() => _TeamStrengthBoardState();
}

class _TeamStrengthBoardState extends State<TeamStrengthBoard> {
  List<Map<String, dynamic>> _teams = const [];
  int? _selectedTeam;
  bool _loading = true;
  String? _error;
  int _request = 0;
  int _selectedView = 1;
  final _comparisonViews = <int>{4};
  static const _bandSideWidth = 88 * 1.2 + 8 + 48;
  static const _views = [
    '成績',
    '選手起用',
    '主力選手',
    '選手一覧',
    '契約',
    'ドラフト',
    '功績',
    '経歴'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TeamStrengthBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.org.kind != widget.org.kind ||
        oldWidget.year != widget.year) {
      _teams = const [];
      _selectedTeam = null;
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http
          .get(Env.api(
              '/team-strength?org=${widget.org.kind.name}&year=${widget.year}'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const FormatException('戦力情報を取得できませんでした');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map) throw const FormatException('戦力情報を取得できませんでした');
      if (!mounted || request != _request) return;
      setState(() {
        _teams = listMapFromJson(data['teams']);
        if (!_teams.any((team) => _int(team['id_team']) == _selectedTeam)) {
          _selectedTeam = _teams.isEmpty ? null : _int(_teams.first['id_team']);
        }
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _error =
          networkErrorMessage(e, fallback: '戦力情報を取得できませんでした。再読み込みしてください。'));
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _viewTabs(),
          const SizedBox(height: 6),
          Expanded(child: _content(context)),
        ],
      );

  Widget _viewTabs() => SizedBox(
        height: TAB_BAR_H,
        child: Row(children: [
          for (var index = 0; index < _views.length; index++) ...[
            if (index > 0) const SizedBox(width: ALL_SPACE_BLOCK),
            Expanded(
              child: Semantics(
                selected: _selectedView == index,
                child: Material(
                  color: _selectedView == index
                      ? widget.org.tabColor
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(TAB_RADIUS),
                  child: InkWell(
                    key: ValueKey('strength-view-$index'),
                    onTap: () => setState(() => _selectedView = index),
                    borderRadius: BorderRadius.circular(TAB_RADIUS),
                    child: Center(
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_views[index],
                              style: TextStyle(
                                fontSize: 12,
                                height: 1,
                                fontWeight: _selectedView == index
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _selectedView == index
                                    ? TAB_COLOR_FONT
                                    : Colors.black87,
                              ))),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _content(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _load, child: const Text('再読み込み')),
      ]));
    }
    if (_teams.isEmpty) {
      return Center(
          child: Text('${widget.year}年の${widget.org.label}の戦力情報はまだ登録されていません。'));
    }
    final team = _teams.firstWhere(
        (row) => _int(row['id_team']) == _selectedTeam,
        orElse: () => _teams.first);
    final background = parseColorNameOrNull('${team['color_back'] ?? ''}') ??
        widget.org.tabColor;
    final headerBackground = Color.lerp(background, Colors.white, 0.22)!;
    final foreground = headerBackground.computeLuminance() > 0.179
        ? Colors.black
        : Colors.white;
    final pitchingRates = enrichStrengthBands(
        team,
        pitchingWorkloadBands(listMapFromJson(team['pitching_workload'])),
        'pitching');
    final lineupGames = _int(team['lineup_game_count']);
    final battingOrder = enrichStrengthBands(
        team, listMapFromJson(team['batting_order']), 'batting');
    final positions = enrichStrengthBands(
        team,
        listMapFromJson(team['positions'])
            .where((row) => row['slot'] != 'P')
            .toList(),
        'fielding');
    final substitutions = listMapFromJson(team['substitutions']);
    final pitchingHand = handednessBand(team, pitching: true);
    final battingHand = handednessBand(team, pitching: false);
    final performance = contributionBands(team);
    final playerColors = <String, Color>{};
    for (final row in [
      ...battingOrder,
      ...positions,
      ...pitchingRates,
      ...substitutions,
      pitchingHand,
      battingHand,
      ...performance
    ]) {
      for (final player in listMapFromJson(row['players'])) {
        playerColors.putIfAbsent(_playerKey(player), () {
          // Keep team-derived RGB variations, softened with white.
          final teamColor = HSLColor.fromColor(background);
          final base = teamColor
              .withSaturation((teamColor.saturation * 0.45).clamp(0.0, 0.45))
              .withLightness((teamColor.lightness * 0.78).clamp(0.18, 0.48))
              .toColor();
          const shifts = <(int, int, int)>[
            (0, 0, 0),
            (24, -12, -8),
            (-16, 20, -8),
            (-8, -12, 24),
            (18, 12, -20),
            (18, -20, 12),
            (-20, 12, 18),
            (-12, -6, 14),
            (12, 8, -14),
            (-8, 16, -16),
            (16, -8, 4),
            (-16, 4, 12),
          ];
          final shift = shifts[playerColors.length % shifts.length];
          int channel(double value, int offset) =>
              (value * 255 + offset).round().clamp(0, 255);
          final varied = Color.fromARGB(255, channel(base.r, shift.$1),
              channel(base.g, shift.$2), channel(base.b, shift.$3));
          return Color.lerp(varied, Colors.white, 0.55)!;
        });
      }
    }
    final notes = team['notes'] is List
        ? (team['notes'] as List)
            .map((note) => '$note')
            .where((note) => note.isNotEmpty)
        : const <String>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_selectedView == 0 || _selectedView == 4 || _selectedView == 6)
        Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              for (final compare in [false, true])
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Material(
                            color: _comparisonViews.contains(_selectedView) ==
                                    compare
                                ? widget.org.tabColor
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                                key: ValueKey('strength-comparison-$compare'),
                                onTap: () => setState(() {
                                      if (compare) {
                                        _comparisonViews.add(_selectedView);
                                      } else {
                                        _comparisonViews.remove(_selectedView);
                                      }
                                    }),
                                child: Padding(
                                    padding: EdgeInsets.zero,
                                    child: SizedBox(
                                        height: TAB_BAR_H,
                                        child: Center(
                                            child: Text(
                                                compare
                                                    ? (widget.org.kind.name ==
                                                            'npb'
                                                        ? '12球団比較'
                                                        : '30球団比較')
                                                    : '各球団',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color: _comparisonViews
                                                                .contains(
                                                                    _selectedView) ==
                                                            compare
                                                        ? Colors.white
                                                        : Colors
                                                            .black87))))))))),
            ])),
      if (_selectedView != 2 &&
          _selectedView != 5 &&
          _selectedView != 7 &&
          !((_selectedView == 0 || _selectedView == 4 || _selectedView == 6) &&
              _comparisonViews.contains(_selectedView)))
        _teamSegments(),
      const SizedBox(height: 6),
      Expanded(
          child: _selectedView == 0 && _comparisonViews.contains(0)
              ? _performanceComparison()
              : _selectedView == 0 || _selectedView == 1
                  ? LayoutBuilder(builder: (context, constraints) {
                      final bands = _selectedView == 0
                          ? performance
                          : [
                              ...pitchingRates,
                              pitchingHand,
                              ...positions,
                              ...battingOrder,
                              battingHand,
                              ...substitutions
                            ];
                      final width = _bandsWidth(bands, constraints.maxWidth);
                      return SingleChildScrollView(
                        key: const ValueKey('strength-horizontal-scroll'),
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                            width: width,
                            child: ListView(
                              key: PageStorageKey(
                                  'strength-rows-${widget.org.kind.name}-${widget.year}-$_selectedTeam-$_selectedView'),
                              padding: const EdgeInsets.only(bottom: 16),
                              children: [
                                if (_selectedView == 0) ...[
                                  _heading('チーム成績への貢献割合', headerBackground,
                                      foreground),
                                  _rates(performance, headerBackground,
                                      foreground, playerColors,
                                      totalUnit: '個'),
                                  const Text(
                                      '塁打の内訳：本塁打×4・三塁打×3・二塁打×2・単打・四球。死球は含みません。'),
                                ] else ...[
                                  _heading(
                                      '投手の投球回負担率', headerBackground, foreground,
                                      detail: 'チーム全投球回が分母／WHIPはシーズン通算'),
                                  _rates(
                                      [pitchingHand, ...pitchingRates],
                                      headerBackground,
                                      foreground,
                                      playerColors,
                                      totalUnit: '回'),
                                  _heading('守備位置のスタメン比率', headerBackground,
                                      foreground,
                                      detail: '途中出場は含みません／UZR未取得は —'),
                                  _rates(positions, headerBackground,
                                      foreground, playerColors),
                                  _heading(
                                      '打順のスタメン比率', headerBackground, foreground,
                                      detail:
                                          '$lineupGames試合の先発起用／OPS・本塁打はシーズン通算'),
                                  _rates([battingHand], headerBackground,
                                      foreground, playerColors,
                                      totalUnit: '打席'),
                                  const Text('両打ちは打席の左右内訳を推測せず、両打として表示します。'),
                                  _rates(battingOrder, headerBackground,
                                      foreground, playerColors),
                                  _heading(
                                      '途中出場の起用割合', headerBackground, foreground,
                                      detail: '各役割の起用総数が分母／途中出場時の役割で集計'),
                                  _rates(substitutions, headerBackground,
                                      foreground, playerColors,
                                      totalUnit: '回'),
                                  if (pitchingRates.isNotEmpty)
                                    _pitchingDetails(team),
                                ],
                                const SizedBox(height: 12),
                                for (final note in notes)
                                  Text(note,
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.black54)),
                                if ('${team['updated_at'] ?? ''}'.isNotEmpty)
                                  Text('更新：${_updatedAt(team['updated_at'])}',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.black54)),
                              ],
                            )),
                      );
                    })
                  : _selectedView == 2
                      ? StrengthRegularGrid(teams: _teams)
                      : _selectedView == 3
                          ? StrengthRosterGrid(team: team, year: widget.year)
                          : _selectedView == 5
                              ? StrengthDraft(year: widget.year)
                              : _selectedView == 6
                                  ? StrengthAchievements(
                                      team: team,
                                      year: widget.year,
                                      comparisonTeams:
                                          _comparisonViews.contains(6)
                                              ? _teams
                                              : null)
                                  : _selectedView == 7
                                      ? StrengthCareers(teams: _teams)
                                      : StrengthContracts(
                                          colorTeams: _teams,
                                          team: team,
                                          year: widget.year,
                                          comparisonTeams:
                                              _comparisonViews.contains(4)
                                                  ? _teams
                                                  : null)),
    ]);
  }

  Widget _performanceComparison() =>
      LayoutBuilder(builder: (context, constraints) {
        final all = [for (final team in _teams) contributionBands(team)];
        final maxima = [
          for (var i = 0; i < 3; i++)
            all.fold<int>(0, (n, bands) => math.max(n, _int(bands[i]['total'])))
        ];
        final width = _bandsWidth([
          for (final bands in all) {...bands[0], 'total': maxima[0]}
        ], math.max(1000.0, constraints.maxWidth));
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: width,
                child: ListView(children: [
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('球団比較：各指標の最多球団を基準に帯の長さを揃えています。')),
                  for (final i in [1, 0, 2]) ...[
                    _heading(['本塁打', '塁打数', '打点'][i], widget.org.tabColor,
                        Colors.white),
                    if (i == 1) _baseLegend(),
                    for (var t = 0; t < _teams.length; t++)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                              width: _bandSideWidth +
                                  (width - _bandSideWidth) *
                                      (maxima[i] > 0
                                          ? _int(all[t][i]['total']) / maxima[i]
                                          : 0),
                              child: _rates(
                                  [
                                    {
                                      ...all[t][i],
                                      'label': _teams[t]['name_team'],
                                      'header_color': parseColorNameOrNull(
                                              '${_teams[t]['color_back']}') ??
                                          widget.org.tabColor
                                    }
                                  ],
                                  Colors.grey,
                                  Colors.black,
                                  {
                                    for (final (index, p)
                                        in listMapFromJson(all[t][i]['players'])
                                            .indexed)
                                      _playerKey(p): Color.lerp(
                                          parseColorNameOrNull(
                                                  '${_teams[t]['color_back']}') ??
                                              Colors.blueGrey,
                                          Colors.white,
                                          .35 + (index % 4) * .1)!
                                  }))),
                  ],
                ])));
      });

  Widget _teamButton(Map<String, dynamic> row) => Semantics(
        selected: _int(row['id_team']) == _selectedTeam,
        child: Material(
          color: _int(row['id_team']) == _selectedTeam
              ? parseColorNameOrNull('${row['color_back']}') ??
                  widget.org.tabColor
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            key: ValueKey('strength-team-${row['id_team']}'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _selectedTeam = _int(row['id_team'])),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      '${row['name_team'] ?? row['name_shortest'] ?? ''}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _int(row['id_team']) == _selectedTeam
                              ? parseColorNameOrNull('${row['color_font']}') ??
                                  Colors.white
                              : Colors.black87))),
            ),
          ),
        ),
      );

  Widget _teamSegments() => LayoutBuilder(builder: (context, constraints) {
        var requiredWidth = 0.0;
        for (final row in _teams) {
          final painter = TextPainter(
              text: TextSpan(
                  text: '${row['name_team'] ?? row['name_shortest'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context))
            ..layout();
          requiredWidth += painter.width + 28;
          painter.dispose();
        }
        final split = widget.org.kind == OrgKind.npb &&
            requiredWidth - 4 > constraints.maxWidth &&
            _teams.every((team) => [1, 2].contains(_int(team['id_league'])));
        if (split) {
          return Column(children: [
            for (final league in [1, 2])
              Padding(
                  padding: EdgeInsets.only(bottom: league == 1 ? 4 : 0),
                  child: Row(children: [
                    for (final team
                        in _teams.where((t) => _int(t['id_league']) == league))
                      Expanded(
                          child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: _teamButton(team))),
                  ])),
          ]);
        }
        return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: SingleChildScrollView(
                child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [for (final team in _teams) _teamButton(team)])));
      });

  Widget _bandDetailsButton(
          Map<String, dynamic> row, Map<String, Color> colors) =>
      IconButton(
          key: ValueKey(
              'strength-detail-${row['unit'] ?? 'starts'}-${row['slot']}'),
          tooltip: '${row['label'] ?? row['slot']}の詳細',
          constraints: const BoxConstraints.tightFor(width: 32, height: 36),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.bar_chart, size: 20),
          onPressed: () => _showBandDetails(row, colors));

  void _showBandDetails(Map<String, dynamic> row, Map<String, Color> colors) {
    final players = listMapFromJson(row['players'])
      ..sort((a, b) => _int(b['count']).compareTo(_int(a['count'])));
    final maxCount = players.fold<int>(
        0, (max, p) => _int(p['count']) > max ? _int(p['count']) : max);
    final total = _int(row['total']);
    showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
              child: SizedBox(
                  width: 560,
                  height: MediaQuery.sizeOf(dialogContext).height * 0.72,
                  child: Column(children: [
                    Padding(
                        padding:
                            const EdgeInsets.only(left: 16, top: 4, right: 4),
                        child: Row(children: [
                          Expanded(
                              child: Text('${row['label'] ?? row['slot']}の詳細',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold))),
                          IconButton(
                              tooltip: '閉じる',
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: const Icon(Icons.close)),
                        ])),
                    Expanded(
                        child: players.isEmpty
                            ? const Center(child: Text('起用情報はありません'))
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: players.length,
                                itemBuilder: (context, index) {
                                  final player = players[index];
                                  final count = _int(player['count']);
                                  final value = row['unit'] == 'outs'
                                      ? inningsLabel(count)
                                      : row['unit'] == 'pa'
                                          ? '$count打席'
                                          : row['unit'] == 'contribution'
                                              ? '$count${row['slot'] == 'home_runs' ? '本' : row['slot'] == 'rbi' ? '点' : '塁打'}'
                                              : const ['PH', 'PR', 'DEF']
                                                      .contains(row['slot'])
                                                  ? '$count回'
                                                  : '$count試合';
                                  return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                                '${player['name']}　$value（${(total > 0 ? count * 100 / total : 0).toStringAsFixed(1)}%）',
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                            if (player['metric_label'] != null)
                                              Text('${player['metric_label']}',
                                                  style: const TextStyle(
                                                      fontSize: 11)),
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                child: SizedBox(
                                                    height: 16,
                                                    child: ColoredBox(
                                                        color: Colors
                                                            .grey.shade100,
                                                        child: FractionallySizedBox(
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            widthFactor:
                                                                maxCount > 0
                                                                    ? count /
                                                                        maxCount
                                                                    : 0,
                                                            child: ColoredBox(
                                                                color: colors[
                                                                        _playerKey(
                                                                            player)] ??
                                                                    Colors
                                                                        .blueGrey))))),
                                          ]));
                                })),
                  ])),
            ));
  }

  Widget _heading(String title, Color background, Color foreground,
          {String? detail}) =>
      Container(
        margin: const EdgeInsets.only(top: 12, bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(4)),
        child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
                width: math.max(280.0, MediaQuery.sizeOf(context).width - 32),
                child: Column(children: [
                  Text(title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: foreground,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  if (detail != null)
                    Text(detail,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: foreground)),
                ]))),
      );

  Widget _pitchingDetails(Map<String, dynamic> team) {
    final players = listMapFromJson(team['pitching_workload'])
      ..sort((a, b) => _int(b['total_outs']).compareTo(_int(a['total_outs'])));
    final total = players.fold<int>(0, (n, p) => n + _int(p['total_outs']));
    return ExpansionTile(
      // Keep expansion state separate from the parent ListView's scroll offset.
      key: PageStorageKey(
          'strength-pitching-details-${widget.org.kind.name}-${widget.year}-${team['id_team']}'),
      title: const Text('各投手の投球回・負担率', style: TextStyle(fontSize: 13)),
      subtitle: const Text('帯の細い投手もすべて確認できます', style: TextStyle(fontSize: 11)),
      children: [
        for (final player in players)
          ListTile(
            dense: true,
            title: Text(
                '${player['name']}　${inningsLabel(_int(player['total_outs']))}',
                style: const TextStyle(fontSize: 12)),
            subtitle: Text(
                '先発 ${inningsLabel(_int(player['starter_outs']))}／中継ぎ・抑え ${inningsLabel(_int(player['relief_outs']))}',
                style: const TextStyle(fontSize: 11)),
            trailing: Text(
                '${(total > 0 ? _int(player['total_outs']) * 100 / total : 0).toStringAsFixed(1)}%'),
          ),
      ],
    );
  }

  String _bandTotal(Map<String, dynamic> row, String unit) {
    if (row['unit'] == 'contribution')
      return '${_int(row['total'])}${row['slot'] == 'home_runs' ? '本' : row['slot'] == 'rbi' ? '点' : '塁打'}';
    if (row['slot'] == 'pitching_hand') return inningsLabel(_int(row['total']));
    if (row['unit'] != 'outs') return '${_int(row['total'])}$unit';
    final outs = _int(row['role_outs']);
    final total = _int(row['total']);
    return '${inningsLabel(outs)}（${(total > 0 ? outs * 100 / total : 0).toStringAsFixed(1)}%）';
  }

  Color _rateHeaderColor(Map<String, dynamic> row) =>
      row['header_color'] as Color? ??
      switch ('${row['slot']}') {
        'starter' || 'relief' || 'P' => const Color(0xFFEF5350),
        'C' => const Color(0xFF2196F3),
        'LF' || 'CF' || 'RF' || 'OF' => const Color(0xFF43A047),
        'DH' => const Color(0xFF9C27B0),
        'pitching_hand' => const Color(0xFFEF5350),
        _ => const Color(0xFFFFD54F),
      };
  Color _rateHeaderTextColor(Map<String, dynamic> row) =>
      _rateHeaderColor(row).computeLuminance() > 0.179
          ? Colors.black
          : Colors.white;
  Widget _bandTotalLabel(Map<String, dynamic> row, String unit) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_bandTotal(row, unit),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                    color: _rateHeaderTextColor(row),
                    fontSize: 10,
                    height: 1.2))),
      );

  Widget _rates(List<Map<String, dynamic>> rows, Color background,
      Color foreground, Map<String, Color> playerColors,
      {String totalUnit = '試合'}) {
    if (rows.isEmpty) {
      return const Text('起用情報はまだ登録されていません。',
          style: TextStyle(fontSize: 12, color: Colors.black54));
    }
    return Column(children: [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: row['slot'] == 'total_bases_walks' &&
                    row['header_color'] == null
                ? 112
                : 72,
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: 88 * 1.2,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                    color: _rateHeaderColor(row),
                    borderRadius: BorderRadius.circular(4)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 88 * 1.2,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${row['label'] ?? row['slot'] ?? ''}',
                          style: TextStyle(
                              color: _rateHeaderTextColor(row),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      _bandTotalLabel(row, totalUnit),
                      if (row['slot'] == 'total_bases_walks' &&
                          row['header_color'] == null)
                        _baseLegend(compact: true),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _rateBand(row, playerColors)),
              SizedBox(
                  width: 48,
                  child: Center(child: _bandDetailsButton(row, playerColors))),
            ]),
          ),
        ),
    ]);
  }

  Widget _rateBand(Map<String, dynamic> row, Map<String, Color> playerColors,
      {double? verticalHeight}) {
    final vertical = verticalHeight != null;
    final players = listMapFromJson(row['players'])
        .where((player) => _int(player['count']) > 0)
        .toList();
    final total = _int(row['total']);
    final used =
        players.fold<int>(0, (sum, player) => sum + _int(player['count']));
    final height = verticalHeight ?? 72.0;

    return ClipRRect(
      key: ValueKey('strength-band-${row['unit'] ?? 'starts'}-${row['slot']}'),
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
          height: height,
          child: ColoredBox(
            color: const Color(0xFFEEF0F3),
            child: Flex(
                direction: vertical ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, player) in players.indexed)
                    Expanded(
                      flex: _int(player['count']),
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                            border: index == 0
                                ? null
                                : (vertical
                                    ? const Border(
                                        top: BorderSide(
                                            color: Color(0xFFD0D0D0), width: 2))
                                    : const Border(
                                        left: BorderSide(
                                            color: Color(0xFFD0D0D0),
                                            width: 2)))),
                        child: _rateSegment(
                            player, total, playerColors[_playerKey(player)]!,
                            vertical: vertical),
                      ),
                    ),
                  // 投手は役割ごとに帯全体を使い、数値の分母はチーム総投球回を維持する。
                  // 野手の未起用分（DHなしの試合など）は空白として残す。
                  if (row['unit'] != 'outs' && total > used)
                    Expanded(flex: total - used, child: const SizedBox()),
                ]),
          )),
    );
  }

  Widget _rateSegment(Map<String, dynamic> player, int total, Color color,
      {bool vertical = false}) {
    final name = '${player['name'] ?? ''}';
    final count = _int(player['count']);
    final rate = '${(total > 0 ? count / total * 100 : 0).toStringAsFixed(1)}%';
    final role = '${player['role'] ?? ''}';
    final relief = player['unit'] == 'outs' && role == '中継ぎ・抑え';
    final starter = player['unit'] == 'outs' && role == '先発';
    final homeRuns = player['contribution_metric'] == 'home_runs';
    final displayValue = player['contribution_metric'] != null
        ? '$count'
        : '${player['value_label']}';
    final showLabels = total > 0 &&
        (homeRuns
            ? count >= 5
            : relief
                ? count * 50 >= total
                : starter
                    ? count * 100 >= total * 3
                    : count * 20 > total);
    final description = player['unit'] == 'outs'
        ? '$name${role.isEmpty ? '' : '（$role）'}：${inningsLabel(count)}（チーム全体の$rate）'
        : '$name：${player['value_label'] ?? '$count${player['unit'] == 'pa' ? '打席' : '回'}'}（$rate）';
    final textColor =
        color.computeLuminance() > 0.179 ? Colors.black : Colors.white;
    final nameStyle = DefaultTextStyle.of(context).style.copyWith(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: textColor);
    final rateStyle =
        nameStyle.copyWith(fontSize: 10, fontWeight: FontWeight.normal);
    return Tooltip(
      message: description,
      child: Semantics(
        label: description,
        excludeSemantics: true,
        child: ColoredBox(
            color: color,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (vertical) {
                  if (!showLabels) return const SizedBox.shrink();
                  final ratePainter = TextPainter(
                    text: TextSpan(text: rate, style: rateStyle),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    maxLines: 1,
                  )..layout();
                  final showRate =
                      ratePainter.width + 8 <= constraints.maxWidth &&
                          ratePainter.height + 4 <= constraints.maxHeight;
                  final rateHeight = showRate ? ratePainter.height : 0.0;
                  ratePainter.dispose();
                  final nameHeight = (constraints.maxHeight - rateHeight - 8)
                      .clamp(0.0, double.infinity);
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (nameHeight > 0)
                            SizedBox(
                              width: double.infinity,
                              height: nameHeight,
                              child:
                                  StrengthVerticalLabel(name, style: nameStyle),
                            ),
                          if (showRate)
                            Text(rate,
                                style: rateStyle, maxLines: 1, softWrap: false),
                        ]),
                  );
                }
                bool fits(String text, TextStyle style) {
                  final painter = TextPainter(
                      text: TextSpan(text: text, style: style),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                      maxLines: 1)
                    ..layout();
                  final fits =
                      painter.width + (relief ? 4 : 8) <= constraints.maxWidth;
                  painter.dispose();
                  return fits;
                }

                TextStyle? fittedNameStyle;
                // 中継ぎは2%以上を対象にし、細い帯でも8pxまで縮小して名前を出す。
                if (showLabels) {
                  for (var size = 12.0;
                      size >= (relief || homeRuns ? 8.0 : 10.0);
                      size -= 0.5) {
                    final candidate = nameStyle.copyWith(fontSize: size);
                    if (fits(name, candidate)) {
                      fittedNameStyle = candidate;
                      break;
                    }
                  }
                }

                return Stack(children: [
                  if (player['parts'] is List)
                    Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 18,
                        child: Row(children: [
                          for (var i = 0;
                              i < listMapFromJson(player['parts']).length;
                              i++)
                            if (_int(listMapFromJson(player['parts'])[i]
                                    ['count']) >
                                0)
                              Expanded(
                                  flex: _int(listMapFromJson(player['parts'])[i]
                                      ['count']),
                                  child: Tooltip(
                                      message:
                                          '${listMapFromJson(player['parts'])[i]['label']}: ${listMapFromJson(player['parts'])[i]['count']}塁打（${(_int(listMapFromJson(player['parts'])[i]['count']) * 100 / count).toStringAsFixed(1)}%）',
                                      child: ColoredBox(
                                          color: _baseColors[i],
                                          child: LayoutBuilder(
                                              builder: (context, bounds) {
                                            final part = listMapFromJson(
                                                player['parts'])[i];
                                            final text = '${part['events']}';
                                            final painter = TextPainter(
                                                text: TextSpan(
                                                    text: text,
                                                    style: const TextStyle(
                                                        fontSize: 10)),
                                                textDirection:
                                                    TextDirection.ltr,
                                                textScaler:
                                                    MediaQuery.textScalerOf(
                                                        context))
                                              ..layout();
                                            final fits = painter.width + 4 <=
                                                    bounds.maxWidth &&
                                                painter.height <=
                                                    bounds.maxHeight;
                                            painter.dispose();
                                            return Center(
                                                child: fits
                                                    ? Text(text,
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            color: _baseColors[
                                                                            i]
                                                                        .computeLuminance() >
                                                                    .179
                                                                ? Colors.black
                                                                : Colors.white))
                                                    : null);
                                          }))))
                        ])),
                  Padding(
                      padding: EdgeInsets.only(
                          bottom: player['parts'] is List ? 18 : 0),
                      child: Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        if (fittedNameStyle != null)
                          Text(name,
                              style: fittedNameStyle,
                              maxLines: 1,
                              softWrap: false),
                        if (player['value_label'] != null &&
                            fits(displayValue, rateStyle))
                          Text(displayValue, style: rateStyle, maxLines: 1),
                        if (showLabels && fits(rate, rateStyle))
                          Text(rate,
                              style: rateStyle, maxLines: 1, softWrap: false),
                        if (showLabels && player['metric_label'] != null)
                          Text('${player['metric_label']}',
                              style: rateStyle, maxLines: 1, softWrap: false),
                      ]))),
                ]);
              },
            )),
      ),
    );
  }

  Widget _baseLegend({bool compact = false}) => Padding(
        key: const ValueKey('total-bases-legend'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Wrap(spacing: 12, runSpacing: 2, children: [
          for (var i = 0; i < baseParts.length; i++)
            Row(
                mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: _baseColors[i],
                          border: Border.all(color: Colors.black26))),
                  const SizedBox(width: 4),
                  Text(baseParts[i].$3,
                      style: TextStyle(
                          fontSize: compact ? 9 : 12, color: Colors.black87)),
                ]),
        ]),
      );

  static const _baseColors = [
    Color(0xFFE86680),
    Color(0xFFF8B6CC),
    Color(0xFFFFBC59),
    Color(0xFFFFF280),
    Color(0xFF8BCB8D)
  ];
  double _bandsWidth(List<Map<String, dynamic>> bands, double viewport) {
    var body = math.max(800.0, viewport - _bandSideWidth);
    for (final band in bands) {
      final total = _int(band['total']);
      for (final p in listMapFromJson(band['players'])) {
        final count = _int(p['count']);
        final threshold = band['slot'] == 'relief'
            ? 0.02
            : band['slot'] == 'starter'
                ? 0.03
                : 0.05;
        final homeRuns =
            band['unit'] == 'contribution' && band['slot'] == 'home_runs';
        if (count <= 0 ||
            total <= 0 ||
            (homeRuns ? count < 5 : count / total < threshold)) continue;
        final name = TextPainter(
            text: TextSpan(
                text: '${p['name']}',
                style: TextStyle(
                    fontSize: homeRuns ? 8 : 12, fontWeight: FontWeight.w600)),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context))
          ..layout();
        final metric = TextPainter(
            text: TextSpan(
                text: '${p['metric_label'] ?? ''}',
                style: const TextStyle(fontSize: 10)),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context))
          ..layout();
        body = math.max(
            body,
            (math.max(name.width, metric.width) + 12) *
                (band['unit'] == 'outs' && band['role_outs'] != null
                    ? _int(band['role_outs'])
                    : total) /
                count);
        name.dispose();
        metric.dispose();
      }
    }
    return body + _bandSideWidth;
  }

  String _updatedAt(dynamic value) {
    final date = DateTime.tryParse('$value');
    if (date == null) return '$value';
    final japan = date.toUtc().add(const Duration(hours: 9));
    return '${japan.year}/${japan.month}/${japan.day} ${japan.hour.toString().padLeft(2, '0')}:${japan.minute.toString().padLeft(2, '0')}（日本時間）';
  }

  String _playerKey(Map<String, dynamic> player) {
    final key = '${player['player_key'] ?? ''}'.trim();
    return key.isNotEmpty
        ? key
        : '${player['name'] ?? ''}'.replaceAll(RegExp(r'[\s　]+'), '');
  }

  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
