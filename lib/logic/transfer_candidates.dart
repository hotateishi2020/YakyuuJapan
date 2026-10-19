import '../data/npb_registration_status.dart';
import '../data/npb_transfer_reports.dart';
import '../data/npb_fa_holders.dart';
import '../tools/json_utils.dart';
import 'contract_fa.dart';
import 'roster_contract_status.dart';
import 'strength_usage.dart';

List<Map<String, dynamic>> transferCandidates(
    List<Map<String, dynamic>> teams, int year) {
  final result = <Map<String, dynamic>>[];
  for (final team in teams.where(npbContractTeam)) {
    final seen = <String>{};
    for (final player in listMapFromJson(team['roster'])) {
      if (!seen.add(usagePlayerKey(player)) ||
          player['departure_confirmed'] == true) {
        continue;
      }
      final status = usageInt(player['move_status_year']) == year
          ? player['move_status']
          : null;
      if (status == 'FA残留' ||
          (usageInt(player['move_method_year']) == year &&
              player['move_method'] == 'FA移籍')) {
        continue;
      }
      final contract = rosterContract(player, team);
      final end = rosterContractEnd(player, contract, year);
      String normalized(dynamic value) =>
          '$value'.replaceAll(RegExp(r'[\s　]'), '').replaceAll('髙', '高');
      final reports = [
        ...npbTransferReports
            .where((e) => e['player_key'] == usagePlayerKey(player)),
        ...npbPostingReports
            .where((e) => normalized(e['name']) == normalized(player['name']))
            .map((e) => {...e, 'type': 'posting'}),
        ...listMapFromJson(player['posting_reports'])
            .map((e) => {...e, 'type': 'posting'}),
        ...listMapFromJson(contract?['posting_reports'])
            .map((e) => {...e, 'type': 'posting'}),
        ...listMapFromJson(player['transfer_reports']),
      ]
          .where((e) =>
              usageInt(e['year']) == year &&
              e['status'] == 'rumored' &&
              '${e['source_url'] ?? ''}'.isNotEmpty)
          .toList();
      // An unknown contract term stays explicitly unknown, never "expired".
      final eligibility = rosterContractLabels(
              {...player, if (end == null) 'contract_end_year': year},
              team,
              year)
          .where((label) => label == '国内FA' || label == '海外FA')
          .toSet();
      if (status == 'FA宣言（移籍先未定）') eligibility.add('FA宣言');
      for (final report in reports) {
        switch (report['type']) {
          case 'posting':
            eligibility.add('ポスティング？');
          case 'international':
            eligibility.remove('国内FA');
            eligibility.add('海外FA');
          case 'domestic':
            if (!eligibility.contains('海外FA')) eligibility.add('国内FA');
        }
      }
      if (eligibility.isEmpty) continue;
      final sources = <String>{
        for (final r in reports) '${r['source_url']}',
        for (final e in contractFaEvents(player, contract, isNpb: true))
          if (usageInt(e['year']) == year && e['projected'] != true)
            '${e['source_url']}',
        for (final e in npbFaHolders)
          if (e['player_key'] == usagePlayerKey(player) &&
              usageInt(e['year']) >= year - 1 &&
              usageInt(e['year']) <= year)
            '${e['source_url']}',
        if (player['status_source'] != null) '${player['status_source']}',
      };
      result.add({
        'player': player,
        'team': team,
        'labels': eligibility.toList(),
        'reported': reports.isNotEmpty,
        'contract': end == null
            ? '契約期限未確認'
            : end == year
                ? '$year年まで'
                : '$end年まで',
        'status': reports.isNotEmpty
            ? '移籍関連の報道あり'
            : status == 'FA宣言（移籍先未定）'
                ? 'FA宣言・移籍先未定'
                : '権利保有・行使未確認',
        'detail': reports.isNotEmpty
            ? reports
                .map((e) => e['detail'] ?? '移籍の可能性に関する報道。')
                .toSet()
                .join('\n')
            : 'FA権保有状況から掲載。権利行使・移籍の意思を示したものではありません。',
        'sources': sources.where((s) => s.isNotEmpty).toList(),
      });
    }
  }
  result.sort((a, b) {
    final priority = (b['reported'] == true ? 1 : 0)
        .compareTo(a['reported'] == true ? 1 : 0);
    if (priority != 0) return priority;
    final team = usageInt(a['team']['id_team'])
        .compareTo(usageInt(b['team']['id_team']));
    return team != 0
        ? team
        : '${a['player']['name']}'.compareTo('${b['player']['name']}');
  });
  return result;
}
