import 'StrengthUsage.dart';
import 'OverseasContracts.dart';

// Individually verified alternate sources. Never derive terms from salary alone.
const contractSupplements = <Map<String, dynamic>>[
  {
    'org': 'npb',
    'name': '坂本勇人',
    'team': '巨人',
    'start_year': 2025,
    'end_year': 2025,
    'source_url':
        'https://news.ntv.co.jp/category/sports/55cae0c829864838b7b8d8af3cfb2015'
  },
  {
    'org': 'npb',
    'name': '坂本勇人',
    'team': '巨人',
    'start_year': 2026,
    'end_year': 2026,
    'source_url':
        'https://www.nikkansports.com/baseball/news/202512090000387.html'
  },
  {
    'org': 'npb',
    'name': '佐藤輝明',
    'team': '阪神',
    'start_year': 2026,
    'end_year': 2026,
    'source_url': 'https://www.sun-tv.co.jp/suntvnews/news/2026/01/31/92359/'
  },
  {
    'org': 'mlb',
    'player_key': 'mlb:660271',
    'team': 'LAD',
    'start_year': 2024,
    'end_year': 2033,
    'signed_date': '2023-12-11',
    'source_url':
        'https://www.mlb.com/dodgers/news/shohei-ohtani-contract-with-dodgers'
  },
  {
    'org': 'mlb',
    'player_key': 'mlb:665742',
    'team': 'NYM',
    'start_year': 2025,
    'end_year': 2039,
    'signed_date': '2024-12-11',
    'source_url':
        'https://www.mlb.com/news/juan-soto-agrees-to-contract-with-mets-sources'
  },
  {
    'org': 'mlb',
    'player_key': 'mlb:592450',
    'team': 'NYY',
    'start_year': 2023,
    'end_year': 2031,
    'signed_date': '2022-12-20',
    'source_url':
        'https://www.mlb.com/yankees/press-release/press-release-yankees-re-sign-outfielder-aaron-judge'
  },
];

Map<String, dynamic> supplementContracts(
    String org, Map<String, dynamic> record) {
  final periods = usageMaps(record['periods'])
      .map((p) => Map<String, dynamic>.from(p))
      .toList();
  for (final supplement in contractSupplements) {
    if (supplement['org'] != org) continue;
    final matches = supplement['player_key'] != null
        ? supplement['player_key'] == record['player_key']
        : usageName('${supplement['name']}') == usageName('${record['name']}');
    if (!matches) continue;
    final index = periods.indexWhere((p) =>
        p['team'] == supplement['team'] &&
        ((supplement['signed_date'] != null &&
                p['signed_date'] == supplement['signed_date']) ||
            (p['start_year'] == supplement['start_year'] &&
                p['end_year'] == supplement['end_year'])));
    final updated = <String, dynamic>{
      if (index >= 0) ...periods[index],
      ...supplement,
      'period': '${supplement['start_year']}〜${supplement['end_year']}年',
      'verified_supplement': true,
    }
      ..remove('org')
      ..remove('name')
      ..remove('player_key');
    if (index >= 0) {
      periods[index] = updated;
    } else {
      periods.add(updated);
    }
  }
  return mergeOverseasContracts({...record, 'periods': periods},
      verifiedTaiwanContracts('${record['player_key']}'));
}
