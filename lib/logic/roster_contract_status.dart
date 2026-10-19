import '../data/npb_fa_holders.dart';
import '../data/npb_transfer_reports.dart';
import '../data/npb_registration_status.dart';
import '../tools/json_utils.dart';
import 'contract_fa.dart';
import 'strength_usage.dart';

bool npbContractTeam(Map<String, dynamic> team) =>
    team['org'] != 'mlb' && ![3, 4].contains(usageInt(team['id_league']));

Map<String, dynamic>? rosterContract(
        Map<String, dynamic> player, Map<String, dynamic> team) =>
    listMapFromJson(team['contracts'])
        .where((c) => usagePlayerKey(c) == usagePlayerKey(player))
        .firstOrNull;

/// Do not turn a salary estimate into a confirmed single-year contract.
int? rosterContractEnd(
    Map<String, dynamic> player, Map<String, dynamic>? contract, int year) {
  final periods = listMapFromJson(contract?['periods']);
  final ends = [
    if (usageInt(player['contract_end_year']) >= year)
      usageInt(player['contract_end_year']),
    for (final p in periods)
      if (usageInt(p['start_year']) > 0 &&
          usageInt(p['end_year']) >= year &&
          usageInt(p['start_year']) <= year + 1)
        usageInt(p['end_year']),
  ];
  return ends.isEmpty ? null : ends.reduce((a, b) => a > b ? a : b);
}

List<Map<String, dynamic>> registrationExemptionEvents(
    Map<String, dynamic> player, Map<String, dynamic>? contract,
    {required bool isNpb}) {
  if (!isNpb) return [];
  final events = <int, Map<String, dynamic>>{};
  for (final e in [
    ...npbRegistrationExemptions
        .where((e) => e['player_key'] == usagePlayerKey(player)),
    ...listMapFromJson(player['foreign_exemption_events']),
    ...listMapFromJson(contract?['foreign_exemption_events']),
    if (usageInt(player['foreign_exemption_year']) > 0)
      {
        'year': player['foreign_exemption_year'],
        'source_url': player['foreign_exemption_source'],
        'detail': '外国人選手登録の適用除外開始年'
      },
  ]) {
    if (usageInt(e['year']) > 0 && '${e['source_url'] ?? ''}'.isNotEmpty) {
      events[usageInt(e['year'])] = {...e, 'type': 'foreign_exemption'};
    }
  }
  return events.values.toList()
    ..sort((a, b) => usageInt(a['year']).compareTo(usageInt(b['year'])));
}

/// Rights are based on current official holders/new acquisitions, not old
/// acquisition history (a right may already have been exercised).
List<String> rosterContractLabels(
    Map<String, dynamic> player, Map<String, dynamic> team, int year) {
  if (!npbContractTeam(team)) return [];
  final contract = rosterContract(player, team);
  final labels = <String>[];
  final exempt = registrationExemptionEvents(player, contract, isNpb: true)
      .any((e) => e['projected'] != true && usageInt(e['year']) <= year);
  if (exempt) labels.add('外国人適用除外');
  if (player['departure_confirmed'] == true) return labels;
  final end = rosterContractEnd(player, contract, year);
  final status = usageInt(player['move_status_year']) == year
      ? '${player['move_status'] ?? ''}'
      : '';
  final exercised = usageInt(player['fa_exercised_year']) >= year - 1 ||
      (usageInt(player['move_method_year']) == year &&
          player['move_method'] == 'FA移籍') ||
      status == 'FA残留';
  if (end == year && !exercised) {
    final rights = <String>{
      for (final e in npbFaHolders)
        if (e['player_key'] == usagePlayerKey(player) &&
            (usageInt(e['year']) == year || usageInt(e['year']) == year - 1))
          '${e['type']}',
      for (final e in contractFaEvents(player, contract, isNpb: true))
        if (usageInt(e['year']) == year && e['projected'] != true)
          '${e['type']}',
      if (status == '国内FA権保有') 'domestic',
      if (status == '海外FA権保有') 'international',
      if (usageInt(player['fa_rights_year']) == year &&
          ['domestic', 'international'].contains(player['fa_rights_type']))
        '${player['fa_rights_type']}',
    };
    if (rights.contains('international')) {
      labels.add('海外FA');
    } else if (rights.contains('domestic')) {
      labels.add('国内FA');
    }
  }
  // A sourced report is scoped to a season; old rumors must not persist forever.
  final rumors = [
    ...npbTransferReports.where((e) =>
        e['type'] == 'posting' && e['player_key'] == usagePlayerKey(player)),
    ...npbPostingReports.where((e) =>
        '${e['name']}'.replaceAll(RegExp(r'[\s　]'), '') ==
        '${player['name']}'.replaceAll(RegExp(r'[\s　]'), '')),
    ...listMapFromJson(player['posting_reports']),
    ...listMapFromJson(contract?['posting_reports']),
  ];
  if (((end != null && end > year) ||
          npbTransferReports.any((e) =>
              e['player_key'] == usagePlayerKey(player) &&
              e['type'] == 'posting' &&
              usageInt(e['year']) == year)) &&
      rumors.any((e) =>
          usageInt(e['year']) == year &&
          e['status'] == 'rumored' &&
          '${e['source_url'] ?? ''}'.isNotEmpty)) {
    labels.add('ポスティング？');
  }
  return labels;
}
