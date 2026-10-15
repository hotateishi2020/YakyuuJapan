import '../data/npb_fa_rights.dart';
import '../tools/json_utils.dart';
import 'strength_usage.dart';

String contractFaLabel(Map<String, dynamic> event) =>
    '${event['type'] == 'international' ? '海外' : '国内'}FA権獲得${event['projected'] == true ? '（見込み）' : ''}';

/// Match official player IDs first; name-only reports are limited to NPB rosters.
List<Map<String, dynamic>> contractFaEvents(
    Map<String, dynamic> player, Map<String, dynamic>? contract,
    {required bool isNpb}) {
  String normalize(dynamic value) => '$value'.replaceAll(RegExp(r'[\s　]'), '');
  final key = usagePlayerKey(player);
  final name = normalize(player['name']);
  final candidates = <Map<String, dynamic>>[
    if (isNpb)
      ...npbFaRights.where((event) => event['player_key'] != null
          ? event['player_key'] == key ||
              (!key.startsWith('npb:') && normalize(event['name']) == name)
          : normalize(event['name']) == name),
    ...listMapFromJson(player['fa_events']),
    ...listMapFromJson(contract?['fa_events']),
  ];
  final result = <String, Map<String, dynamic>>{};
  for (final event in candidates) {
    final year = usageInt(event['year']);
    if (year < 1993 ||
        !['domestic', 'international'].contains(event['type']) ||
        '${event['source_url'] ?? ''}'.isEmpty) {
      continue;
    }
    final id = '$year-${event['type']}';
    // An acquisition report supersedes an estimate for the same year/right.
    if (result[id]?['projected'] == false && event['projected'] == true) {
      continue;
    }
    result[id] = {...event, 'year': year};
  }
  return result.values.toList()
    ..sort((a, b) => usageInt(a['year']).compareTo(usageInt(b['year'])));
}
