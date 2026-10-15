import '../tools/json_utils.dart';
import 'strength_usage.dart';

Map<String, dynamic> strengthPlayerMetrics(
    Map<String, dynamic> team, Map<String, dynamic> player) {
  var key = usagePlayerKey(player);
  // Lineup sources sometimes abbreviate names and use a different kanji form.
  // Resolve only a unique roster match; never replace an established ID.
  if (key.startsWith('npb:name:')) {
    String normalized(dynamic name) => '$name'
        .replaceAll(RegExp(r'[\s　・]+'), '')
        .replaceAll('瀨', '瀬')
        .replaceAll('髙', '高')
        .replaceAll('﨑', '崎');
    final name = normalized(player['name']);
    final matches = listMapFromJson(team['roster'])
        .where(
            (p) => name.length >= 3 && normalized(p['name']).startsWith(name))
        .toList();
    if (matches.length == 1) key = usagePlayerKey(matches.single);
  }
  final result = <String, dynamic>{};
  for (final field in [
    'roster',
    'batting_stats',
    'pitching_stats',
    'fielding_metrics'
  ]) {
    for (final p in listMapFromJson(team[field])) {
      if (usagePlayerKey(p) == key) result.addAll(p);
    }
  }
  return {...player, ...result};
}

List<Map<String, dynamic>> enrichStrengthBands(Map<String, dynamic> team,
        List<Map<String, dynamic>> bands, String kind) =>
    [
      for (final band in bands)
        {
          ...band,
          'players': [
            for (final p in listMapFromJson(band['players']))
              {
                ...strengthPlayerMetrics(team, p),
                ...p,
                'metric_label': (() {
                  final metrics = strengthPlayerMetrics(team, p);
                  if (kind == 'pitching') {
                    return 'WHIP ${metricValue(metrics['whip'], 2)}';
                  }
                  if (kind == 'batting') {
                    return battingMetricLabel(metrics);
                  }
                  final uzr = metrics['uzr_by_position'] is Map
                      ? (metrics['uzr_by_position'] as Map)[band['slot']]
                      : null;
                  return 'UZR ${metricValue(uzr, 1)}';
                })()
              }
          ]
        }
    ];
String metricValue(dynamic value, int digits) =>
    double.tryParse('$value')?.toStringAsFixed(digits) ?? '—';

String opsValue(dynamic value) =>
    metricValue(value, 3).replaceFirst(RegExp(r'^0\.'), '.');

String battingMetricLabel(Map<String, dynamic> metrics) =>
    'OPS ${opsValue(metrics['ops'])}  ${metrics['home_runs'] ?? '—'}本';

Map<String, dynamic> handednessBand(Map<String, dynamic> team,
    {required bool pitching}) {
  final counts = <String, int>{};
  for (final raw in listMapFromJson(
      team[pitching ? 'pitching_workload' : 'batting_stats'])) {
    final p = strengthPlayerMetrics(team, raw);
    final hand = '${p[pitching ? 'throws' : 'bats'] ?? ''}';
    final label = hand.startsWith('右') || hand == 'R'
        ? (pitching ? '右投' : '右打')
        : hand.startsWith('左') || hand == 'L'
            ? (pitching ? '左投' : '左打')
            : !pitching && (hand == '両' || hand == 'S')
                ? '両打'
                : '不明';
    counts[label] =
        (counts[label] ?? 0) + usageInt(p[pitching ? 'total_outs' : 'pa']);
  }
  final total = counts.values.fold<int>(0, (n, v) => n + v);
  return {
    'slot': pitching ? 'pitching_hand' : 'batting_hand',
    'label': pitching ? '投手の左右' : '打者の左右',
    'unit': pitching ? 'outs' : 'pa',
    'role_outs': total,
    'total': total,
    'players': [
      for (final e in counts.entries)
        if (e.value > 0)
          {
            'name': e.key,
            'player_key': 'hand:${e.key}',
            'count': e.value,
            'unit': pitching ? 'outs' : 'pa'
          }
    ]
  };
}

const baseParts = [
  ('home_runs', 4, '本塁打'),
  ('triples', 3, '三塁打'),
  ('doubles', 2, '二塁打'),
  ('singles', 1, '単打'),
  ('walks', 1, '四球')
];
List<Map<String, dynamic>> contributionBands(Map<String, dynamic> team) => [
      for (final metric in [
        ('home_runs', '本塁打'),
        ('total_bases_walks', '塁打数'),
        ('rbi', '打点')
      ])
        (() {
          final players = [
            for (final p in listMapFromJson(team['batting_stats']))
              if (usageInt(p[metric.$1]) > 0)
                {
                  ...p,
                  'count': usageInt(p[metric.$1]),
                  'contribution_metric': metric.$1,
                  'value_label':
                      '${usageInt(p[metric.$1])}${metric.$1 == 'home_runs' ? '本' : metric.$1 == 'rbi' ? '打点' : '塁打'}',
                  if (metric.$1 == 'total_bases_walks')
                    'parts': [
                      for (final part in baseParts)
                        {
                          'label': part.$3,
                          'events': usageInt(p[part.$1]),
                          'count': usageInt(p[part.$1]) * part.$2
                        }
                    ]
                }
          ]..sort(
              (a, b) => usageInt(b['count']).compareTo(usageInt(a['count'])));
          return <String, dynamic>{
            'slot': metric.$1,
            'label': metric.$2,
            'total': players.fold<int>(0, (n, p) => n + usageInt(p['count'])),
            'unit': 'contribution',
            'players': players
          };
        })()
    ];

const pitcherAceSlots = {
  'SP_L': '左の先発エース',
  'SP_R': '右の先発エース',
  'RP_L': '左のリリーフエース',
  'RP_R': '右のリリーフエース',
  'CL': '守護神'
};
Map<String, List<Map<String, dynamic>>> selectPitcherAces(
    Map<String, dynamic> team) {
  final players = [
    for (final p in listMapFromJson(team['pitching_workload']))
      strengthPlayerMetrics(team, p)
  ];
  final result = <String, List<Map<String, dynamic>>>{};
  Map<String, dynamic>? best(
      List<Map<String, dynamic>> list, String primary, String secondary) {
    list.sort((a, b) {
      final n = usageInt(b[primary]).compareTo(usageInt(a[primary]));
      return n != 0
          ? n
          : usageInt(b[secondary]).compareTo(usageInt(a[secondary]));
    });
    return list.isEmpty ? null : list.first;
  }

  final closer = best(players.where((p) => usageInt(p['saves']) > 0).toList(),
      'saves', 'relief_outs');
  if (closer != null) result['CL'] = [closer];
  for (final hand in ['L', 'R']) {
    bool matches(Map<String, dynamic> p) =>
        [hand == 'L' ? '左' : '右', hand].contains(p['throws']);
    final starter = best(
        players
            .where((p) => matches(p) && usageInt(p['starter_outs']) > 0)
            .toList(),
        'starter_outs',
        'starts');
    final relief = best(
        players
            .where((p) =>
                matches(p) &&
                usageInt(p['relief_outs']) > 0 &&
                usagePlayerKey(p) !=
                    (closer == null ? '' : usagePlayerKey(closer)))
            .toList(),
        'holds',
        'relief_outs');
    if (starter != null) result['SP_$hand'] = [starter];
    if (relief != null) result['RP_$hand'] = [relief];
  }
  return result;
}

const benchRegularSlots = {
  'PH_L': '左代打',
  'PH_R': '右代打',
  'PR': '代走',
  'DEF_IF': '内野代守',
  'DEF_OF': '外野代守',
};

Map<String, List<Map<String, dynamic>>> selectBenchRegulars(
    Map<String, dynamic> team,
    Map<String, List<Map<String, dynamic>>> regulars) {
  final used = regulars.values
      .expand((players) => players)
      .map((p) => usagePlayerKey(strengthPlayerMetrics(team, p)))
      .toSet();
  final groups = <String, List<Map<String, dynamic>>>{};
  final bands = [
    ...listMapFromJson(team['substitutions']),
    ...listMapFromJson(team['defense_substitutions'])
  ];
  for (final slot in benchRegularSlots.keys) {
    final source = bands
        .where((b) => b['slot'] == (slot.startsWith('PH_') ? 'PH' : slot))
        .firstOrNull;
    final players = <Map<String, dynamic>>[];
    for (final raw in listMapFromJson(source?['players'])) {
      final p = {...raw, ...strengthPlayerMetrics(team, raw)};
      final hand = '${p['bats'] ?? ''}';
      // Switch hitters can be candidates on either side, but are selected once.
      if (slot == 'PH_L' && !['左', 'L', '両', 'S'].contains(hand)) continue;
      if (slot == 'PH_R' && !['右', 'R', '両', 'S'].contains(hand)) continue;
      if (usageInt(raw['count']) <= 0) continue;
      players.add({
        ...p,
        'count': usageInt(raw['count']),
        'position': slot,
        'usage_rate': usageInt(source?['total']) > 0
            ? usageInt(raw['count']) / usageInt(source?['total'])
            : 0.0
      });
    }
    final total = players.fold<int>(0, (sum, p) => sum + usageInt(p['count']));
    for (final p in players) {
      p['usage_rate'] = total > 0 ? usageInt(p['count']) / total : 0.0;
    }
    players.sort((a, b) {
      final count = usageInt(b['count']).compareTo(usageInt(a['count']));
      return count != 0
          ? count
          : usagePlayerKey(a).compareTo(usagePlayerKey(b));
    });
    groups[slot] = players;
  }
  final result = <String, List<Map<String, dynamic>>>{};
  final candidates = groups.values.expand((p) => p).toList()
    ..sort((a, b) {
      final count = usageInt(b['count']).compareTo(usageInt(a['count']));
      if (count != 0) return count;
      final slot = benchRegularSlots.keys
          .toList()
          .indexOf(a['position'])
          .compareTo(benchRegularSlots.keys.toList().indexOf(b['position']));
      return slot != 0 ? slot : usagePlayerKey(a).compareTo(usagePlayerKey(b));
    });
  for (final p in candidates) {
    final slot = '${p['position']}';
    if (result.containsKey(slot) || used.contains(usagePlayerKey(p))) continue;
    result[slot] = [p];
    used.add(usagePlayerKey(p));
  }
  for (final p in candidates) {
    final first = result[p['position']]?.first;
    if (first == null ||
        usageInt(p['count']) * 10 < usageInt(first['count']) * 7 ||
        !used.add(usagePlayerKey(p))) continue;
    result[p['position']]!.add(p);
  }
  return result;
}
