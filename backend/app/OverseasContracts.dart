import 'StrengthUsage.dart';
import 'ContractExchange.dart';

Map<String, dynamic> overseasContractHistory(List<Map<String, dynamic>> history,
    int firstNpbYear, Map<String, double> rates, int mlbId) {
  final salaries = <Map<String, dynamic>>[];
  final periods = <Map<String, dynamic>>[];
  final affiliations = <Map<String, dynamic>>[];
  const source = 'https://frontofficemoves.com/data/contracts.json';
  for (final c in history) {
    final season = usageInt(c['yr']);
    final start = usageInt(c['ds']) > 0 ? usageInt(c['ds']) : season;
    final duration =
        usageInt(c['dy']) > 0 ? usageInt(c['dy']) : usageInt(c['y']);
    final date = DateTime.tryParse('${c['d']}');
    if (season >= firstNpbYear ||
        start >= firstNpbYear ||
        (start <= 0 && (date == null || date.year >= firstNpbYear))) continue;
    final end = start > 0 && duration > 0 ? start + duration - 1 : null;
    // A contract spanning the NPB arrival requires manual review.
    if (end != null && end >= firstNpbYear) continue;
    final metadata = <String, dynamic>{
      'team': c['t'],
      'source_url': source,
      'source_player_id': mlbId,
      'origin': 'pre_npb',
      ...contractExchange(c['d'], rates),
    };
    if (season > 0) affiliations.add({...metadata, 'year': season});
    periods.add({
      ...metadata,
      'start_year': start > 0 ? start : null,
      'end_year': end,
      'period': start > 0 && end != null ? '$start〜$end年' : '',
      'detail': [
        if (usageInt(c['tv']) > 0) '契約総額 USD ${c['dt'] ?? c['tv']}',
        if (usageInt(c['min']) > 0) '年俸下限 USD ${c['min']}（実受取額未確認）',
        if (c['mn'] == 1) 'マイナー契約',
      ].join(' / '),
    });
    // Do not turn multi-year totals, AAV or league minima into annual pay.
    if (season > 0 && usageInt(c['y']) == 1 && usageInt(c['tv']) > 0) {
      salaries.add({
        ...metadata,
        'year': season,
        'amount': usageInt(c['tv']),
        'currency': 'USD'
      });
    }
  }
  return {
    'salary_history': salaries,
    'periods': periods,
    'affiliation_history': affiliations,
    'source_player_id': mlbId
  };
}

Map<String, dynamic> mergeOverseasContracts(
    Map<String, dynamic> record, Map<String, dynamic> overseas) {
  if (overseas.isEmpty) return record;
  final salaries = usageMaps(record['salary_history']).toList();
  for (final salary in usageMaps(overseas['salary_history'])) {
    if (!salaries.any((s) => s['year'] == salary['year'])) salaries.add(salary);
  }
  List<Map<String, dynamic>> merge(
      String field, String Function(Map<String, dynamic>) key) {
    final items = usageMaps(record[field]).toList();
    final keys = items.map(key).toSet();
    for (final item in usageMaps(overseas[field])) {
      if (keys.add(key(item))) items.add(item);
    }
    return items;
  }

  return {
    ...record,
    'salary_history': salaries,
    'periods': merge(
        'periods',
        (p) =>
            '${p['team']}/${p['start_year']}/${p['end_year']}/${p['signed_date']}'),
    'affiliation_history':
        merge('affiliation_history', (p) => '${p['team']}/${p['year']}'),
    'overseas_contracts': overseas,
  };
}

// Taiwanese reports distinguish monthly salaries and signing bonuses;
// neither is treated as a full annual salary.
Map<String, dynamic> verifiedTaiwanContracts(String key) {
  if (key == 'npb:23525152') {
    const source = 'https://www.cna.com.tw/news/aspt/202503280079.aspx';
    return {
      'salary_history': <Map<String, dynamic>>[],
      'periods': <Map<String, dynamic>>[],
      'affiliation_history': [
        for (final year in [2024, 2025])
          {
            'year': year,
            'team': '味全ドラゴンズ',
            'origin': 'pre_npb',
            'monthly_amount': year == 2025 ? 400000 : 280000,
            'currency': 'TWD',
            'source_url': source,
            'detail': '月給 ${year == 2025 ? 40 : 28}万台湾ドル（年俸への換算なし）'
          },
      ],
    };
  }
  if (key == 'npb:33935152') {
    return {
      'salary_history': <Map<String, dynamic>>[],
      'periods': <Map<String, dynamic>>[],
      'affiliation_history': [
        {
          'year': 2019,
          'team': '統一ライオンズ',
          'origin': 'pre_npb',
          'signing_bonus': 5300000,
          'currency': 'TWD',
          'detail': '契約金 530万台湾ドル（年俸とは別）',
          'source_url': 'https://www.cna.com.tw/news/aspt/201907230167.aspx'
        },
        {
          'year': 2020,
          'team': '統一ライオンズ',
          'origin': 'pre_npb',
          'monthly_amount': 100000,
          'currency': 'TWD',
          'detail': '月給 10万台湾ドル（年俸への換算なし）',
          'source_url': 'https://www.cna.com.tw/news/aspt/202101170182.aspx'
        },
      ],
    };
  }
  return {};
}
