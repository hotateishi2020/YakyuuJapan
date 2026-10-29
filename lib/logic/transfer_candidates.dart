import '../data/npb_registration_status.dart';
import '../data/npb_transfer_reports.dart';
import '../data/npb_fa_holders.dart';
import '../data/npb_retirement_announcements.dart';
import '../tools/json_utils.dart';
import 'contract_fa.dart';
import 'roster_contract_status.dart';
import 'strength_usage.dart';

bool _retiring(
    Map<String, dynamic> player, Map<String, dynamic> team, int year) {
  final retirementYear = usageInt(player['retirement_year']);
  if ((player['retirement_confirmed'] == true ||
          player['retirement_announced'] == true) &&
      (retirementYear == 0 || retirementYear <= year)) {
    return true;
  }
  if (usageInt(player['move_status_year']) == year &&
      const {'引退', '現役引退', '引退表明', '引退予定', '今季限りで引退'}
          .contains(player['move_status'])) {
    return true;
  }
  return npbRetirementAnnouncements.any((announcement) =>
      usageInt(announcement['year']) <= year &&
      (announcement['player_key'] == usagePlayerKey(player) ||
          (usageInt(team['id_team']) == announcement['team_id'] &&
              '${player['name']}'.replaceAll(RegExp(r'[\s　]'), '') ==
                  '${announcement['name']}'.replaceAll(RegExp(r'[\s　]'), ''))));
}

enum TransferSort { attention, team }

List<Map<String, dynamic>> transferCandidates(
    List<Map<String, dynamic>> teams, int year, {TransferSort sort = TransferSort.attention}) {
  final result = <Map<String, dynamic>>[];
  for (final team in teams.where(npbContractTeam)) {
    final seen = <String>{};
    for (final player in listMapFromJson(team['roster'])) {
      if (!seen.add(usagePlayerKey(player)) ||
          player['departure_confirmed'] == true ||
          _retiring(player, team, year)) {
        continue;
      }
      final status = usageInt(player['move_status_year']) == year
          ? player['move_status']
          : null;
      final method = '${player['move_method'] ?? ''}';
      final draftType = '${player['arrival_draft_type'] ?? ''}';
      final activeDraft = method.contains('現役ドラフト') || draftType.contains('現役');
      final rookieDraft = !activeDraft &&
          (method.contains('ドラフト') || draftType.isNotEmpty ||
              usageInt(player['arrival_draft_rank']) > 0);
      if (rookieDraft) continue;
      final arrivalYear = usageInt(player['arrival_year']);
      final announced = DateTime.tryParse('${player['arrival_as_of'] ?? player['move_method_as_of'] ?? player['status_as_of'] ?? ''}');
      final newArrival = player['new_arrival'] == true &&
          (arrivalYear == year || arrivalYear == year + 1) &&
          (announced != null ? announced.year == year :
              arrivalYear == year || usageInt(player['move_method_year']) == year);
      if (newArrival) {
        final previous = player['previous_team'];
        final previousName = previous is Map
            ? '${previous['name'] ?? previous['label'] ?? ''}'
            : '${player['previous_team_name'] ?? previous ?? ''}';
        final sources = <String>{
          for (final key in ['status_source', 'arrival_source', 'move_method_source'])
            if ('${player[key] ?? ''}'.isNotEmpty) '${player[key]}',
        };
        result.add({
          'player': player, 'team': team,
          'labels': [method.isEmpty ? '新加入' : method],
          'reported': false, 'attention': 3,
          'attention_reason': '入団・移籍決定',
          'contract': '入団決定', 'status': '入団決定',
          'detail': [
            if (previousName.isNotEmpty && previousName != '前所属未確認') '$previousName → ${team['name_team']}',
            if (announced != null) '${announced.toIso8601String().substring(0,10)} 発表',
          ].join('\n'),
          'sources': sources.toList(),
        });
        continue;
      }
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
      if (status == 'ポスティング容認') eligibility.add('ポスティング容認');
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
        'attention': status == 'ポスティング容認' || status == 'FA宣言（移籍先未定）'
            ? 3 : reports.isNotEmpty ? 2 : 1,
        'attention_reason': status == 'ポスティング容認' || status == 'FA宣言（移籍先未定）'
            ? 'FA宣言・ポスティング容認' : reports.isNotEmpty ? '移籍関連の報道あり' : '権利保有・行使未確認',
        'contract': end == null
            ? '契約期限未確認'
            : end == year
                ? '$year年まで'
                : '$end年まで',
        'status': status == 'ポスティング容認' ? 'ポスティング容認・契約成立未確認' : reports.isNotEmpty
            ? '移籍関連の報道あり'
            : status == 'FA宣言（移籍先未定）'
                ? 'FA宣言・移籍先未定'
                : '権利保有・行使未確認',
        'detail': status == 'ポスティング容認' ? '球団の公式発表により容認を確認。移籍先との契約成立は別途確認します。' : reports.isNotEmpty
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
    final attention = usageInt(b['attention']).compareTo(usageInt(a['attention']));
    final team = usageInt(a['team']['id_team']).compareTo(usageInt(b['team']['id_team']));
    final primary = sort == TransferSort.attention ? attention : team;
    if (primary != 0) return primary;
    final secondary = sort == TransferSort.attention ? team : attention;
    if (secondary != 0) return secondary;
    return '${a['player']['name']}'.compareTo('${b['player']['name']}');
  });
  return result;
}
