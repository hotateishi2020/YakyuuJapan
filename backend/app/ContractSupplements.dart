import 'ContractTransferShares.dart';
import 'ContractSalaryShares.dart';
import 'StrengthUsage.dart';
import 'OverseasContracts.dart';

// Individually verified alternate sources. Never derive terms from salary alone.
const contractSupplements = <Map<String, dynamic>>[
  // MLB contract seasons verified against the linked club/MLB reports.
  {
    'org': 'mlb', 'player_key': 'mlb:673513', 'team': 'SD',
    'start_year': 2024, 'end_year': 2028, 'signed_date': '2023-12-23',
    'source_url': 'https://www.mlb.com/ja/news/yuki-matsui-would-become-free-agent-if-he-exercises-opt-out-rights',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:672960', 'team': 'TOR',
    'start_year': 2026, 'end_year': 2029, 'signed_date': '2026-01-04',
    'source_url': 'https://www.mlb.com/ja/news/blue-jays-sign-kazuma-okamoto',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:808959', 'team': 'CWS',
    'start_year': 2026, 'end_year': 2027, 'signed_date': '2025-12-21',
    'source_url': 'https://www.mlb.com/amp/news/munetaka-murakami-white-sox-contract.html',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:579328', 'team': 'LAA',
    'start_year': 2025, 'end_year': 2027, 'signed_date': '2024-11-27',
    'source_url': 'https://www.mlb.com/press-release/press-release-angels-sign-lhp-yusei-kikuchi',
    'detail': '契約総額 USD 63000000',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:807799', 'team': 'BOS',
    'start_year': 2023, 'end_year': 2027, 'signed_date': '2022-12-15',
    'source_url': 'https://www.mlb.com/press-release/press-release-masataka-yoshida-signs-contract-with-red-sox',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:684007', 'team': 'CHC',
    'start_year': 2026, 'end_year': 2026, 'signed_date': '2025-11-18',
    'source_url': 'https://www.mlb.com/cubs/news/shota-imanaga-accepts-qualifying-offer-from-cubs',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:673548', 'team': 'CHC',
    'start_year': 2022, 'end_year': 2026, 'signed_date': '2022-03-18',
    'source_url': 'https://www.mlb.com/cubs/news/seiya-suzuki-signs-5-year-deal-with-cubs',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:608372', 'team': 'COL',
    'start_year': 2026, 'end_year': 2026, 'signed_date': '2026-02-10',
    'source_url': 'https://www.mlb.com/news/tomoyuki-sugano-throws-rockies-spring-training',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:837227', 'team': 'HOU',
    'start_year': 2026, 'end_year': 2028, 'signed_date': '2026-01-02',
    'source_url': 'https://www.mlb.com/amp/news/tatsuya-imai-astros-deal.html',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:808967', 'team': 'LAD',
    'start_year': 2024, 'end_year': 2035, 'signed_date': '2023-12-27',
    'source_url': 'https://www.mlb.com/news/yoshinobu-yamamoto-dodgers-free-agent-deal',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:673540', 'team': 'NYM',
    'start_year': 2023, 'end_year': 2027, 'signed_date': '2022-12-17',
    'source_url': 'https://www.mlb.com/news/kodai-senga-s-future-uncertain-entering-offseason',
  },
  {
    'org': 'mlb', 'player_key': 'mlb:506433', 'team': 'SD',
    'start_year': 2023, 'end_year': 2028, 'signed_date': '2023-02-09',
    'source_url': 'https://www.mlb.com/news/yu-darvish-padres-extension',
    'detail': '契約総額 USD 108000000',
  },
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
  return supplementTransferShares(org, supplementSalaryShares(org, mergeOverseasContracts({...record, 'periods': periods},
      verifiedTaiwanContracts('${record['player_key']}'))));
}
