import 'player_detail_dialog.dart';
import '../logic/favorite_team.dart';
import '../config/org_config.dart';
import 'compact_card_layout.dart';
import 'team_section_layout.dart';
import '../logic/career_regions.dart';
import 'package:flutter/material.dart';
import '../tools/json_utils.dart';
import '../tools/color_parse.dart';
import '../logic/strength_usage.dart';
import 'strength_research.dart' show showStrengthSource;

const careerCategories = ['高校', '大学', '社会人', '独立', '出身地'];

List<Map<String, dynamic>> careerGroups(
    List<Map<String, dynamic>> teams, String category) {
  final groups = <String, Map<String, dynamic>>{};
  for (final team in teams) {
    for (final p in listMapFromJson(team['roster'])) {
      if (p['active'] == false ||
          (p['departure_confirmed'] == true &&
              p['departure_type'] == 'retired')) {
        continue;
      }
      if (category == '出身地') {
        final path = careerRegionPath(p);
        final country = path.isNotEmpty &&
                    '${p['birth_country'] ?? p['country'] ?? ''}'
                        .trim()
                        .isNotEmpty ||
                (path.length >= 3 && path.first == '日本')
            ? path.first
            : '国未確認';
        final area = country == '日本' && path.length >= 3
            ? path[2]
            : ('${p['birth_state'] ?? ''}'.trim().isNotEmpty
                ? '${p['birth_state']}'
                : '${p['birth_place'] ?? ''}'.trim().isNotEmpty
                    ? '${p['birth_place']}'
                    : '都道府県・州未確認');
        final name = '$country / $area';
        final region = country == '日本' && path.length >= 3 ? path[1] : country;
        final group = groups.putIfAbsent(
            name,
            () => {
                  'name': name,
                  'region': region,
                  'area': area,
                  'players': <String, Map<String, dynamic>>{}
                });
        (group['players'] as Map<String, Map<String, dynamic>>).putIfAbsent(
            '${team['id_team']}:${usagePlayerKey(p)}',
            () => {
                  'player': p,
                  'team': team,
                  'career': {
                    'detail': path.join(' / '),
                    'source_url': p['birth_source_url'] ?? p['source_url']
                  }
                });
        continue;
      }
      for (final career in listMapFromJson(p['career_history'])) {
        final name = '${career['team'] ?? ''}'.trim();
        if (career['category'] != category || name.isEmpty) continue;
        final group = groups.putIfAbsent(name,
            () => {'name': name, 'players': <String, Map<String, dynamic>>{}});
        (group['players'] as Map<String, Map<String, dynamic>>).putIfAbsent(
            usagePlayerKey(p),
            () => {'player': p, 'team': team, 'career': career});
      }
    }
  }
  return [
    for (final group in groups.values)
      {
        'name': group['name'],
        if (category == '出身地') ...{
          'region': group['region'],
          'area': group['area']
        },
        'players': (group['players'] as Map<String, Map<String, dynamic>>)
            .values
            .toList()
          ..sort((a, b) =>
              '${a['player']['name']}'.compareTo('${b['player']['name']}')),
      }
  ]..sort((a, b) {
      final count = (b['players'] as List)
          .length
          .compareTo((a['players'] as List).length);
      return count != 0 ? count : '${a['name']}'.compareTo('${b['name']}');
    });
}

Widget careerGroupCard(
        BuildContext context, Map<String, dynamic> group, double width,
        {required String category, Widget? subtitle, Widget? footer}) =>
    Container(
        width: width,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade600),
            borderRadius: BorderRadius.circular(8)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              '${group['area'] ?? group['name']}  ${(group['players'] as List).length}人',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          if (subtitle != null) subtitle,
          const Divider(),
          Wrap(spacing: 5, runSpacing: 5, children: [
            for (final entry in listMapFromJson(group['players']))
              Material(
                  color:
                      (parseColorNameOrNull('${entry['team']['color_back']}') ??
                              Colors.blueGrey)
                          .withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(4),
                  child: InkWell(
                      onTap: () => showStrengthSource(
                              context,
                              '${entry['player']['name']}',
                              '${entry['team']['name_team']}\n$category：${group['name']}\n${entry['career']['detail'] ?? ''}',
                              [
                                if (entry['career']['source_url'] != null)
                                  '${entry['career']['source_url']}'
                              ]),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 5),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            PlayerNameLink(player: {
                              ...entry['player'],
                              'id_team': entry['team']['id_team']
                            }, child: Text('${entry['player']['name']}')),
                            Text('${entry['team']['name_team']}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black54)),
                          ])))),
          ]),
          if (footer != null) footer,
        ]));

class StrengthCareers extends StatefulWidget {
  const StrengthCareers(
      {super.key,
      required this.teams,
      this.initialCategory,
      this.org = OrgConfig.npb});
  final List<Map<String, dynamic>> teams;
  final String? initialCategory;
  final OrgConfig org;
  @override
  State<StrengthCareers> createState() => _StrengthCareersState();
}

class _StrengthCareersState extends State<StrengthCareers> {
  String category = '高校';
  final _singleTeamCategories = <String>{};
  final _selectedTeams = <String, String>{};
  @override
  void initState() {
    super.initState();
    category = widget.initialCategory ?? '高校';
  }

  Widget _groupCard(Map<String, dynamic> group, double width) =>
      careerGroupCard(context, group, width, category: category);

  Widget _birthplaceRegions(List<Map<String, dynamic>> groups) {
    final regions = <String, List<Map<String, dynamic>>>{};
    for (final group in groups) {
      regions.putIfAbsent('${group['region']}', () => []).add(group);
    }
    final names = regions.keys.toList()
      ..sort((a, b) => compareCareerAreas(a, b));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final name in names)
        Container(
          key: ValueKey('birth-region-$name'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blueGrey.withValues(alpha: .05),
            border: Border.all(color: Colors.blueGrey, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, constraints) {
              final columns = (constraints.maxWidth / 300).floor().clamp(1, 6);
              final cardWidth =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              final areas = regions[name]!
                ..sort((a, b) => compareCareerAreas(
                    '$name > ${a['area']}', '$name > ${b['area']}'));
              return CompactCardLayout(columns: columns, children: [
                for (final group in areas) _groupCard(group, cardWidth),
              ]);
            }),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (TeamSectionLayout.embedded(context) && widget.initialCategory == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final value in careerCategories) ...[
          Padding(
              padding: const EdgeInsets.all(8),
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          StrengthCareers(
              teams: widget.teams, initialCategory: value, org: widget.org),
        ],
      ]);
    }
    final embedded = TeamSectionLayout.embedded(context);
    final favorite = favoriteTeamRow(widget.teams);
    final singleTeam = !embedded && _singleTeamCategories.contains(category);
    final selectedTeam =
        widget.teams.any((t) => '${t['id_team']}' == _selectedTeams[category])
            ? _selectedTeams[category]
            : widget.teams.isEmpty
                ? null
                : '${(favorite ?? widget.teams.first)['id_team']}';
    final visibleTeams = singleTeam
        ? widget.teams.where((t) => '${t['id_team']}' == selectedTeam).toList()
        : widget.teams;
    final groups = careerGroups(visibleTeams, category);
    return Column(children: [
      if (!TeamSectionLayout.embedded(context))
        Row(children: [
          for (final value in careerCategories)
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Material(
                        color: category == value
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                            onTap: () => setState(() => category = value),
                            borderRadius: BorderRadius.circular(20),
                            child: SizedBox(
                                height: 32,
                                child: Center(
                                    child: Text(value,
                                        style: TextStyle(
                                            color: category == value
                                                ? Colors.white
                                                : Colors.black87)))))))),
        ]),
      if (!embedded) ...[
        const SizedBox(height: 8),
        SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: false,
                    label: Text(
                        widget.org.kind == OrgKind.npb ? '12球団表示' : '30球団表示')),
                const ButtonSegment(value: true, label: Text('各球団')),
              ],
              selected: {singleTeam},
              onSelectionChanged: (values) => setState(() {
                if (values.single) {
                  _singleTeamCategories.add(category);
                } else {
                  _singleTeamCategories.remove(category);
                }
              }),
            )),
        if (singleTeam && selectedTeam != null)
          DropdownButton<String>(
            key: ValueKey('career-team-$category'),
            isExpanded: true,
            value: selectedTeam,
            items: [
              for (final team in widget.teams)
                DropdownMenuItem(
                    value: '${team['id_team']}',
                    child: Text('${team['name_team']}'))
            ],
            onChanged: (value) => setState(() {
              if (value != null) _selectedTeams[category] = value;
            }),
          ),
      ],
      const SizedBox(height: 8),
      SectionExpanded(child: LayoutBuilder(builder: (context, constraints) {
        final columns = (constraints.maxWidth / 320).floor().clamp(1, 6);
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return sectionScrollView(context,
            key: PageStorageKey(
                'career-$category-${singleTeam ? selectedTeam : 'all'}'),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (groups.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('確認できた所属歴はまだありません。')),
                  if (category == '出身地')
                    _birthplaceRegions(groups)
                  else
                    CompactCardLayout(columns: columns, children: [
                      for (final group in groups) _groupCard(group, width),
                    ]),
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                          category == '出身地'
                              ? '地域・都道府県別に表示しています。海外は国・州などで分類します。選手を押すと詳細を表示します。'
                              : '表示中のリーグの現役名簿から、確認できた所属歴を集計。人数の多い順（同数は名称順）。同一チーム内の選手の重複は除きます。未取得の経歴は含みません。選手を押すと詳細を表示します。',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54))),
                ]));
      })),
    ]);
  }
}
