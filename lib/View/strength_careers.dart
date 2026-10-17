import '../logic/career_regions.dart';
import 'package:flutter/material.dart';
import '../tools/json_utils.dart';
import '../tools/color_parse.dart';
import '../logic/strength_usage.dart';
import 'strength_research.dart' show showStrengthSource;

const careerCategories = ['高校', '大学', '社会人', '独立', '出身地'];

List<Map<String, dynamic>> careerGroups(List<Map<String, dynamic>> teams, String category) {
  final groups = <String, Map<String, dynamic>>{};
  for (final team in teams) {
    for (final p in listMapFromJson(team['roster'])) {
      if (p['active'] == false || (p['departure_confirmed'] == true && p['departure_type'] == 'retired')) {
        continue;
      }
      if (category == '出身地') {
        final path = careerRegionPath(p);
        final country = path.isNotEmpty && path.first == '日本' ? '日本' : '${p['birth_country'] ?? p['country'] ?? '国未確認'}';
        final area = country == '日本' && path.length >= 3 ? path[2] : '${p['birth_state'] ?? p['birth_place'] ?? '都道府県・州未確認'}';
        final name = '$country / $area';
        final group = groups.putIfAbsent(name, () => {'name': name, 'players': <String, Map<String, dynamic>>{}});
        (group['players'] as Map<String, Map<String, dynamic>>).putIfAbsent('${team['id_team']}:${usagePlayerKey(p)}', () => {'player': p, 'team': team, 'career': {'detail': path.join(' / '), 'source_url': p['source_url']}});
        continue;
      }
      for (final career in listMapFromJson(p['career_history'])) {
        final name = '${career['team'] ?? ''}'.trim();
        if (career['category'] != category || name.isEmpty) continue;
        final group = groups.putIfAbsent(name, () => {'name': name, 'players': <String, Map<String, dynamic>>{}});
        (group['players'] as Map<String, Map<String, dynamic>>).putIfAbsent(usagePlayerKey(p), () => {'player': p, 'team': team, 'career': career});
      }
    }
  }
  return [
    for (final group in groups.values)
      {
        'name': group['name'],
        'players': (group['players'] as Map<String, Map<String, dynamic>>).values.toList()..sort((a, b) => '${a['player']['name']}'.compareTo('${b['player']['name']}')),
      }
  ]..sort((a, b) {
      final count = (b['players'] as List).length.compareTo((a['players'] as List).length);
      return count != 0 ? count : '${a['name']}'.compareTo('${b['name']}');
    });
}

class StrengthCareers extends StatefulWidget {
  const StrengthCareers({super.key, required this.teams});
  final List<Map<String, dynamic>> teams;
  @override
  State<StrengthCareers> createState() => _StrengthCareersState();
}

class _StrengthCareersState extends State<StrengthCareers> {
  String category = '高校';
  @override
  Widget build(BuildContext context) {
    final groups = careerGroups(widget.teams, category);
    return Column(children: [
      Row(children: [
        for (final value in careerCategories) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Material(color: category == value ? Theme.of(context).colorScheme.primary : Colors.grey.shade200, borderRadius: BorderRadius.circular(20), child: InkWell(onTap: () => setState(() => category = value), borderRadius: BorderRadius.circular(20), child: SizedBox(height: 32, child: Center(child: Text(value, style: TextStyle(color: category == value ? Colors.white : Colors.black87)))))))),
      ]),
      const SizedBox(height: 8),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final columns = (constraints.maxWidth / 320).floor().clamp(1, 6);
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return SingleChildScrollView(
            key: PageStorageKey('career-$category'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (groups.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('確認できた所属歴はまだありません。')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final group in groups)
                  Container(
                      width: width,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade600), borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('${group['name']}  ${(group['players'] as List).length}人', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const Divider(),
                        Wrap(spacing: 5, runSpacing: 5, children: [
                          for (final entry in listMapFromJson(group['players']))
                            Material(
                                color: (parseColorNameOrNull('${entry['team']['color_back']}') ?? Colors.blueGrey).withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(4),
                                child: InkWell(
                                    onTap: () => showStrengthSource(context, '${entry['player']['name']}', '${entry['team']['name_team']}\n$category：${group['name']}\n${entry['career']['detail'] ?? ''}', [if (entry['career']['source_url'] != null) '${entry['career']['source_url']}']),
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                                          Text('${entry['player']['name']}'),
                                          Text('${entry['team']['name_team']}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                                        ])))),
                        ]),
                      ])),
              ]),
              const Padding(padding: EdgeInsets.all(8), child: Text('表示中のリーグの現役名簿から、確認できた所属歴を集計。人数の多い順（同数は名称順）。同一チーム内の選手の重複は除きます。未取得の経歴は含みません。選手を押すと出典を表示します。', style: TextStyle(fontSize: 11, color: Colors.black54))),
            ]));
      })),
    ]);
  }
}
