import 'StrengthUsage.dart';

// Reported remaining salary, not the acquiring club's CBT payroll charge.
// Keep annual salary once; team shares are its breakdown, never extra income.
const verifiedSalaryShares = <Map<String, dynamic>>[
  {
    'org': 'mlb', 'player_key': 'mlb:669373', 'year': 2026,
    'amount': 32000000, 'currency': 'USD', 'team': 'LAD',
    'source_url': 'https://www.truebluela.com/dodgers-roster/121072/dodgers-finalize-tarik-skubal-trade',
    'team_shares': [
      {'team': 'DET', 'amount': 22193548, 'estimated': true,
        'detail': '年俸総額から移籍後の負担額を差し引いた推定額'},
      {'team': 'LAD', 'amount': 9806452, 'estimated': true,
        'detail': '2026-08-02移籍、残り57日分の報道額。CBTを含まない'},
    ],
  },
];

Map<String, dynamic> supplementSalaryShares(String org, Map<String, dynamic> record) {
  if (!verifiedSalaryShares.any((s) => s['org'] == org && s['player_key'] == record['player_key'])) return record;
  final salaries = usageMaps(record['salary_history']).map((s) => Map<String, dynamic>.from(s)).toList();
  for (final item in verifiedSalaryShares) {
    if (item['org'] != org || item['player_key'] != record['player_key']) continue;
    final index = salaries.indexWhere((s) => usageInt(s['year']) == item['year']);
    final updated = <String, dynamic>{
      if (index >= 0) ...salaries[index], ...item,
    }..remove('org')..remove('player_key')..remove('share_method');
    if (index < 0) { salaries.add(updated); } else { salaries[index] = updated; }
  }
  return {...record, 'salary_history': salaries};
}
