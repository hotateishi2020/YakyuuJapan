import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/org_config.dart';
import 'season_titles_table.dart';

/// MLB uses the same cells, winner links and surfaces as the NPB title board.
class MlbSeasonTitlesTable extends StatelessWidget {
  const MlbSeasonTitlesTable(
      {super.key, required this.groups, required this.year});
  final Map<String, List<Map<String, dynamic>>> groups;
  final int year;

  static final _leaguePrefix = RegExp(
      r'(?:アメリカン|ナショナル|ア|ナ)[・･]?リーグ|American League|National League|\bAL\b|\bNL\b',
      caseSensitive: false);

  int? league(Map<String, dynamic> row) {
    final id = int.tryParse('${row['id_league']}');
    if (id == 3 || id == 4) return id;
    final text = '${row['league'] ?? ''} ${row['detail'] ?? ''}';
    if (RegExp(r'ア(?:メリカン)?[・･]?リーグ|American League|\bAL\b',
            caseSensitive: false)
        .hasMatch(text)) return 3;
    if (RegExp(r'ナ(?:ショナル)?[・･]?リーグ|National League|\bNL\b',
            caseSensitive: false)
        .hasMatch(text)) return 4;
    return null;
  }

  String category(Map<String, dynamic> row) =>
      '${row['detail'] ?? ''}'.replaceAll(_leaguePrefix, '').trim();

  @override
  Widget build(BuildContext context) {
    final shared = SeasonTitlesTable(groups: groups, year: year);
    return LayoutBuilder(builder: (context, constraints) {
      final portrait = constraints.maxWidth < 700;
      final width = math.max(0.0, constraints.maxWidth - 32);
      Widget result(List<Map<String, dynamic>> values,
              {int? side, bool logo = false}) =>
          shared.winners(values,
              showLogo: logo,
              background: side == null
                  ? Colors.white
                  : Color.lerp(
                      OrgConfig.mlb.leagueColor(side), Colors.white, .92));
      Widget leagueHeader(int id) => shared.cell(
          Text(OrgConfig.mlb.leagueName(id),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          color: OrgConfig.mlb.leagueColor(id));

      Widget grid(String key, String title,
          List<(String, List<Map<String, dynamic>>, bool)> columns) {
        final effective = columns.isEmpty
            ? <(String, List<Map<String, dynamic>>, bool)>[(title, [], false)]
            : columns;
        final unknown = [
          for (final (_, values, _) in effective)
            ...values.where((r) => league(r) == null)
        ];
        final table =
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          shared.label(title, SeasonTitlesTable.red),
          if (portrait) ...[
            shared.line([
              shared.label('項目', SeasonTitlesTable.purple),
              leagueHeader(3),
              leagueHeader(4)
            ]),
            for (final (heading, values, logo) in effective)
              shared.line([
                shared.cell(Text(heading, textAlign: TextAlign.center)),
                for (final id in [3, 4])
                  result(values.where((r) => league(r) == id).toList(),
                      side: id, logo: logo)
              ]),
          ] else ...[
            shared.leagueLine([
              shared.label('', SeasonTitlesTable.purple),
              for (final (heading, _, _) in effective)
                shared.label(heading, SeasonTitlesTable.gold)
            ]),
            for (final id in [3, 4])
              shared.leagueLine([
                leagueHeader(id),
                for (final (_, values, logo) in effective)
                  result(values.where((r) => league(r) == id).toList(),
                      side: id, logo: logo)
              ]),
          ],
          // Do not silently discard winners whose source lacks a league.
          if (unknown.isNotEmpty)
            for (final (heading, values, logo) in effective)
              if (values.any((r) => league(r) == null))
                shared.line([
                  shared.cell(Text(heading, textAlign: TextAlign.center)),
                  result(values.where((r) => league(r) == null).toList(),
                      logo: logo)
                ]),
        ]);
        return SizedBox(
            key: ValueKey('mlb-titles-grid-$key'),
            width: width,
            child: shared.surface(SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                    width: portrait
                        ? width - 2
                        : math.max(width - 2, 112 + effective.length * 150.0),
                    child: table))));
      }

      List<(String, List<Map<String, dynamic>>, bool)> categories(String key) {
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final row in groups[key] ?? <Map<String, dynamic>>[]) {
          final heading = category(row);
          grouped
              .putIfAbsent(heading.isEmpty ? '受賞者' : heading, () => [])
              .add(row);
        }
        return [
          for (final entry in grouped.entries) (entry.key, entry.value, false)
        ];
      }

      return ColoredBox(
          color: const Color(0xfff6f8fb),
          child: SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('$year年 タイトル',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: SeasonTitlesTable.ink)),
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('「現在首位」は受賞確定ではありません。未定の項目は受賞者を表示していません。',
                            style: TextStyle(
                                fontSize: 12, color: SeasonTitlesTable.muted))),
                    shared.surface(Column(
                        key: const ValueKey('mlb-titles-grid-series'),
                        children: [
                          shared.label('ワールドシリーズ', SeasonTitlesTable.red),
                          shared.line([
                            shared.label('優勝チーム', SeasonTitlesTable.gold),
                            shared.label('MVP', SeasonTitlesTable.gold)
                          ]),
                          shared.line([
                            result(groups['series_champion'] ?? [], logo: true),
                            result(groups['series_mvp'] ?? [])
                          ]),
                        ])),
                    const SizedBox(height: 20),
                    grid('league', 'リーグ表彰', [
                      for (final entry in const {
                        'league_champion': 'リーグ優勝',
                        'series_entrants': 'ワールドシリーズ進出',
                        'league_mvp': 'リーグMVP',
                        'rookie': '新人王',
                        'manager': '最優秀監督賞'
                      }.entries)
                        (
                          entry.value,
                          groups[entry.key] ?? [],
                          entry.key == 'league_champion' ||
                              entry.key == 'series_entrants'
                        ),
                    ]),
                    for (final entry in const {
                      'glove': 'ゴールドグラブ賞',
                      'major': '個人タイトル',
                      'monthly': '月間MVP',
                      'weekly': '週間MVP'
                    }.entries) ...[
                      const SizedBox(height: 20),
                      grid(entry.key, entry.value, categories(entry.key)),
                    ],
                    const SizedBox(height: 20),
                    shared.surface(Column(children: [
                      shared.label('オールスター', SeasonTitlesTable.green),
                      shared.line([
                        shared.label('MVP', SeasonTitlesTable.gold),
                        shared.label('ホームランダービー優勝', SeasonTitlesTable.gold)
                      ]),
                      shared.line([
                        result(groups['allstar_mvp'] ?? []),
                        result(groups['derby'] ?? [])
                      ]),
                    ])),
                    if ((groups['records'] ?? []).isNotEmpty) ...[
                      const SizedBox(height: 20),
                      grid('records', 'シーズン記録更新', categories('records')),
                    ],
                  ],
                )),
          ));
    });
  }
}
